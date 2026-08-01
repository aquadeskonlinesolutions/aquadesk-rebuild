-- AquaDesk Rebuild — crew token scoped to the schedule date it was
-- generated for, not real calendar "today".
--
-- Real, business-critical workflow the user described: a dive center
-- builds tomorrow's schedule before closing up today, specifically so
-- staff can check it that same evening — but the rebuild's token system
-- only ever considered a token valid if `staff_token_date` matched real
-- calendar today, so viewing Phase 3 for a schedule built ahead (e.g.
-- tomorrow) still silently reused/returned *today's* token, and even if
-- it hadn't, get_crew_schedule only ever showed schedules where
-- schedule_date = today regardless of what token was entered — tomorrow's
-- schedule was structurally unreachable via any token until tomorrow
-- actually arrived.
--
-- Confirmed against the live app's real mechanism (scheduling.html's
-- generateToken()/refreshStaffToken(), staff.html's submitToken()):
-- the token's date is whichever schedule date is currently selected in
-- Scheduling when the token is (re)generated, NOT `localTodayStr()`
-- unconditionally — `cleanDateValue(selectedDate) || localTodayStr()`.
-- staff.html's own token lookup doesn't compare against real today at
-- all (`.eq('staff_token', entered).single()`, no date filter in the
-- WHERE) — it trusts whatever date is stored alongside that token
-- (`data.staff_token_date`) as the schedule date to load. There's only
-- ever one live token app-wide (a single `dive_centers.staff_token`
-- column, same as this rebuild) — generating a token for a new date
-- overwrites whatever was there, which is what naturally invalidates an
-- older date's token once a newer one is generated, not a calendar-day
-- expiry check.
--
-- generate_daily_staff_token gains a required p_schedule_date parameter
-- (the caller's currently-viewed Scheduling date, not "today") — the old
-- 1-parameter overload is dropped, not left dangling. get_crew_schedule's
-- lookup drops the `staff_token_date = v_today` comparison entirely and
-- instead uses the matched row's own staff_token_date as the date to
-- filter schedules by.

begin;

drop function if exists public.generate_daily_staff_token(uuid);

create or replace function public.generate_daily_staff_token(p_dive_center_id uuid, p_schedule_date date)
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
      staff_token_date = p_schedule_date
  where id = p_dive_center_id;

  return v_token;
end;
$$;

grant execute on function public.generate_daily_staff_token(uuid, date) to authenticated;

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
    'trips', v_trips
  );
end;
$$;

grant execute on function public.get_crew_schedule(text) to anon, authenticated;

commit;
