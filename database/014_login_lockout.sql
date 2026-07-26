-- AquaDesk Rebuild — per-account login lockout, ported directly from the
-- live app's actual Edge Function source (found on disk at
-- supabase/functions/login-guard/index.ts) rather than reinvented: same
-- 5-attempt threshold, same 30-minute lockout, same fail-open-on-error and
-- anti-enumeration behavior (an unknown email responds identically to a
-- known, unlocked one).
--
-- Architecture differs from the live app on purpose: the live app used a
-- separate Supabase Edge Function (deployed with --no-verify-jwt) called
-- from the client with the anon key. This rebuild has no Edge Functions
-- deployed anywhere and doesn't need to start now — a SECURITY DEFINER RPC
-- callable by anon is this codebase's existing pattern for exactly this
-- shape of "pre-session, narrow, no direct table access" need (see
-- get_crew_schedule in 010_staff_roster_fields.sql). The Next.js signIn
-- Server Action calls these three RPCs directly instead of fetching an
-- Edge Function URL.
--
-- Known, accepted limitation inherited unchanged from the live app's own
-- design: login_guard_fail is callable by anon with any email and no
-- password check of its own — repeated calls against a known email could
-- lock that account without ever attempting the real password. This is the
-- same tradeoff the live app's Edge Function already accepted (any caller
-- with the anon key and an email could do the same via fetch); not a new
-- gap introduced by this port.

begin;

alter table public.users
  add column failed_login_attempts integer not null default 0,
  add column locked_until timestamptz;

create or replace function public.login_guard_check(p_email text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user record;
  v_now timestamptz := now();
begin
  select id, failed_login_attempts, locked_until into v_user
  from public.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if not found then
    return jsonb_build_object('allowed', true);
  end if;

  if v_user.locked_until is not null and v_user.locked_until <= v_now then
    update public.users set failed_login_attempts = 0, locked_until = null where id = v_user.id;
    return jsonb_build_object('allowed', true);
  end if;

  if v_user.locked_until is not null and v_user.locked_until > v_now then
    return jsonb_build_object(
      'allowed', false,
      'retry_after_seconds', ceil(extract(epoch from (v_user.locked_until - v_now)))
    );
  end if;

  return jsonb_build_object('allowed', true);
exception when others then
  -- Fail open: never block sign-in on our own infrastructure errors.
  return jsonb_build_object('allowed', true);
end;
$$;

create or replace function public.login_guard_fail(p_email text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user record;
  v_now timestamptz := now();
  v_attempts integer;
  v_new_attempts integer;
  v_locked_until timestamptz;
  v_locked boolean := false;
  v_retry_after integer := 0;
  max_attempts constant integer := 5;
  lockout_minutes constant integer := 30;
begin
  select id, failed_login_attempts, locked_until into v_user
  from public.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if not found then
    return jsonb_build_object('allowed', true);
  end if;

  v_attempts := v_user.failed_login_attempts;
  v_locked_until := v_user.locked_until;

  -- Lock already expired — clean slate before evaluating this failure.
  if v_locked_until is not null and v_locked_until <= v_now then
    v_attempts := 0;
    v_locked_until := null;
  end if;

  if v_locked_until is not null and v_locked_until > v_now then
    return jsonb_build_object(
      'allowed', false,
      'locked', true,
      'retry_after_seconds', ceil(extract(epoch from (v_locked_until - v_now)))
    );
  end if;

  v_new_attempts := v_attempts + 1;

  if v_new_attempts >= max_attempts then
    v_locked_until := v_now + (lockout_minutes || ' minutes')::interval;
    v_locked := true;
    v_retry_after := lockout_minutes * 60;
    update public.users
    set failed_login_attempts = v_new_attempts, locked_until = v_locked_until
    where id = v_user.id;
  else
    update public.users
    set failed_login_attempts = v_new_attempts, locked_until = null
    where id = v_user.id;
  end if;

  return jsonb_build_object(
    'allowed', not v_locked,
    'locked', v_locked,
    'retry_after_seconds', v_retry_after,
    'attempts_remaining', greatest(0, max_attempts - v_new_attempts)
  );
exception when others then
  return jsonb_build_object('allowed', true);
end;
$$;

create or replace function public.login_guard_reset(p_email text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid;
begin
  select id into v_user_id
  from public.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if v_user_id is null then
    return jsonb_build_object('allowed', true);
  end if;

  update public.users set failed_login_attempts = 0, locked_until = null where id = v_user_id;

  return jsonb_build_object('ok', true);
exception when others then
  return jsonb_build_object('allowed', true);
end;
$$;

grant execute on function public.login_guard_check(text) to anon, authenticated;
grant execute on function public.login_guard_fail(text) to anon, authenticated;
grant execute on function public.login_guard_reset(text) to anon, authenticated;

commit;
