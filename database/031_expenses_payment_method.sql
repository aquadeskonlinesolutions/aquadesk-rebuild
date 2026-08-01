-- AquaDesk Rebuild — replace expenses.paid_by (free-text "who/what funded
-- this", matching the live app's real field exactly) with a real payment
-- method (reusing the existing public.payment_method enum, already used by
-- deposits.method) plus reading the already-existing expenses.created_by
-- column (present since 001_schema_and_rls.sql, already written on every
-- save, but never selected/displayed anywhere until now).
--
-- User's explicit ask, after clarifying: "Paid By" as free text was
-- confusing — should instead show who recorded the expense (the logged-in
-- user, captured automatically, not a manual field) and how it was paid
-- (a real dropdown). No live-app precedent for a payment-method field on
-- expenses at all (confirmed by grepping reports.html) — this is a
-- genuine, deliberate improvement over the live app, not a parity fix.

begin;

alter table public.expenses
  add column payment_method public.payment_method,
  drop column paid_by;

commit;
