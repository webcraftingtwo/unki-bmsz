-- ═══════════════════════════════════════════════════════════════════════
-- UNKI GEOTECH · 0003 · get the helper functions out of the public API
--
-- APPLIED to project `GeoTech` (finnereptajssuzshrrc) on 2026-09-24.
--
-- Supabase's security linter caught three things, and one of them was
-- worth having caught: every function in `public` is exposed by PostgREST
-- as an RPC endpoint. That meant `handle_new_geotech_user()` — the
-- SECURITY DEFINER trigger that creates profiles — was callable by
-- anyone, signed in or not, at /rest/v1/rpc/handle_new_geotech_user. It
-- would error without a trigger context rather than do damage, but a
-- security-definer function that writes profiles has no business being
-- on the public API surface.
--
-- `current_role_geo()` and `current_section()` were exposed the same way.
-- Those only ever return the CALLER's own role and section, so the
-- exposure was not a leak, but there is no reason for them to be callable.
--
-- The fix is placement, not permission: revoking EXECUTE would break the
-- RLS policies, which have to call these as the querying role. A schema
-- outside PostgREST's exposed list (`public, graphql_public`) is not
-- reachable over HTTP at all, while policies can still call into it.
--
-- `can_read_all()` also had a mutable search_path. Set here.
--
-- After this migration the linter reports no findings, and the RLS suite
-- still passes unchanged.
-- ═══════════════════════════════════════════════════════════════════════

create schema if not exists geo_private;
comment on schema geo_private is
  'Not in PostgREST''s exposed schemas, so nothing here is reachable over HTTP. RLS helpers and trigger functions only.';

grant usage on schema geo_private to authenticated, anon;

-- ── the helpers, re-homed ─────────────────────────────────────────────
create function geo_private.current_role_geo() returns geo_role
  language sql stable security definer set search_path = public as $$
    select role from profiles where id = auth.uid() and active
  $$;

create function geo_private.current_section() returns geo_section
  language sql stable security definer set search_path = public as $$
    select section from profiles where id = auth.uid() and active
  $$;

create function geo_private.can_read_all() returns boolean
  language sql stable set search_path = public, geo_private as $$
    select geo_private.current_role_geo() in ('chief_geologist', 'mrm_manager')
  $$;

-- ── policies, repointed ───────────────────────────────────────────────
drop policy profiles_read_self    on profiles;
drop policy profiles_read_section on profiles;
drop policy limits_read           on limit_sets;
drop policy limits_insert_chief   on limit_sets;
drop policy shifts_insert         on shift_records;
drop policy shifts_read           on shift_records;
drop policy facelogs_insert       on face_logs;
drop policy facelogs_read         on face_logs;
drop policy offsets_insert        on offset_sets;
drop policy offsets_read          on offset_sets;
drop policy stations_insert       on offset_stations;
drop policy stations_read         on offset_stations;
drop policy structures_insert     on structures;
drop policy structures_read       on structures;
drop policy audit_insert          on audit_log;
drop policy audit_read            on audit_log;

create policy profiles_read_self on profiles
  for select using (id = auth.uid());
create policy profiles_read_section on profiles
  for select using (section = geo_private.current_section() or geo_private.can_read_all());

create policy limits_read on limit_sets
  for select using (auth.uid() is not null);
create policy limits_insert_chief on limit_sets
  for insert with check (geo_private.current_role_geo() = 'chief_geologist'
                         and authorised_by = auth.uid());

create policy shifts_insert on shift_records
  for insert with check (observer = auth.uid() and section = geo_private.current_section());
create policy shifts_read on shift_records
  for select using (section = geo_private.current_section() or geo_private.can_read_all());

create policy facelogs_insert on face_logs
  for insert with check (observer = auth.uid() and section = geo_private.current_section());
create policy facelogs_read on face_logs
  for select using (section = geo_private.current_section() or geo_private.can_read_all());

create policy offsets_insert on offset_sets
  for insert with check (observer = auth.uid() and section = geo_private.current_section());
create policy offsets_read on offset_sets
  for select using (section = geo_private.current_section() or geo_private.can_read_all());

-- Stations inherit their parent's section.
create policy stations_insert on offset_stations
  for insert with check (exists (
    select 1 from offset_sets s
    where s.id = offset_set_id and s.observer = auth.uid()));
create policy stations_read on offset_stations
  for select using (exists (
    select 1 from offset_sets s
    where s.id = offset_set_id
      and (s.section = geo_private.current_section() or geo_private.can_read_all())));

create policy structures_insert on structures
  for insert with check (observer = auth.uid() and section = geo_private.current_section());
create policy structures_read on structures
  for select using (section = geo_private.current_section() or geo_private.can_read_all());

create policy audit_insert on audit_log
  for insert with check (actor = auth.uid());
create policy audit_read on audit_log
  for select using (geo_private.can_read_all()
                    or geo_private.current_role_geo() = 'section_geologist');

-- ── trigger functions, re-homed ───────────────────────────────────────
create function geo_private.handle_new_geotech_user()
  returns trigger language plpgsql security definer set search_path = public as $$
declare
  md        jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_emp     text  := btrim(coalesce(md ->> 'employee_no', ''));
  v_name    text  := btrim(coalesce(md ->> 'full_name', ''));
  v_section text  := btrim(coalesce(md ->> 'section', ''));
begin
  if v_emp = '' then raise exception 'employee number is required'; end if;
  if v_name = '' then raise exception 'full name is required'; end if;
  if v_section not in ('14 South', '16 North') then
    raise exception 'section must be 14 South or 16 North';
  end if;

  -- Role is still not read from md. Still not a typo.
  insert into profiles (id, employee_no, full_name, role, section,
                        role_source, section_source)
  values (new.id, v_emp, v_name, 'geological_technician', v_section::geo_section,
          'self-declared', 'self-declared');
  return new;
end $$;

create function geo_private.offset_station_cause_required() returns trigger
  language plpgsql set search_path = public as $$
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

drop trigger on_auth_user_created_geotech on auth.users;
create trigger on_auth_user_created_geotech
  after insert on auth.users
  for each row execute function geo_private.handle_new_geotech_user();

drop trigger offset_station_cause_required on offset_stations;
create trigger offset_station_cause_required
  before insert on offset_stations
  for each row execute function geo_private.offset_station_cause_required();

-- Nothing left in public but tables and views.
drop function public.handle_new_geotech_user();
drop function public.offset_station_cause_required();
drop function public.can_read_all();
drop function public.current_section();
drop function public.current_role_geo();
