begin;

-- Round 7 Fix 2: Rental and Join Ride collapsed into the same boolean
-- (schedules.is_joiner), so a Rental trip displayed as "Join Ride" after
-- every page reload — is_joiner alone can't distinguish "we rented a boat
-- with guests" from "we joined someone else's boat." Adds a real 3-value
-- mode column; is_joiner stays as-is (still correctly derived as
-- boat_mode <> 'own_boat' at every write site) since other code already
-- reads it for "is this our own boat" checks unrelated to this display bug.
alter table public.schedules
  add column boat_mode text not null default 'own_boat'
  check (boat_mode in ('own_boat', 'join_ride', 'rental'));

-- Best-effort backfill for existing rows: the old data never distinguished
-- Rental from Join Ride, so every pre-existing is_joiner=true row backfills
-- as 'join_ride' (the more common of the two in practice) — this can't be
-- retroactively corrected, only prevented going forward.
update public.schedules
set boat_mode = case when is_joiner then 'join_ride' else 'own_boat' end;

commit;
