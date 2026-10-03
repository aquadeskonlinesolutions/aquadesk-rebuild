-- AquaDesk Rebuild — block direct UPDATE/DELETE of deposits through the API
--
-- The generic operational-table policies (001_schema_and_rls.sql) let any
-- dive-center user update or delete any of their center's deposits
-- directly through the REST API, bypassing the app (e.g. changing an
-- amount after it was taken). Every legitimate deposit write path was
-- checked (2026-10-03) and none needs a direct client UPDATE or DELETE:
--   - Add Deposit (addDeposit server action)  -> INSERT, still allowed
--   - Cancel Deposit (cancel_deposit RPC, 047) -> SECURITY DEFINER, runs as
--     the table owner, not subject to these policies
--   - Void Visit (voidVisit) -> deletes the visit; the FK cascade removes
--     its deposits, and referential actions are not subject to RLS
--   - Data migration ETL (database/migration/etl.js) -> service role, bypasses RLS
-- There is no "delete deposit" feature in the app (confirmed with MK:
-- a wrong deposit is corrected with Cancel Deposit + full refund, which
-- keeps an audit trail).
--
-- Restrictive policies AND with the existing permissive ones, so
-- deposits_update / deposits_delete (001) and deposits_delete_not_cancelled
-- (047) stay in place untouched. SELECT and INSERT policies, and tenant
-- isolation, are unchanged. The currently deployed code never updates or
-- deletes deposits directly, so it keeps working after this runs.

begin;

create policy deposits_no_client_update on public.deposits as restrictive for update
  using (false) with check (false);

create policy deposits_no_client_delete on public.deposits as restrictive for delete
  using (false);

commit;

-- ---- Rollback (safe at any time) ------------------------------------------
-- begin;
-- drop policy if exists deposits_no_client_update on public.deposits;
-- drop policy if exists deposits_no_client_delete on public.deposits;
-- commit;
