-- AquaDesk Rebuild — deposit cancellation (soft state, never a delete)
--
-- A deposit can now be cancelled when a diver decides not to continue.
-- Each dive center has its own policy, so staff choose how much of the
-- deposit is refunded; the rest is forfeited (retained by the center).
--
-- Purely additive: no existing column, constraint, policy or function is
-- changed. Every existing deposit row is backfilled to status = 'active'
-- (via the column default) and behaves exactly as before.
--
-- Money model (cash basis, confirmed by MK 2026-10-03): the original
-- deposit row's amount/deposit_date are never touched, so the day it was
-- received keeps its figures. The refund is a cash outflow on the
-- cancellation day (cancelled_date, Asia/Manila), through refund_method/
-- refund_channel. The forfeited amount was already counted as money in on
-- the day it was received and is NOT counted again.
--
-- Deposits are applied to a bill as a lump sum at checkout (see
-- checkoutVisit) — there is no per-deposit partial application in this
-- schema. So a deposit is either fully refundable (its visit is still
-- open, or it has no visit) or fully consumed (its visit was checked out
-- / closed). The refundable amount is therefore the whole amount, and a
-- deposit on a closed bill cannot be cancelled until the bill is unlocked.
--
-- The only way to cancel is the cancel_deposit() RPC below, which verifies
-- the billing password server-side (same bcrypt hash as
-- verify_billing_unlock), rate-limits wrong attempts (same 5 attempts /
-- 30 minutes as login lockout, migration 014), locks the row, and writes
-- an audit_logs entry. A guard trigger blocks any other path (e.g. a
-- direct client UPDATE, which the existing deposits_update RLS policy
-- would otherwise allow) from setting or changing the cancellation fields.

begin;

alter table public.deposits
  add column status text not null default 'active',
  add column cancelled_at timestamptz,
  add column cancelled_date date,
  add column cancelled_by uuid references public.users(id) on delete set null,
  add column cancel_reason text,
  add column refund_amount numeric(12,2),
  add column forfeited_amount numeric(12,2),
  add column refund_method public.payment_method,
  add column refund_channel public.payment_channel,
  add column refund_custom_channel_id uuid references public.payment_channels(id) on delete set null;

alter table public.deposits
  add constraint deposits_status_check check (status in ('active', 'cancelled')),
  add constraint deposits_cancellation_fields_check check (
    (
      status = 'active'
      and cancelled_at is null and cancelled_date is null and cancel_reason is null
      and refund_amount is null and forfeited_amount is null
      and refund_method is null and refund_channel is null and refund_custom_channel_id is null
    )
    or (
      status = 'cancelled'
      and cancelled_at is not null and cancelled_date is not null
      and cancel_reason is not null and length(btrim(cancel_reason)) > 0
      and refund_amount is not null and refund_amount >= 0
      and forfeited_amount is not null and forfeited_amount >= 0
      and refund_amount + forfeited_amount = amount
      and (refund_amount = 0 or refund_method is not null)
      and (refund_method is distinct from 'online' or refund_channel is not null)
    )
  );

-- Settlement/report lookups by cancellation day.
create index deposits_cancelled_date_idx on public.deposits (dive_center_id, cancelled_date)
  where status = 'cancelled';

-- ---- Wrong-password rate limiting ------------------------------------------
-- No client policies: only cancel_deposit() (SECURITY DEFINER) reads/writes.
create table public.billing_password_attempts (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  user_id uuid not null,
  action text not null,
  succeeded boolean not null,
  attempted_at timestamptz not null default now()
);
create index billing_password_attempts_user_idx on public.billing_password_attempts (user_id, attempted_at desc);
alter table public.billing_password_attempts enable row level security;
revoke all on public.billing_password_attempts from anon, authenticated;

-- ---- Guard: cancellation fields only change through cancel_deposit() --------
create or replace function public.guard_deposit_cancellation()
returns trigger
language plpgsql as $$
declare
  v_via_rpc boolean := coalesce(current_setting('aquadesk.cancel_deposit', true), '') = 'on';
