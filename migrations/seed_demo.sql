-- ═══════════════════════════════════════════════════════════════════════
-- UNKI GEOTECH · seeded demonstration data — 50 faces
--
-- RUN against project `GeoTech` (finnereptajssuzshrrc) on 2026-09-24.
-- This is DATA, not schema, which is why it is not a numbered migration.
-- It requires 0004 (the demo flag) to have been applied first.
--
-- NOTHING HERE WAS MEASURED. Fifty invented faces, six hundred invented
-- station readings, seventeen invented structures. Every row carries
-- `demo = true`, the technicians who "captured" them are named "(demo)",
-- and review.html says so in a banner and on every affected row. Do not
-- remove any of those markings; they are the only thing standing between
-- this data and a report.
--
-- It is deterministic, not random: the same input gives the same output,
-- so the figures can be reasoned about and reproduced. `reported_stats`
-- is left NULL throughout, because no handset computed these — which
-- also keeps them out of `offset_stat_drift`, correctly.
--
-- To remove it all, see the foot of migrations/0004_demo_flag.sql.
-- ═══════════════════════════════════════════════════════════════════════

-- ── 1 · demo technicians ──────────────────────────────────────────────
-- Their profiles are created by the trigger from 0002/0003, which means
-- they are created as geological_technician like anybody else. Passwords
-- are random and discarded: nobody signs in as these people.
with people(emp, nm, sec) as (values
  ('DEMO-4471','T. Chidindi (demo)','14 South'),
  ('DEMO-4890','P. Sibanda (demo)', '14 South'),
  ('DEMO-5310','L. Mutasa (demo)',  '14 South'),
  ('DEMO-5102','R. Mabhena (demo)', '16 North'),
  ('DEMO-5744','N. Gumbo (demo)',   '16 North')
), made as (
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change)
  select '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
         'authenticated','authenticated',
         'demo-' || lower(p.emp) || '@geotech.unki.invalid',
         extensions.crypt(encode(extensions.gen_random_bytes(24),'hex'),
                          extensions.gen_salt('bf')),
         now(),
         '{"provider":"email","providers":["email"]}'::jsonb,
         jsonb_build_object('employee_no', p.emp, 'full_name', p.nm, 'section', p.sec),
         now(), now(), '', '', '', ''
  from people p
  returning id, email)
insert into auth.identities (id, provider_id, user_id, identity_data, provider,
                             last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), m.id::text, m.id,
       jsonb_build_object('sub', m.id::text, 'email', m.email, 'email_verified', true),
       'email', now(), now(), now()
from made m;

-- ── 2 · the fifty face specifications ─────────────────────────────────
create temp table seed as
with idx as (select generate_series(1,50) as i),
base as (
  select i,
    (array['14S B1','14S B2','14S B3','14S B4','14S B5','14S B6','14S B7','14S B8',
           '16N B1','16N B2','16N B3','16N B4','16N B5','16N B6','16N B7','16N B8',
           '16N B9','16N Strike'])[1 + ((i*7) % 18)] as bord,
    (i*7) % 10 as severity,
    (array[5.2,6.2,7.2,8.2,9.2])[1 + (i % 5)] as face_length,
    (i % 13)::numeric as dist_to_face,
    (array['1','2','3','S'])[1 + (i % 4)] as tarp,
    (array['Over-charging / excess explosive','Hole deviation — drilling alignment',
           'Rig not aligned to BMSZ sidewall mark','Incorrect burden or spacing',
           'Sockets / misfire redrill','Poor ground conditions',
           'Support installation requirement','Marking not followed by crew',
           'Other — see notes'])[1 + (i % 9)] as cause,
    (now() - ((50 - i) * 17 || ' hours')::interval) as ts
  from idx
), typed as (
  select b.*,
    case when b.bord like '14S%' then '14 South' else '16 North' end::geo_section as section,
    case when b.bord = '16N Strike' or b.i % 4 = 0 then 'decline' else 'bord' end::geo_heading as heading
  from base b
)
select t.*,
  case when t.heading = 'bord' then 45  else 150  end as hw_limit,
  case when t.heading = 'bord' then -135 else -100 end as fw_limit,
  (floor(t.face_length)::int - 1) as n_stations,
  (select p.id from profiles p
    where p.section = t.section and p.employee_no like 'DEMO-%'
    order by p.employee_no
    offset (t.i % (select count(*) from profiles p2
                    where p2.section = t.section and p2.employee_no like 'DEMO-%'))
    limit 1) as observer
