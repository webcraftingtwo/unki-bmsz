-- ═══════════════════════════════════════════════════════════════════════
-- UNKI GEOTECH · 0001 · initial schema
--
-- Target: GeoTech's OWN Supabase project. NOT valterra-slam-reentry.
-- Nothing in this file has been applied anywhere. Apply it to the new
-- project before deploying any app code that writes these tables.
--
-- WHAT THIS FILE IS FOR, beyond holding the data:
--
--   1. IT MAKES THE APP'S PROMISES ENFORCEABLE. Three rules that
--      index.html can only ask for politely become guarantees here:
--
--      · "Never overwrite an observation. Corrections are new rows."
--        (§9.1) — capture tables grant INSERT and SELECT only. There is
--        no UPDATE and no DELETE policy for anyone, including the Chief
--        Geologist. A correction is a new row that supersedes.
--
--      · "The server recomputes every aggregate at ingest and ignores
--        the handset's own breach counts and means." — the handset's
--        figures land in `reported_stats` and are NEVER read as truth.
--        The authoritative numbers are VIEWS over the stations and the
--        snapshotted limits, so there is nothing to trust and nothing
--        to re-run. `offset_stat_drift` surfaces any disagreement.
--
--      · Section compartmentalization — RLS, not a UI mirror.
--
--   2. IT ENCODES THE STANDARD AS CONSTRAINTS. F/W readings negative,
--      no station zero, rounds at 2 m and 5 m only, sections exactly
--      '14 South' and '16 North'. A bad row cannot be written.
--
-- Anything the standard does not fix is marked DERIVED so the Chief
-- Geologist can rule on it. No invented Unki policy.
-- ═══════════════════════════════════════════════════════════════════════

begin;

create extension if not exists pgcrypto;

-- ── enumerations ──────────────────────────────────────────────────────
-- Sections are exactly these two. Zones live inside them; nothing else
-- exists (CLAUDE.md, section compartmentalization).
create type geo_section as enum ('14 South', '16 North');

-- The four GeoTech roles. SLAM's own roles are NOT reproduced here —
-- this is a separate project and a separate identity space.
create type geo_role as enum (
  'geological_technician',  -- capture; cannot alter validated interpretations
  'section_geologist',      -- review, comment, notified on doubtful calls
  'chief_geologist',        -- authorise deviations, version limit sets, full read
  'mrm_manager'             -- read and report, signs stopped-end log
);

-- §9.8: bord/ledging decline vs decline/strike drive. Sets the design cut.
create type geo_heading as enum ('bord', 'decline');

-- TARP class. DERIVED: the notes give the four values but not their
-- meaning, so nothing hangs off the choice yet (open decision 14).
create type geo_tarp as enum ('1', '2', '3', 'S');

-- ── identity ──────────────────────────────────────────────────────────
-- One row per signed-in person, keyed to Supabase auth. Role and section
-- live HERE, server-side — never taken from the client. This is what
-- replaces the app's self-declared `roleSource` (open decision 19).
create table profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  employee_no   text        not null unique,
  full_name     text        not null,
  role          geo_role    not null default 'geological_technician',
  section       geo_section not null,
  active        boolean     not null default true,
  created_at    timestamptz not null default now()
);
comment on table profiles is
  'Role and section are server-side facts. A client never asserts either.';

-- Helpers. STABLE + security definer so policies can read the caller's
-- own profile without recursing through profiles' own RLS.
create or replace function current_role_geo() returns geo_role
  language sql stable security definer set search_path = public as $$
    select role from profiles where id = auth.uid() and active
  $$;

create or replace function current_section() returns geo_section
  language sql stable security definer set search_path = public as $$
    select section from profiles where id = auth.uid() and active
  $$;

-- Who may read beyond their own section.
create or replace function can_read_all() returns boolean
  language sql stable as $$
    select current_role_geo() in ('chief_geologist', 'mrm_manager')
  $$;

-- ── limit sets: versioned data, never constants ────────────────────────
-- "Limit sets are versioned data, never hard-coded constants. Changing
-- one requires Chief Geologist authorisation and an audit row."
-- Rows are immutable; a revision is a NEW version. Every offset_set
-- snapshots the values it was judged by, so a revision here can never
-- restate what an old face was measured against.
create table limit_sets (
  -- A limit set is one version covering BOTH heading types, so the key is
  -- the pair. `version` alone would let only one of the two rows exist.
  version       text        not null,
  heading       geo_heading not null,
  hw_limit_cm   integer     not null,
  fw_limit_cm   integer     not null check (fw_limit_cm < 0),
  label         text        not null,
  source        text        not null,   -- the sheet or note it came from
  authorised_by uuid        not null references profiles (id),
  authorised_at timestamptz not null default now(),
  primary key (version, heading)
);
comment on table limit_sets is
  'Immutable. A changed limit is a new version, authorised by the Chief Geologist (STD-201 §7.3).';

