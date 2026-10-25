-- AquaDesk Rebuild — explicit Data API grants (Supabase change of 2026-10-30)
--
-- From 2026-10-30 Supabase no longer gives new tables in "public" automatic
-- grants to anon / authenticated / service_role. Every table in this project was
-- created before that and relies on those automatic grants, so a schema rebuilt
-- from migrations (db reset, preview branch, new project) would have NO table
-- access. This file writes the access down explicitly.
--
-- ADDITIVE ONLY. On production every statement below is already true, so running
-- it there changes nothing (verified against pg_class ACLs on 2026-10-25).
-- Row access is still decided by RLS (enabled on every table); grants only open
-- the door that RLS then guards.
--
-- Deliberately narrower than production in a few places (no behaviour change,
-- RLS already blocks them): authenticated gets only SELECT/INSERT/UPDATE/DELETE
-- (never TRUNCATE/TRIGGER/REFERENCES); dive_center_trace_counters and
-- billing_password_attempts have no client grants (only SECURITY DEFINER
-- functions touch them); activity_bundle_snapshots is read-only; dive_centers
-- gets UPDATE + column-level SELECT that leaves out the two password hashes
-- (same as 051). anon gets NO table grants: public pages use only the
-- functions listed at the bottom.
-- Tightening of what production has today lives in 062 (needs MK's approval).

begin;

-- ---- authenticated (signed-in app users) -------------------------------------
grant select, insert, update, delete on public.activities to authenticated;
grant select on public.activity_bundle_snapshots to authenticated;
grant select, insert, update, delete on public.addon_categories to authenticated;
grant select, insert, update, delete on public.audit_logs to authenticated;
grant select, insert, update, delete on public.boats to authenticated;
grant select, insert, update, delete on public.bundles to authenticated;
grant select, insert, update, delete on public.course_rates to authenticated;
grant select, insert, update, delete on public.deposits to authenticated;
grant select, insert, update, delete on public.dive_sites to authenticated;
grant select, insert, update, delete on public.diver_notes to authenticated;
grant select, insert, update, delete on public.diver_registrations to authenticated;
grant select, insert, update, delete on public.diver_staff_defaults to authenticated;
grant select, insert, update, delete on public.divers to authenticated;
grant select, insert, update, delete on public.equipment to authenticated;
grant select, insert, update, delete on public.equipment_rental_rates to authenticated;
grant select, insert, update, delete on public.exchange_rates to authenticated;
grant select, insert, update, delete on public.expense_categories to authenticated;
grant select, insert, update, delete on public.expenses to authenticated;
grant select, insert, update, delete on public.fuel_logs to authenticated;
grant select, insert, update, delete on public.govt_fees to authenticated;
grant select, insert, update, delete on public.groups to authenticated;
grant select, insert, update, delete on public.invoice_emails to authenticated;
grant select, insert, update, delete on public.join_ride_records to authenticated;
grant select, insert, update, delete on public.join_ride_statements to authenticated;
grant select, insert, update, delete on public.manifests to authenticated;
grant select, insert, update, delete on public.medical_questions to authenticated;
grant select, insert, update, delete on public.other_charges to authenticated;
grant select, insert, update, delete on public.packages to authenticated;
grant select, insert, update, delete on public.payment_channels to authenticated;
grant select, insert, update, delete on public.payment_surcharges to authenticated;
grant select, insert, update, delete on public.payments to authenticated;
grant select, insert, update, delete on public.platform_admins to authenticated;
grant select, insert, update, delete on public.privacy_notice to authenticated;
grant select, insert, update, delete on public.rate_tiers to authenticated;
grant select, insert, update, delete on public.rental_gear_records to authenticated;
grant select, insert, update, delete on public.schedule_crew to authenticated;
grant select, insert, update, delete on public.schedule_day_diver_exclusions to authenticated;
grant select, insert, update, delete on public.schedule_diver_dive_tanks to authenticated;
grant select, insert, update, delete on public.schedule_divers to authenticated;
grant select, insert, update, delete on public.schedule_sites to authenticated;
grant select, insert, update, delete on public.schedule_spare_tanks to authenticated;
grant select, insert, update, delete on public.schedule_staff_dive_tanks to authenticated;
grant select, insert, update, delete on public.schedule_team_clip_divers to authenticated;
grant select, insert, update, delete on public.schedule_team_clips to authenticated;
grant select, insert, update, delete on public.schedules to authenticated;
grant select, insert, update, delete on public.staff to authenticated;
grant select, insert, update, delete on public.staff_certifications to authenticated;
grant select, insert, update, delete on public.staff_commission_records to authenticated;
grant select, insert, update, delete on public.tanks to authenticated;
grant select, insert, update, delete on public.trip_types to authenticated;
grant select, insert, update, delete on public.users to authenticated;
grant select, insert, update, delete on public.visit_addons to authenticated;
grant select, insert, update, delete on public.visit_rate_selections to authenticated;
grant select, insert, update, delete on public.visits to authenticated;

grant update on public.dive_centers to authenticated;
do $$
declare cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'dive_centers'
    and column_name not in ('billing_unlock_hash', 'owner_unlock_hash');
  execute 'grant select (' || cols || ') on public.dive_centers to authenticated';
end $$;

-- ---- service_role (server-side admin client) ---------------------------------
grant select, insert, update, delete on public.activities to service_role;
grant select, insert, update, delete on public.activity_bundle_snapshots to service_role;
grant select, insert, update, delete on public.addon_categories to service_role;
grant select, insert, update, delete on public.audit_logs to service_role;
grant select, insert, update, delete on public.billing_password_attempts to service_role;
grant select, insert, update, delete on public.boats to service_role;
grant select, insert, update, delete on public.bundles to service_role;
grant select, insert, update, delete on public.course_rates to service_role;
grant select, insert, update, delete on public.deposits to service_role;
grant select, insert, update, delete on public.dive_center_trace_counters to service_role;
grant select, insert, update, delete on public.dive_centers to service_role;
grant select, insert, update, delete on public.dive_sites to service_role;
grant select, insert, update, delete on public.diver_notes to service_role;
grant select, insert, update, delete on public.diver_registrations to service_role;
grant select, insert, update, delete on public.diver_staff_defaults to service_role;
grant select, insert, update, delete on public.divers to service_role;
grant select, insert, update, delete on public.equipment to service_role;
grant select, insert, update, delete on public.equipment_rental_rates to service_role;
grant select, insert, update, delete on public.exchange_rates to service_role;
grant select, insert, update, delete on public.expense_categories to service_role;
grant select, insert, update, delete on public.expenses to service_role;
grant select, insert, update, delete on public.fuel_logs to service_role;
grant select, insert, update, delete on public.govt_fees to service_role;
grant select, insert, update, delete on public.groups to service_role;
grant select, insert, update, delete on public.invoice_emails to service_role;
grant select, insert, update, delete on public.join_ride_records to service_role;
grant select, insert, update, delete on public.join_ride_statements to service_role;
grant select, insert, update, delete on public.manifests to service_role;
grant select, insert, update, delete on public.medical_questions to service_role;
grant select, insert, update, delete on public.other_charges to service_role;
grant select, insert, update, delete on public.packages to service_role;
grant select, insert, update, delete on public.payment_channels to service_role;
grant select, insert, update, delete on public.payment_surcharges to service_role;
grant select, insert, update, delete on public.payments to service_role;
grant select, insert, update, delete on public.platform_admins to service_role;
grant select, insert, update, delete on public.privacy_notice to service_role;
grant select, insert, update, delete on public.rate_tiers to service_role;
grant select, insert, update, delete on public.rental_gear_records to service_role;
grant select, insert, update, delete on public.schedule_crew to service_role;
grant select, insert, update, delete on public.schedule_day_diver_exclusions to service_role;
grant select, insert, update, delete on public.schedule_diver_dive_tanks to service_role;
grant select, insert, update, delete on public.schedule_divers to service_role;
grant select, insert, update, delete on public.schedule_sites to service_role;
grant select, insert, update, delete on public.schedule_spare_tanks to service_role;
grant select, insert, update, delete on public.schedule_staff_dive_tanks to service_role;
grant select, insert, update, delete on public.schedule_team_clip_divers to service_role;
grant select, insert, update, delete on public.schedule_team_clips to service_role;
grant select, insert, update, delete on public.schedules to service_role;
grant select, insert, update, delete on public.staff to service_role;
grant select, insert, update, delete on public.staff_certifications to service_role;
grant select, insert, update, delete on public.staff_commission_records to service_role;
grant select, insert, update, delete on public.tanks to service_role;
grant select, insert, update, delete on public.trip_types to service_role;
grant select, insert, update, delete on public.users to service_role;
grant select, insert, update, delete on public.visit_addons to service_role;
grant select, insert, update, delete on public.visit_rate_selections to service_role;
grant select, insert, update, delete on public.visits to service_role;
grant select, insert, update, delete on public.dive_centers to service_role;

-- ---- functions -----------------------------------------------------------------
-- signed-in users: every function the app or an RLS policy calls
grant execute on function public.activity_dive_count(text) to authenticated;
grant execute on function public.apply_bundle(uuid, uuid, numeric) to authenticated;
grant execute on function public.calculate_visit_total(uuid) to authenticated;
grant execute on function public.cancel_deposit(uuid, numeric, text, text, public.payment_method, public.payment_channel, uuid) to authenticated;
grant execute on function public.check_unlock_password(text, text) to authenticated;
grant execute on function public.current_can_view_revenue() to authenticated;
grant execute on function public.current_dive_center_id() to authenticated;
grant execute on function public.diver_exists_for_path(uuid, uuid) to authenticated;
grant execute on function public.generate_daily_staff_token(uuid, date) to authenticated;
grant execute on function public.is_owner() to authenticated;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.log_bill_unlock(uuid, uuid, text) to authenticated;
grant execute on function public.log_payment_event(uuid, text, text) to authenticated;
grant execute on function public.password_status() to authenticated;
grant execute on function public.remove_bundle(uuid) to authenticated;
grant execute on function public.set_billing_unlock(uuid, text) to authenticated;
grant execute on function public.set_owner_unlock(uuid, text) to authenticated;
grant execute on function public.switch_visit_mode(uuid, text, boolean) to authenticated;
grant execute on function public.unlock_bill(uuid, text, text) to authenticated;
grant execute on function public.visit_addons_totals(uuid[]) to authenticated;
grant execute on function public.get_crew_schedule(text) to authenticated;
grant execute on function public.check_returning_diver(uuid, text) to authenticated;
grant execute on function public.get_diver_prefill(uuid, uuid) to authenticated;
grant execute on function public.get_registration_config(uuid, uuid) to authenticated;
grant execute on function public.login_guard_check(text) to authenticated;
grant execute on function public.login_guard_fail(text) to authenticated;
grant execute on function public.login_guard_reset(text) to authenticated;
grant execute on function public.set_diver_cert_card_url(uuid, uuid, text) to authenticated;
grant execute on function public.submit_diver_registration(jsonb) to authenticated;

-- anon (public pages: registration, staff crew page, login lockout, cert-card upload)
grant execute on function public.check_returning_diver(uuid, text) to anon;
grant execute on function public.diver_exists_for_path(uuid, uuid) to anon;
grant execute on function public.get_crew_schedule(text) to anon;
grant execute on function public.get_diver_prefill(uuid, uuid) to anon;
grant execute on function public.get_registration_config(uuid, uuid) to anon;
grant execute on function public.login_guard_check(text) to anon;
grant execute on function public.login_guard_fail(text) to anon;
grant execute on function public.login_guard_reset(text) to anon;
grant execute on function public.set_diver_cert_card_url(uuid, uuid, text) to anon;
grant execute on function public.submit_diver_registration(jsonb) to anon;

-- service_role keeps execute on all of the above
grant execute on function public.activity_dive_count(text) to service_role;
grant execute on function public.apply_bundle(uuid, uuid, numeric) to service_role;
grant execute on function public.calculate_visit_total(uuid) to service_role;
grant execute on function public.cancel_deposit(uuid, numeric, text, text, public.payment_method, public.payment_channel, uuid) to service_role;
grant execute on function public.check_unlock_password(text, text) to service_role;
grant execute on function public.current_can_view_revenue() to service_role;
grant execute on function public.current_dive_center_id() to service_role;
grant execute on function public.diver_exists_for_path(uuid, uuid) to service_role;
grant execute on function public.generate_daily_staff_token(uuid, date) to service_role;
grant execute on function public.is_owner() to service_role;
grant execute on function public.is_platform_admin() to service_role;
grant execute on function public.log_bill_unlock(uuid, uuid, text) to service_role;
grant execute on function public.log_payment_event(uuid, text, text) to service_role;
grant execute on function public.password_status() to service_role;
grant execute on function public.remove_bundle(uuid) to service_role;
grant execute on function public.set_billing_unlock(uuid, text) to service_role;
grant execute on function public.set_owner_unlock(uuid, text) to service_role;
grant execute on function public.switch_visit_mode(uuid, text, boolean) to service_role;
grant execute on function public.unlock_bill(uuid, text, text) to service_role;
grant execute on function public.visit_addons_totals(uuid[]) to service_role;
grant execute on function public.get_crew_schedule(text) to service_role;
grant execute on function public.check_returning_diver(uuid, text) to service_role;
grant execute on function public.get_diver_prefill(uuid, uuid) to service_role;
grant execute on function public.get_registration_config(uuid, uuid) to service_role;
grant execute on function public.login_guard_check(text) to service_role;
grant execute on function public.login_guard_fail(text) to service_role;
grant execute on function public.login_guard_reset(text) to service_role;
grant execute on function public.set_diver_cert_card_url(uuid, uuid, text) to service_role;
grant execute on function public.submit_diver_registration(jsonb) to service_role;

-- internal functions: no client access, but the server-side admin client
-- (service_role) must keep running them (e.g. the audit trigger calls
-- bill_audit_money when a service_role write happens)
grant execute on function public.bill_audit_money(numeric) to service_role;
grant execute on function public.billing_password_gate(text, text, text) to service_role;
grant execute on function public.verify_billing_unlock(uuid, text) to service_role;
grant execute on function public.verify_owner_unlock(uuid, text) to service_role;

commit;

-- Rollback: nothing to undo on production (grants already existed). On a rebuilt
-- schema, revoke the same statements.
