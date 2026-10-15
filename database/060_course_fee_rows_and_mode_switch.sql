-- AquaDesk Rebuild — Fun Diving <-> Course switch + course fee rows
--
-- ADDITIVE ONLY. No existing row is read, changed or deleted by this file.
--
--   1. activities.row_type may now also be 'course_fee' (it could only be
--      'bundle'). Every existing row keeps its blank row_type. New course fee
--      rows (a row added to a bill while it is in Course mode) get 'course_fee'.
--   2. visits.mode_switched_at — new nullable column, NULL on every existing
--      visit. Set the first time staff switch a bill's mode. It tells Apply
--      Charges that the bill's unmarked rows are fun dives (a bill switched to
--      Course keeps its earlier fun dives billed as they are), while an older
--      course bill (NULL) keeps behaving exactly as today.
--   3. Duplicate protection: at most ONE blank course fee row per visit (no
--      course name, no staff, 0 rate). A double click can't leave two empty
--      fee rows. Rows staff have filled in are never blocked, and a visit can
--      hold any number of course fees.
--   4. Bill lock on the mode itself: a visit's experience_type can't be changed
--      unless the bill is open (database refuses, even outside the app).
--      service_role / postgres (maintenance) are let through, as in 057.
--   5. switch_visit_mode() — one all-or-nothing database function: checks the
--      bill is open and the caller's own dive center, flips the mode, stamps
--      mode_switched_at, optionally removes ONLY rows marked 'course_fee'
--      (never older unmarked course rows) when switching to Fun, and writes
--      audit_logs 'visit_mode_switched' (who, from -> to, fee rows kept or
--      removed). Billing Audit lists these.
--
-- Deploy order: this migration first, then the app code.

begin;

-- ---- 1. course_fee row type ---------------------------------------------------
alter table public.activities drop constraint activities_row_type_check;
alter table public.activities
  add constraint activities_row_type_check check (row_type in ('bundle', 'course_fee'));

-- ---- 2. when a bill's mode was switched ----------------------------------------
alter table public.visits add column mode_switched_at timestamptz;

-- ---- 3. no duplicate blank course fee row per visit ----------------------------
create unique index activities_one_blank_course_fee_per_visit
  on public.activities (visit_id)
  where row_type = 'course_fee'
    and status <> 'cancelled'
    and dive_rate = 0
    and coalesce(btrim(dive_site), '') = ''
    and coalesce(btrim(staff_name), '') = '';

-- ---- 4. mode changes follow the bill lock ---------------------------------------
create or replace function public.guard_visit_mode_change()
returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return NEW;
  end if;
  if OLD.visit_status is distinct from 'open' then
    raise exception 'This bill is closed. Unlock it with the billing password before changing it.'
      using errcode = 'P0001';
  end if;
  return NEW;
end;
$$;

revoke all on function public.guard_visit_mode_change() from public, anon, authenticated;

create trigger visits_mode_change_lock
  before update on public.visits
  for each row
  when (OLD.experience_type is distinct from NEW.experience_type)
  execute function public.guard_visit_mode_change();

-- ---- 5. the switch itself -----------------------------------------------------
-- p_to: 'fun_diving' | 'dive_course'.
-- p_remove_course_fees: only used when switching to Fun; removes the visit's rows
-- whose row_type = 'course_fee' (nothing else).
create or replace function public.switch_visit_mode(
  p_visit_id uuid,
  p_to text,
  p_remove_course_fees boolean default false
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dc uuid := public.current_dive_center_id();
  v_visit record;
  v_diver text;
  v_fee_rows int := 0;
  v_removed int := 0;
  v_note text;
begin
  if v_dc is null then
    raise exception 'Not signed in.';
  end if;
  if p_to not in ('fun_diving', 'dive_course') then
    raise exception 'Unknown mode.';
  end if;

  select id, diver_id, visit_status, experience_type into v_visit
    from public.visits where id = p_visit_id and dive_center_id = v_dc for update;
  if not found then
    raise exception 'Visit not found.';
  end if;
  if v_visit.visit_status <> 'open' then
    raise exception 'This bill is closed. Unlock it with the billing password before changing it.';
  end if;
  if v_visit.experience_type::text = p_to then
    raise exception 'This bill is already in that mode.';
  end if;

  select count(*) into v_fee_rows from public.activities
   where visit_id = p_visit_id and row_type = 'course_fee' and status <> 'cancelled';

  update public.visits
     set experience_type = p_to::public.experience_type,
         mode_switched_at = now()
   where id = p_visit_id;

  if p_to = 'fun_diving' and p_remove_course_fees then
    delete from public.activities where visit_id = p_visit_id and row_type = 'course_fee';
    get diagnostics v_removed = row_count;
  end if;

  select trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')) into v_diver
    from public.divers where id = v_visit.diver_id;

  v_note := format('%s — %s → %s', coalesce(nullif(v_diver, ''), 'Diver'),
                   case v_visit.experience_type::text when 'fun_diving' then 'Fun Diving' else 'Course' end,
                   case p_to when 'fun_diving' then 'Fun Diving' else 'Course' end);
  if p_to = 'fun_diving' then
    v_note := v_note || case
      when v_fee_rows = 0 then '; no course fee rows on the bill'
      when p_remove_course_fees then format('; course fee removed (%s row%s)', v_removed, case when v_removed = 1 then '' else 's' end)
      else format('; course fee kept (%s row%s)', v_fee_rows, case when v_fee_rows = 1 then '' else 's' end)
    end;
  end if;

  insert into public.audit_logs (dive_center_id, action, target_type, target_id, performed_by, notes)
  values (v_dc, 'visit_mode_switched', 'visits', p_visit_id, auth.uid(), v_note);

  return jsonb_build_object('from', v_visit.experience_type::text, 'to', p_to,
                            'course_fee_rows', v_fee_rows, 'removed', v_removed);
end;
$$;

revoke all on function public.switch_visit_mode(uuid, text, boolean) from public, anon;
grant execute on function public.switch_visit_mode(uuid, text, boolean) to authenticated;

commit;

-- ---- Rollback ----------------------------------------------------------------
-- Safe only while no 'course_fee' row exists (select count(*) from activities
-- where row_type = 'course_fee') — the old check would refuse the constraint.
-- begin;
-- drop function if exists public.switch_visit_mode(uuid, text, boolean);
-- drop trigger if exists visits_mode_change_lock on public.visits;
-- drop function if exists public.guard_visit_mode_change();
-- drop index if exists public.activities_one_blank_course_fee_per_visit;
-- alter table public.visits drop column if exists mode_switched_at;
-- alter table public.activities drop constraint if exists activities_row_type_check;
-- alter table public.activities add constraint activities_row_type_check check (row_type in ('bundle'));
-- commit;
