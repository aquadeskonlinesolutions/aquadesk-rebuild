-- AquaDesk Rebuild — tighten what anon / authenticated can do (NOT YET APPROVED)
--
-- 061 writes down today's access. This file removes access production has today
-- but nothing needs. Each revoke was checked against the app and against a real
-- anon session on 2026-10-25: anon sees zero rows in every table except
-- privacy_notice (which the registration page reads through
-- get_registration_config, not directly); public pages call only functions and
-- storage. RLS already stops all of this, so nothing visible changes. Run only
-- after MK approves, and after 061.
--
-- Does NOT touch any row of data.

begin;

-- anon: no direct table access at all
revoke all on public.activities from anon;
revoke all on public.activity_bundle_snapshots from anon;
revoke all on public.addon_categories from anon;
revoke all on public.audit_logs from anon;
revoke all on public.billing_password_attempts from anon;
revoke all on public.boats from anon;
revoke all on public.bundles from anon;
revoke all on public.course_rates from anon;
revoke all on public.deposits from anon;
revoke all on public.dive_center_trace_counters from anon;
revoke all on public.dive_centers from anon;
revoke all on public.dive_sites from anon;
revoke all on public.diver_notes from anon;
revoke all on public.diver_registrations from anon;
revoke all on public.diver_staff_defaults from anon;
revoke all on public.divers from anon;
revoke all on public.equipment from anon;
revoke all on public.equipment_rental_rates from anon;
revoke all on public.exchange_rates from anon;
revoke all on public.expense_categories from anon;
revoke all on public.expenses from anon;
revoke all on public.fuel_logs from anon;
revoke all on public.govt_fees from anon;
revoke all on public.groups from anon;
revoke all on public.invoice_emails from anon;
revoke all on public.join_ride_records from anon;
revoke all on public.join_ride_statements from anon;
revoke all on public.manifests from anon;
revoke all on public.medical_questions from anon;
revoke all on public.other_charges from anon;
revoke all on public.packages from anon;
revoke all on public.payment_channels from anon;
revoke all on public.payment_surcharges from anon;
revoke all on public.payments from anon;
revoke all on public.platform_admins from anon;
revoke all on public.privacy_notice from anon;
revoke all on public.rate_tiers from anon;
revoke all on public.rental_gear_records from anon;
revoke all on public.schedule_crew from anon;
revoke all on public.schedule_day_diver_exclusions from anon;
revoke all on public.schedule_diver_dive_tanks from anon;
revoke all on public.schedule_divers from anon;
revoke all on public.schedule_sites from anon;
revoke all on public.schedule_spare_tanks from anon;
revoke all on public.schedule_staff_dive_tanks from anon;
revoke all on public.schedule_team_clip_divers from anon;
revoke all on public.schedule_team_clips from anon;
revoke all on public.schedules from anon;
revoke all on public.staff from anon;
revoke all on public.staff_certifications from anon;
revoke all on public.staff_commission_records from anon;
revoke all on public.tanks from anon;
revoke all on public.trip_types from anon;
revoke all on public.users from anon;
revoke all on public.visit_addons from anon;
revoke all on public.visit_rate_selections from anon;
revoke all on public.visits from anon;

