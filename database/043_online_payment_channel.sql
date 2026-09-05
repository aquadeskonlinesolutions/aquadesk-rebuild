-- AquaDesk Rebuild — Online payment channel
--
-- "Online" as a payment method needs a required sub-detail: which channel
-- (E-Wallet / PayPal / Wise / Bank). This adds one new enum and a nullable
-- channel column everywhere a payment method is recorded — the 3 places
-- that already had payment_method (payments, deposits, expenses) plus 3
-- places that had no payment-method concept at all until now (join ride
-- settlement, rental gear settlement, staff commission payout).
--
-- Every new column is nullable and nothing existing is backfilled or
-- constrained — a historical settled record simply keeps a blank method/
-- channel, which is accurate (we don't actually know what it was paid
-- with). "Online requires a channel" is enforced only in the app's server
-- actions for new writes going forward, not as a DB check constraint,
-- specifically so this migration can't fail or lock out old rows.

begin;

create type public.payment_channel as enum ('e_wallet', 'paypal', 'wise', 'bank');

-- Already had a method concept — just add the channel alongside it.
alter table public.payments add column online_channel public.payment_channel;
alter table public.deposits add column channel public.payment_channel;
alter table public.expenses add column channel public.payment_channel;

-- Had no payment-method concept at all before this — settling one of
-- these records now optionally captures how it was paid.
alter table public.join_ride_records
  add column payment_method public.payment_method,
  add column channel public.payment_channel;

alter table public.rental_gear_records
  add column payment_method public.payment_method,
  add column channel public.payment_channel;

alter table public.staff_commission_records
  add column payment_method public.payment_method,
  add column channel public.payment_channel;

commit;