-- The limits in service today, from the supplied face marking sheets.
-- Seeded without an authoriser; the insert below is intentionally left
-- for the Chief Geologist to run so the authorisation is real.
--   bord:    +45 / -135  (Sheet 2NB3 12-07-10)
--   decline: +150 / -100 (Sheets MM 26-04-10, NS3 12-07-10)

-- ── shift ─────────────────────────────────────────────────────────────
create table shift_records (
  id            uuid primary key default gen_random_uuid(),
  observer      uuid        not null references profiles (id),
  section       geo_section not null,
  shift_name    text        not null,
  -- A / B / C, 6-on/3-off (CLAUDE.md). Nullable because the field app
  -- hardcodes shiftName and does not ask which of the three it is yet.
  shift_type    text        check (shift_type in ('A', 'B', 'C')),
  started_at    timestamptz not null,
  ended_at      timestamptz,
  deviation     text,                   -- §7.3; recorded, never granted by the app
  device        text,
  client_ts     timestamptz not null,   -- when the device thinks it happened
  created_at    timestamptz not null default now()
);

-- ── face log ──────────────────────────────────────────────────────────
-- One per face visit. Carries the acknowledgement that gated it: the
-- named miner who declared the area made safe, and the readiness the
-- technician confirmed (§9.2, §8.3).
create table face_logs (
  id              uuid primary key default gen_random_uuid(),
  shift_id        uuid        references shift_records (id),
  observer        uuid        not null references profiles (id),
  section         geo_section not null,

  bord            text        not null,
  level           text,
  peg             text,
  advance_m       numeric(6,2),
  face_length_m   numeric(6,2) not null check (face_length_m > 0),
  face_width_m    numeric(6,2),
  face_height_m   numeric(6,2),

  channel_id      text,
  dist_to_face_m  numeric(6,2),
  -- §9 of the notes: past 9 m the channel assay cannot be tied to the
  -- face, so the face is flagged for sampling. Derived, not asserted.
  sample_flagged  boolean generated always as (dist_to_face_m > 9) stored,

  tarp            geo_tarp,
  structural      text,

  -- The acknowledgement gate. A face log without a named miner and a
  -- made-safe declaration should not exist; the constraint says so.
  area_safe       boolean     not null,
  miner_name      text        not null check (length(btrim(miner_name)) > 0),
  team            text[]      not null default '{}',
  readiness       jsonb       not null default '{}'::jsonb,

  -- How the face arrived. 'manual' means nothing cleared it for entry
  -- (REWORK 3, open decisions 25 and 30). Kept so a reviewer can tell.
  source          text        not null default 'manual'
                    check (source in ('manual', 'reentry')),

  device          text,
  client_ts       timestamptz not null,
  created_at      timestamptz not null default now(),

  constraint face_log_area_must_be_safe check (area_safe)
);
comment on constraint face_log_area_must_be_safe on face_logs is
  'Geology does not send anyone to a face that has not been made safe. The app blocks it; this makes it unwritable.';

-- ── offsets: the core record ──────────────────────────────────────────
-- The limit snapshot is COPIED onto the row, not referenced live. That is
-- the whole point: a limit revised next year must not restate what this
-- face was judged against.
create table offset_sets (
  id             uuid primary key default gen_random_uuid(),
  shift_id       uuid        references shift_records (id),
  face_log_id    uuid        references face_logs (id),
  observer       uuid        not null references profiles (id),
  section        geo_section not null,

  bord           text        not null,
  heading        geo_heading not null,
  face_length_m  numeric(6,2) not null check (face_length_m > 0),
  interval_m     integer     not null default 1 check (interval_m = 1),

  -- Snapshot. Not a foreign key to today's values.
  limit_version  text        not null,
  limit_label    text        not null,
  hw_limit_cm    integer     not null,
  fw_limit_cm    integer     not null check (fw_limit_cm < 0),

  -- What the handset computed. Kept for comparison and audit. NEVER
  -- read as truth — see offset_set_stats.
  reported_stats jsonb,

  device         text,
  client_ts      timestamptz not null,
  created_at     timestamptz not null default now()
);
comment on column offset_sets.reported_stats is
  'The device''s own aggregates. Retained for drift comparison only; offset_set_stats is authoritative.';