-- authenticated: no TRUNCATE / TRIGGER / REFERENCES anywhere
revoke truncate, trigger, references on public.activities from authenticated;
revoke truncate, trigger, references on public.activity_bundle_snapshots from authenticated;
revoke truncate, trigger, references on public.addon_categories from authenticated;
revoke truncate, trigger, references on public.audit_logs from authenticated;
revoke truncate, trigger, references on public.boats from authenticated;
revoke truncate, trigger, references on public.bundles from authenticated;
revoke truncate, trigger, references on public.course_rates from authenticated;
revoke truncate, trigger, references on public.deposits from authenticated;
revoke truncate, trigger, references on public.dive_centers from authenticated;
revoke truncate, trigger, references on public.dive_sites from authenticated;
revoke truncate, trigger, references on public.diver_notes from authenticated;
revoke truncate, trigger, references on public.diver_registrations from authenticated;
revoke truncate, trigger, references on public.diver_staff_defaults from authenticated;
revoke truncate, trigger, references on public.divers from authenticated;
revoke truncate, trigger, references on public.equipment from authenticated;
revoke truncate, trigger, references on public.equipment_rental_rates from authenticated;
revoke truncate, trigger, references on public.exchange_rates from authenticated;
revoke truncate, trigger, references on public.expense_categories from authenticated;
revoke truncate, trigger, references on public.expenses from authenticated;
revoke truncate, trigger, references on public.fuel_logs from authenticated;
revoke truncate, trigger, references on public.govt_fees from authenticated;
revoke truncate, trigger, references on public.groups from authenticated;
revoke truncate, trigger, references on public.invoice_emails from authenticated;
revoke truncate, trigger, references on public.join_ride_records from authenticated;
revoke truncate, trigger, references on public.join_ride_statements from authenticated;
revoke truncate, trigger, references on public.manifests from authenticated;
revoke truncate, trigger, references on public.medical_questions from authenticated;
revoke truncate, trigger, references on public.other_charges from authenticated;
revoke truncate, trigger, references on public.packages from authenticated;
revoke truncate, trigger, references on public.payment_channels from authenticated;
revoke truncate, trigger, references on public.payment_surcharges from authenticated;
revoke truncate, trigger, references on public.payments from authenticated;
revoke truncate, trigger, references on public.platform_admins from authenticated;
revoke truncate, trigger, references on public.privacy_notice from authenticated;
revoke truncate, trigger, references on public.rate_tiers from authenticated;
revoke truncate, trigger, references on public.rental_gear_records from authenticated;
revoke truncate, trigger, references on public.schedule_crew from authenticated;
revoke truncate, trigger, references on public.schedule_day_diver_exclusions from authenticated;
revoke truncate, trigger, references on public.schedule_diver_dive_tanks from authenticated;
revoke truncate, trigger, references on public.schedule_divers from authenticated;
revoke truncate, trigger, references on public.schedule_sites from authenticated;
revoke truncate, trigger, references on public.schedule_spare_tanks from authenticated;
revoke truncate, trigger, references on public.schedule_staff_dive_tanks from authenticated;
revoke truncate, trigger, references on public.schedule_team_clip_divers from authenticated;
revoke truncate, trigger, references on public.schedule_team_clips from authenticated;
revoke truncate, trigger, references on public.schedules from authenticated;
revoke truncate, trigger, references on public.staff from authenticated;
revoke truncate, trigger, references on public.staff_certifications from authenticated;
revoke truncate, trigger, references on public.staff_commission_records from authenticated;
revoke truncate, trigger, references on public.tanks from authenticated;
revoke truncate, trigger, references on public.trip_types from authenticated;
revoke truncate, trigger, references on public.users from authenticated;
revoke truncate, trigger, references on public.visit_addons from authenticated;
revoke truncate, trigger, references on public.visit_rate_selections from authenticated;
revoke truncate, trigger, references on public.visits from authenticated;
revoke insert, delete on public.dive_centers from authenticated;
revoke all on public.dive_center_trace_counters from authenticated;

-- anon: no execute on functions that only signed-in users may run
-- (each already refuses anon inside, this closes the door as well)
revoke execute on function public.calculate_visit_total(uuid) from public, anon;
revoke execute on function public.generate_daily_staff_token(uuid, date) from public, anon;
revoke execute on function public.log_bill_unlock(uuid, uuid, text) from public, anon;
revoke execute on function public.set_billing_unlock(uuid, text) from public, anon;
revoke execute on function public.set_owner_unlock(uuid, text) from public, anon;

commit;

-- Rollback: re-run the matching grants from 061, or
--   grant all on all tables in schema public to anon;  (restores today's state)
