-- AquaDesk Rebuild — "today" column defaults use the Asia/Manila date
--
-- Two date columns default to CURRENT_DATE, which on Supabase is the UTC
-- date — so between 00:00 and 08:00 Manila a row left to its default got
-- yesterday's date:
--   visits.visit_start     (001) — actually relied on: createVisit and the
--                                   divers page's visit insert don't set it
--   deposits.deposit_date  (001) — addDeposit always sets it; default unused
-- Both now default to (now() at time zone 'Asia/Manila')::date, the same
-- expression every SQL function in this project already uses.
-- (govt_fees.date has no default — 006 dropped it — so it is not touched.)
--
-- Only the DEFAULT changes: no column, type, constraint, existing row,
-- function, grant or policy is touched, and rows that set the value
-- explicitly (all deposits) behave exactly as before. The currently
-- deployed code keeps working unchanged.

begin;

alter table public.visits   alter column visit_start  set default ((now() at time zone 'Asia/Manila')::date);
alter table public.deposits alter column deposit_date set default ((now() at time zone 'Asia/Manila')::date);

commit;

-- ---- Rollback (safe any time) -----------------------------------------------
-- begin;
-- alter table public.visits   alter column visit_start  set default current_date;
-- alter table public.deposits alter column deposit_date set default current_date;
-- commit;