begin
  if TG_OP = 'INSERT' then
    if NEW.status <> 'active' and not v_via_rpc then
      raise exception 'A deposit can only be created as active.';
    end if;
    return NEW;
  end if;

  if OLD.status = 'cancelled' and not v_via_rpc then
    raise exception 'A cancelled deposit cannot be edited.';
  end if;

  if not v_via_rpc and (
    NEW.status, NEW.cancelled_at, NEW.cancelled_date, NEW.cancelled_by, NEW.cancel_reason,
    NEW.refund_amount, NEW.forfeited_amount, NEW.refund_method, NEW.refund_channel,
    NEW.refund_custom_channel_id
  ) is distinct from (
    OLD.status, OLD.cancelled_at, OLD.cancelled_date, OLD.cancelled_by, OLD.cancel_reason,
    OLD.refund_amount, OLD.forfeited_amount, OLD.refund_method, OLD.refund_channel,
    OLD.refund_custom_channel_id
  ) then
    raise exception 'Deposits can only be cancelled through cancel_deposit().';
  end if;

  return NEW;
end;
$$;

create trigger deposits_guard_cancellation before insert or update on public.deposits
  for each row execute function public.guard_deposit_cancellation();

-- A cancelled deposit is part of the money trail — never hard-deleted by a
-- client. Restrictive, so it narrows the existing deposits_delete policy
-- only for cancelled rows; active deposits are unaffected. (FK cascades,
-- e.g. deleting a whole dive center, are not subject to RLS.)
create policy deposits_delete_not_cancelled on public.deposits as restrictive for delete
  using (status <> 'cancelled');