-- Two rounds, the same stations walked at 2 m and then 5 m from the face
-- (REWORK 2, note 6). No station zero; the first is 1 m off the sidewall.
-- F/W is always negative — the footwall is below the BMSZ datum.
create table offset_stations (
  id             uuid primary key default gen_random_uuid(),
  offset_set_id  uuid        not null references offset_sets (id) on delete cascade,
  round_dist_m   integer     not null check (round_dist_m in (2, 5)),
  station_dist_m integer     not null check (station_dist_m >= 1),
  hw_cm          integer     not null,
  fw_cm          integer     not null check (fw_cm < 0),
  mining_height_cm integer generated always as (hw_cm - fw_cm) stored,
  cause          text,
  unique (offset_set_id, round_dist_m, station_dist_m)
);
comment on table offset_stations is
  'No station zero (§9.8.ii as amended). F/W negative by constraint. Mining height is derived, never entered.';

-- A station past the cut must carry a cause. Enforced here as well as in
-- the app, because this is the record that drives blast practice.
create or replace function offset_station_cause_required() returns trigger
  language plpgsql as $$
declare s offset_sets;
begin
  select * into s from offset_sets where id = new.offset_set_id;
  if (new.hw_cm > s.hw_limit_cm or new.fw_cm < s.fw_limit_cm)
     and (new.cause is null or length(btrim(new.cause)) = 0) then
    raise exception
      'station % m in the % m round is past the cut and needs a cause',
      new.station_dist_m, new.round_dist_m;
  end if;
  return new;
end $$;

create trigger offset_station_cause_required
  before insert on offset_stations
  for each row execute function offset_station_cause_required();

-- ── structures ────────────────────────────────────────────────────────
-- Photos live in Storage, not in the row. A data URL in Postgres is
-- fine on a device and wrong here (open decision 29).
create table structures (
  id             uuid primary key default gen_random_uuid(),
  shift_id       uuid        references shift_records (id),
  observer       uuid        not null references profiles (id),
  section        geo_section not null,
  bord           text,

  type           text        not null,
  strike_deg     integer     check (strike_deg between 0 and 360),
  dip_deg        integer     check (dip_deg between 0 and 90),
  dip_direction  text,
  width_m        numeric(6,2),
  dist_from_face_m numeric(6,2),
  displacement_m numeric(6,2),          -- geological, NOT blast over-break
  confidence     text,
  note           text,

  photo_path     text,                  -- Storage object path, never a data URL
  photo_strokes  integer not null default 0,

  device         text,
  client_ts      timestamptz not null,
  created_at     timestamptz not null default now()
);
comment on column structures.displacement_m is
  'Geological displacement. Blast over-break is offset_stations, never this.';

-- ── audit ─────────────────────────────────────────────────────────────
create table audit_log (
  id         bigserial primary key,
  actor      uuid references profiles (id),
  action     text        not null,
  table_name text,
  row_id     text,
  detail     jsonb,
  at         timestamptz not null default now()
);

-- ═══════════════════════════════════════════════════════════════════════
-- THE AUTHORITATIVE FIGURES
--
-- Derived from the stations and the snapshotted limits. Not stored, not
-- submitted, not trusted from anywhere. This is the rework's "the server
-- recomputes every aggregate at ingest" made structural: there is no
-- ingest step to get wrong, because the number IS the derivation.
--
-- 200 cm is the mining-height flag. It is a mine threshold, not a
-- statutory one — change it here and in the app together.
-- ═══════════════════════════════════════════════════════════════════════

create or replace view offset_round_stats as
select
  s.id                                   as offset_set_id,
  st.round_dist_m,
  count(*)                               as stations,
  count(*) filter (where st.hw_cm > s.hw_limit_cm) as hw_breaches,
  count(*) filter (where st.fw_cm < s.fw_limit_cm) as fw_breaches,
  round(avg(st.hw_cm)::numeric, 2)       as mean_hw_cm,
  round(avg(st.fw_cm)::numeric, 2)       as mean_fw_cm,
  round(avg(st.mining_height_cm)::numeric, 2) as mean_mining_height_cm,
  round(avg(st.hw_cm - s.hw_limit_cm)
        filter (where st.hw_cm > s.hw_limit_cm)::numeric, 2) as mean_hw_excess_cm,
  round(avg(s.fw_limit_cm - st.fw_cm)
        filter (where st.fw_cm < s.fw_limit_cm)::numeric, 2) as mean_fw_excess_cm,
  bool_or(st.mining_height_cm > 200)     as height_flag,
  (s.hw_limit_cm - s.fw_limit_cm)        as design_cut_cm,
  round(((avg(st.mining_height_cm) - (s.hw_limit_cm - s.fw_limit_cm))
         / (s.hw_limit_cm - s.fw_limit_cm) * 100)::numeric, 1) as over_cut_pct
