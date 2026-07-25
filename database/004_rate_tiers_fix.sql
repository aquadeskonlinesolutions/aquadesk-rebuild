-- AquaDesk Rebuild — Fix rate_tiers to match the live app's actual usage
-- The original Stage 1a schema invented a rate_tiers shape (tier_name,
-- min_dives, max_dives, rate) that doesn't match how the live app's
-- settings.html actually reads/writes this table (tier_from, tier_to,
-- base_rate, rate_type). Worse, it had no column at all to distinguish the
-- three kinds of tiered rates the live app manages in one table: the base
-- per-dive rate, the nitrox add-on rate, and the 15L tank add-on rate —
-- they'd silently collide. Caught while building the Settings > Pricing &
-- Rates page, before anything used the table, so this is a plain fix, not
-- a migration with real data to preserve.

begin;

alter table public.rate_tiers
  drop column tier_name,
  drop column min_dives,
  drop column max_dives;

alter table public.rate_tiers
  add column tier_from integer not null default 1,
  add column tier_to integer,
  add column rate_type text not null default 'base_dive'
    check (rate_type in ('base_dive', 'nitrox', 'tank_15l'));

alter table public.rate_tiers rename column rate to base_rate;

alter table public.rate_tiers alter column tier_from drop default;
alter table public.rate_tiers alter column rate_type drop default;

commit;
