-- AquaDesk Rebuild — Staff Commission / Payout Summary
--
-- Replaces the whole-calendar-month commission model with per-line-item
-- (one row per dive-group or course-group, keyed by its real activity
-- date) so a secretary can mark an arbitrary date range "paid" without
-- affecting entries outside that range — the live app only supports a
-- single paid/unpaid status per staff per calendar month, which is one of
-- the exact limitations this feature replaces.
--
-- Also adds dive-center-wide configurable rates: a flat divemaster
-- per-dive rate, an optional ratio bonus (no formula — just an on/off
-- flag and a reference "extra rate" the UI pre-fills into a manual bonus
-- field), and a join ride rate. None of these have any live-app
-- precedent (confirmed by grepping all old HTML reference files) — the
-- live app hardcodes a join-ride rate in reports.html's UI copy and has
-- no divemaster-rate or ratio-bonus concept anywhere.
--
-- No real data exists in staff_commission_records yet, so this is a
-- plain alter, not a migration with data to preserve (same situation as
-- 006_govt_fees_daily_log.sql).

begin;

alter table public.dive_centers
  add column divemaster_rate_per_dive numeric(12,2) not null default 0,
  add column ratio_bonus_enabled boolean not null default false,
  add column ratio_bonus_extra_rate numeric(12,2) not null default 0,
  add column join_ride_rate_per_diver_per_dive numeric(12,2) not null default 0;

alter table public.staff_commission_records
  drop column period_month,
  add column activity_date date not null,
  add column divers integer not null default 0,
  add column bonus_amount numeric(12,2) not null default 0;

create index staff_commission_records_dive_center_date_idx
  on public.staff_commission_records (dive_center_id, activity_date);

commit;
