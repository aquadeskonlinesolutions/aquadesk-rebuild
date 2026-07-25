-- AquaDesk Rebuild — Registration flow server-side functions
-- These are the safe gateway for the public, unauthenticated /register page.
-- Anon has no RLS-granted access to divers/diver_registrations/medical_questions/
-- etc. at all — every read and write for registration goes through one of
-- these SECURITY DEFINER functions, which validate the dive center is real
-- and active before doing anything.

create or replace function public.get_registration_config(
  p_dive_center_id uuid,
  p_group_id uuid default null
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_dc record;
  v_group record;
  v_registered_count integer;
  v_result jsonb;
begin
  select id, name, logo_url, waiver_content, offers_dive_insurance, insurance_referral_link, subscription_status
    into v_dc
  from public.dive_centers
  where id = p_dive_center_id;

  if v_dc.id is null or v_dc.subscription_status not in ('trial', 'active') then
    return jsonb_build_object('error', 'This registration link is not currently available.');
  end if;

  v_result := jsonb_build_object(
    'dive_center', jsonb_build_object(
      'id', v_dc.id,
      'name', v_dc.name,
      'logo_url', v_dc.logo_url,
      'waiver_content', v_dc.waiver_content,
      'offers_dive_insurance', v_dc.offers_dive_insurance,
      'insurance_referral_link', v_dc.insurance_referral_link
    ),
    'medical_questions', (
      select coalesce(jsonb_agg(jsonb_build_object('id', id, 'question_text', question_text) order by sort_order), '[]'::jsonb)
      from public.medical_questions
      where dive_center_id = p_dive_center_id and is_active = true
    ),
    'equipment_rental_rates', (
      select coalesce(jsonb_agg(jsonb_build_object('id', id, 'item_name', item_name, 'rate', rate, 'charge_type', charge_type) order by item_name), '[]'::jsonb)
      from public.equipment_rental_rates
      where dive_center_id = p_dive_center_id and is_active = true
    ),
    'privacy_notice', (select content from public.privacy_notice where id = true)
  );

  if p_group_id is not null then
    select id, group_name, leader_name, arrival_date, expected_count, is_active
      into v_group
    from public.groups
    where id = p_group_id and dive_center_id = p_dive_center_id;

    if v_group.id is not null and v_group.is_active then
      select count(*) into v_registered_count from public.divers where group_id = v_group.id;
      v_result := v_result || jsonb_build_object('group', jsonb_build_object(
        'id', v_group.id,
        'group_name', v_group.group_name,
        'leader_name', v_group.leader_name,
        'arrival_date', v_group.arrival_date,
        'expected_count', v_group.expected_count,
        'registered_count', v_registered_count
      ));
    end if;
  end if;

  return v_result;
end;
$$;

grant execute on function public.get_registration_config(uuid, uuid) to anon, authenticated;

-- Step 1 of returning-diver flow: match by email, return only enough to ask
-- "is this you?" — never hand back PII from an email guess without confirmation.
create or replace function public.check_returning_diver(p_dive_center_id uuid, p_email text)
returns table(id uuid, first_name text, last_name text)
language sql stable security definer set search_path = public as $$
  select d.id, d.first_name, d.last_name
  from public.divers d
  where d.dive_center_id = p_dive_center_id
    and d.email is not null
    and lower(d.email) = lower(p_email)
  order by d.created_at desc
  limit 1;
$$;

grant execute on function public.check_returning_diver(uuid, text) to anon, authenticated;

-- Step 2: only called after the diver confirms "yes, that's me".
create or replace function public.get_diver_prefill(p_diver_id uuid, p_dive_center_id uuid)
returns table(
  first_name text, last_name text, nationality text, birthday date,
  phone text, whatsapp text, notes text
)
language sql stable security definer set search_path = public as $$
  select d.first_name, d.last_name, d.nationality, d.birthday, d.phone, d.whatsapp, d.notes
  from public.divers d
  where d.id = p_diver_id and d.dive_center_id = p_dive_center_id;
$$;

grant execute on function public.get_diver_prefill(uuid, uuid) to anon, authenticated;

-- The actual submission. Creates or updates the diver master record and
-- always inserts a fresh, immutable diver_registrations row for this visit.
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
      notes = case when v_new_note is not null
        then coalesce(v_existing_notes || E'\n', '') || v_new_note
        else v_existing_notes
      end
    where id = v_diver_id;
  else
    insert into public.divers (
      dive_center_id, first_name, last_name, birthday, age, nationality, email, phone, whatsapp,
      certification_level, training_agency, logged_dives, nitrox_certified, group_id,
      needs_equipment, equipment_requested, notes
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
      v_new_note
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
    waiver_signature_url, waiver_signed, duplicate_email_flag
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
    coalesce((p_payload->>'duplicate_email_flag')::boolean, false)
  )
  returning id into v_registration_id;

  return jsonb_build_object('diver_id', v_diver_id, 'registration_id', v_registration_id);
end;
$$;

grant execute on function public.submit_diver_registration(jsonb) to anon, authenticated;
