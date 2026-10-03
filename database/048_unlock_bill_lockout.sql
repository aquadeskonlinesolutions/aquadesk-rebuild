-- AquaDesk Rebuild — wrong-password lockout for Unlock Bill
--
-- Unlock Bill previously called verify_billing_unlock (unlimited guesses)
-- and then wrote the visit + audit row from the app. This adds:
--
--   billing_password_gate(): an internal helper with exactly the same
--     lockout rules cancel_deposit() (migration 047) already uses — 5
--     wrong tries -> 30-minute lock, "N attempt(s) left", reset by a
--     correct attempt — reading/writing the same billing_password_attempts
--     table. Failures are counted per user across ALL actions (confirmed
--     by MK 2026-10-03: one shared counter), which is also how
--     cancel_deposit already counts. Not callable by clients.
--
--   unlock_bill(): verifies the billing password through the gate, then
--     reopens the visit and writes the 'bill_unlocked' audit row (the same
--     row log_bill_unlock writes) in one transaction. Returns jsonb and
--     never raises for expected failures, so a wrong-password attempt is
--     committed (a raise would roll it back and defeat the lockout).
--
-- Purely additive: verify_billing_unlock and log_bill_unlock are untouched
-- and the currently deployed code keeps working.

begin;

create or replace function public.billing_password_gate(p_kind text, p_password text, p_action text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_user record;
  v_hash text;
  v_now timestamptz := now();
  v_last_success timestamptz;
  v_fail_count integer;
  v_last_fail timestamptz;
  v_label text := case when p_kind = 'owner' then 'owner' else 'billing' end;
  max_attempts constant integer := 5;
  lockout_minutes constant integer := 30;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'not_authenticated', 'error', 'Not signed in.');
  end if;
  select id, dive_center_id, role, is_active into v_user from public.users where id = v_uid;
  if not found or not v_user.is_active then
    return jsonb_build_object('ok', false, 'code', 'forbidden', 'error', 'You do not have permission to do this.');
  end if;
  if p_kind not in ('billing', 'owner') then
    return jsonb_build_object('ok', false, 'code', 'forbidden', 'error', 'Unknown password type.');
  end if;
  if p_kind = 'owner' and v_user.role <> 'owner' then
    return jsonb_build_object('ok', false, 'code', 'forbidden', 'error', 'Only the owner can use the owner password.');
  end if;

  -- Same counting as cancel_deposit (047): failures since the last success,
  -- inside the window, for this user, across every action.
  select max(attempted_at) into v_last_success
  from public.billing_password_attempts where user_id = v_uid and succeeded;
  select count(*), max(attempted_at) into v_fail_count, v_last_fail
  from public.billing_password_attempts
  where user_id = v_uid and not succeeded
    and attempted_at > v_now - make_interval(mins => lockout_minutes)
    and attempted_at > coalesce(v_last_success, '-infinity'::timestamptz);

  if v_fail_count >= max_attempts then
    return jsonb_build_object(
      'ok', false, 'code', 'rate_limited',
      'error', format('Too many wrong %s password attempts. Try again in %s minute(s).', v_label,
        greatest(1, ceil(extract(epoch from (v_last_fail + make_interval(mins => lockout_minutes) - v_now)) / 60)::int)),
      'retry_after_seconds', greatest(0, ceil(extract(epoch from (v_last_fail + make_interval(mins => lockout_minutes) - v_now)))::int)
    );
  end if;

  select case when p_kind = 'owner' then owner_unlock_hash else billing_unlock_hash end
  into v_hash from public.dive_centers where id = v_user.dive_center_id;
  if v_hash is null then
    return jsonb_build_object('ok', false, 'code', 'no_password',
      'error', format('No %s password is set for this dive center. The owner can set one in Settings > Passwords.', v_label));
  end if;

  if p_password is null or v_hash <> crypt(p_password, v_hash) then
    insert into public.billing_password_attempts (dive_center_id, user_id, action, succeeded)
    values (v_user.dive_center_id, v_uid, p_action, false);
    return jsonb_build_object(
      'ok', false, 'code', 'wrong_password',
      'error', case
        when max_attempts - (v_fail_count + 1) <= 0
          then format('Incorrect %s password. Too many attempts — locked for %s minutes.', v_label, lockout_minutes)
        else format('Incorrect %s password. %s attempt(s) left.', v_label, max_attempts - (v_fail_count + 1))
      end,
      'attempts_remaining', greatest(0, max_attempts - (v_fail_count + 1))
    );
  end if;

  insert into public.billing_password_attempts (dive_center_id, user_id, action, succeeded)
  values (v_user.dive_center_id, v_uid, p_action, true);
  return jsonb_build_object('ok', true, 'dive_center_id', v_user.dive_center_id);
end;
$$;

-- Internal only: called from other SECURITY DEFINER functions, never by clients.
revoke all on function public.billing_password_gate(text, text, text) from public, anon, authenticated;

create or replace function public.unlock_bill(p_visit_id uuid, p_password text, p_notes text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_gate jsonb;
  v_dc uuid;
  v_found uuid;
begin
  v_gate := public.billing_password_gate('billing', p_password, 'unlock_bill');
  if not (v_gate->>'ok')::boolean then
    return v_gate;
  end if;
  v_dc := (v_gate->>'dive_center_id')::uuid;

  update public.visits
    set is_paid = false, is_active = true, visit_status = 'open'
    where id = p_visit_id and dive_center_id = v_dc
    returning id into v_found;
  if v_found is null then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'error', 'Visit not found.');
  end if;

  insert into public.audit_logs (dive_center_id, action, target_type, target_id, performed_by, notes)
  values (v_dc, 'bill_unlocked', 'visits', p_visit_id, auth.uid(), p_notes);

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.unlock_bill(uuid, text, text) from public, anon;
grant execute on function public.unlock_bill(uuid, text, text) to authenticated;

commit;

-- ---- Rollback (safe at any time; attempt rows are kept) ---------------------
-- Redeploy code that calls verify_billing_unlock first if 051 was applied.
-- begin;
-- drop function if exists public.unlock_bill(uuid, text, text);
-- drop function if exists public.billing_password_gate(text, text, text);
-- commit;