from typed t;

-- ── 3 · shifts, face logs, offset sets ────────────────────────────────
insert into shift_records (observer, section, shift_name, started_at, ended_at,
                           device, client_ts, created_at, demo)
select distinct observer, section, 'Morning',
       ts::date + time '06:30', ts::date + time '15:00',
       'demo-seed', ts::date + time '06:30', ts::date + time '06:30', true
from seed;

create temp table seed_log as
with ins as (
  insert into face_logs (shift_id, observer, section, bord, level, peg, advance_m,
                         face_length_m, face_width_m, face_height_m,
                         channel_id, dist_to_face_m, tarp, structural,
                         area_safe, miner_name, team, readiness, source,
                         device, client_ts, created_at, demo)
  select
    (select sr.id from shift_records sr
      where sr.observer = s.observer and sr.started_at::date = s.ts::date and sr.demo limit 1),
    s.observer, s.section, s.bord,
    case when s.section = '14 South' then '2 Level' else '3 Level' end,
    'SP-' || case when s.section='14 South' then '2S' else '3N' end || '-' ||
      lpad(((s.i * 13) % 200)::text, 3, '0'),
    round((1.7 + (s.i % 9) * 0.1)::numeric, 2),
    s.face_length,
    round((5.9 + (s.i % 7) * 0.2)::numeric, 2),
    round((1.7 + (s.i % 11) * 0.2)::numeric, 2),
    'CH-' || replace(s.bord, ' ', '') || '-' || lpad((s.i % 40)::text, 2, '0'),
    s.dist_to_face, s.tarp::geo_tarp,
    case when s.severity >= 8 then 'Heavy over-break on both walls; blast practice review requested.'
         when s.severity <= 2 then 'Clean profile, within cut on both walls.'
         else null end,
    true,
    (array['P. Ncube (Miner)','S. Moyo (Miner)','K. Dube (Miner)',
           'J. Phiri (Miner)','M. Zulu (Miner)','T. Banda (Miner)'])[1 + (s.i % 6)],
    case when s.i % 3 = 0 then array['Shift Boss (S/B)','Miner','Team Leader']
         when s.i % 3 = 1 then array['Shift Boss (S/B)','Miner']
         else array['Miner'] end,
    '{"End is supported":true,"End is lashed to the footwall":true}'::jsonb,
    'manual', 'demo-seed', s.ts, s.ts, true
  from seed s
  returning id, bord, observer, created_at)
select * from ins;

create temp table seed_set as
with ins as (
  insert into offset_sets (shift_id, face_log_id, observer, section, bord, heading,
                           face_length_m, interval_m, limit_version, limit_label,
                           hw_limit_cm, fw_limit_cm, reported_stats,
                           device, client_ts, created_at, demo)
  select
    (select sr.id from shift_records sr
      where sr.observer = s.observer and sr.started_at::date = s.ts::date and sr.demo limit 1),
    (select fl.id from seed_log fl
      where fl.bord = s.bord and fl.observer = s.observer and fl.created_at = s.ts limit 1),
    s.observer, s.section, s.bord, s.heading,
    s.face_length, 1, '2026-09-CG-REWORK',
    case when s.heading='bord' then 'Bord / ledging decline' else 'Decline / strike drive' end,
    s.hw_limit, s.fw_limit,
    null,                        -- no handset computed these
    'demo-seed', s.ts + interval '25 minutes', s.ts + interval '25 minutes', true
  from seed s
  returning id, bord, observer, created_at)
select * from ins;

