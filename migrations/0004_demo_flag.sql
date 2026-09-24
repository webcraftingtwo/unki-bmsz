-- ═══════════════════════════════════════════════════════════════════════
-- UNKI GEOTECH · 0004 · a demo flag on the capture tables
--
-- APPLIED to project `GeoTech` (finnereptajssuzshrrc) on 2026-09-24.
--
-- Seeded demonstration data went into this project so the dashboard has
-- something to show. On the device store such rows carry `demo:true`,
-- review.html says so in a banner, and its "remove" touches nothing
-- without that flag. The server had no equivalent, which would have left
-- fifty invented faces sitting in the same tables as real measurement,
-- indistinguishable from it.
--
-- That is the failure this column exists to prevent. An over-break
-- figure nobody measured must never be able to pass as one somebody
-- walked a face to get.
--
-- Default false, so a row written by the field app is real unless
-- something deliberately says otherwise — the app never sets it.
-- ═══════════════════════════════════════════════════════════════════════

alter table face_logs     add column demo boolean not null default false;
alter table offset_sets   add column demo boolean not null default false;
alter table structures    add column demo boolean not null default false;
alter table shift_records add column demo boolean not null default false;

comment on column face_logs.demo is
  'Seeded demonstration data. Never set by the field app. review.html says so on every affected row.';
comment on column offset_sets.demo is
  'Seeded demonstration data. Never set by the field app. review.html says so on every affected row.';
comment on column structures.demo is
  'Seeded demonstration data. Never set by the field app. review.html says so on every affected row.';
comment on column shift_records.demo is
  'Seeded demonstration data. Never set by the field app. review.html says so on every affected row.';

-- Finding them is cheap, and worth having as a view rather than a query
-- people have to remember.
create or replace view demo_inventory as
  select 'face_logs'     as table_name, count(*) as rows from face_logs     where demo
  union all select 'offset_sets',   count(*) from offset_sets   where demo
  union all select 'structures',    count(*) from structures    where demo
  union all select 'shift_records', count(*) from shift_records where demo
  union all select 'offset_stations', count(*) from offset_stations
    where offset_set_id in (select id from offset_sets where demo);
alter view demo_inventory set (security_invoker = on);

-- ── REMOVING THE DEMO DATA ─────────────────────────────────────────────
-- The capture tables have no UPDATE or DELETE policy, by design, so this
-- cannot be done from the app by anybody. It is an administrative act
-- against the database. Order matters: stations before their parent set,
-- and the demo technicians last, because their profiles are referenced
-- by every row they "captured".
--
--   delete from offset_stations where offset_set_id in
--     (select id from offset_sets where demo);
--   delete from offset_sets   where demo;
--   delete from structures    where demo;
--   delete from face_logs     where demo;
--   delete from shift_records where demo;
--   delete from auth.users where email like 'demo-%@geotech.unki.invalid';
--
-- The last line cascades to the demo profiles. It does NOT touch a real
-- account: those do not carry the `demo-` prefix.
