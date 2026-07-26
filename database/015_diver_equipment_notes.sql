-- AquaDesk Rebuild — Equipment Management tab (Divers page) needs a place
-- for staff prep remarks per diver, distinct from divers.notes (which is
-- unused by anything currently — the Diver Detail Notes panel actually
-- writes to its own diver_notes table, not this column) and distinct from
-- equipment_requested (the diver's own requested items, set at
-- registration). The live app used a column literally named
-- "equipment notes" (with a space) on divers — same concept, real name here.

begin;

alter table public.divers
  add column equipment_notes text;

commit;