from offset_sets s
join offset_stations st on st.offset_set_id = s.id
group by s.id, st.round_dist_m, s.hw_limit_cm, s.fw_limit_cm;

create or replace view offset_set_stats as
select
  s.id                                   as offset_set_id,
  s.bord,
  s.section,
  s.observer,
  s.created_at,
  count(distinct st.round_dist_m)        as rounds,
  count(*)                               as stations,
  count(*) filter (where st.hw_cm > s.hw_limit_cm) as hw_breaches,
  count(*) filter (where st.fw_cm < s.fw_limit_cm) as fw_breaches,
  round(avg(st.hw_cm)::numeric, 2)       as mean_hw_cm,
  round(avg(st.fw_cm)::numeric, 2)       as mean_fw_cm,
  round(avg(st.mining_height_cm)::numeric, 2) as mean_mining_height_cm,
  round(avg(st.hw_cm - s.hw_limit_cm)
        filter (where st.hw_cm > s.hw_limit_cm)::numeric, 2) as mean_hw_excess_cm,
  round(avg(s.fw_limit_cm - st.fw_cm)
        filter (where st.fw_cm < s.fw_limit_cm)::numeric, 2) as mean_fw_excess_cm,
  bool_or(st.mining_height_cm > 200)     as height_flag,
  (s.hw_limit_cm - s.fw_limit_cm)        as design_cut_cm,
  round((avg(st.mining_height_cm) - (s.hw_limit_cm - s.fw_limit_cm))::numeric, 2)
                                         as vs_design_cut_cm,
  -- The one conversion for management. Everything above stays in cm.
  round((avg(st.mining_height_cm) / 100)::numeric, 2) as mean_mining_height_m
from offset_sets s
join offset_stations st on st.offset_set_id = s.id
group by s.id, s.bord, s.section, s.observer, s.created_at,
         s.hw_limit_cm, s.fw_limit_cm;

-- Where the handset and the server disagree. Not an error path — a
-- data-quality signal worth looking at, and the reason reported_stats
-- is kept at all.
create or replace view offset_stat_drift as
select
  v.offset_set_id,
  v.bord,
  v.mean_mining_height_cm                             as server_mean_height_cm,
  (s.reported_stats ->> 'meanHeight')::numeric        as device_mean_height_cm,
  round(v.mean_mining_height_cm
        - (s.reported_stats ->> 'meanHeight')::numeric, 2) as drift_cm,
  v.hw_breaches                                       as server_hw_breaches,
  (s.reported_stats ->> 'hwB')::integer               as device_hw_breaches
from offset_set_stats v
join offset_sets s on s.id = v.offset_set_id
where s.reported_stats is not null
  and (
    abs(v.mean_mining_height_cm
        - coalesce((s.reported_stats ->> 'meanHeight')::numeric, 0)) > 0.01
    or v.hw_breaches <> coalesce((s.reported_stats ->> 'hwB')::integer, -1)
  );

-- ═══════════════════════════════════════════════════════════════════════
-- RLS
--
-- Every table. Capture tables are INSERT + SELECT only: no UPDATE and no
-- DELETE policy exists for any role, so "never overwrite an observation"
-- is a property of the database rather than a habit of the app.
--
-- Reads are scoped to the caller's section. Chief Geologist and MRM
-- Manager read across sections; nobody else does, and the client cannot
-- widen it.
-- ═══════════════════════════════════════════════════════════════════════

alter table profiles        enable row level security;
alter table limit_sets      enable row level security;
alter table shift_records   enable row level security;
alter table face_logs       enable row level security;
alter table offset_sets     enable row level security;
alter table offset_stations enable row level security;
alter table structures      enable row level security;
alter table audit_log       enable row level security;

-- profiles: read your own row always; read your section; full read for
-- Chief Geologist and MRM Manager. Nobody self-assigns a role — there is
-- no INSERT or UPDATE policy, so provisioning is an admin action.
create policy profiles_read_self on profiles
  for select using (id = auth.uid());
create policy profiles_read_section on profiles
  for select using (section = current_section() or can_read_all());

-- limit_sets: everyone reads. Only the Chief Geologist writes a version.
create policy limits_read on limit_sets
  for select using (auth.uid() is not null);
