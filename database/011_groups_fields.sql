-- AquaDesk Rebuild — groups: capture the two fields the old app's
-- create-group-link form already collects but the original schema had
-- nowhere to store (departure_date, notes). Confirmed via
-- 001_schema_and_rls.sql that groups previously had only
-- group_name/leader_name/arrival_date/expected_count/is_active.

begin;

alter table public.groups
  add column departure_date date,
  add column notes text;

commit;
