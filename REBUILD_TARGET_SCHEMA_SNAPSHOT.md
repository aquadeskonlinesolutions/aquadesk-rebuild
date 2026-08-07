# AquaDesk — Rebuild Target Schema Snapshot (migration-relevant traps)

Pulled 2026-08-07 via `database/migration/preflight.js` against the real
rebuild production project (`vqwrluiikodconwlmwls`). This is the
**target** side's schema constraints — every generated column, NOT NULL
column, enum label set, and check constraint the migration ETL needs to
respect. Complements `LIVE_APP_SCHEMA_SNAPSHOT.md` (the **source** side).

**Re-run this before building/adjusting `transforms.js` for each new
batch** (Atlas, Divergems, Dive Nation) — the target schema can change
between sessions same as any other part of this codebase, and this
snapshot can go stale:

```bash
cd database/migration
AQUADESK_TARGET_DB_URL='<pooler connection string>' npm run preflight
```

This consolidates four separate ad hoc diagnostic scripts written (and
deleted) while building the first real migration batch on 2026-08-07 —
each one caught a real rollback-causing schema mismatch that a dry-run
against exported JSON alone couldn't see. See CLAUDE.md's retrospective
for that session for the full account of what each one caught and why
they're now permanent tooling instead of one-off scripts.

---

## Generated columns — never insert into these directly

```
auth.identities.email = lower((identity_data ->> 'email'::text))
auth.users.confirmed_at = LEAST(email_confirmed_at, phone_confirmed_at)
```

## Enum types — exact real labels (old-schema values almost never match verbatim)

```
activity_status: [planned, scheduled, ongoing, completed, cancelled]
boat_type: [outrigger, flat_boat, chase_boat, speed_boat]
certification_level: [none, open_water_diver, advanced_open_water, rescue_diver, divemaster, instructor]
charge_type: [per_dive, per_day]
clip_source: [manual, returned, carryover]
commission_group: [dive_educator, dive_leader]
commission_status: [unpaid, paid]
expense_category: [fuel, boat_maintenance, equipment_maintenance, compressor_fill_station, staff_meals, food_expenses, office_supplies, utilities, licenses_permits, marketing, repairs, other, uncategorized]
experience_type: [fun_diving, dive_course]
fuel_type: [gasoline, diesel]
join_ride_direction: [joined_our_boat, we_joined_another_boat]
payment_method: [cash, card, online]
pricing_mode: [tier, package]
rental_gear_status: [to_collect, collected, to_pay, paid]
staff_employment_status: [full_time, part_time, freelance]
staff_position: [secretary, divemaster, instructor, crew]
subscription_status: [trial, active, suspended, cancelled]
tank_type: [air_12l, air_15l, nitrox]
training_agency: [padi, ssi, naui, cmas, other]
user_role: [owner, secretary]
visit_status: [open, closed, voided]
```

## Check constraints (plain-text columns with enum-like allowed values)

```
dive_sites_fuel_estimate_check: fuel_estimate in ('Low','Medium','High')
expenses_amount_check: amount > 0
govt_fees_fee_type_check: fee_type in ('Marine Fee','Shark Fee','Other Fee')
invoice_emails_email_delivery_status_check: email_delivery_status in ('not_sent','sent','failed')
join_ride_records_check: direction-gated status set (see LIVE_DATA_MIGRATION_MAPPING.md)
payment_surcharges_surcharge_type_check: surcharge_type in ('card','online')
privacy_notice_id_check: singleton (id must be true)
rate_tiers_rate_type_check: rate_type in ('base_dive','nitrox','tank_15l')
schedule_diver_dive_tanks_tank_type_check: tank_type in ('nitrox','air_15l')
schedule_spare_tanks_quantity_check: quantity > 0
```

## NOT NULL columns with no default — every row must explicitly supply these