-- ── 4 · stations ──────────────────────────────────────────────────────
-- The index is recovered from the sets' own created_at order, so this
-- step does not depend on the temp tables above surviving.
with numbered as (
  select os.*, row_number() over (order by os.created_at) as i
  from offset_sets os where os.demo
), spec as (
  select n.*, (n.i * 7) % 10 as severity,
    (floor(n.face_length_m)::int - 1) as n_stations,
    (array['Over-charging / excess explosive','Hole deviation — drilling alignment',
           'Rig not aligned to BMSZ sidewall mark','Incorrect burden or spacing',
           'Sockets / misfire redrill','Poor ground conditions',
           'Support installation requirement','Marking not followed by crew',
           'Other — see notes'])[1 + (n.i % 9)] as cause
  from numbered n
), grid as (
  select s.*, st.station, rd.round_dist
  from spec s
  cross join lateral generate_series(1, s.n_stations) as st(station)
  cross join lateral (values (2), (5)) as rd(round_dist)
), valued as (
  select g.*,
    case when g.heading = 'bord'
      then 36 + g.severity * 3  + (((g.i * g.station * 13) % 7) - 3)
      else 140 + g.severity * 13 + (((g.i * g.station * 13) % 7) - 3)
    end
    + case when g.round_dist = 5 then ((g.i + g.station) % 5) - 2 else 0 end as hw_cm,
    case when g.heading = 'bord'
      then -128 - g.severity * 3 - (((g.i * g.station * 11) % 5) - 2)
      else  -92 - g.severity * 5 - (((g.i * g.station * 11) % 5) - 2)
    end
    - case when g.round_dist = 5 then ((g.i * g.station) % 5) - 2 else 0 end as fw_cm
  from grid g
)
insert into offset_stations (offset_set_id, round_dist_m, station_dist_m,
                             hw_cm, fw_cm, cause)
select v.id, v.round_dist, v.station, v.hw_cm, v.fw_cm,
       -- The trigger refuses a station past the cut with no cause, so
       -- this is not decoration.
       case when v.hw_cm > v.hw_limit_cm or v.fw_cm < v.fw_limit_cm
            then v.cause else null end
from valued v;

-- ── 5 · structures, on a third of the faces ───────────────────────────
-- photo_path stays null: there is no Storage bucket, so a seeded
-- structure has no image, exactly as a real one synced today would not.
with numbered as (
  select fl.*, row_number() over (order by fl.created_at) as i
  from face_logs fl where fl.demo
)
insert into structures (shift_id, observer, section, bord, type, strike_deg, dip_deg,
                        dip_direction, width_m, dist_from_face_m, displacement_m,
                        confidence, note, photo_path, photo_strokes,
                        device, client_ts, created_at, demo)
select n.shift_id, n.observer, n.section, n.bord,
  (array['Fault','Dyke','Xenolith','Vein','Replacement pegmatite','Shear',
         'Sill','Autolith'])[1 + (n.i % 8)],
  ((n.i * 37) % 360), ((n.i * 17) % 90),
  (array['NE','SE','SW','NW','N','S','E','W'])[1 + (n.i % 8)],
  round((0.2 + (n.i % 9) * 0.15)::numeric, 2),
  round((0.4 + (n.i % 6) * 0.45)::numeric, 2),
  case when (n.i % 8) = 0 then round((0.3 + (n.i % 5) * 0.2)::numeric, 2) else null end,
  (array['Certain','Probable','Possible'])[1 + (n.i % 3)],
  (array['Oblique to layering; reef offset down-dip, marking stepped accordingly.',
         'Dolerite. Wet contact on the north side — standing water in the footwall.',
         'Isolated fragment in the hangingwall. Lashed to waste.',
         'Late fluid-derived, carbonate filled. Thin and discontinuous.',
         'Coarse pyroxenite replacing reef, undulatory contacts. PGE barren — to waste.',
         'Deformation without displacement; no offset measured on the contact.',
         'Concordant sheet, not common at this level.',
         'Inclusion related to the host; no grade implication.'])[1 + (n.i % 8)],
  null, 0, 'demo-seed', n.created_at + interval '40 minutes',
  n.created_at + interval '40 minutes', true
from numbered n
where n.i % 3 = 1;

-- ── what it produced, as run ──────────────────────────────────────────
--   50 shift_records · 50 face_logs · 50 offset_sets · 600 offset_stations
--   17 structures · 0 rows left unmarked
--   bord    35 faces, mean 190 cm against a 180 cm cut, 24 over / 11 within
--   decline 15 faces, mean 312 cm against a 250 cm cut, 12 over /  3 within
--
-- Note that all fifteen decline faces trip the 200 cm height flag. That
-- is not a fault in the data — it is open decision 35 appearing in it.
-- The flag is a flat threshold and the decline design cut is 250 cm, so
-- a decline face flags even when it is exactly on cut.