create policy limits_insert_chief on limit_sets
  for insert with check (current_role_geo() = 'chief_geologist'
                         and authorised_by = auth.uid());

-- The capture tables. One INSERT policy each: you may only write rows
-- attributed to yourself, in your own section.
create policy shifts_insert on shift_records
  for insert with check (observer = auth.uid() and section = current_section());
create policy shifts_read on shift_records
  for select using (section = current_section() or can_read_all());

create policy facelogs_insert on face_logs
  for insert with check (observer = auth.uid() and section = current_section());
create policy facelogs_read on face_logs
  for select using (section = current_section() or can_read_all());

create policy offsets_insert on offset_sets
  for insert with check (observer = auth.uid() and section = current_section());
create policy offsets_read on offset_sets
  for select using (section = current_section() or can_read_all());

-- Stations inherit their parent's section; you may only attach them to
-- a set you own.
create policy stations_insert on offset_stations
  for insert with check (exists (
    select 1 from offset_sets s
    where s.id = offset_set_id and s.observer = auth.uid()));
create policy stations_read on offset_stations
  for select using (exists (
    select 1 from offset_sets s
    where s.id = offset_set_id
      and (s.section = current_section() or can_read_all())));

create policy structures_insert on structures
  for insert with check (observer = auth.uid() and section = current_section());
create policy structures_read on structures
  for select using (section = current_section() or can_read_all());

-- audit_log: append by anyone signed in, read by the reviewers.
create policy audit_insert on audit_log
  for insert with check (actor = auth.uid());
create policy audit_read on audit_log
  for select using (can_read_all() or current_role_geo() = 'section_geologist');

-- ── privileges: stated, not inherited ─────────────────────────────────
-- Supabase's default privileges grant ALL on new tables in `public` to
-- `anon` and `authenticated`. With no UPDATE policy, RLS already blocks
-- an overwrite — but it blocks it SILENTLY, as "0 rows affected", which a
-- client can easily read as success. Revoking the verb outright makes the
-- refusal loud, and means a policy added here by mistake in five years
-- still cannot reach the data. Belt and braces on the one rule that
-- matters most (§9.1).
revoke all on all tables in schema public from anon;
revoke update, delete, truncate on all tables in schema public from authenticated;

-- Provisioning is an administrative act, not a self-service one. There is
-- no INSERT policy on profiles and now no INSERT privilege either. NOTE:
-- this makes the field app's self-serve registration impossible against
-- this schema by design — open decisions 18 and 19 need a ruling before
-- either side changes.
revoke insert on profiles from authenticated;

-- Views run with the privileges of the querying user in PG15+ when
-- declared security_invoker, so RLS on the base tables applies to them.
alter view offset_round_stats set (security_invoker = on);
alter view offset_set_stats   set (security_invoker = on);
alter view offset_stat_drift  set (security_invoker = on);

-- ── indexes on the paths the dashboard actually reads ─────────────────
create index face_logs_shift_idx      on face_logs (shift_id);
create index face_logs_section_ts_idx on face_logs (section, created_at desc);
create index face_logs_flagged_idx    on face_logs (sample_flagged) where sample_flagged;
create index offset_sets_shift_idx    on offset_sets (shift_id);
create index offset_sets_section_ts_idx on offset_sets (section, created_at desc);
create index offset_stations_set_idx  on offset_stations (offset_set_id, round_dist_m);
create index structures_shift_idx     on structures (shift_id);

commit;

-- ═══════════════════════════════════════════════════════════════════════
-- STILL TO DO, and deliberately not guessed at here
--
-- · Seed limit_sets with the two sets in service. Left for the Chief
--   Geologist to run so `authorised_by` is a real person (§7.3).
-- · A Storage bucket for face photos, with a policy matching the
--   section scoping above (open decision 29).
-- · Rule R4 (§9.7) has no home in the app since the BMSZ screen was
--   removed, so it has no table here either. If a marking decision
--   returns, the block returns with it (open decision 23).
-- · `shift_records.shift_type` has no source: the field app never asks
--   which of A / B / C the shift is. Either it collects it or the column
--   goes; do not backfill a guess.
-- · Account recovery (open decision 22) — Supabase auth gives password
--   reset, but a technician underground has no email. Needs a ruling.
-- · Whether GeoTech writes a cycle state back to SLAM, or SLAM reads a
--   marking-exists flag. That crosses into another project's database
--   and is not this migration's business.
-- ═══════════════════════════════════════════════════════════════════════
