-- ═══════════════════════════════════════════════════════════════════════
-- UNKI GEOTECH · 0002 · how a profile comes into existence
--
-- APPLIED to project `GeoTech` (finnereptajssuzshrrc) on 2026-09-24.
--
-- 0001 left `profiles` with no INSERT policy and no INSERT privilege, on
-- the reasoning that provisioning is an administrative act (open
-- decisions 18 and 19). That is the right shape and it also makes the
-- app's self-serve registration impossible, so something had to give.
--
-- This is the narrow resolution: a profile is created by a trigger on
-- auth.users, not by the client. The client still cannot write to
-- profiles. What the client CAN do is hand over signup metadata, and the
-- trigger decides what to believe:
--
--   · ROLE IS NEVER BELIEVED. Everyone is created a geological_technician
--     no matter what the form said. A self-declared `chief_geologist`
--     would otherwise grant §7.3 deviation authority and the right to
--     version limit sets to whoever typed it. Elevation is an admin act,
--     run against the database directly — see the note at the foot.
--
--   · SECTION IS BELIEVED, AND RECORDED AS SELF-ASSERTED. It has to be:
--     nobody can sign up otherwise, and there is no MRM provisioning UI
--     yet. But section IS the RLS read boundary, so a person who types
--     "16 North" reads 16 North. `section_source` marks every such row so
--     MRM can audit and correct them, and so this is visible rather than
--     silent. This is the weakest point in the auth design and it needs
--     the ruling on decision 18 before production.
-- ═══════════════════════════════════════════════════════════════════════

alter table profiles
  add column role_source text not null default 'self-declared'
    check (role_source in ('self-declared', 'provisioned')),
  add column section_source text not null default 'self-declared'
    check (section_source in ('self-declared', 'provisioned'));

comment on column profiles.role_source is
  'How the role got here. A self-declared role is always geological_technician; anything higher was provisioned by MRM.';
comment on column profiles.section_source is
  'Section is the RLS read boundary. self-declared means the person typed it at signup and nobody has confirmed it.';

-- NOTE: migration 0003 moves this function to the geo_private schema and
-- repoints the trigger. It is kept here as applied, for the history.
create or replace function handle_new_geotech_user()
  returns trigger language plpgsql security definer set search_path = public
as $$
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

  -- Note what is NOT read from md: role. It is not a typo.
  insert into profiles (id, employee_no, full_name, role, section,
                        role_source, section_source)
  values (new.id, v_emp, v_name, 'geological_technician', v_section::geo_section,
          'self-declared', 'self-declared');

  return new;
end $$;

create trigger on_auth_user_created_geotech
  after insert on auth.users
  for each row execute function handle_new_geotech_user();

-- The employee number is the unique handle, so a second signup with the
-- same number fails on the profiles unique constraint and takes the
-- auth.users insert down with it. That is deliberate: no orphaned auth
-- user with no profile, and no second account on one employee number.

-- ── promoting someone, for whoever ends up doing it ────────────────────
-- There is no UPDATE policy and no UPDATE privilege on profiles, so this
-- cannot be done from the app by anyone, including a Chief Geologist.
-- It is run against the database directly, which is the point:
--
--   update profiles
--      set role = 'chief_geologist', role_source = 'provisioned'
--    where employee_no = 'UK-0001';
--
--   update profiles
--      set section = '16 North', section_source = 'provisioned'
--    where employee_no = 'UK-5102';
