-- AquaDesk Rebuild — capture "another dive center's divers joined our boat"
-- (the reverse of the existing is_joiner/joiner_boat_name pair, which means
-- "WE joined THEM"). The live app captured this via a JSON blob in
-- schedules.notes (joinerDivers/joinerDC/joinerNotes) — this rebuild
-- deliberately doesn't replicate that pattern, so real columns instead.
--
-- Column names chosen to be clearly distinct from is_joiner/joiner_boat_name
-- so the two directions can never be confused. Applies to any trip
-- regardless of boat mode, matching the live app's scheduling.html
-- joinerHTML() rendering it unconditionally per trip.

begin;

alter table public.schedules
  add column guest_divers_count integer,
  add column guest_dive_center_name text,
  add column guest_notes text;

commit;
