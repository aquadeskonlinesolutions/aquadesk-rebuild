-- AquaDesk Rebuild — Bill/payment notes
--
-- A small free-text notes field tied to the bill itself (one per visit's
-- payments row), separate from the existing diver-level `diver_notes`
-- table — this is scoped to a single bill, not the diver generally.
-- Nullable, no backfill needed (no existing payments row has this today).

begin;

alter table public.payments add column notes text;

commit;
