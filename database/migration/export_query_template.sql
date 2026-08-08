-- Reusable read-only export query for pulling one or more dive centers'
-- data out of the LIVE Supabase project's SQL Editor. Never run against
-- anything but the live project's own SQL Editor (this repo's tooling
-- never connects to live directly — see CLAUDE.md's absolute rule).
--
-- HOW TO USE: replace the uuid list below with the dive_center_id(s) you
-- want to export, run in the live project's SQL Editor, then export the
-- result grid as CSV. Hand the CSV to database/migration/ (see etl.js) —
-- it expects the same "table_name,data" shape this query produces.
--
-- Known dive_center_id values (see CLAUDE.md for the full up-to-date table):
--   Test Dive Center            720ac8bb-ca1f-4da8-93bd-38270d32336e  (migrated)
--   Package Test Dive Center    5e1a7e2b-7ca8-47d3-aa2d-6dfd5543b291  (migrated)
--   Atlas Divers Malapascua     e7227551-a7d1-4daa-98cc-1e78ddd2b933  (migrated)
--   Divergems Diving Center     04ea0a3d-79e6-4876-843c-ee54c1966e07  (migrated)
--   Dive Nation Malapascua      6ac592ff-c612-42df-b243-0f24aea9f226  (not yet)
--   Demo Dive Center            a6aaa2ba-5a7a-4e01-b4ff-29a8bafb828c  (excluded — never migrate)

