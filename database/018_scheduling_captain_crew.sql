-- AquaDesk Rebuild — Scheduling: per-trip captain + crew capture
--
-- scheduling.html captures a boat's captain and crew fresh per trip (not
-- from a fixed per-boat roster — settings.html's Fleet section has no
-- crew field at all), defaulting to 3 crew slots with a "+ Add Crew" to
-- add more, stored in the live app's schedules.notes JSON blob. This
-- project has a standing rule against JSON-blob structural state (the
-- same reasoning schedule_sites already follows for multi-site trips),
-- so captain becomes a real column and crew becomes a real child table —
-- the relational equivalent, arbitrary length, delete-and-reinsert same
-- as schedule_sites.
--
-- Also updates get_crew_schedule (010_staff_roster_fields.sql) to surface
-- both fields — staff.html's real crew view shows "Captain:"/"Crew:" too
-- (confirmed in the old app's source), and the schedule's own captain is
-- what should render there now, not boats.captain (which was always
-- empty for this purpose — boats never had a captain source for trips).

begin;

alter table public.schedules add column captain text;

create table public.schedule_crew (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  schedule_id uuid not null references public.schedules(id) on delete cascade,
  crew_name text not null,
  sort_order integer not null default 0
);

-- Same 4-policy shape as every other operational table added post-001
-- (the one-time policy-creation loop in 001 already ran and can't be
-- re-run for new tables).
alter table public.schedule_crew enable row level security;
create policy schedule_crew_select on public.schedule_crew for select
  using (dive_center_id = public.current_dive_center_id());
create policy schedule_crew_insert on public.schedule_crew for insert
  with check (dive_center_id = public.current_dive_center_id());
create policy schedule_crew_update on public.schedule_crew for update
  using (dive_center_id = public.current_dive_center_id())
  with check (dive_center_id = public.current_dive_center_id());
create policy schedule_crew_delete on public.schedule_crew for delete
  using (dive_center_id = public.current_dive_center_id());

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
