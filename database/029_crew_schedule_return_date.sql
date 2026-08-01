-- AquaDesk Rebuild — get_crew_schedule never returned the schedule date
-- it was actually filtering by, so the crew view's header always showed
-- real calendar "today" (StaffScheduleClient.tsx's fmtHeaderDate() called
-- new Date() with no arguments) even for a schedule built ahead and
-- viewed via migration 028's per-schedule-date token.
--
-- Found while live-verifying migration 028's fix: generated a token
-- while viewing a schedule built for tomorrow, confirmed /staff correctly
-- found and rendered that schedule's trips (right boat/captain/divers),
-- but the header still said "today"'s real date instead of the schedule
-- date the token/trips actually belong to.
--
-- Based on 028's actual latest body (confirmed via grep — no
-- create-or-replace of this function since 028) with one addition: the
-- already-computed v_schedule_date local variable is now included in the
-- returned jsonb.

begin;

create or replace function public.get_crew_schedule(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_dive_center_id uuid;
  v_dive_center_name text;
  v_schedule_date date;
  v_trips jsonb;
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
