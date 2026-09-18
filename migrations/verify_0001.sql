-- ═══════════════════════════════════════════════════════════════════════
-- UNKI GEOTECH · verification suite for 0001_geotech_init.sql
--
-- A safety-critical schema should not be reviewed by reading it. This
-- runs it against a real Postgres and checks that the constraints, the
-- derived figures and the RLS policies actually do what the migration
-- claims. It asserts, among other things, the NS3 12-07-10 regression
-- target from CLAUDE.md — mean H/W 245.33, mean F/W -134.5, mean mining
-- height 379.83, mean H/W excess 95.33, mean F/W excess 34.5, 3.80 m to
-- management — computed server-side from the stations, not from the
-- handset's own numbers.
--
-- It writes rows, so run it on a THROWAWAY database. Never against the
-- GeoTech project and never, under any circumstances, against SLAM's.
--
--   initdb -D /tmp/pg -U postgres -A trust
--   pg_ctl -D /tmp/pg -o "-p 5488 -k /tmp/pg" start
--   createdb -p 5488 -h /tmp/pg -U postgres geotech_verify
--   psql -p 5488 -h /tmp/pg -U postgres -d geotech_verify \
--        -v ON_ERROR_STOP=1 -f migrations/verify_0001.sql
--
-- Expected last line: 0 failed of 58 checks
-- ═══════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on
\echo '── harness: the pieces Supabase supplies ──'
-- Harness only: the bits Supabase supplies. NOT part of the migration.
create schema if not exists auth;
create table auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid
  language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public, auth to anon, authenticated;
grant select on auth.users to anon, authenticated;
-- Supabase's own default privileges, reproduced so the RLS test is realistic.
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;

\echo '── applying the migration under test ──'
\i migrations/0001_geotech_init.sql

\echo '── checks ──'
create table tres(n int generated always as identity, label text, pass boolean, note text);
create or replace function t(l text, p boolean, note text default null) returns void
  language sql as $$ insert into tres(label,pass,note) values (l,p,note) $$;
-- rejects(sql) — true when the statement is refused by the database.
create or replace function rejects(stmt text) returns boolean language plpgsql as $$
begin execute stmt; return false;
exception when others then return true; end $$;

-- ── seed ──────────────────────────────────────────────────────────────
insert into auth.users(id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333');
insert into profiles(id, employee_no, full_name, role, section) values
  ('11111111-1111-1111-1111-111111111111','UK-4471','T. Chidindi','geological_technician','14 South'),
  ('22222222-2222-2222-2222-222222222222','UK-0001','C. Geologist','chief_geologist','16 North'),
  ('33333333-3333-3333-3333-333333333333','UK-9002','N. Other','geological_technician','16 North');

-- A limit SET is both headings of one version — the bug this caught.
insert into limit_sets(version,heading,hw_limit_cm,fw_limit_cm,label,source,authorised_by) values
  ('2026-09-CG-REWORK','bord',    45,-135,'Bord / ledging decline','Sheet 2NB3 12-07-10','22222222-2222-2222-2222-222222222222'),
  ('2026-09-CG-REWORK','decline',150,-100,'Decline / strike drive','Sheets MM 26-04-10, NS3 12-07-10','22222222-2222-2222-2222-222222222222');
select t('both headings of one limit version coexist',
         (select count(*) from limit_sets where version='2026-09-CG-REWORK') = 2);
select t('design cut derives to 1.80 m bord / 2.50 m decline',
         (select array_agg((hw_limit_cm-fw_limit_cm) order by heading) from limit_sets) = array[180,250]);

insert into shift_records(id,observer,section,shift_name,started_at,client_ts) values
  ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','14 South','Morning',now(),now());

-- ── the NS3 regression target (CLAUDE.md, sheet NS3 12-07-10) ─────────
insert into face_logs(id,shift_id,observer,section,bord,face_length_m,channel_id,
                      dist_to_face_m,area_safe,miner_name,client_ts)
values ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111','14 South','NS3',7.2,'CH-NS3',11,
        true,'P. Ncube (Miner)',now());

