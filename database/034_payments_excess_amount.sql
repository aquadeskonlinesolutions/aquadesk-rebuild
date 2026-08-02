begin;

-- Tendered-but-unbilled amount (near-universal for foreign cash handed over
-- in whole bills/notes — e.g. $205 at ₱57 for an ₱11,500 bill overshoots by
-- ₱185). payments.total_paid/total_collected stay capped to what was billed
-- (the existing, deliberate "reconcile to what was billed, not what was
-- physically handed over" design) — this column captures the excess as its
-- own real, auditable figure instead of silently dropping it, so Dashboard/
-- Diver Form/Settlement/Reports can all show the same labeled number rather
-- than each re-deriving (or losing) it independently.
alter table payments
  add column excess_amount numeric not null default 0;

commit;