(Columns with a default are omitted here if they're safe to just not
send — the ones below have **no** default at all, so a missing/null
value fails outright. Columns *with* a default still fail if you send an
**explicit** `null` rather than omitting the key — this bit 4 real
columns on 2026-08-07: `diver_registrations.waiver_signed`,
`exchange_rates.updated_at`, `schedule_team_clips.staff_name`,
`staff_commission_records.staff_name`,
`schedule_staff_dive_tanks.staff_name` — all now fixed in
`transforms.js` with explicit fallbacks, but re-check this list against
transforms.js for each new batch, don't assume it's still complete.)

```
activities: dive_center_id, diver_id, visit_id, date
audit_logs: action, target_type
boats: dive_center_id, name
course_rates: dive_center_id, course_name
deposits: dive_center_id, diver_id, amount, method
dive_centers: name
dive_sites: dive_center_id, site_name
diver_notes: dive_center_id, diver_id, note
diver_registrations: dive_center_id, diver_id
diver_staff_defaults: dive_center_id, diver_id
divers: dive_center_id, first_name, last_name
equipment: dive_center_id, name
equipment_rental_rates: dive_center_id, item_name
exchange_rates: dive_center_id, currency_code, rate_to_php
expenses: dive_center_id, date, category, amount
fuel_logs: dive_center_id
govt_fees: dive_center_id, date, fee_type
groups: dive_center_id, group_name
invoice_emails: dive_center_id, diver_id, visit_id
join_ride_records: dive_center_id, direction, date, company, status
join_ride_statements: dive_center_id, company
manifests: dive_center_id, schedule_id
medical_questions: dive_center_id, question_text
other_charges: dive_center_id, charge_name, charge_type
packages: dive_center_id, package_name
payment_surcharges: dive_center_id, surcharge_type
payments: dive_center_id, diver_id, visit_id
platform_admins: user_id, full_name, email
privacy_notice: content
rate_tiers: dive_center_id, tier_from, rate_type
rental_gear_records: dive_center_id, date, equipment
schedule_crew: dive_center_id, schedule_id, crew_name
schedule_day_diver_exclusions: dive_center_id, diver_id, schedule_date
schedule_diver_dive_tanks: dive_center_id, schedule_diver_id, site_index, tank_type
schedule_divers: dive_center_id, schedule_id, diver_id
schedule_sites: dive_center_id, schedule_id, dive_site_id
schedule_spare_tanks: dive_center_id, schedule_id, tank_type
schedule_staff_dive_tanks: dive_center_id, schedule_id, staff_name, site_index
schedule_team_clip_divers: dive_center_id, clip_id, diver_id
schedule_team_clips: dive_center_id, schedule_date
schedules: dive_center_id, schedule_date
staff: dive_center_id, first_name, last_name
staff_certifications: dive_center_id, staff_id, cert_name
staff_commission_records: dive_center_id, staff_name, commission_group, activity_date
tanks: dive_center_id, type
trip_types: dive_center_id, name
users: id, dive_center_id, full_name, email
visit_rate_selections: dive_center_id, visit_id, site_key
visits: dive_center_id, diver_id, experience_type
```

## Tables that exist in the target schema

```
activities, audit_logs, boats, course_rates, deposits, dive_centers,
dive_sites, diver_notes, diver_registrations, diver_staff_defaults,
divers, equipment, equipment_rental_rates, exchange_rates, expenses,
fuel_logs, govt_fees, groups, invoice_emails, join_ride_records,
join_ride_statements, manifests, medical_questions, other_charges,
packages, payment_surcharges, payments, platform_admins, privacy_notice,
rate_tiers, rental_gear_records, schedule_crew,
schedule_day_diver_exclusions, schedule_diver_dive_tanks,
schedule_divers, schedule_sites, schedule_spare_tanks,
schedule_staff_dive_tanks, schedule_team_clip_divers,
schedule_team_clips, schedules, staff, staff_certifications,
staff_commission_records, tanks, trip_types, users,
visit_rate_selections, visits
```

If a future batch's real data touches a table not in
`LIVE_DATA_MIGRATION_MAPPING.md`'s scope, cross-check against this list
before assuming it's out of scope.