insert into offset_sets(id,shift_id,face_log_id,observer,section,bord,heading,face_length_m,
                        limit_version,limit_label,hw_limit_cm,fw_limit_cm,reported_stats,client_ts)
values ('cccccccc-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
        '14 South','NS3','decline',7.2,'2026-09-CG-REWORK','Decline / strike drive',150,-100,
        '{"meanHeight":379.83,"hwB":6}'::jsonb, now());

insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm,cause)
select 'cccccccc-0000-0000-0000-000000000001', 2, i,
       (array[245,247,251,243,242,244])[i], (array[-132,-134,-132,-137,-134,-138])[i],
       'Over-charging / excess explosive'
from generate_series(1,6) i;

select t('NS3 stations = 6',        (select stations from offset_round_stats where round_dist_m=2) = 6);
select t('NS3 mean H/W 245.33',     (select mean_hw_cm from offset_round_stats where round_dist_m=2) = 245.33);
select t('NS3 mean F/W -134.50',    (select mean_fw_cm from offset_round_stats where round_dist_m=2) = -134.50);
select t('NS3 mean mining height 379.83',
         (select mean_mining_height_cm from offset_round_stats where round_dist_m=2) = 379.83);
select t('NS3 mean H/W excess 95.33',
         (select mean_hw_excess_cm from offset_round_stats where round_dist_m=2) = 95.33);
select t('NS3 mean F/W excess 34.50',
         (select mean_fw_excess_cm from offset_round_stats where round_dist_m=2) = 34.50);
select t('NS3 reaches management as 3.80 m',
         (select mean_mining_height_m from offset_set_stats) = 3.80);
select t('NS3 breaches 6/6 on both walls',
         (select hw_breaches=6 and fw_breaches=6 from offset_set_stats));
select t('NS3 trips the 200 cm height flag', (select height_flag from offset_set_stats));
select t('NS3 over cut ~52%', (select over_cut_pct from offset_round_stats where round_dist_m=2) = 51.9,
         (select over_cut_pct::text from offset_round_stats where round_dist_m=2));
select t('mining height is derived, not entered',
         (select bool_and(mining_height_cm = hw_cm - fw_cm) from offset_stations));
select t('past 9 m the face is flagged for sampling', (select sample_flagged from face_logs));

-- the handset agrees, so there is no drift to report
select t('no drift when device and server agree', (select count(*) from offset_stat_drift) = 0);
update offset_sets set reported_stats = '{"meanHeight":300.00,"hwB":2}'::jsonb;
select t('drift view catches a device disagreeing', (select count(*) from offset_stat_drift) = 1,
         (select drift_cm::text from offset_stat_drift));
update offset_sets set reported_stats = '{"meanHeight":379.83,"hwB":6}'::jsonb;

-- ── the standard, as constraints ──────────────────────────────────────
select t('F/W must be negative', rejects($$insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm,cause)
  values ('cccccccc-0000-0000-0000-000000000001',5,1,245,132,'x')$$));
select t('no station zero', rejects($$insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm,cause)
  values ('cccccccc-0000-0000-0000-000000000001',5,0,245,-132,'x')$$));
select t('only the 2 m and 5 m rounds', rejects($$insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm,cause)
  values ('cccccccc-0000-0000-0000-000000000001',3,1,245,-132,'x')$$));
select t('a station past the cut needs a cause', rejects($$insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm)
  values ('cccccccc-0000-0000-0000-000000000001',5,1,245,-132)$$));
select t('a station within the cut needs none', not rejects($$insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm)
  values ('cccccccc-0000-0000-0000-000000000001',5,1,140,-90)$$));
select t('one reading per station per round', rejects($$insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm)
  values ('cccccccc-0000-0000-0000-000000000001',5,1,141,-91)$$));
