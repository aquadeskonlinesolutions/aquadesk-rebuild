-- AquaDesk Rebuild — staff crew page can tell rental trips from join rides
--
-- get_crew_schedule returned is_joiner, which is true for BOTH a rental
-- boat and a join ride (scheduling sets is_joiner = boat_mode <> 'own_boat'),
-- so the public /staff page showed every rental as "Join Ride" /
-- "Joining: <name>" and hid its captain. This adds one key to each trip:
-- 'boat_mode' ('own_boat' | 'join_ride' | 'rental', from schedules.boat_mode,
-- migration 036).
--
-- Based on 053's body verbatim (the latest create-or-replace of this
-- function, confirmed via grep); the ONLY change is the added 'boat_mode'
-- line. Additive: no key removed or renamed, same signature, same
-- SECURITY DEFINER + search_path, same crew-code lookup and dive-center
-- scoping, same grant. The currently deployed page ignores the new key,
-- so it keeps working before and after this runs.
--
-- Run on the rebuild Supabase project only: ref vqwrluiikodconwlmwls
-- (the one aquadesk.online uses). Never on xaabndtaevwgicibzcqm.

begin;

create or replace function public.get_crew_schedule(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_dive_center_id uuid;
  v_dive_center_name text;
  v_schedule_date date;
  v_trips jsonb;
  v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  select id, name, staff_token_date into v_dive_center_id, v_dive_center_name, v_schedule_date
  from public.dive_centers
  where staff_token = p_token;

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
      'boat_mode', s.boat_mode,
      'joiner_boat_name', s.joiner_boat_name,
      'guest_divers_count', s.guest_divers_count,
      'guest_dive_center_name', s.guest_dive_center_name,
      'guest_notes', s.guest_notes,
      'boat', jsonb_build_object('name', b.name, 'captain', s.captain),
      'crew', (
        select coalesce(jsonb_agg(sc.crew_name order by sc.sort_order), '[]'::jsonb)
        from public.schedule_crew sc
        where sc.schedule_id = s.id
      ),
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
          'age', case
            when d.birthday is not null then
              extract(year from v_today)::int - extract(year from d.birthday)::int
              - case
                  when (extract(month from v_today), extract(day from v_today))
                     < (extract(month from d.birthday), extract(day from d.birthday))
                  then 1 else 0
                end
            else d.age
          end,
          'group_name', g.group_name,
          'staff_name', coalesce(st.first_name || ' ' || st.last_name, sd.staff_name),
          'staff_position', st.position,
          'is_15l', sd.is_15l,
          'nitrox_requested', sd.nitrox_requested,
          'experience_type', sd.experience_type,
          'course_name', (
            select cr.course_name
            from public.visits v
            join public.course_rates cr on cr.id = v.course_rate_id
            where v.diver_id = d.id and v.is_active = true and v.visit_status = 'open'
              and v.course_rate_id is not null
            order by v.created_at desc
            limit 1
          ),
          'notes', sd.notes,
          'dive_tanks', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'site_index', sdt.site_index,
              'tank_type', sdt.tank_type
            )), '[]'::jsonb)
            from public.schedule_diver_dive_tanks sdt
            where sdt.schedule_diver_id = sd.id
          )
        )), '[]'::jsonb)
        from public.schedule_divers sd
        join public.divers d on d.id = sd.diver_id
        left join public.staff st on st.id = sd.staff_id
        left join public.groups g on g.id = d.group_id
        where sd.schedule_id = s.id
      ),
      'staff_dive_tanks', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'staff_name', sfdt.staff_name,
          'site_index', sfdt.site_index
        )), '[]'::jsonb)
        from public.schedule_staff_dive_tanks sfdt
        where sfdt.schedule_id = s.id
      ),
      'spare_tanks', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'tank_type', spt.tank_type,
          'quantity', spt.quantity
        ) order by spt.sort_order), '[]'::jsonb)
        from public.schedule_spare_tanks spt
        where spt.schedule_id = s.id
      )
    ) as trip
    from public.schedules s
    left join public.boats b on b.id = s.boat_id
    where s.dive_center_id = v_dive_center_id
      and s.schedule_date = v_schedule_date
      and s.cancelled = false
  ) trips;

  return jsonb_build_object(
    'dive_center_id', v_dive_center_id,
    'dive_center_name', v_dive_center_name,
    'schedule_date', v_schedule_date,
    'trips', v_trips
  );
end;
$$;

grant execute on function public.get_crew_schedule(text) to anon, authenticated;

commit;

-- ---- Rollback (safe any time) -----------------------------------------------
-- Re-run database/053_crew_schedule_live_age.sql in full: it restores the
-- previous get_crew_schedule body (no boat_mode key) unchanged. The page
-- falls back to is_joiner when the key is missing.
