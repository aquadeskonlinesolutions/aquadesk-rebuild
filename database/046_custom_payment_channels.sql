-- AquaDesk Rebuild — Payment Channel "+ Add Channel"
--
-- Same pattern as 045's Expense "+ Add Category": the 4 fixed channels
-- (E-Wallet, PayPal, Wise, Bank) are untouched — same enum, same labels.
-- One new enum sentinel ('custom') plus one new shared per-dive-center
-- lookup table, referenced by a new nullable FK column on every one of
-- the 6 tables that records a channel (added across migrations 043/045):
-- payments, deposits, expenses, join_ride_records, rental_gear_records,
-- staff_commission_records.
--
-- Note: ALTER TYPE ... ADD VALUE cannot be *used* within the same
-- transaction that adds it. Nothing else in this migration references
-- 'custom', so it's safe inside one begin/commit.

begin;

alter type public.payment_channel add value 'custom';

create table public.payment_channels (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  label text not null,
  normalized_label text not null,
  created_at timestamptz not null default now(),
  unique (dive_center_id, normalized_label)
);

alter table public.payment_channels enable row level security;
create policy payment_channels_select on public.payment_channels for select
  using (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue());
create policy payment_channels_write on public.payment_channels for all
  using (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue())
  with check (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue());

alter table public.payments
  add column custom_online_channel_id uuid references public.payment_channels(id) on delete set null;
alter table public.deposits
  add column custom_channel_id uuid references public.payment_channels(id) on delete set null;
alter table public.expenses
  add column custom_channel_id uuid references public.payment_channels(id) on delete set null;
alter table public.join_ride_records
  add column custom_channel_id uuid references public.payment_channels(id) on delete set null;
alter table public.rental_gear_records
  add column custom_channel_id uuid references public.payment_channels(id) on delete set null;
alter table public.staff_commission_records
  add column custom_channel_id uuid references public.payment_channels(id) on delete set null;

commit;