select t('a face not made safe cannot be written', rejects($$insert into face_logs(observer,section,bord,face_length_m,area_safe,miner_name,client_ts)
  values ('11111111-1111-1111-1111-111111111111','14 South','X',7.2,false,'P. Ncube',now())$$));
select t('a face with no named miner cannot be written', rejects($$insert into face_logs(observer,section,bord,face_length_m,area_safe,miner_name,client_ts)
  values ('11111111-1111-1111-1111-111111111111','14 South','X',7.2,true,'   ',now())$$));
select t('a section outside 14 South / 16 North cannot be written',
  rejects($$insert into face_logs(observer,section,bord,face_length_m,area_safe,miner_name,client_ts)
  values ('11111111-1111-1111-1111-111111111111','12 East','X',7.2,true,'P. Ncube',now())$$));
select t('the station interval is 1 m, not a choice',
  rejects($$insert into offset_sets(observer,section,bord,heading,face_length_m,interval_m,
    limit_version,limit_label,hw_limit_cm,fw_limit_cm,client_ts)
  values ('11111111-1111-1111-1111-111111111111','14 South','Y','bord',7.2,2,'v','l',45,-135,now())$$));
select t('a limit set with a positive F/W cannot be written',
  rejects($$insert into limit_sets(version,heading,hw_limit_cm,fw_limit_cm,label,source,authorised_by)
  values ('bad','bord',45,135,'l','s','22222222-2222-2222-2222-222222222222')$$));

-- 16 North face, for the section-scoping tests below.
insert into face_logs(shift_id,observer,section,bord,face_length_m,area_safe,miner_name,client_ts)
values (null,'33333333-3333-3333-3333-333333333333','16 North','16N B4',7.2,true,'S. Moyo (Miner)',now());
\set tech '11111111-1111-1111-1111-111111111111'
\set chief '22222222-2222-2222-2222-222222222222'

-- ── as the 14 South technician ────────────────────────────────────────
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :'tech';
select t('technician is who the server says, not who the client claims',
         (select employee_no from profiles where id = auth.uid()) = 'UK-4471');
select t('sees own section''s faces', (select count(*) from face_logs where section='14 South') = 1);
select t('cannot see another section''s faces', (select count(*) from face_logs where section='16 North') = 0);
select t('views inherit RLS (security_invoker)', (select count(*) from offset_set_stats) = 1);

-- append-only: no UPDATE and no DELETE policy exists, for anyone
select t('cannot overwrite an observation',
  rejects($$update face_logs set miner_name='Someone Else'$$));
select t('cannot delete an observation', rejects($$delete from face_logs$$));
select t('cannot alter a station reading',
  rejects($$update offset_stations set hw_cm = 1$$));
select t('cannot revise a limit set in place',
  rejects($$update limit_sets set hw_limit_cm = 999$$));
select t('the observation survived',
         (select miner_name from face_logs where bord='NS3') = 'P. Ncube (Miner)');

-- attribution cannot be forged
select t('cannot sign a face log with someone else''s name',
  rejects($$insert into face_logs(observer,section,bord,face_length_m,area_safe,miner_name,client_ts)
    values ('33333333-3333-3333-3333-333333333333','14 South','Z',7.2,true,'P. Ncube',now())$$));
select t('cannot write into another section',
  rejects($$insert into face_logs(observer,section,bord,face_length_m,area_safe,miner_name,client_ts)
    values ('11111111-1111-1111-1111-111111111111','16 North','Z',7.2,true,'P. Ncube',now())$$));
select t('a technician cannot author a limit set (§7.3 is the Chief''s)',
  rejects($$insert into limit_sets(version,heading,hw_limit_cm,fw_limit_cm,label,source,authorised_by)
    values ('tech-made','bord',45,-135,'l','s','11111111-1111-1111-1111-111111111111')$$));
select t('cannot forge an audit row as someone else',
  rejects($$insert into audit_log(actor,action) values ('22222222-2222-2222-2222-222222222222','faked')$$));
