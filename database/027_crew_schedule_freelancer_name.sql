-- AquaDesk Rebuild — get_crew_schedule: surface a freelancer's real name
-- instead of null.
--
-- Same root cause as migration 026: get_crew_schedule's own staff_name
-- expression (`case when st.id is not null then ... else null end`) only
-- ever resolved a name for a real `staff` row — a freelancer-led team
-- (schedule_divers.staff_id null by design) always came back with
-- staff_name = null, which src/app/staff/StaffScheduleClient.tsx's
-- groupByStaff then bucketed as literally "Unassigned" — the exact same
-- display bug just found and fixed in Scheduling's own Build/Complete
-- phases, present here too since this RPC is a separate consumer of
-- schedule_divers that a TypeScript-only grep wouldn't catch (see this
-- project's own standing lesson about columns read only by a SQL
-- function). Now that schedule_divers.staff_name exists (migration 026),
-- prefer it whenever there's no real staff row to join to.
--
-- CORRECTION: this migration's first version was written against 018's
-- body of get_crew_schedule, not the real latest one — 022 (per-dive
-- tank detail, staff_dive_tanks, spare_tanks, course_name) and 023
-- (dive_center_name) both landed after 018 and were silently reverted by
-- that mistake, breaking /staff with "Cannot read properties of
-- undefined (reading 'forEach')" on trip.staff_dive_tanks. This version
-- is based on 023's real body (the actual latest at the time this was
-- written) with only the one intended staff_name fix layered on top.

begin;

create or replace function public.get_crew_schedule(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_dive_center_id uuid;
  v_dive_center_name text;
  v_today date := (now() at time zone 'Asia/Manila')::date;
  v_trips jsonb;
begin
  select id, name into v_dive_center_id, v_dive_center_name
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
          'age', d.age,
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
      and s.schedule_date = v_today
      and s.cancelled = false
  ) trips;

  return jsonb_build_object(
    'dive_center_id', v_dive_center_id,
    'dive_center_name', v_dive_center_name,
    'trips', v_trips
  );
end;
$$;

grant execute on function public.get_crew_schedule(text) to anon, authenticated;

commit;
