-- AquaDesk Rebuild — last_dive_date: add the missing evergreen copy
--
-- last_dive_date has only ever existed on diver_registrations (the
-- immutable per-registration-event snapshot, migration 001) — it was
-- never added to divers (the evergreen, editable profile), unlike every
-- other field collected at registration that also needs a correctable
-- evergreen copy (accommodation, emergency contact fields, insurance —
-- all added to divers by migration 008, alongside the exact same fields
-- already on diver_registrations). last_dive_date was missed at that
-- time. Confirmed by trying to write a real divers.last_dive_date value
-- and hitting "column does not exist" — the earlier assumption (made
-- while planning Diver Form's last-dive-date UI) that this column
-- already existed on divers was wrong; it only looked that way from a
-- line-number grep that didn't check which CREATE TABLE block the line
-- was actually inside.
--
-- Diver Form needs an EDITABLE last dive date (a secretary correcting a
-- diver's accidental registration input) — that has to be the evergreen
-- divers copy, not diver_registrations, which is enforced immutable
-- once signed (enforce_registration_immutability). Matches exactly how
-- Diver Detail already edits divers.accommodation, never
-- diver_registrations.accommodation.

begin;

alter table public.divers add column last_dive_date date;

-- submit_diver_registration: copy last_dive_date onto divers too, same
-- as accommodation/emergency-contact/insurance already are, on both the
-- insert-new-diver and update-existing-diver branches. Everything else
-- in this function is unchanged from 017's version.
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
    insert into public.divers (
      dive_center_id, first_name, last_name, birthday, age, nationality, email, phone, whatsapp,
      certification_level, training_agency, logged_dives, last_dive_date, nitrox_certified, group_id,
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
