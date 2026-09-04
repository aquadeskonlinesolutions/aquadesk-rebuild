-- AquaDesk Rebuild — Diver trace numbers
--
-- Every diver gets a permanent, human-readable trace number of the form
-- {dive_center_code}-{NNNN} (e.g. DN-0001), assigned once at creation and
-- never changed. Two separate uniqueness guarantees combine to make this
-- safe:
--   1. dive_centers.dive_center_code — one short code per dive center,
--      unique at the DB level.
--   2. dive_center_trace_counters — one atomically-incrementing counter
--      per dive center, starting at 1.
-- Because the code prefix is itself globally unique, the combined string
-- can never collide across dive centers even though the counter alone
-- only guarantees uniqueness within one dive center — so divers.trace_number
-- only needs a single unique constraint on the whole column, not a
-- composite one.
--
-- Investigation (see session write-up) confirmed there is exactly ONE
-- diver-creation path in the whole app: the SECURITY DEFINER function
-- public.submit_diver_registration(jsonb) — called only from the public
-- /register wizard, and used for both individual and group registrations,
-- new-diver and returning-diver (update) branches. Trace-number assignment
-- is wired into that function's insert-new-diver branch only; the
-- returning-diver update branch is untouched (a diver's number never
-- changes once assigned). Based on 024_diver_last_dive_date.sql's version
-- of the function — the chronologically latest of its 4 prior
-- redefinitions.
--
-- This migration does NOT backfill divers.trace_number for existing
-- divers — that's a separate, reviewed-before-running step (oldest
-- registration first, per dive center) since it's a one-time assignment
-- that can't be redone.

begin;

-- ── dive_centers.dive_center_code ──────────────────────────────────────

alter table public.dive_centers add column dive_center_code text;

update public.dive_centers set dive_center_code = case name
  when 'Dive Nation Malapascua'   then 'DN'
  when 'Atlas Divers Malapascua'  then 'AT'
  when 'Divergems Diving Center'  then 'DG'
  when 'Test Dive Center'         then 'TD'
  when 'Package Test Dive Center' then 'PT'
  when 'Demo Dive Center'         then 'DC'
end;

-- Fails loudly (not silently) if any dive center — including one added
-- between the investigation and this migration actually running — was
-- missed above, rather than leaving a null code that the NOT NULL
-- constraint below would reject anyway with a less obvious error.
do $$
begin
  if exists (select 1 from public.dive_centers where dive_center_code is null) then
    raise exception 'One or more dive_centers rows have no dive_center_code assigned — update the backfill above before rerunning.';
  end if;
end $$;

alter table public.dive_centers
  alter column dive_center_code set not null,
  add constraint dive_centers_dive_center_code_format check (dive_center_code ~ '^[A-Z]{2,4}$'),
  add constraint dive_centers_dive_center_code_key unique (dive_center_code);

-- ── divers.trace_number ──────────────────────────────────────────────────

alter table public.divers add column trace_number text;

alter table public.divers
  add constraint divers_trace_number_format check (trace_number ~ '^[A-Z]{2,4}-[0-9]{4,}$'),
  add constraint divers_trace_number_key unique (trace_number);

-- ── Per-dive-center atomic counter ─────────────────────────────────────
--
-- One row per dive center; "next_number" is the number that will be
-- handed out to the next new diver. Incremented with a single
-- UPDATE ... RETURNING inside submit_diver_registration's SECURITY
-- DEFINER transaction — Postgres's row lock on that UPDATE serializes
-- two concurrent registrations at the same dive center automatically, so
-- no explicit locking code is needed and no two divers can ever be
-- handed the same number. Internal-only table: RLS is enabled with no
-- policies (nothing but the SECURITY DEFINER function ever touches it),
-- matching this codebase's existing internal-only tables.

create table public.dive_center_trace_counters (
  dive_center_id uuid primary key references public.dive_centers(id) on delete cascade,
  next_number integer not null default 1 check (next_number > 0)
);

alter table public.dive_center_trace_counters enable row level security;

insert into public.dive_center_trace_counters (dive_center_id)
select id from public.dive_centers;

