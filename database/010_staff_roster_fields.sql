-- AquaDesk Rebuild — Staff roster: emergency contact + certifications,
-- self-view RLS split, and the crew daily-access-token mechanism.
--
-- Scope decisions confirmed with the user before writing this:
-- 1. The crew schedule view (old app's staff.html) is being built now,
--    even though Scheduling isn't built yet. Token generation is kept as
--    its own reusable SECURITY DEFINER function (generate_daily_staff_token)
--    so Scheduling can call the same thing later instead of duplicating it.
--    An interim trigger point lives on the new Staff page in the meantime.
-- 2. "Secretary can view own profile only" = read-only, own row only —
--    staff_select is split below; staff_owner_write (all mutations) stays
--    owner-only, unchanged.
-- 3. Certifications (one-to-many, own expiry per cert) + emergency contact
--    (mirrors divers' migration-008 shape exactly) are new fields the user
--    asked for beyond the original Stage 1a schema.
-- 4. staff.daily_rate stays fully separate from Reports' per-dive
--    commission rate (dive_centers.divemaster_rate_per_dive) — no change
--    needed here, just confirming no linkage was added.

begin;

-- 1. Emergency contact fields on staff, same shape as divers (008).
alter table public.staff
  add column emergency_contact_name text,
  add column emergency_contact_phone text,
  add column emergency_contact_relationship text,
  add column emergency_contact_whatsapp text,
  add column emergency_contact_email text;

-- 2. Certifications (plural, own expiry each) — denormalized dive_center_id
-- on the child table, matching this schema's established convention
-- (activities, diver_registrations, etc. — not a join-based RLS check).
create table public.staff_certifications (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,
  cert_name text not null,
  expiry_date date,
  created_at timestamptz not null default now()
);

alter table public.staff_certifications enable row level security;

create policy staff_certifications_select on public.staff_certifications for select
  using (
    dive_center_id = public.current_dive_center_id()
    and (
      public.is_owner()
      or staff_id in (select id from public.staff where user_id = auth.uid())
    )
  );

create policy staff_certifications_owner_write on public.staff_certifications for all
  using (dive_center_id = public.current_dive_center_id() and public.is_owner())
  with check (dive_center_id = public.current_dive_center_id() and public.is_owner());

-- 3. Replace staff_select: previously granted every tenant user (owner or
-- secretary) read of every staff row. A secretary should now only see
-- their own linked row (staff.user_id = auth.uid()); owners still see
-- everything. staff_owner_write (insert/update/delete) is unchanged —
-- this stays read-only self-view, no self-edit, per the user's answer.
drop policy staff_select on public.staff;
create policy staff_select on public.staff for select
  using (
    dive_center_id = public.current_dive_center_id()
    and (public.is_owner() or user_id = auth.uid())
  );

-- 4. Reusable daily crew-access-token generator. Not owner-gated —
-- any authenticated tenant user (owner or secretary) can trigger this,
-- matching the old app's secretary-driven "open Scheduling, get a code"
-- flow. Scheduling will call this exact same function later instead of
-- re-implementing token generation.
create or replace function public.generate_daily_staff_token(p_dive_center_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_token text;
begin
  if public.current_dive_center_id() <> p_dive_center_id then
    raise exception 'Cannot generate a crew code for another dive center.';
  end if;

  v_token := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));

  update public.dive_centers
  set staff_token = v_token,
      staff_token_date = (now() at time zone 'Asia/Manila')::date
  where id = p_dive_center_id;

  return v_token;
end;
$$;

grant execute on function public.generate_daily_staff_token(uuid) to authenticated;

-- 5. Anon-callable crew schedule view. The only anon-facing piece of the
-- whole Staff feature — mirrors the registration RPCs' "anon has zero
-- direct table access, only a narrow SECURITY DEFINER gateway" pattern.
-- Validates the token AND that it was generated today (Asia/Manila) —
-- an old or wrong token returns nothing, never another dive center's data.
--
-- Known limitation: schedules/schedule_divers have no real writer until
-- Scheduling is built, so this returns an empty trips array until then
-- (or until test rows are seeded directly for verification).
create or replace function public.get_crew_schedule(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_dive_center_id uuid;
  v_today date := (now() at time zone 'Asia/Manila')::date;
  v_trips jsonb;
begin
  select id into v_dive_center_id
  from public.dive_centers
  where staff_token = p_token and staff_token_date = v_today;

  if v_dive_center_id is null then
    return jsonb_build_object('error', 'This code is invalid or has expired.');
  end if;

  select coalesce(jsonb_agg(trip order by trip->>'departure_time'), '[]'::jsonb)
  into v_trips
  from (
    select jsonb_build_object(
      'schedule_id', s.id,
      'departure_time', s.departure_time,
      'notes', s.notes,
      'is_joiner', s.is_joiner,
      'joiner_boat_name', s.joiner_boat_name,
      'boat', jsonb_build_object('name', b.name, 'captain', b.captain),
      'dive_sites', (
        select coalesce(jsonb_agg(ds.site_name order by ss.sort_order), '[]'::jsonb)
        from public.schedule_sites ss
        join public.dive_sites ds on ds.id = ss.dive_site_id
        where ss.schedule_id = s.id
      ),
      'divers', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'diver_name', d.first_name || ' ' || d.last_name,
          'nationality', d.nationality,
          'certification_level', d.certification_level,
          'logged_dives', d.logged_dives,
          'age', d.age,
          'group_name', g.group_name,
          'staff_name', case when st.id is not null then st.first_name || ' ' || st.last_name else null end,
          'staff_position', st.position,
          'is_15l', sd.is_15l,
          'nitrox_requested', sd.nitrox_requested,
          'experience_type', sd.experience_type,
          'notes', sd.notes
        )), '[]'::jsonb)
        from public.schedule_divers sd
        join public.divers d on d.id = sd.diver_id
        left join public.staff st on st.id = sd.staff_id
        left join public.groups g on g.id = d.group_id
        where sd.schedule_id = s.id
      ),
      'tank_tally', (
        select jsonb_build_object(
          'tank_12l', count(*) filter (where sd.is_15l is not true),
          'tank_15l', count(*) filter (where sd.is_15l is true),
          'nitrox', count(*) filter (where sd.nitrox_requested is true)
        )
        from public.schedule_divers sd
        where sd.schedule_id = s.id
      )
    ) as trip
    from public.schedules s
    left join public.boats b on b.id = s.boat_id
    where s.dive_center_id = v_dive_center_id
      and s.schedule_date = v_today
      and s.cancelled = false
  ) trips;

  return jsonb_build_object('dive_center_id', v_dive_center_id, 'trips', v_trips);
end;
$$;

grant execute on function public.get_crew_schedule(text) to anon, authenticated;

commit;