select t('can append an audit row as self',
  not rejects($$insert into audit_log(actor,action) values ('11111111-1111-1111-1111-111111111111','signed in')$$));
select t('a technician cannot read the audit log', (select count(*) from audit_log) = 0);
select t('can write own face log',
  not rejects($$insert into face_logs(observer,section,bord,face_length_m,area_safe,miner_name,client_ts)
    values ('11111111-1111-1111-1111-111111111111','14 South','14S B2',6.2,true,'P. Ncube',now())$$));
commit;

-- ── as the Chief Geologist ────────────────────────────────────────────
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = :'chief';
select t('Chief reads across sections', (select count(*) from face_logs) = 3);
select t('Chief reads the audit log', (select count(*) from audit_log) = 1);
select t('Chief can author a limit set',
  not rejects($$insert into limit_sets(version,heading,hw_limit_cm,fw_limit_cm,label,source,authorised_by)
    values ('2027-01-CG','bord',50,-130,'revised','CG ruling','22222222-2222-2222-2222-222222222222')$$));
select t('Chief cannot author one in another''s name',
  rejects($$insert into limit_sets(version,heading,hw_limit_cm,fw_limit_cm,label,source,authorised_by)
    values ('2027-02-CG','bord',50,-130,'revised','CG ruling','11111111-1111-1111-1111-111111111111')$$));
select t('a revised limit is a new version, not an edit',
         (select count(distinct version) from limit_sets) = 2);
select t('the old face still reports against the limits that judged it',
         (select hw_limit_cm from offset_sets) = 150);
select t('not even the Chief Geologist can overwrite an observation',
  rejects($$update face_logs set miner_name='Chief Edit'$$));
commit;

-- ── as an anonymous visitor ───────────────────────────────────────────
begin;
set local role anon;
select t('an anonymous reader cannot even read the table',
  rejects($$select count(*) from face_logs$$));
commit;
-- A 16 North offset set with its own stations, seeded past RLS so the
-- 14 South technician's reads have something they must NOT return.
insert into offset_sets(id,observer,section,bord,heading,face_length_m,
                        limit_version,limit_label,hw_limit_cm,fw_limit_cm,client_ts)
values ('dddddddd-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333',
        '16 North','16N B4','bord',7.2,'2026-09-CG-REWORK','Bord / ledging decline',45,-135,now());
insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm)
select 'dddddddd-0000-0000-0000-000000000001',2,i,40,-130 from generate_series(1,6) i;

select t('the store holds stations from both sections',
  (select count(*) from offset_stations) = 13, (select count(*)::text from offset_stations));

begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';
select t('technician sees only their own section''s stations',
  (select count(*) from offset_stations) = 7, (select count(*)::text from offset_stations));
select t('technician sees only their own section''s offset sets',
  (select count(*) from offset_sets) = 1);
select t('the other section''s face never reaches the dashboard view',
  (select count(*) from offset_set_stats where section = '16 North') = 0);
select t('cannot attach stations to a set that is not yours',
  rejects($$insert into offset_stations(offset_set_id,round_dist_m,station_dist_m,hw_cm,fw_cm)
    values ('dddddddd-0000-0000-0000-000000000001',5,9,40,-130)$$));
commit;

select t('confirmed past RLS: the other set still has exactly its 6 stations',
  (select count(*) from offset_stations
   where offset_set_id='dddddddd-0000-0000-0000-000000000001') = 6);

begin;
set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-2222-2222-222222222222';
select t('Chief sees every section''s stations',
  (select count(*) from offset_stations) = 13, (select count(*)::text from offset_stations));
commit;

\echo ''
\pset tuples_only on
select case when pass then 'ok   ' else 'FAIL ' end || label
       || coalesce(' — ' || note, '') from tres order by n;
select '';
select count(*) filter (where not pass) || ' failed of ' || count(*) || ' checks' from tres;
\pset tuples_only off