-- Keeps future dive centers (onboarded manually, per the investigation —
-- there's no app-side "create dive center" insert today) from ever
-- needing a manual follow-up step to get a counter row.
create or replace function public.seed_dive_center_trace_counter()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.dive_center_trace_counters (dive_center_id) values (new.id);
  return new;
end;
$$;

create trigger dive_centers_seed_trace_counter
  after insert on public.dive_centers
  for each row execute function public.seed_dive_center_trace_counter();

-- ── submit_diver_registration: assign a trace number on new-diver insert ──
--
-- Unchanged from 024's version except: (1) the initial lookup now also
-- reads dive_center_code, (2) the insert-new-diver branch now atomically
-- claims the next counter number and includes trace_number in the
-- insert. The returning-diver (update) branch is untouched — no new
-- trace number there.

create or replace function public.submit_diver_registration(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dive_center_id uuid := (p_payload->>'dive_center_id')::uuid;
  v_existing_diver_id uuid := nullif(p_payload->>'existing_diver_id', '')::uuid;
  v_diver_id uuid;
  v_registration_id uuid;
  v_status public.subscription_status;
  v_dc_code text;
  v_assigned_number integer;
  v_trace_number text;
  v_existing_dc uuid;
  v_existing_notes text;
  v_new_note text := nullif(p_payload->>'note', '');
begin
  select subscription_status, dive_center_code into v_status, v_dc_code
  from public.dive_centers where id = v_dive_center_id;
  if v_status is null or v_status not in ('trial', 'active') then
    raise exception 'Registration is not available for this dive center.';
  end if;

  if coalesce(p_payload->>'first_name', '') = '' or coalesce(p_payload->>'last_name', '') = '' then
    raise exception 'First name and last name are required.';
  end if;
  if coalesce((p_payload->>'waiver_signed')::boolean, false) is not true then
    raise exception 'The waiver must be signed.';
  end if;
  if p_payload->>'privacy_consent_at' is null then
    raise exception 'Privacy consent is required.';
  end if;

  if v_existing_diver_id is not null then
    select dive_center_id, notes into v_existing_dc, v_existing_notes
    from public.divers
    where id = v_existing_diver_id;

    if v_existing_dc is null or v_existing_dc <> v_dive_center_id then
      raise exception 'Diver not found for this dive center.';
    end if;

    v_diver_id := v_existing_diver_id;

    update public.divers set
      first_name = p_payload->>'first_name',
      last_name = p_payload->>'last_name',
      birthday = nullif(p_payload->>'birthday', '')::date,
      age = nullif(p_payload->>'age', '')::integer,
      nationality = p_payload->>'nationality',
      email = nullif(p_payload->>'email', ''),
      phone = nullif(p_payload->>'phone', ''),
      whatsapp = nullif(p_payload->>'whatsapp', ''),
      certification_level = (p_payload->>'certification_level')::public.certification_level,
      training_agency = nullif(p_payload->>'training_agency', '')::public.training_agency,
      logged_dives = coalesce((p_payload->>'logged_dives')::integer, 0),
      last_dive_date = nullif(p_payload->>'last_dive_date', '')::date,
      nitrox_certified = coalesce((p_payload->>'nitrox_certified')::boolean, false),
      group_id = nullif(p_payload->>'group_id', '')::uuid,
      needs_equipment = coalesce((p_payload->>'needs_equipment')::boolean, false),
      equipment_requested = p_payload->>'equipment_requested',
      accommodation = p_payload->>'accommodation',
      emergency_contact_name = p_payload->>'emergency_contact_name',
      emergency_contact_phone = p_payload->>'emergency_contact_phone',
      emergency_contact_relationship = p_payload->>'emergency_contact_relationship',
      emergency_contact_whatsapp = p_payload->>'emergency_contact_whatsapp',
      emergency_contact_email = p_payload->>'emergency_contact_email',
      food_allergies = p_payload->>'food_allergies',
      has_dive_insurance = (p_payload->>'has_dive_insurance')::boolean,
      insurance_provider = p_payload->>'insurance_provider',
      insurance_policy_number = p_payload->>'insurance_policy_number',
      is_minor = coalesce((p_payload->>'is_minor')::boolean, false),
      notes = case when v_new_note is not null
        then coalesce(v_existing_notes || E'\n', '') || v_new_note
        else v_existing_notes
      end
    where id = v_diver_id;
  else
    update public.dive_center_trace_counters
      set next_number = next_number + 1
      where dive_center_id = v_dive_center_id
      returning next_number - 1 into v_assigned_number;

    if v_assigned_number is null then
      raise exception 'No trace-number counter configured for this dive center.';
    end if;

    v_trace_number := v_dc_code || '-' || lpad(v_assigned_number::text, 4, '0');

    insert into public.divers (
      dive_center_id, first_name, last_name, birthday, age, nationality, email, phone, whatsapp,
      certification_level, training_agency, logged_dives, last_dive_date, nitrox_certified, group_id,
      needs_equipment, equipment_requested, notes,
      accommodation, emergency_contact_name, emergency_contact_phone, emergency_contact_relationship,
      emergency_contact_whatsapp, emergency_contact_email, food_allergies,
      has_dive_insurance, insurance_provider, insurance_policy_number, is_minor, trace_number
    ) values (
      v_dive_center_id,
      p_payload->>'first_name', p_payload->>'last_name',
      nullif(p_payload->>'birthday', '')::date, nullif(p_payload->>'age', '')::integer,
      p_payload->>'nationality', nullif(p_payload->>'email', ''), nullif(p_payload->>'phone', ''), nullif(p_payload->>'whatsapp', ''),
      (p_payload->>'certification_level')::public.certification_level,
      nullif(p_payload->>'training_agency', '')::public.training_agency,
      coalesce((p_payload->>'logged_dives')::integer, 0),
      nullif(p_payload->>'last_dive_date', '')::date,
      coalesce((p_payload->>'nitrox_certified')::boolean, false),
      nullif(p_payload->>'group_id', '')::uuid,
      coalesce((p_payload->>'needs_equipment')::boolean, false),
      p_payload->>'equipment_requested',
      v_new_note,
      p_payload->>'accommodation',
      p_payload->>'emergency_contact_name', p_payload->>'emergency_contact_phone',
      p_payload->>'emergency_contact_relationship', p_payload->>'emergency_contact_whatsapp',
      p_payload->>'emergency_contact_email', p_payload->>'food_allergies',
      (p_payload->>'has_dive_insurance')::boolean, p_payload->>'insurance_provider',
      p_payload->>'insurance_policy_number', coalesce((p_payload->>'is_minor')::boolean, false),
      v_trace_number
    )
    returning id into v_diver_id;
  end if;

  insert into public.diver_registrations (
    dive_center_id, diver_id, group_id, arrival_date, departure_date, accommodation,
    emergency_contact_name, emergency_contact_phone, emergency_contact_whatsapp,
    emergency_contact_email, emergency_contact_relationship,
    last_dive_date, food_allergies, has_dive_insurance, insurance_provider, insurance_policy_number, wants_insurance_referral,
    certification_level, equipment_preference, equipment_requested, needs_equipment,
    medical_answers, medical_answers_snapshot, medical_flag,
    privacy_consent_at, privacy_notice_snapshot, waiver_content_snapshot, waiver_date, waiver_opened,
    waiver_signature_url, waiver_signed, duplicate_email_flag,
    first_name, last_name, birthday, nationality, email, phone, whatsapp
  ) values (
    v_dive_center_id, v_diver_id, nullif(p_payload->>'group_id', '')::uuid,
    nullif(p_payload->>'arrival_date', '')::date, nullif(p_payload->>'departure_date', '')::date,
    p_payload->>'accommodation',
    p_payload->>'emergency_contact_name', p_payload->>'emergency_contact_phone',
    p_payload->>'emergency_contact_whatsapp',
    p_payload->>'emergency_contact_email', p_payload->>'emergency_contact_relationship',
    nullif(p_payload->>'last_dive_date', '')::date, p_payload->>'food_allergies',
    (p_payload->>'has_dive_insurance')::boolean, p_payload->>'insurance_provider',
    p_payload->>'insurance_policy_number', (p_payload->>'wants_insurance_referral')::boolean,
    (p_payload->>'certification_level')::public.certification_level,
    p_payload->>'equipment_preference', p_payload->>'equipment_requested',
    coalesce((p_payload->>'needs_equipment')::boolean, false),
    (p_payload->'medical_answers'), (p_payload->'medical_answers_snapshot'),
    coalesce((p_payload->>'medical_flag')::boolean, false),
    (p_payload->>'privacy_consent_at')::timestamptz, p_payload->>'privacy_notice_snapshot',
    p_payload->>'waiver_content_snapshot', (p_payload->>'waiver_date')::timestamptz,
    coalesce((p_payload->>'waiver_opened')::boolean, true),
    p_payload->>'waiver_signature_url', true,
    coalesce((p_payload->>'duplicate_email_flag')::boolean, false),
    p_payload->>'first_name', p_payload->>'last_name',
    nullif(p_payload->>'birthday', '')::date, p_payload->>'nationality',
    nullif(p_payload->>'email', ''), nullif(p_payload->>'phone', ''), nullif(p_payload->>'whatsapp', '')
  )
  returning id into v_registration_id;

  return jsonb_build_object('diver_id', v_diver_id, 'registration_id', v_registration_id, 'trace_number', v_trace_number);
end;
$$;

grant execute on function public.submit_diver_registration(jsonb) to anon, authenticated;

commit;
