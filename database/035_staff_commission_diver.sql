begin;

-- Our Dive Educators (Reports > Staff Activity Summary) moves from one
-- aggregated row per (staff, date, course) to one row per (staff, date,
-- course, student) — each student on a course now generates their own
-- commission row instead of being folded into a shared group. diver_id lets
-- that per-student row be matched/updated on save (app-level lookup in
-- reports/actions.ts's findExistingCommission, same as the existing
-- staff_name/title/activity_date match — there is no DB unique constraint on
-- this table to update, matching is entirely app-level) and lets the UI show
-- "Diver Name" without re-deriving it from free text. Nullable and unused by
-- dive_leader-group rows (Leading Our Dives stays grouped per trip, not per
-- diver).
alter table staff_commission_records
  add column diver_id uuid references divers(id) on delete set null;

commit;
