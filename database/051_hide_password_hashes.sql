-- AquaDesk Rebuild — close the password-lockout bypass (Fix 6, part 2 of 2)
--
-- !!! Run this ONLY AFTER the code that uses password_status() /
-- check_unlock_password() / unlock_bill() is deployed. The code deployed
-- before that reads dive_centers.*_unlock_hash and calls verify_*_unlock
-- directly, and would break (Settings > Passwords, Settings > Pricing,
-- Unlock Bill) if this ran first.
--
-- Before this, any logged-in staff user could:
--   1. read dive_centers.billing_unlock_hash / owner_unlock_hash (bcrypt,
--      cost 6) through the API and brute-force them offline, and
--   2. call verify_billing_unlock / verify_owner_unlock directly with
--      unlimited guesses,
-- either of which bypasses the 5-tries/30-minute lockout.
--
-- Postgres can't deny one column while the table-level SELECT grant
-- exists, so this replaces the table-level SELECT for anon/authenticated
-- with a column-level grant on every column EXCEPT the two hashes.
-- RLS policies are unchanged; service_role and SECURITY DEFINER functions
-- (cancel_deposit, unlock_bill, set_*_unlock, password_status, ...) are
-- unaffected.
--
-- NOTE for future migrations: a NEW column added to dive_centers after
-- this is not readable by the app until it is granted explicitly, e.g.
--   grant select (new_column) on public.dive_centers to anon, authenticated;
-- Also, select('*') on dive_centers now fails for staff (no app code uses it).

begin;

revoke select on public.dive_centers from anon, authenticated;

do $$
declare
  v_cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
  into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'dive_centers'
    and column_name not in ('billing_unlock_hash', 'owner_unlock_hash');
  execute format('grant select (%s) on public.dive_centers to anon, authenticated', v_cols);
end $$;

revoke execute on function public.verify_billing_unlock(uuid, text) from public, anon, authenticated;
revoke execute on function public.verify_owner_unlock(uuid, text) from public, anon, authenticated;

commit;

-- ---- Rollback (safe any time) -----------------------------------------------
-- begin;
-- grant select on public.dive_centers to anon, authenticated;
-- grant execute on function public.verify_billing_unlock(uuid, text) to public, anon, authenticated;
-- grant execute on function public.verify_owner_unlock(uuid, text) to public, anon, authenticated;
-- commit;
