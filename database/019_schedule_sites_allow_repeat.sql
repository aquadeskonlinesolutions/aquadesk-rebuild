-- AquaDesk Rebuild — schedule_sites must allow the same dive site twice
-- on one trip
--
-- Found while verifying the package-mode pricing fix (Diver Form Apply
-- Charges session): a package like "Shark Diving" (dive_site =
-- "Kimud, Kimud, Monad") genuinely revisits one site twice on a single
-- trip — confirmed directly from the user's own real business example
-- and from scheduling.html's real sites array, which has no
-- distinct-values requirement. schedule_sites' original
-- unique(schedule_id, dive_site_id) constraint made that impossible:
-- TripCard's replaceScheduleSites does one bulk insert of all slots,
-- so picking "Kimud" twice made the *entire* insert fail the unique
-- constraint — silently, since that insert never checked its .error —
-- leaving schedule_sites completely empty for the trip and,
-- downstream, markBoatReturned's siteNames list empty too.
--
-- The real invariant is per-slot uniqueness (sort_order), not per-site
-- uniqueness — a trip can have "Dive 1 = Kimud" and "Dive 2 = Kimud"
-- as two distinct slots.

begin;

alter table public.schedule_sites
  drop constraint schedule_sites_schedule_id_dive_site_id_key;

alter table public.schedule_sites
  add constraint schedule_sites_schedule_id_sort_order_key unique (schedule_id, sort_order);

commit;
