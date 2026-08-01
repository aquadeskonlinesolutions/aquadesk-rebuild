-- AquaDesk Rebuild — schedule_divers.staff_name: fixes a real freelancer
-- name-loss bug found in Scheduling.
--
-- A team's staff assignment can be a freelancer (no `staff` table row —
-- schedule_divers.staff_id is null by design, only a free-typed name
-- exists). saveTripTeams (scheduling/actions.ts) never persisted that
-- typed name anywhere on schedule_divers — only staff_id. So every time
-- a trip built around a freelancer was reloaded (TripCard.tsx's own
-- Build-phase reload, and Phase 3's per-team summary/preview), the
-- freelancer's name couldn't be reconstructed and silently fell back to
-- "Unassigned" — reported by the user as "Phase 2/3: clips is assigned
-- to unassigned." schedule_team_clips and schedule_staff_dive_tanks
-- already denormalize staff_name for the exact same reason (a freelancer
-- has no stable staff_id to look up later) — this column brings
-- schedule_divers in line with that same established pattern.
--
-- Written for every team (real staff or freelancer), not just
-- freelancers, so the reload path has one single source of truth
-- instead of two different lookup strategies depending on whether
-- staff_id is set.

begin;

alter table public.schedule_divers
  add column staff_name text;

commit;
