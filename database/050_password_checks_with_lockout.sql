-- AquaDesk Rebuild — password checks that go through the lockout (Fix 6, part 1 of 2)
--
-- Purely additive. Safe to run BEFORE the matching code deploy: nothing
-- existing changes, and the currently deployed code keeps working.
-- Requires 048 (billing_password_gate).
--
--   password_status(): tells any active staff user whether the owner and
--     billing passwords are SET for their own dive center — booleans only,
--     never the hashes. Replaces the app reading *_unlock_hash columns
--     directly (Settings > Passwords, Settings > Pricing), which is what
--     lets 051 hide those columns.
--
--   check_unlock_password(kind, password): verifies the 'billing' or
--     'owner' password for the caller's own dive center through
--     billing_password_gate (048): same 5 tries / 30-minute lock and the
--     same shared per-user counter as Cancel Deposit and Unlock Bill. The
--     owner password can only be checked by an owner. Replaces direct
--     verify_billing_unlock / verify_owner_unlock calls, which 051 revokes.

begin;

create or replace function public.password_status()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'owner_set', dc.owner_unlock_hash is not null,
    'billing_set', dc.billing_unlock_hash is not null
  )
  from public.dive_centers dc
  join public.users u on u.dive_center_id = dc.id
  where u.id = auth.uid() and u.is_active;
$$;

revoke all on function public.password_status() from public, anon;
grant execute on function public.password_status() to authenticated;

create or replace function public.check_unlock_password(p_kind text, p_password text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  return public.billing_password_gate(p_kind, p_password, 'check_' || coalesce(p_kind, ''));
end;
$$;

revoke all on function public.check_unlock_password(text, text) from public, anon;
grant execute on function public.check_unlock_password(text, text) to authenticated;

commit;

-- ---- Rollback (safe any time BEFORE 051; after 051, roll 051 back first) ----
-- begin;
-- drop function if exists public.check_unlock_password(text, text);
-- drop function if exists public.password_status();
-- commit;
