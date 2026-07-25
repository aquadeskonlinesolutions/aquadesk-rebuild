-- AquaDesk Rebuild — Fix govt_fees to match the live app's actual usage
-- Same root cause as the rate_tiers/dive_sites/boats fixes: the original
-- schema shaped this as a rate-config table (fee_name, amount, is_active),
-- but reports.html's real Government Fees tab is a **daily log** — one row
-- per day's fee collection, with a fixed 3-option fee type, a hand-typed
-- rate, a diver count, and a computed total. There is no separate
-- "standard rate" concept anywhere in the live app for this.
--
-- This was caught only while building Reports (which reads this table for
-- its Overview money-out total) — Settings > Pricing & Rates had already
-- shipped a "Government Fees" rate-config section against the old shape,
-- and Dashboard's "government fees not logged today" alert had been
-- skipped entirely because no daily-log table existed. Both get fixed
-- alongside this migration: the Settings section is removed (wrong
-- feature, not just a wrong field), and the Dashboard alert is restored.
--
-- No real data exists in this table yet (nothing in the live rebuild has
-- ever written to it — the Settings section that did was never used with
-- real numbers), so this is a plain fix, not a migration with data to
-- preserve.

begin;

alter table public.govt_fees
  drop column fee_name,
  drop column amount,
  drop column is_active;

alter table public.govt_fees
  add column date date not null default current_date,
  add column fee_type text not null default 'Marine Fee'
    check (fee_type in ('Marine Fee', 'Shark Fee', 'Other Fee')),
  add column rate numeric(12,2) not null default 0,
  add column divers integer not null default 0,
  add column total numeric(12,2) not null default 0,
  add column created_at timestamptz not null default now();

alter table public.govt_fees alter column date drop default;
alter table public.govt_fees alter column fee_type drop default;

create index govt_fees_dive_center_date_idx on public.govt_fees (dive_center_id, date);

commit;
