-- AquaDesk Rebuild — Spare Tanks: quantity per type
--
-- schedule_spare_tanks (020) modeled "carrying more than one of a type"
-- as adding another identical row — functionally fine but a clunky UI
-- (repeat the same dropdown pick N times to mean "N of them"). Real ask:
-- one row per tank type, with a quantity on it.

begin;

alter table public.schedule_spare_tanks
  add column quantity integer not null default 1 check (quantity > 0);

commit;