with target as (
  select unnest(array[
    '00000000-0000-0000-0000-000000000000'::uuid -- REPLACE with real dive_center_id(s), comma-separated
  ]) as dive_center_id
)
select 'dive_centers' as table_name, jsonb_agg(row_to_json(t)) as data from public.dive_centers t where t.id in (select dive_center_id from target)
union all
select 'activities', jsonb_agg(row_to_json(t)) from public.activities t where t.dive_center_id in (select dive_center_id from target)
union all
select 'audit_logs', jsonb_agg(row_to_json(t)) from public.audit_logs t where t.dive_center_id in (select dive_center_id from target)
union all
select 'boats', jsonb_agg(row_to_json(t)) from public.boats t where t.dive_center_id in (select dive_center_id from target)
union all
select 'course_rates', jsonb_agg(row_to_json(t)) from public.course_rates t where t.dive_center_id in (select dive_center_id from target)
union all
select 'deposits', jsonb_agg(row_to_json(t)) from public.deposits t where t.dive_center_id in (select dive_center_id from target)
union all
select 'dive_sites', jsonb_agg(row_to_json(t)) from public.dive_sites t where t.dive_center_id in (select dive_center_id from target)
union all
select 'diver_notes', jsonb_agg(row_to_json(t)) from public.diver_notes t where t.dive_center_id in (select dive_center_id from target)
union all
select 'diver_registrations', jsonb_agg(row_to_json(t)) from public.diver_registrations t where t.dive_center_id in (select dive_center_id from target)
union all
select 'diver_staff_defaults', jsonb_agg(row_to_json(t)) from public.diver_staff_defaults t where t.dive_center_id in (select dive_center_id from target)
union all
select 'divers', jsonb_agg(row_to_json(t)) from public.divers t where t.dive_center_id in (select dive_center_id from target)
union all
select 'equipment', jsonb_agg(row_to_json(t)) from public.equipment t where t.dive_center_id in (select dive_center_id from target)
union all
select 'equipment_rental_rates', jsonb_agg(row_to_json(t)) from public.equipment_rental_rates t where t.dive_center_id in (select dive_center_id from target)
union all
select 'exchange_rates', jsonb_agg(row_to_json(t)) from public.exchange_rates t where t.dive_center_id in (select dive_center_id from target)
union all
select 'expenses', jsonb_agg(row_to_json(t)) from public.expenses t where t.dive_center_id in (select dive_center_id from target)
union all
select 'fuel_logs', jsonb_agg(row_to_json(t)) from public.fuel_logs t where t.dive_center_id in (select dive_center_id from target)
union all
select 'govt_fees', jsonb_agg(row_to_json(t)) from public.govt_fees t where t.dive_center_id in (select dive_center_id from target)
union all
select 'groups', jsonb_agg(row_to_json(t)) from public.groups t where t.dive_center_id in (select dive_center_id from target)
union all
select 'invoice_emails', jsonb_agg(row_to_json(t)) from public.invoice_emails t where t.dive_center_id in (select dive_center_id from target)
union all
select 'join_ride_records', jsonb_agg(row_to_json(t)) from public.join_ride_records t where t.dive_center_id in (select dive_center_id from target)
union all
select 'join_ride_statements', jsonb_agg(row_to_json(t)) from public.join_ride_statements t where t.dive_center_id in (select dive_center_id from target)
union all
select 'manifests', jsonb_agg(row_to_json(t)) from public.manifests t where t.dive_center_id in (select dive_center_id from target)
union all
select 'medical_questions', jsonb_agg(row_to_json(t)) from public.medical_questions t where t.dive_center_id in (select dive_center_id from target)
union all
select 'other_charges', jsonb_agg(row_to_json(t)) from public.other_charges t where t.dive_center_id in (select dive_center_id from target)
union all
select 'packages', jsonb_agg(row_to_json(t)) from public.packages t where t.dive_center_id in (select dive_center_id from target)
union all
select 'payment_surcharges', jsonb_agg(row_to_json(t)) from public.payment_surcharges t where t.dive_center_id in (select dive_center_id from target)
union all
select 'payments', jsonb_agg(row_to_json(t)) from public.payments t where t.dive_center_id in (select dive_center_id from target)
union all
select 'rate_tiers', jsonb_agg(row_to_json(t)) from public.rate_tiers t where t.dive_center_id in (select dive_center_id from target)
union all
select 'rental_gear_records', jsonb_agg(row_to_json(t)) from public.rental_gear_records t where t.dive_center_id in (select dive_center_id from target)
union all
select 'schedule_day_diver_exclusions', jsonb_agg(row_to_json(t)) from public.schedule_day_diver_exclusions t where t.dive_center_id in (select dive_center_id from target)
union all
select 'schedule_team_clip_divers', jsonb_agg(row_to_json(t)) from public.schedule_team_clip_divers t where t.dive_center_id in (select dive_center_id from target)
union all
select 'schedule_team_clips', jsonb_agg(row_to_json(t)) from public.schedule_team_clips t where t.dive_center_id in (select dive_center_id from target)
union all
select 'schedules', jsonb_agg(row_to_json(t)) from public.schedules t where t.dive_center_id in (select dive_center_id from target)
union all
select 'staff', jsonb_agg(row_to_json(t)) from public.staff t where t.dive_center_id in (select dive_center_id from target)
union all
select 'staff_commission_records', jsonb_agg(row_to_json(t)) from public.staff_commission_records t where t.dive_center_id in (select dive_center_id from target)
union all
select 'tanks', jsonb_agg(row_to_json(t)) from public.tanks t where t.dive_center_id in (select dive_center_id from target)
union all
select 'users', jsonb_agg(row_to_json(t)) from public.users t where t.dive_center_id in (select dive_center_id from target)
union all
select 'visit_rate_selections', jsonb_agg(row_to_json(t)) from public.visit_rate_selections t where t.dive_center_id in (select dive_center_id from target)
union all
select 'visits', jsonb_agg(row_to_json(t)) from public.visits t where t.dive_center_id in (select dive_center_id from target)
union all
select 'auth_users', jsonb_agg(row_to_json(t)) from auth.users t where t.id in (select id from public.users where dive_center_id in (select dive_center_id from target))
union all
select 'auth_identities', jsonb_agg(row_to_json(t)) from auth.identities t where t.user_id in (select id from public.users where dive_center_id in (select dive_center_id from target));
