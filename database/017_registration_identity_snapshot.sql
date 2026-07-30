-- AquaDesk Rebuild — Registration identity snapshot + per-dive tank tables
--
-- diver_registrations already snapshots accommodation/certification_level/
-- waiver_content/medical_answers specifically so a signed record can't
-- drift after a later profile edit (enforced by
-- enforce_registration_immutability once waiver_signed = true) — but it
-- never snapshotted the diver's own identity (name/DOB/nationality/email/
-- phone), only a diver_id FK. That means Diver Form's "Signed Documents"
-- print (a real legal waiver) could only ever show the *current, mutable*
-- divers row — a later name correction would silently rewrite what an old
-- signed document appears to say. Fixed by giving identity the same
-- snapshot treatment as every other signed fact on this table.
-- RegistrationWizard.tsx already submits all of these fields to
-- submit_diver_registration — they were just never written to
-- diver_registrations, only to divers.
--
-- Also adds real per-dive nitrox/15L tank tracking for Scheduling —
-- schedule_divers keeps its one-row-per-diver-per-trip shape (nothing
-- changes for /crew, Boat Manifest, or warnings, which all read its
-- existing is_15l/nitrox_requested columns as before), but those two
-- columns become derived summary flags ("at least one dive uses this
-- tank"), same as the live app's own real mechanism. The actual per-dive
-- detail lives in these two new additive tables, keyed by schedule_sites'
-- existing sort_order — no JSON blob, matching this project's standing
-- rule against JSON-blob structural state.

begin;

alter table public.diver_registrations
  add column first_name text,
  add column last_name text,
  add column birthday date,
  add column nationality text,
  add column email text,
  add column phone text,
  add column whatsapp text;

create table public.schedule_diver_dive_tanks (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  schedule_diver_id uuid not null references public.schedule_divers(id) on delete cascade,
  site_index integer not null,
  tank_type text not null check (tank_type in ('nitrox', 'air_15l')),
  unique (schedule_diver_id, site_index)
);

create table public.schedule_staff_dive_tanks (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  schedule_id uuid not null references public.schedules(id) on delete cascade,
  staff_name text not null,
  site_index integer not null,
  unique (schedule_id, staff_name, site_index)
);

-- Same 4-policy shape as every other "operational" table (the one-time
-- do $$ loop that created those already ran in 001 and can't be re-run).
alter table public.schedule_diver_dive_tanks enable row level security;
create policy schedule_diver_dive_tanks_select on public.schedule_diver_dive_tanks for select
  using (dive_center_id = public.current_dive_center_id());
create policy schedule_diver_dive_tanks_insert on public.schedule_diver_dive_tanks for insert
  with check (dive_center_id = public.current_dive_center_id());
create policy schedule_diver_dive_tanks_update on public.schedule_diver_dive_tanks for update
  using (dive_center_id = public.current_dive_center_id())
  with check (dive_center_id = public.current_dive_center_id());
create policy schedule_diver_dive_tanks_delete on public.schedule_diver_dive_tanks for delete
  using (dive_center_id = public.current_dive_center_id());

alter table public.schedule_staff_dive_tanks enable row level security;
create policy schedule_staff_dive_tanks_select on public.schedule_staff_dive_tanks for select
  using (dive_center_id = public.current_dive_center_id());
create policy schedule_staff_dive_tanks_insert on public.schedule_staff_dive_tanks for insert
  with check (dive_center_id = public.current_dive_center_id());
create policy schedule_staff_dive_tanks_update on public.schedule_staff_dive_tanks for update
  using (dive_center_id = public.current_dive_center_id())
  with check (dive_center_id = public.current_dive_center_id());
create policy schedule_staff_dive_tanks_delete on public.schedule_staff_dive_tanks for delete
  using (dive_center_id = public.current_dive_center_id());

-- submit_diver_registration: now also copies identity fields onto
-- diver_registrations (in addition to divers, which it already did).
-- Everything else in this function is unchanged from 008's version.
create or replace function public.submit_diver_registration(p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dive_center_id uuid := (p_payload->>'dive_center_id')::uuid;
  v_existing_diver_id uuid := nullif(p_payload->>'existing_diver_id', '')::uuid;
  v_diver_id uuid;
  v_registration_id uuid;
  v_status public.subscription_status;
  v_existing_dc uuid;
  v_existing_notes text;
  v_new_note text := nullif(p_payload->>'note', '');
begin
  select subscription_status into v_status from public.dive_centers where id = v_dive_center_id;
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
    insert into public.divers (
      dive_center_id, first_name, last_name, birthday, age, nationality, email, phone, whatsapp,
      certification_level, training_agency, logged_dives, nitrox_certified, group_id,
      needs_equipment, equipment_requested, notes,
      accommodation, emergency_contact_name, emergency_contact_phone, emergency_contact_relationship,
      emergency_contact_whatsapp, emergency_contact_email, food_allergies,
      has_dive_insurance, insurance_provider, insurance_policy_number, is_minor
    ) values (
      v_dive_center_id,
      p_payload->>'first_name', p_payload->>'last_name',
      nullif(p_payload->>'birthday', '')::date, nullif(p_payload->>'age', '')::integer,
      p_payload->>'nationality', nullif(p_payload->>'email', ''), nullif(p_payload->>'phone', ''), nullif(p_payload->>'whatsapp', ''),
      (p_payload->>'certification_level')::public.certification_level,
      nullif(p_payload->>'training_agency', '')::public.training_agency,
      coalesce((p_payload->>'logged_dives')::integer, 0),
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
      p_payload->>'insurance_policy_number', coalesce((p_payload->>'is_minor')::boolean, false)
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

  return jsonb_build_object('diver_id', v_diver_id, 'registration_id', v_registration_id);
end;
$$;

grant execute on function public.submit_diver_registration(jsonb) to anon, authenticated;

commit;
