-- AquaDesk Rebuild — Backfill trace numbers for existing divers
--
-- Depends on 041_diver_trace_numbers.sql already being applied
-- (dive_centers.dive_center_code, divers.trace_number, and
-- dive_center_trace_counters must all already exist).
--
-- Assigns trace numbers to every existing diver, per dive center, oldest
-- registration first (divers.created_at ascending — the diver row's
-- original creation moment, set once at insert and never touched again;
-- NOT diver_registrations.created_at, which can have multiple rows per
-- diver from repeat visits). Ties broken by id for a deterministic,
-- reproducible result — a small handful of rows in the Package Test Dive
-- Center fixture share an identical created_at timestamp (a batch-seeded
-- fixture), so a tiebreak is genuinely needed, not just defensive.
--
-- Idempotent / gap-safe: only fills divers.trace_number where it's
-- currently null, and numbers them starting after however many trace
-- numbers that dive center has already handed out live (via
-- submit_diver_registration, active as soon as 041 is applied) — so
-- running this some time after 041, with real registrations happening
-- in between, still produces a consistent, non-colliding result rather
-- than renumbering or duplicating anything. Safe to run more than once:
-- a second run is a no-op (every divers.trace_number is already non-null
-- by then).

begin;

with existing_counts as (
  select dive_center_id, count(*) as already_assigned
  from public.divers
  where trace_number is not null
  group by dive_center_id
),
numbered as (
  select
    d.id,
    dc.dive_center_code || '-' || lpad(
      (coalesce(ec.already_assigned, 0)
        + row_number() over (partition by d.dive_center_id order by d.created_at asc, d.id asc))::text,
      4, '0'
    ) as new_trace_number
  from public.divers d
  join public.dive_centers dc on dc.id = d.dive_center_id
  left join existing_counts ec on ec.dive_center_id = d.dive_center_id
  where d.trace_number is null
)
update public.divers d
set trace_number = numbered.new_trace_number
from numbered
where d.id = numbered.id;

-- Advance each dive center's counter past every number now in use, so the
-- next live registration continues from the right place instead of
-- colliding with a just-backfilled number. Every diver has a trace_number
-- at this point (backfilled or already live-assigned), and numbers within
-- a dive center are contiguous from 1, so count(*) is exactly the highest
-- number in use.
update public.dive_center_trace_counters c
set next_number = greatest(c.next_number, sub.total + 1)
from (
  select dive_center_id, count(*) as total
  from public.divers
  group by dive_center_id
) sub
where c.dive_center_id = sub.dive_center_id;

commit;
