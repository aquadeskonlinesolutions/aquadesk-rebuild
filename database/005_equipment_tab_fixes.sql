-- AquaDesk Rebuild — Fix boats/dive_sites to match the live app's actual usage
-- Same root cause as 004_rate_tiers_fix.sql: the Stage 1a blueprint's table
-- inventory named these fields from a shallow pass over the live app,
-- without checking their real type/shape. Caught while building Settings >
-- Equipment, before anything used either table, so this is a plain fix,
-- not a migration with real data to preserve.
--
-- boats.capacity: live app tracks diver capacity per boat (used for trip
-- planning); the column didn't exist at all.
--
-- dive_sites.shark_fee: live app treats this as a per-site Yes/No toggle
-- ("does the shark fee apply diving at this site"), not a PHP amount — the
-- actual shark fee charge amount lives in other_charges/activities. Was
-- typed numeric(12,2) here, which doesn't match the toggle it actually is.
--
-- dive_sites.fuel_estimate: live app treats this as a Low/Medium/High
-- category select, not a PHP amount — was also typed numeric(12,2).
--
-- dive_sites.distance / linked_package_id: live app has both (a
-- human-readable travel time like "30 mins", and an optional link to a
-- package when the dive center uses package-mode pricing); neither
-- existed at all.

begin;

alter table public.boats
  add column capacity integer;

alter table public.dive_sites
  add column distance text,
  add column linked_package_id uuid references public.packages(id) on delete set null;

alter table public.dive_sites
  drop column shark_fee,
  drop column fuel_estimate;

alter table public.dive_sites
  add column shark_fee boolean not null default false,
  add column fuel_estimate text not null default 'High'
    check (fuel_estimate in ('Low', 'Medium', 'High'));

commit;