-- ---- The cancel operation ---------------------------------------------------
-- Returns jsonb, never raises for expected failures, so a wrong-password
-- attempt row is committed (a raise would roll it back and defeat the
-- rate limit). Codes: not_authenticated, forbidden, rate_limited,
-- invalid_refund, invalid_reason, invalid_refund_method, no_password,
-- wrong_password, not_found, already_cancelled, consumed, refund_too_high.
create or replace function public.cancel_deposit(
  p_deposit_id uuid,
  p_refund_amount numeric,
  p_reason text,
  p_password text,
  p_refund_method public.payment_method,
  p_refund_channel public.payment_channel,
  p_refund_custom_channel_id uuid
)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_user record;
  v_dep record;
  v_visit record;
  v_hash text;
  v_now timestamptz := now();
  v_cancelled_date date := (now() at time zone 'Asia/Manila')::date;
  v_last_success timestamptz;
  v_fail_count integer;
  v_last_fail timestamptz;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_refund numeric(12,2);
  v_forfeit numeric(12,2);
  v_method public.payment_method;
  v_channel public.payment_channel;
  v_custom_channel uuid;
  v_visit_updated_at timestamptz;
  max_attempts constant integer := 5;
  lockout_minutes constant integer := 30;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'not_authenticated', 'error', 'Not signed in.');
  end if;

  select id, dive_center_id, is_active into v_user from public.users where id = v_uid;
  if not found or not v_user.is_active then
    return jsonb_build_object('ok', false, 'code', 'forbidden', 'error', 'You do not have permission to cancel deposits.');
  end if;

  -- Rate limit: failures since the last successful attempt, inside the window.
  select max(attempted_at) into v_last_success
  from public.billing_password_attempts
  where user_id = v_uid and succeeded;

  select count(*), max(attempted_at) into v_fail_count, v_last_fail
  from public.billing_password_attempts
  where user_id = v_uid and not succeeded
    and attempted_at > v_now - make_interval(mins => lockout_minutes)
    and attempted_at > coalesce(v_last_success, '-infinity'::timestamptz);

  if v_fail_count >= max_attempts then
    return jsonb_build_object(
      'ok', false, 'code', 'rate_limited',
      'error', format('Too many wrong billing password attempts. Try again in %s minute(s).',
        greatest(1, ceil(extract(epoch from (v_last_fail + make_interval(mins => lockout_minutes) - v_now)) / 60)::int)),
      'retry_after_seconds', greatest(0, ceil(extract(epoch from (v_last_fail + make_interval(mins => lockout_minutes) - v_now)))::int)
    );
  end if;

  -- Input checks that need no password.
  if p_refund_amount is null or p_refund_amount < 0 or p_refund_amount <> round(p_refund_amount, 2) then
    return jsonb_build_object('ok', false, 'code', 'invalid_refund',
      'error', 'Refund amount must be 0 or more, with at most 2 decimal places.');
  end if;
  if v_reason = '' then
    return jsonb_build_object('ok', false, 'code', 'invalid_reason', 'error', 'A cancellation reason is required.');
  end if;
  if length(v_reason) > 1000 then
    return jsonb_build_object('ok', false, 'code', 'invalid_reason', 'error', 'Cancellation reason is too long (max 1000 characters).');
  end if;
  v_refund := p_refund_amount;

  if v_refund > 0 then
    if p_refund_method is null then
      return jsonb_build_object('ok', false, 'code', 'invalid_refund_method', 'error', 'Select how the refund was paid out.');
    end if;
    v_method := p_refund_method;
    if v_method = 'online' then
      if p_refund_channel is null then
        return jsonb_build_object('ok', false, 'code', 'invalid_refund_method', 'error', 'Select an Online channel for the refund.');
      end if;
      v_channel := p_refund_channel;
      if v_channel = 'custom' then
        if p_refund_custom_channel_id is null or not exists (
          select 1 from public.payment_channels
          where id = p_refund_custom_channel_id and dive_center_id = v_user.dive_center_id
        ) then
          return jsonb_build_object('ok', false, 'code', 'invalid_refund_method', 'error', 'Select a valid Online channel for the refund.');
        end if;
        v_custom_channel := p_refund_custom_channel_id;
      end if;
    end if;
  end if;

  -- Billing password (same hash verify_billing_unlock checks).
  select billing_unlock_hash into v_hash from public.dive_centers where id = v_user.dive_center_id;
  if v_hash is null then
    return jsonb_build_object('ok', false, 'code', 'no_password',
      'error', 'No billing password is set for this dive center. The owner can set one in Settings > Passwords.');
  end if;
  if p_password is null or v_hash <> crypt(p_password, v_hash) then
    insert into public.billing_password_attempts (dive_center_id, user_id, action, succeeded)
    values (v_user.dive_center_id, v_uid, 'cancel_deposit', false);
    return jsonb_build_object(
      'ok', false, 'code', 'wrong_password',
      'error', case
        when max_attempts - (v_fail_count + 1) <= 0
          then format('Incorrect billing password. Too many attempts — locked for %s minutes.', lockout_minutes)
        else format('Incorrect billing password. %s attempt(s) left.', max_attempts - (v_fail_count + 1))
      end,
      'attempts_remaining', greatest(0, max_attempts - (v_fail_count + 1))
    );
  end if;
  insert into public.billing_password_attempts (dive_center_id, user_id, action, succeeded)
  values (v_user.dive_center_id, v_uid, 'cancel_deposit', true);

  -- Lock the deposit row: a concurrent second cancel waits here, then sees
  -- status = 'cancelled' below and is rejected (no duplicate effects).
  select * into v_dep from public.deposits where id = p_deposit_id for update;
  if not found or v_dep.dive_center_id <> v_user.dive_center_id then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'error', 'Deposit not found.');
  end if;
  if v_dep.status = 'cancelled' then
    return jsonb_build_object('ok', false, 'code', 'already_cancelled', 'error', 'This deposit has already been cancelled.');
  end if;

  if v_dep.visit_id is not null then
    select is_paid, visit_status into v_visit from public.visits where id = v_dep.visit_id for update;
    if found and (v_visit.is_paid or v_visit.visit_status = 'closed') then
      return jsonb_build_object('ok', false, 'code', 'consumed',
        'error', 'This deposit was already applied to a closed bill, so it can''t be cancelled. Unlock the bill first if it needs correcting.');
    end if;
  end if;

  if v_refund > v_dep.amount then
    return jsonb_build_object('ok', false, 'code', 'refund_too_high',
      'error', format('Refund can''t be more than the refundable amount (%s).', to_char(v_dep.amount, 'FM999,999,990.00')));
  end if;
  v_forfeit := v_dep.amount - v_refund;

  perform set_config('aquadesk.cancel_deposit', 'on', true);
  update public.deposits set
    status = 'cancelled',
    cancelled_at = v_now,
    cancelled_date = v_cancelled_date,
    cancelled_by = v_uid,
    cancel_reason = v_reason,
    refund_amount = v_refund,
    forfeited_amount = v_forfeit,
    refund_method = v_method,
    refund_channel = v_channel,
    refund_custom_channel_id = v_custom_channel
  where id = p_deposit_id and status = 'active';
  perform set_config('aquadesk.cancel_deposit', 'off', true);

  -- Bump the visit's optimistic-concurrency token (visits_set_updated_at,
  -- migration 033) — the deposits total this bill was loaded with is now
  -- stale, so a Save/Checkout from another open session must hit the
  -- existing "someone else changed this bill" conflict instead of closing
  -- the bill with this cancelled deposit still credited. The new token is
  -- returned so the cancelling user's own page keeps working.
  if v_dep.visit_id is not null then
    update public.visits set is_active = is_active
    where id = v_dep.visit_id
    returning updated_at into v_visit_updated_at;
  end if;

  insert into public.audit_logs (dive_center_id, action, target_type, target_id, performed_by, notes)
  values (
    v_dep.dive_center_id, 'deposit_cancelled', 'deposits', v_dep.id, v_uid,
    format('Deposit of %s received %s cancelled. Refunded %s%s, forfeited %s. Reason: %s',
      to_char(v_dep.amount, 'FM999,999,990.00'), v_dep.deposit_date,
      to_char(v_refund, 'FM999,999,990.00'),
      case when v_refund > 0 then ' via ' || v_method::text || coalesce(' (' || v_channel::text || ')', '') else '' end,
      to_char(v_forfeit, 'FM999,999,990.00'), v_reason)
  );

  return jsonb_build_object(
    'ok', true,
    'deposit_id', v_dep.id,
    'refund_amount', v_refund,
    'forfeited_amount', v_forfeit,
    'cancelled_at', v_now,
    'cancelled_date', v_cancelled_date,
    'visit_updated_at', v_visit_updated_at
  );
