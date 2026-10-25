-- AquaDesk Rebuild — registration: no nitrox request without nitrox certification
--
-- The registration equipment list is built from the centre's Settings >
-- Equipment items. If a centre has a "Nitrox" item, the form now hides it
-- from divers who are not nitrox certified and clears it if they un-tick
-- "Nitrox certified" afterwards. This migration enforces the same rule in
-- the database so a hand-made request can't bypass the form.
--
-- Base: 041's submit_diver_registration (the latest create-or-replace of
-- this function, confirmed via grep) verbatim; the ONLY changes are the
-- v_equipment variable + filter block at the top, and the three places that
-- stored p_payload->>'equipment_requested' now store v_equipment.
-- Silent filter, not an error: the rest of the registration still saves.
-- Does not touch staff paths (diver form Edit Equipment / Edit Diver Info
-- write the divers table directly, not through this function), any stored
-- row, or any other function. Existing rows are never rewritten.
-- Grants unchanged (create or replace keeps them); restated below per the
-- project rule.
--
-- Rollback: re-run the create-or-replace of submit_diver_registration from
-- 041_diver_trace_numbers.sql in full.

begin;

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
  v_equipment text := p_payload->>'equipment_requested';
begin
  -- Nitrox request is only valid for a nitrox-certified diver: drop any
  -- equipment item whose name contains "nitrox" when the payload says the
  -- diver is not certified. Anything else (certified divers, other items,
  -- a malformed equipment_requested) is passed through exactly as before.
  begin
    if coalesce((p_payload->>'nitrox_certified')::boolean, false) is not true
       and v_equipment is not null
       and exists (
         select 1 from jsonb_array_elements(v_equipment::jsonb->'items') i
         where lower(coalesce(i->>'name', '')) like '%nitrox%'
       ) then
      v_equipment := jsonb_set(
        v_equipment::jsonb, '{items}',
        coalesce((
          select jsonb_agg(i) from jsonb_array_elements(v_equipment::jsonb->'items') i
          where lower(coalesce(i->>'name', '')) not like '%nitrox%'
        ), '[]'::jsonb)
      )::text;
    end if;
  exception when others then
    v_equipment := p_payload->>'equipment_requested';
  end;

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
      equipment_requested = v_equipment,
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
      v_equipment,
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
    p_payload->>'equipment_preference', v_equipment,
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

revoke all on function public.submit_diver_registration(jsonb) from public;
grant execute on function public.submit_diver_registration(jsonb) to anon, authenticated, service_role;

commit;