end;
$$;

revoke all on function public.cancel_deposit(uuid, numeric, text, text, public.payment_method, public.payment_channel, uuid) from public, anon;
grant execute on function public.cancel_deposit(uuid, numeric, text, text, public.payment_method, public.payment_channel, uuid) to authenticated;

commit;

-- ---- Rollback (run manually only if this migration must be reverted) -------
-- Only safe before any deposit has actually been cancelled — once one has,
-- dropping these columns destroys the cancellation record. Check first:
--   select count(*) from public.deposits where status = 'cancelled';
--
-- begin;
-- drop function if exists public.cancel_deposit(uuid, numeric, text, text, public.payment_method, public.payment_channel, uuid);
-- drop policy if exists deposits_delete_not_cancelled on public.deposits;
-- drop trigger if exists deposits_guard_cancellation on public.deposits;
-- drop function if exists public.guard_deposit_cancellation();
-- drop table if exists public.billing_password_attempts;
-- drop index if exists public.deposits_cancelled_date_idx;
-- alter table public.deposits
--   drop constraint if exists deposits_cancellation_fields_check,
--   drop constraint if exists deposits_status_check,
--   drop column if exists refund_custom_channel_id,
--   drop column if exists refund_channel,
--   drop column if exists refund_method,
--   drop column if exists forfeited_amount,
--   drop column if exists refund_amount,
--   drop column if exists cancel_reason,
--   drop column if exists cancelled_by,
--   drop column if exists cancelled_date,
--   drop column if exists cancelled_at,
--   drop column if exists status;
-- commit;
-- (audit_logs rows with action = 'deposit_cancelled' are deliberately kept.)
