# AquaDesk — Live Data Migration Mapping

**Purpose**: a field-level map from the OLD live app's real Supabase schema
(inferred from `diver-form.html`/`divers.html`/`register.html`/
`scheduling.html`/`staff.html`/`reports.html`/`settings.html`/
`boat-manifest.html`/`dashboard.html`/`login.html`/`office.html` — never
from the live database directly, since this project's absolute rule is
never to connect to the live Supabase project) against the rebuild's actual
current schema (`database/001_schema_and_rls.sql` + migrations 002–035).

This is preparation for a future one-time ETL that moves every real dive
center's live data into the rebuild's database before cutover — it is a
**mapping document, not a migration script**. Nothing here has been run
against real data. Built 2026-08-06 by four parallel research passes (diver-
facing data, scheduling/staff, reports/financial, settings/admin + auth),
merged below.

**Important caveat on confidence**: every "old column" fact in this
document comes from reading the old app's client-side JS, not the live
database's actual `information_schema`. Two projects' worth of drift
(manual DB edits, an even-older app version's leftover columns, GoTrue
version differences) can't be ruled out from JS alone. Wherever a
sub-document says "verify against real data" or "confirm before assuming,"
treat that as a required pre-ETL step, not optional polish — the
recommended way to do that without violating the never-connect-to-live
rule is a **read-only `information_schema` export the user runs themselves**
via the live project's Supabase dashboard SQL editor (or asks a
live-app-side engineer to run), pasted back in for review — not a live
connection from this environment.

---

## Cross-cutting decisions needed before ETL can be written (ranked by stakes)

### 1. Real historical data loss: old app's 3-way boat mode has no new-schema equivalent
The old app's `schedules` records own-boat / **join-a-boat** / **rent-a-boat**
as three distinct modes, each carrying its own free-text field (`joinDC` —
which dive center we joined; `owner` — who we rented from). The rebuild's
schema only has a 2-way `is_joiner` boolean + `joiner_boat_name` — a
deliberate, accepted rebuild-time simplification for *new* data, but it
means every historical rental trip and every historical join-ride trip
become indistinguishable once migrated, and the `joinDC`/`owner` text is
unrecoverable. **Needs a decision**: accept the loss (matches the rebuild's
already-accepted design), or add a small schema migration before ETL
(e.g. `schedules.boat_mode` enum + one or two more free-text columns) to
preserve it. This is the only place in the whole mapping where a schema
change, not just an ETL transform, may be warranted.

### 2. Plaintext billing/owner passwords must be re-hashed, never copied
`dive_centers.billing_password`/`owner_password` are stored and compared as
**plaintext** in the old app. The rebuild uses bcrypt hashes
(`billing_unlock_hash`/`owner_unlock_hash`) behind a `verify_*_unlock` RPC.
A raw copy would either fail outright or (worse) silently store a plaintext
value in a column the app assumes is always a bcrypt hash. Either re-hash
during ETL (`crypt(old_plaintext, gen_salt('bf'))`) or — safer — force every
migrated dive center's owner to set both unlock secrets fresh post-cutover.

### 3. Login passwords: verbatim `auth.users`/`auth.identities` row copy recommended
Both projects run Supabase Auth (GoTrue); bcrypt hashes are portable across
projects with no external key material. Recommendation: copy `auth.users`/
`auth.identities` rows **verbatim**, preserving UUIDs (avoids remapping
every FK that points at a user), rather than reconstructing rows field by
field — this project has twice been bitten (see its own retrospectives
#26/#27/#40) by hand-built `auth.users` rows missing required `''` token
columns or correct `identity_data` shape. A verbatim copy of an already-
working row sidesteps that whole class of bug. One exception: any account
whose `password_changed` is still `false` in the live DB has never
rotated off the old app's **shared, hardcoded, all-accounts temp password
`'aquadesk123'`** — those specific accounts should be forced through a real
password reset during migration, not carried over with a known-guessable
credential intact.

### 4. `payment_surcharges.percentage` → `rate` needs a `/100` rescale
Old stores `5` meaning 5%; new stores `0.05`. A raw copy makes every
surcharge 100x too large — confirmed against the rebuild's own
`saveSurcharges` action, not assumed. Mechanical, no judgment call needed,
just must not be missed.

### 5. `activities.notes` — same column name, opposite meaning
Old: a JSON-encoded tank-flag blob. New: genuine free-text notes (flags
moved to `activities.flags`). **A naive column-name-matching ETL will
silently corrupt this column** — it's the single easiest mistake to make
in the whole migration precisely because nothing about the column name
signals the danger.

### 6. Business decisions on backfill quality, not just mechanics
A few fields have no clean source and need a judgment call, not a formula:
- `staff_commission_records.divers` (new column, no old equivalent — needs
  either a real cross-reference against historical `activities`/
  `schedule_divers`, or a `0` default with a note that it's approximate)
- `invoice_emails.email_sent_at`/`_by`/`_delivery_status` (old app
  conflated "invoice generated" and "email sent" into one timestamp; decide
  whether to leave these null or treat old `sent_at` as a proxy for "email
  sent" when the diver had an email on file)
- `trip_types` (no per-tenant old data exists at all — it's a seeding
  decision: scan each tenant's historical `schedules.notes` blobs for
  distinct trip-type names used, seed one row per name with default
  duration values, flag for owner correction post-migration)
- `diver_registrations` backfill fields (emergency contact, accommodation,
  insurance, last-dive-date, and the whole migration-017 identity snapshot)
  — the *old* app's own registration-insert never captured these onto
  `diver_registrations` at all, only onto the mutable `divers` row. The only
  available source is each diver's **current** `divers` value, which is a
  reconstructed approximation of a historical snapshot, not a genuine one.
  Worth flagging in migrated rows if the old/new distinction ever matters
  legally (e.g. a migration-run marker).

### 7. Two real, permanent data-loss items (no destination exists anywhere)
- `diver_notes.author_name` — old snapshots a note's author name at write
  time (survives that author later being renamed/deleted); new resolves
  the author via a live join to `users.full_name` at render time instead.
  A migrated note whose `created_by` can't resolve to a migrated user will
  show no author, and any note whose author *is* migrated will now show
  that user's *current* name, not their name at the time of the note.
- `expenses.paid_by` — dropped outright by migration 031, no replacement
  column exists. Recommend folding the old free-text value into `notes`
  (e.g. prefix `"Paid by: {old value} — "`) rather than losing it, since
  the new `payment_method` enum can't represent an arbitrary "who/what
  funded it" string and shouldn't be guessed at from the old text.

---

## Consolidated enum / value-transform checklist

Every one of these needs an explicit lookup table in the ETL script — none
are safe as a bare `.toLowerCase()`:

| Table.column | Old values | New values |
|---|---|---|
| `activities.status` | `Planned/Scheduled/Ongoing/Completed/Cancelled` | lowercase — confirm exact `activity_status` enum labels before writing the transform |
| `divers.certification_level` / `diver_registrations.certification_level` | old free-text/looser enum | `public.certification_level` — audit every distinct old value first, an unmapped one hard-fails the row |
| `boats.boat_type` | `Outrigger/Flat Boat/Chase Boat/Speed Boat` | `outrigger/flat_boat/chase_boat/speed_boat` |
| `boats.fuel_type` | `Gasoline/Diesel` | `gasoline/diesel` (note: `fuel_logs.fuel_type` is a *different* column that's already lowercase old-side — don't apply this same transform there) |
| `staff.position` (mapped from old `access_level`, **not** `role`) | old `access_level` already lowercase | direct match — but must read `access_level`, the cosmetic `role` field is a decoy |
| `staff.employment_status` | `Full Time/Part Time/Freelance` | `full_time/part_time/freelance` |
| `expenses.category` | `Fuel/Boat Maintenance/.../Uncategorized` (13 values) | `fuel/boat_maintenance/...` — 3 values need an explicit lookup, not mechanical (`Compressor / Fill Station`, `Licenses & Permits`, general space→underscore) |
| `join_ride_records.status` | `To Collect/Statement Printed/Collected/Expected To Pay/Statement Received/Paid` | `to_collect/statement_printed/collected/expected_to_pay/statement_received/paid`, direction-gated by a check constraint |
| `join_ride_statements.status` | always literal `Statement Printed` | `statement_printed` |
| `rental_gear_records.status` | `To Collect/Collected/To Pay/Paid` | `to_collect/collected/to_pay/paid` |
| `staff_commission_records.status` | `Paid/Unpaid` | `paid/unpaid` |
| `tanks.type` | `Air 12L/Air 15L/Nitrox` | `air_12l/air_15l/nitrox` |
| `payment_surcharges.surcharge_type` | loose free text (old app fuzzy-matches `.includes('card'/'credit'/'online')`) | strict enum `card/online` — audit real distinct values first |
| `dive_centers.pricing_mode` | inconsistent free text (old app itself normalizes several spelling variants) | `package/tier` — migrate the *normalized* value, not the raw stored string |
| `dive_centers.subscription_status` | presumed free text | `trial/active/suspended/cancelled` — verify |

---

## New-only tables/columns with no old-schema source (seeding/default decisions, not migration bugs)

- `schedules.trip_type_id` → seed `trip_types` per tenant by scanning historical blobs (see decision #6 above), else `null`
- `schedule_divers.source_clip_id` → always `null`, never persisted old-side
- `schedule_spare_tanks` → always zero rows, genuinely new feature
- `staff_certifications` → always zero rows, genuinely new feature
- `staff.emergency_contact_*` (5 columns) → always `null`, genuinely new feature
- `payments.excess_amount` → default `0`
- `activities.discount` → default `0`
- `activities.package_id` → leave `null`
- `visits.updated_at` → default `now()` or migration-run time
- `dive_centers.divemaster_rate_per_dive`, `ratio_bonus_enabled`, `ratio_bonus_extra_rate`, `join_ride_rate_per_diver_per_dive` → schema defaults (`0`/`false`/`0`/`0`), owner configures post-migration
- `staff_commission_records.bonus_amount` → backfill from old `additional_rate` (a reasonable, not purely mechanical, fold-in)
- `staff_commission_records.diver_id` → resolve old free-text `diver_name` against migrated `divers` by name match; `null` if no confident match
- `medical_questions.sort_order` → synthesize from old `created_at` ordering (`row_number() over (...)`), since the new schema dropped `created_at` on this table entirely in favor of explicit ordering
- `dive_centers.staff_token`/`staff_token_date` → don't migrate at all, ephemeral by design, let it regenerate

---

## Recommended ETL build order (respects FK dependencies)

1. **Auth**: `auth.users` + `auth.identities` (verbatim copy, see decision #3)
2. **Tenant root**: `dive_centers` (re-hash billing/owner passwords, re-sanitize waiver_content, re-upload logo to new Storage bucket)
3. **Users**: `public.users`, `platform_admins` (for old `is_platform_admin=true` rows)
4. **Config tables** (no dependencies on operational data): `staff`, `boats`, `dive_sites`, `course_rates`, `rate_tiers`, `packages`, `other_charges`, `equipment_rental_rates`, `payment_surcharges`, `exchange_rates`, `medical_questions`, `tanks`, `equipment`, `trip_types` (seeding pass)
5. **Divers**: `divers`, then `diver_registrations` (needs `divers.id` + `groups.id`), `groups` (can actually run before/parallel with `divers` — no hard dependency either direction beyond FK nullability)
6. **Visits & money**: `visits` → `activities` → `payments` → `deposits` → `invoice_emails` → `visit_rate_selections` → `diver_notes`
7. **Scheduling**: `schedules` → `schedule_sites`/`schedule_crew`/`schedule_divers` → `schedule_diver_dive_tanks`/`schedule_staff_dive_tanks` → `schedule_team_clips`/`schedule_team_clip_divers` → `schedule_day_diver_exclusions` → `fuel_logs` → `manifests` (only if the insert bypasses the auto-create trigger)
8. **Reports/financial**: `expenses`, `govt_fees`, `join_ride_statements` → `join_ride_records` (FK to statements), `rental_gear_records`, `staff_commission_records`
9. **Audit trail** (optional, lower priority — confirm with the user whether old audit history is worth migrating at all): `audit_logs`
10. **Singleton**: `privacy_notice` (exactly one row, don't fan out per tenant)

---

## Suggested next steps

1. **Decide the cross-cutting items above** — especially #1 (boat-mode
   schema addition or accept the loss) and #3's password-reset carve-out
   for `password_changed=false` accounts.
2. **Get a read-only `information_schema` snapshot of the live project**,
   run by the user via the Supabase dashboard (not a live connection from
   this session) — needed to validate every "confirm against real data"
   flag scattered through the four detailed sections below, before any
   ETL code is written against assumptions taken from JS alone.
3. Once decisions are made and the schema snapshot confirms the enum/value
   assumptions, build the actual ETL script (likely a Node/`pg` script per
   this project's own established direct-SQL tooling pattern), table by
   table in the order above, with a **rehearsal run against a disposable
   copy first** — never the real target project — before any real cutover.

---

The four detailed per-domain mappings follow below, unedited from the
research passes that produced them.

# AquaDesk migration mapping — diver-facing data

Scope: `diver-form.html`, `divers.html`, `register.html` (old app) vs. the
rebuild schema (`database/001_schema_and_rls.sql` + migrations 002–035).

Method: old columns are taken from actual `.insert(...)`/`.update(...)`/`.select(...)`
payloads in the three old HTML files (grepped, then read in context), not
from any assumed/remembered schema. New columns are taken from
`001_schema_and_rls.sql`'s `create table` blocks plus every later `alter
table` found by grepping all of `database/002*.sql`–`035*.sql` for each
table name.

**Two critical non-obvious findings up front** (see full detail in their
table sections below — do not build the ETL without reading these):

1. **`activities.notes` means two completely different things in the two
   schemas, despite having the identical column name.** Old: a JSON-encoded
   text blob of nitrox/15L tank flags (`{nitrox_requested, tank_15l_requested,
   nitrox_tank_count, tank_15l_count}`). New: a genuine free-text notes
   field, semantically unrelated. **Never copy `old.activities.notes` →
   `new.activities.notes` directly** — it must be parsed and moved into
   `new.activities.flags` (jsonb) instead; `new.activities.notes` should be
   left null for migrated rows.
2. **Old `divers` duplicates the "latest registration event" snapshot data
   onto the mutable diver row itself** (waiver/medical/privacy/insurance-
   preference/equipment-preference/arrival/departure fields all exist
   directly on old `divers`, in addition to `diver_registrations`). **New
   `divers` dropped all of that** — those fields exist **only** on
   `diver_registrations` now. The evergreen "current" value for any of them
   must be derived from each diver's most recent `diver_registrations` row,
   not copied from the old `divers` row.

---

## 1. `divers`

### Old columns (as written/read by register.html + diver-form.html + divers.html)

Register.html's `diverData` object (used for both the `divers` insert for a
new diver, and passed to the `update_returning_diver_registration` RPC for
a returning one) is the fullest single view of the old row shape:

`id, dive_center_id, group_id, first_name, last_name, birthday, age,
is_minor, nationality, arrival_date, departure_date, accommodation, email,
phone, whatsapp, emergency_contact_name, emergency_contact_phone,
emergency_contact_email, emergency_contact_relationship,
certification_level, training_agency, logged_dives, last_dive_date,
nitrox_certified, food_allergies, has_dive_insurance, insurance_provider,
insurance_policy_number, wants_insurance_referral, needs_equipment,
equipment_preference, equipment_requested, waiver_signed, waiver_opened,
waiver_date, waiver_signature_url, waiver_content_snapshot, medical_flag,
medical_answers, medical_answers_snapshot, privacy_notice_snapshot,
privacy_consent_at, duplicate_email_flag, notes, cert_card_url
(set later via `set_diver_cert_card_url` RPC)`

Additional columns only visible from diver-form.html/divers.html read/update
calls (not in the register.html insert payload above):
- `emergency_contact_whatsapp` — read in `openEditDiverModal`, conditionally
  written in `saveDiverInfo` (diver-form.html line ~4109; old app tolerates
  this column not existing yet — it retries the update with the field
  stripped if the update errors on that column name, implying this was a
  late/optional addition even in the old app).
- `medical_acknowledged` (boolean) — `divers.html`'s `addMedicalAck()`.
- `medical_acknowledged_at`, `medical_acknowledged_by` — `diver-form.html`'s
  `acknowledgeMedical()`.
- `'equipment notes'` — **literal column name with a space in it** —
  `divers.html`'s `saveEquipRemarks()` / `renderEquipTable()`.
- `created_at` — implicit, used for default ordering.

### New columns (`divers`, 001 + 008 + 015 + 024)

`id, dive_center_id, first_name, last_name, age, birthday, nationality,
email, phone, whatsapp, certification_level, training_agency, logged_dives,
nitrox_certified, group_id, needs_equipment, equipment_requested,
medical_acknowledged, medical_acknowledged_at, medical_acknowledged_by,
cert_card_url, notes, created_at` (001)
+ `accommodation, emergency_contact_name, emergency_contact_phone,
emergency_contact_relationship, emergency_contact_whatsapp,
emergency_contact_email, food_allergies, has_dive_insurance,
insurance_provider, insurance_policy_number, is_minor` (008)
+ `equipment_notes` (015)
+ `last_dive_date` (024)

### Field-by-field mapping

| Old `divers` column | New `divers` column | Notes |
|---|---|---|
| `id` | `id` | direct |
| `dive_center_id` | `dive_center_id` | direct |
| `group_id` | `group_id` | direct (map old group id → new `groups.id` via the groups ETL) |
| `first_name` | `first_name` | direct |
| `last_name` | `last_name` | direct |
| `birthday` | `birthday` | direct |
| `age` | `age` | direct |
| `is_minor` | `is_minor` | direct |
| `nationality` | `nationality` | direct |
| `email` | `email` | direct |
| `phone` | `phone` | direct |
| `whatsapp` | `whatsapp` | direct |
| `emergency_contact_name` | `emergency_contact_name` | direct |
| `emergency_contact_phone` | `emergency_contact_phone` | direct |
| `emergency_contact_email` | `emergency_contact_email` | direct |
| `emergency_contact_relationship` | `emergency_contact_relationship` | direct |
| `emergency_contact_whatsapp` | `emergency_contact_whatsapp` | direct (optional column even in old app — may be null/absent on very old rows) |
| `certification_level` | `certification_level` | **enum check** — see Type/constraint differences below |
| `training_agency` | `training_agency` | enum — verify old free-text/enum values against new `public.training_agency` enum labels |
| `logged_dives` | `logged_dives` | direct (new: `not null default 0`) |
| `last_dive_date` | `last_dive_date` | direct (new column added late, migration 024 — same name, same meaning) |
| `nitrox_certified` | `nitrox_certified` | direct (new: `not null default false`) |
| `food_allergies` | `food_allergies` | direct |
| `has_dive_insurance` | `has_dive_insurance` | direct (nullable both sides) |
| `insurance_provider` | `insurance_provider` | direct |
| `insurance_policy_number` | `insurance_policy_number` | direct |
| `needs_equipment` | `needs_equipment` | direct (new: `not null default false`) |
| `equipment_requested` | `equipment_requested` | direct — **both sides store this as a JSON-encoded `text` string**, not jsonb; pass the string through unchanged. See "type differences" note on shape below. |
| `'equipment notes'` (space in name) | `equipment_notes` | rename only — same text semantics (migration 015's own comment confirms this 1:1 intent) |
| `medical_acknowledged` | `medical_acknowledged` | direct boolean |
| `medical_acknowledged_at` | `medical_acknowledged_at` | direct |
| `medical_acknowledged_by` | `medical_acknowledged_by` | direct (FK to `users.id` — must remap to the new `users` row for the same person) |
| `cert_card_url` | `cert_card_url` | direct, but **points at a Storage path in the OLD live project's `cert-cards` bucket** — the file itself must be re-uploaded to the new project's `cert-cards` bucket (see `003_cert_card_storage.sql`) and the path rewritten; a raw string copy will point at nothing |
| `notes` | `notes` | direct (free-text secretary notes; same semantic both sides) |
| `arrival_date` | *(none on `divers`)* | **dropped from the evergreen row.** New schema keeps `arrival_date` only on `diver_registrations`. ETL: write into the diver's migrated `diver_registrations` row(s) instead (see Section 2); do not attempt to write to `divers.arrival_date`, it doesn't exist. |
| `departure_date` | *(none on `divers`)* | same as `arrival_date` above — `diver_registrations`-only in the new schema |
| `accommodation` | `accommodation` | **present on both**, but semantically different: old writes it to `divers` (mutable "current") once at registration and again on every profile edit; new `divers.accommodation` (migration 008) is the same "current, editable" concept — direct copy is correct here, `diver_registrations.accommodation` is the separate immutable-per-event copy (Section 2) |
| `waiver_signed` | *(none)* | dropped from `divers` — lives only on `diver_registrations` now (latest row = "current" state) |
| `waiver_opened` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `waiver_date` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `waiver_signature_url` | *(none)* | dropped from `divers` — `diver_registrations`-only (also a Storage/data-URL asset — see Section 2's notes on this field) |
| `waiver_content_snapshot` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `medical_flag` | *(none)* | dropped from `divers` — `diver_registrations`-only. **New app's live "medical flag banner" must be derived from the diver's latest `diver_registrations.medical_flag`**, not a `divers` column — confirm the rebuild's own read path does this before assuming migrated data will display correctly. |
| `medical_answers` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `medical_answers_snapshot` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `privacy_notice_snapshot` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `privacy_consent_at` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `duplicate_email_flag` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `equipment_preference` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| `wants_insurance_referral` | *(none)* | dropped from `divers` — `diver_registrations`-only |
| *(none)* | `created_at` | new-only, but trivially backfillable from the old row's own `created_at` if present, else the earliest known activity for that diver |

### Structural changes
- **Snapshot fields consolidated onto `diver_registrations` only.** This is
  the single biggest structural change for this table. Any old `divers` row
  being migrated needs **at least one corresponding `diver_registrations`
  row created** carrying the waiver/medical/privacy/insurance-referral/
  equipment-preference/arrival/departure data — if the old dive center's
  data has `divers` rows with waiver/medical data set directly but genuinely
  no matching `diver_registrations` history row (plausible for divers who
  pre-date the old app's own registration-history feature), a synthetic
  `diver_registrations` row must be fabricated from the `divers` row's own
  fields so this data isn't silently lost.
- `equipment_requested` keeps the same "JSON text blob, not jsonb" shape on
  both sides (old: `JSON.stringify({type:'partial', items, computer})`,
  same key shape expected new-side) — no reshaping needed, just copy the
  string.

### Type/constraint differences
- `certification_level`: new schema is a real Postgres enum
  (`public.certification_level`) with a `not null default 'none'`. Confirm
  every distinct value present in the old data (a free-text or looser
  enum in the old app) has a matching label in the new enum before bulk
  insert — an unmapped value will hard-fail the whole row.
- `training_agency`: same enum-mapping caution as above
  (`public.training_agency`), but nullable in the new schema.
- `first_name`/`last_name`: `not null` in both, but confirm no old rows
  have empty-string names that would violate a stricter new check if one
  exists.
- `logged_dives`, `nitrox_certified`, `needs_equipment`,
  `medical_acknowledged`, `is_minor`: all `not null default ...` in the new
  schema — old rows with `null` in these columns need a coalesce to the
  same default during ETL (0 / false / false / false / false respectively).

---

## 2. `diver_registrations`

### Old columns
Old app writes this table in exactly one place — `register.html`'s
new-diver path (line ~1879), immediately after the `divers` insert (the
returning-diver path presumably has the old app's `update_returning_
diver_registration` RPC write an equivalent row server-side, not visible
in this file's JS):

`diver_id, dive_center_id, waiver_signed, waiver_date,
waiver_signature_url, waiver_content_snapshot, medical_flag,
medical_answers, medical_answers_snapshot, privacy_notice_snapshot,
privacy_consent_at, arrival_date, departure_date, certification_level,
equipment_requested, group_id, needs_equipment, equipment_preference`

Notably **absent from the old insert**: `emergency_contact_*`,
`last_dive_date`, `food_allergies`, `has_dive_insurance`,
`insurance_provider`, `insurance_policy_number`,
`wants_insurance_referral`, `waiver_opened`, `duplicate_email_flag`,
identity fields (`first_name`/`last_name`/`birthday`/`nationality`/`email`/
`phone`/`whatsapp`) — the old app apparently only snapshots a subset onto
this table even though it collects (and writes onto `divers`) the fuller
set. This looks like the old app's own incomplete-snapshot bug/gap, not
something the new schema is missing — see "Structural changes" below.

### New columns (001 + 017)
`id, dive_center_id, diver_id, group_id, arrival_date, departure_date,
accommodation, emergency_contact_name, emergency_contact_phone,
emergency_contact_whatsapp, emergency_contact_email,
emergency_contact_relationship, last_dive_date, food_allergies,
has_dive_insurance, insurance_provider, insurance_policy_number,
wants_insurance_referral, certification_level, equipment_preference,
equipment_requested, needs_equipment, medical_answers,
medical_answers_snapshot, medical_flag, privacy_consent_at,
privacy_notice_snapshot, waiver_content_snapshot, waiver_date,
waiver_opened, waiver_signature_url, waiver_signed, duplicate_email_flag,
created_at` (001)
+ `first_name, last_name, birthday, nationality, email, phone, whatsapp`
(017, the identity snapshot)

### Field-by-field mapping

| Old `diver_registrations` column | New `diver_registrations` column | Notes |
|---|---|---|
| `diver_id` | `diver_id` | remap to new `divers.id` |
| `dive_center_id` | `dive_center_id` | remap to new dive center id |
| `group_id` | `group_id` | remap to new `groups.id` |
| `arrival_date` | `arrival_date` | direct |
| `departure_date` | `departure_date` | direct |
| `certification_level` | `certification_level` | same enum caution as `divers.certification_level` |
| `equipment_requested` | `equipment_requested` | direct (JSON text blob, same shape) |
| `needs_equipment` | `needs_equipment` | direct |
| `equipment_preference` | `equipment_preference` | direct |
| `waiver_signed` | `waiver_signed` | direct |
| `waiver_date` | `waiver_date` | direct — **type note**: old app writes this as `new Date().toISOString().split('T')[0]` (a bare `YYYY-MM-DD` date string) while the new column is `timestamptz`; confirm the ETL casts this correctly (likely fine as an implicit date→timestamptz cast at local midnight, but verify against the actual values, not assumed) |
| `waiver_signature_url` | `waiver_signature_url` | **not actually a URL in the old app** — it's a raw `canvas.toDataURL()` base64 data URI string, stored directly in the text column (confirmed: `const signatureUrl=canvas.toDataURL();`). Copy as-is; this is very large text per row — flag for the ETL script's row-size expectations, don't assume it's a short Storage path. |
| `waiver_content_snapshot` | `waiver_content_snapshot` | direct |
| `medical_flag` | `medical_flag` | direct |
| `medical_answers` | `medical_answers` | direct (jsonb both sides — old app passes a plain JS object `{questionId: true/false}`, supabase-js serializes it; confirm the new schema's expected key shape — `question id → boolean` — still matches, since the new app's own question ids may differ post-migration if `medical_questions` rows are re-created rather than id-preserved) |
| `privacy_notice_snapshot` | `privacy_notice_snapshot` | direct |
| `privacy_consent_at` | `privacy_consent_at` | direct (timestamptz both sides) |
| *(not written by old app)* | `medical_answers_snapshot` | old app never populates this on insert (only `divers.medical_answers_snapshot`, a different table — see structural note); **no source data for this new-schema column from the old registration-insert path.** If backfilling, derive it from `medical_answers` + a `medical_questions` join the same way `register.html`'s own `buildMedicalAnswersSnapshot()` does (question_text + boolean answer), not a raw copy. |
| *(not written by old app's registration insert)* | `emergency_contact_name`, `emergency_contact_phone`, `emergency_contact_whatsapp`, `emergency_contact_email`, `emergency_contact_relationship` | **no old `diver_registrations` source** — these were only ever written to old `divers`, never snapshotted historically. Backfill option: copy the diver's `divers` row values at migration time as a best-effort "point-in-time" snapshot (acknowledging it's actually the *current* value, not truly what was true at that historical registration event) — flag this compromise explicitly if done, don't silently present it as an authentic historical snapshot. |
| *(not written by old app's registration insert)* | `last_dive_date` | same gap/backfill caveat as emergency contact fields above — old app only wrote this to `divers`, never to `diver_registrations` |
| *(not written by old app's registration insert)* | `food_allergies`, `has_dive_insurance`, `insurance_provider`, `insurance_policy_number`, `wants_insurance_referral` | same gap — old app collected these (they're in the `divers` insert) but never included them in the `diver_registrations` insert shown in this file. Same backfill-from-`divers`-with-caveat option as above. |
| *(not written by old app's registration insert)* | `accommodation` | same gap as above — collected, written to `divers`, never snapshotted to `diver_registrations` in the code path read here |
| *(not written by old app's registration insert)* | `waiver_opened` | same gap — `divers.waiver_opened` is set, but the `diver_registrations` insert in `register.html` never includes it |
| *(not written by old app's registration insert)* | `duplicate_email_flag` | same gap — set on `divers`, not included in this `diver_registrations` insert |
| *(not written by old app's registration insert)* | `first_name`, `last_name`, `birthday`, `nationality`, `email`, `phone`, `whatsapp` | **structurally new** (migration 017, the identity snapshot — this is a genuine rebuild-only improvement with zero old-app precedent at all, old or new-schema gap). Backfill from the linked `divers` row at migration time, same "current value stood in for a historical snapshot" caveat as above — there is no way to recover the *actual* historical name/DOB/etc. at each past registration event from old data, since the old app never captured it either. |

### Structural changes
- The old app's own `diver_registrations` insert (register.html) is
  **missing several fields it collects and writes to `divers`** — this
  looks like a genuine old-app gap (a partial/incomplete snapshot), not a
  deliberate design. The new schema's `diver_registrations` is the fuller,
  corrected version. This means: **for old data, `diver_registrations`
  rows are missing fields the new schema expects a "real" registration
  snapshot to have** — the ETL cannot get these from old `diver_
  registrations` at all, only from old `divers` (the mutable "current"
  copy), with the accuracy caveat noted per-field above.
- Migration 017's identity-snapshot fields
  (`first_name`/`last_name`/`birthday`/`nationality`/`email`/`phone`/
  `whatsapp`) have **no old-schema equivalent whatsoever** — old
  `diver_registrations` never stored identity fields at all, relying
  purely on the `diver_id` FK (which is exactly the bug 017 fixed for the
  rebuild). No ETL source data can make these truly historically accurate;
  backfilling from current `divers` values is the only option and should
  be flagged as such in the migrated data (e.g., a migration-run marker)
  if the difference between "genuinely captured at signing" vs.
  "reconstructed at migration time" ever matters legally.

### Type/constraint differences
- `waiver_signature_url` is unbounded free text holding a full base64
  data URI in the old app — verify the new column has no length
  constraint that would reject these (001 shows plain `text`, so should
  be fine, but worth a sanity check on actual row sizes before a bulk
  load).
- `arrival_date`/`departure_date` are real `date` columns on both sides —
  no conversion needed, but note register.html's raw `<input type=date>.
  value` strings pass straight through as-is, so format should already
  be `YYYY-MM-DD` on the old side.

---

## 3. `visits`

### Old columns
From `createVisitWithExperience` (diver-form.html) and `ensureOpenVisit`
(divers.html) insert payloads, plus fields read/updated elsewhere:

`id, dive_center_id, diver_id, course_rate_id, visit_start, visit_end,
is_active, is_paid, experience_type, visit_status, invoice_count`

(`visit_status` values seen in use: `'open'`, `'closed'`; `experience_type`
values seen: `'fun_diving'`, `'dive_course'`)

### New columns (001 + 033)
`id, dive_center_id, diver_id, course_rate_id, experience_type,
visit_start, visit_end, visit_status, is_active, is_paid, invoice_count,
created_at` (001) + `updated_at` (033, with a `set_updated_at` trigger)

### Field-by-field mapping

| Old `visits` column | New `visits` column | Notes |
|---|---|---|
| `id` | `id` | direct |
| `dive_center_id` | `dive_center_id` | remap |
| `diver_id` | `diver_id` | remap to new `divers.id` |
| `course_rate_id` | `course_rate_id` | remap to new `course_rates.id` (rebuild-side Settings data, not part of this diver-facing mapping — coordinate with whoever migrates `course_rates`) |
| `experience_type` | `experience_type` | direct — **enum check**: confirm `'fun_diving'`/`'dive_course'` (the only two values seen in old app usage) match `public.experience_type`'s labels exactly |
| `visit_start` | `visit_start` | direct (`date`, `not null default current_date` in new — old always sets it explicitly on insert, so should be fine) |
| `visit_end` | `visit_end` | direct (nullable both sides; old only sets it on `confirmMarkPaid`) |
| `visit_status` | `visit_status` | direct — **enum check**: old app only ever sets `'open'`/`'closed'` in the code read here; confirm `public.visit_status` has no additional required states or different casing |
| `is_active` | `is_active` | direct |
| `is_paid` | `is_paid` | direct |
| `invoice_count` | `invoice_count` | direct (`integer`, incremented client-side both on `emailBill()` and `confirmMarkPaid()`) |
| *(none — implicit)* | `created_at` | new-only default; backfill from old `visit_start` if no better source exists |
| *(none)* | `updated_at` | **new-only, no old equivalent at all** (migration 033, added for optimistic-concurrency checks — a rebuild-only feature). Backfill to `now()` or the row's own `visit_end`/last-known-modified time if available; there is no historically-accurate source. |

### Structural changes
None beyond the new `updated_at` addition — this table is essentially
unchanged shape-for-shape between old and new.

### Type/constraint differences
- `visit_status` and `experience_type` are real enums in the new schema
  (`not null` on `experience_type`) — confirm no old row has a null/blank
  `experience_type`, which would fail the new `not null` constraint (old
  app always sets a default of `'fun_diving'` on insert, so this should be
  safe, but verify against actual historical data rather than assuming
  every row followed that code path).

---

## 4. `activities`

### Old columns
From `addActivityRow`/`saveActivity`/`getActiveScheduleAssignmentsForCurrentDiver`
(diver-form.html) and `saveGroupPricedActivity` (divers.html):

`id, dive_center_id, diver_id, visit_id, schedule_id, date, dive_site,
staff_name, dive_rate, fuel_surcharge, marine_tax, shark_fee, nitrox_fee,
fifteen_l_fee, equipment_rental, equipment_breakdown, addons,
addon_breakdown, status, total, notes`

`status` values seen: `'Planned'`, `'Scheduled'`, `'Ongoing'`,
`'Completed'`, `'Cancelled'` (note the **capitalized** values — see
Type/constraint differences).

`notes` (old): **a JSON-encoded text blob**, not free text — parsed by
`getActivityRowFlags()`:
```
{ nitrox_requested: bool, tank_15l_requested: bool,
  nitrox_tank_count: number, tank_15l_count: number }
```

### New columns (001 + 032)
`id, dive_center_id, diver_id, visit_id, schedule_id, date, dive_site,
staff_name, dive_rate, fuel_surcharge, marine_tax, shark_fee, nitrox_fee,
fifteen_l_fee, equipment_rental, equipment_breakdown, addons,
addon_breakdown, discount, total, status, flags, notes, created_at` (001)
+ `package_id` (032)

### Field-by-field mapping

| Old `activities` column | New `activities` column | Notes |
|---|---|---|
| `id` | `id` | direct |
| `dive_center_id` | `dive_center_id` | remap |
| `diver_id` | `diver_id` | remap |
| `visit_id` | `visit_id` | remap to new `visits.id` |
| `schedule_id` | `schedule_id` | remap to new `schedules.id` (scheduling-side, out of this doc's direct scope — nullable on both sides, fine to leave null if the schedule itself isn't migrated) |
| `date` | `date` | direct |
| `dive_site` | `dive_site` | direct (free text both sides — old app stores the raw joined site combo string, e.g. `"Kimud, Kimud, Monad"`; new schema's own 032 comment confirms this must stay the raw combo text, not a package display name — no transformation needed, just don't "clean it up" during ETL) |
| `staff_name` | `staff_name` | direct |
| `dive_rate` | `dive_rate` | direct (numeric) |
| `fuel_surcharge` | `fuel_surcharge` | direct |
| `marine_tax` | `marine_tax` | direct |
| `shark_fee` | `shark_fee` | direct |
| `nitrox_fee` | `nitrox_fee` | direct |
| `fifteen_l_fee` | `fifteen_l_fee` | direct |
| `equipment_rental` | `equipment_rental` | direct |
| `equipment_breakdown` | `equipment_breakdown` | direct (jsonb both sides, shape `{breakdown: [...]}` from old app — pass through unchanged) |
| `addons` | `addons` | direct |
| `addon_breakdown` | `addon_breakdown` | direct (jsonb, pass through) |
| `status` | `status` | **value-casing mismatch** — see Type/constraint differences below |
| `total` | `total` | direct, but **new schema computes this server-side via a trigger** (`compute_activity_total`, per the 001 comment) — do not trust a raw copy of the old stored value if the new trigger will immediately recompute it from the other numeric columns on insert/update; verify old and trigger-recomputed totals actually agree before assuming a straight copy is safe |
| `notes` (JSON tank-flags blob) | `flags` (jsonb) | **reshape, not copy** — parse the old JSON string (`JSON.parse(act.notes)`) and write a structured object to the new `flags` column. Confirmed real-world shape written by the *rebuild itself*: `{nitrox_requested: true}` / `{tank_15l_requested: true}` (per `markBoatReturned`'s own writes) — the ETL should likely emit `{nitrox_requested: <bool>, tank_15l_requested: <bool>}` (dropping the old `*_tank_count` fields, which have no apparent new-schema consumer based on the rebuild's own write shape — confirm against actual rebuild read code before discarding them, in case a consumer does exist) |
| *(no free-text equivalent existed in old app)* | `notes` | **leave null/empty for migrated rows** — see the critical warning at the top of this document. Do not copy old `activities.notes` into new `activities.notes`; that column meant something else entirely in the old schema. |
| *(none)* | `discount` | new-only column, `not null default 0`. No old per-row discount existed (old app's discount is a single whole-bill field on `payments.discount`, not per-activity) — default every migrated row to `0`. |
| *(none)* | `package_id` | new-only (032), a display-identity FK to `packages.id`, not used for pricing. No old-schema source exists at all (old app has no such link). Leave null for migrated rows — it's optional/display-only per 032's own comment, safe to omit entirely. |
| *(none — implicit)* | `created_at` | backfill from old row's own timestamp if available, else `date` at a nominal time |

### Structural changes
- **`notes` column-name collision with different semantics** — the single
  most dangerous trap in this whole mapping; repeated here because it's
  easy to miss in a mechanical column-name-matching ETL. Old `notes` (JSON
  tank flags) → new `flags` (jsonb). New `notes` (free text) has no old
  source and should stay empty for migrated data.
- `total` moves from "whatever the client last computed and sent" to
  "server-computed by trigger" — after migration, don't assume the
  migrated `total` value is authoritative; let the trigger (or an
  equivalent one-time recompute pass) establish it from the other numeric
  columns, matching how every *new* row is created going forward.

### Type/constraint differences
- **`status` enum casing**: old app's UI options are
  `Planned/Scheduled/Ongoing/Completed/Cancelled` (capitalized). Confirm
  `public.activity_status`'s actual labels — 001's `activities.status`
  default is `'planned'` (lowercase), strongly suggesting the new enum
  uses lowercase labels. **This needs a value transform, not a direct
  copy** — verify the new enum's exact label set (`select enum_range(null::
  public.activity_status)`) and lowercase/remap every old status value
  during ETL, or every row will fail to insert.
- `dive_rate`/`fuel_surcharge`/etc. are all `numeric(12,2) not null default
  0` in the new schema — old app frequently leaves these as empty
  string/`undefined` in the UI before a save; confirm the old *data* (not
  just the old UI's in-memory state) never has null/non-numeric values in
  these columns, or coalesce to 0 during ETL.

---

## 5. `payments`

### Old columns
From `buildPaymentPayload`/`upsertPaymentRecord` (diver-form.html):

`dive_center_id, diver_id, visit_id, cash_amount, cash_amount_foreign,
cash_currency, cash_exchange_rate, card_amount, online_amount, total_paid,
balance, discount, grand_total_php, card_surcharge_rate,
online_surcharge_rate, card_surcharge_amount, online_surcharge_amount,
total_surcharge, total_collected, is_paid, paid_at`

Also referenced defensively (read-only fallback, `divers.html`'s
`paymentAmount()`): `p.amount`, `p.is_paid` — `amount` does not appear in
any old *write* payload found in these three files; treat it as a
possible legacy/dead column from an even older app version, or defensive
paranoia with no real data behind it. Verify against the actual old
production `payments` table's column list before assuming it's safe to
ignore — if any real old rows only populate `amount` (not `total_paid`),
they need special-cased handling.

### New columns (001 + 034)
`id, dive_center_id, diver_id, visit_id, cash_amount, cash_amount_foreign,
cash_currency_code, cash_exchange_rate, card_amount, online_amount,
total_paid, balance, discount, grand_total_php, card_surcharge_rate,
online_surcharge_rate, card_surcharge_amount, online_surcharge_amount,
total_surcharge, total_collected, is_paid, paid_at, created_at` (001)
+ `excess_amount` (034)

### Field-by-field mapping

| Old `payments` column | New `payments` column | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | remap |
| `diver_id` | `diver_id` | remap |
| `visit_id` | `visit_id` | remap to new `visits.id` — **new schema has `unique` on this column** (one payment row per visit); confirm no old dive center somehow has >1 payment row per visit (the old app's own `upsert(...,{onConflict:'visit_id'})` strongly implies this was already a 1:1 invariant in the old app too, so should be safe) |
| `cash_amount` | `cash_amount` | direct |
| `cash_amount_foreign` | `cash_amount_foreign` | direct (nullable both sides) |
| `cash_currency` | `cash_currency_code` | **rename only** — same semantic (e.g. `'USD'`), just a different column name |
| `cash_exchange_rate` | `cash_exchange_rate` | direct |
| `card_amount` | `card_amount` | direct |
| `online_amount` | `online_amount` | direct |
| `total_paid` | `total_paid` | direct |
| `balance` | `balance` | direct |
| `discount` | `discount` | direct |
| `grand_total_php` | `grand_total_php` | direct |
| `card_surcharge_rate` | `card_surcharge_rate` | direct |
| `online_surcharge_rate` | `online_surcharge_rate` | direct |
| `card_surcharge_amount` | `card_surcharge_amount` | direct |
| `online_surcharge_amount` | `online_surcharge_amount` | direct |
| `total_surcharge` | `total_surcharge` | direct |
| `total_collected` | `total_collected` | direct |
| `is_paid` | `is_paid` | direct |
| `paid_at` | `paid_at` | direct (timestamptz both sides) |
| *(none — implicit)* | `created_at` | backfill from `paid_at` or the linked visit's timestamps |
| *(no old equivalent — concept didn't exist)* | `excess_amount` | **new-only** (034) — "tendered but unbilled" foreign-cash overage. No old data captured this at all (old app's `cash_amount` is already the PHP-converted, capped figure). Default every migrated row to `0` — there's no way to reconstruct a historically-accurate excess figure after the fact from what the old schema stored. |

### Structural changes
None beyond the new `excess_amount` addition and the `cash_currency` →
`cash_currency_code` rename — this table is essentially unchanged
shape-for-shape.

### Type/constraint differences
- `visit_id` is `unique` (one row per visit) in the new schema — verify
  during ETL rather than assuming, since a violation here will hard-fail
  that row's insert.
- All numeric columns are `numeric(12,2) not null default 0` (or
  `numeric(6,4)` for the two surcharge *rate* columns) — coalesce nulls
  to 0 during ETL.

---

## 6. `deposits`

### Old columns
From `confirmAddDeposit` (diver-form.html):

`dive_center_id, visit_id, diver_id, amount, method, deposit_date,
received_by, recorded_by_user_id`

### New columns (001, unchanged by any later migration)
`id, dive_center_id, diver_id, visit_id, amount, method, deposit_date,
received_by, recorded_by_user_id, created_at`

### Field-by-field mapping

| Old `deposits` column | New `deposits` column | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | remap |
| `diver_id` | `diver_id` | remap |
| `visit_id` | `visit_id` | remap (nullable on both sides) |
| `amount` | `amount` | direct (`numeric(12,2) not null` — confirm no old zero/negative amounts, which the new schema doesn't explicitly forbid but the old app's own UI validation (`amountVal<=0` rejected client-side) suggests shouldn't exist in real data) |
| `method` | `method` | direct — **enum check**: new column is `public.payment_method not null`; confirm old app's `depositMethod` select values (`'cash'` seen as the default) match the enum's exact labels |
| `deposit_date` | `deposit_date` | direct |
| `received_by` | `received_by` | direct (free text — old app auto-fills this with a staff/dive-center display name, not a FK; copy as-is) |
| `recorded_by_user_id` | `recorded_by_user_id` | remap to new `users.id` |

### Structural changes
None — this table is unchanged shape-for-shape between old and new.

### Type/constraint differences
- `method` enum-label verification is the only real risk here.

---

## 7. `invoice_emails`

### Old columns
From two call sites in diver-form.html (`emailBill()` and
`confirmMarkPaid()`), both writing the identical shape:

`dive_center_id, visit_id, diver_id, sent_at, sent_by, invoice_snapshot`

### New columns (001 + 008)
`id, dive_center_id, diver_id, visit_id, invoice_snapshot, sent_at,
sent_by` (001) + `email_sent_at, email_sent_by, email_delivery_status`
(008)

### Field-by-field mapping

| Old `invoice_emails` column | New `invoice_emails` column | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | remap |
| `visit_id` | `visit_id` | remap |
| `diver_id` | `diver_id` | remap |
| `sent_at` | `sent_at` | direct — **semantic note**: in the old app, this timestamp actually means "bill closed / invoice snapshot generated," not necessarily "email delivered" (it's set even when no email exists for the diver, via the `confirmMarkPaid` snapshot-save step, and separately in `emailBill()` when an email *was* attempted). The new schema's own migration-008 comment confirms this exact reading (`sent_at`/`sent_by` = "invoice generated / bill closed by") — no transform needed, just don't assume `sent_at` implies successful delivery. |
| `sent_by` | `sent_by` | remap to new `users.id` |
| `invoice_snapshot` | `invoice_snapshot` | direct (jsonb) — old shape from `buildInvoiceSnapshot()`: `{diver_name, nationality, activities: [...], discount, payment: {...}, grand_total, total_collected, closed_at, closed_by}`. Pass through as opaque jsonb; **do not assume the rebuild's own snapshot-reading code (Billing Audit, etc.) expects exactly this same key set** — CLAUDE.md's own history notes the rebuild's checkout flow was later simplified to trust `grand_total` (snake_case) specifically because it's the only writer; spot-check the rebuild's actual snapshot-reader against these old keys before assuming migrated old snapshots will render correctly, since the old app was never the same writer. |
| *(no old equivalent — the "email actually sent" step didn't exist as a separate concept in the old app until the rebuild formalized it)* | `email_sent_at`, `email_sent_by`, `email_delivery_status` | **new-only** (008). The old app's single `sent_at`/`sent_by` conflates "invoice generated" and "email sent" into one timestamp; the new schema deliberately split them. ETL options: (a) leave these three null/`'not_sent'` for all migrated rows (safest, since old data can't reliably distinguish "closed with no email" from "closed and emailed"), or (b) if the old diver had a real `email` on file, treat migration as a best-effort proxy for "was probably emailed" and copy `sent_at`/`sent_by` into `email_sent_at`/`email_sent_by` with `email_delivery_status='sent'` — this is a business-judgment call, not a mechanical one; confirm with the user which read they want before choosing. |

### Structural changes
The old app's one `sent_at`/`sent_by` pair correctly maps to the new
schema's *original* pair of the same name — the new schema's actual
structural addition is the three `email_*` columns tracking the separate,
later-introduced "send an email" step. This is additive, not a
reshaping of existing data.

### Type/constraint differences
- `email_delivery_status` has a `check` constraint
  (`'not_sent' | 'sent' | 'failed'`) — any migrated row populating this
  column must use one of exactly these three values.

---

## 8. `groups`

### Old columns
From `createGroup()` and `confirmGroupFromSelection()` (divers.html), plus
`loadGroupFromLink()`'s read (`register.html`):

`id, dive_center_id, group_name, leader_name, expected_count,
arrival_date, departure_date, notes, is_active`

### New columns (001 + 011)
`id, dive_center_id, group_name, leader_name, arrival_date,
expected_count, is_active, created_at` (001) + `departure_date, notes`
(011)

### Field-by-field mapping

| Old `groups` column | New `groups` column | Notes |
|---|---|---|
| `id` | `id` | direct |
| `dive_center_id` | `dive_center_id` | remap |
| `group_name` | `group_name` | direct |
| `leader_name` | `leader_name` | direct (nullable both sides) |
| `expected_count` | `expected_count` | direct |
| `arrival_date` | `arrival_date` | direct |
| `departure_date` | `departure_date` | direct — added by migration 011 specifically to close this old-app gap; full 1:1 coverage now |
| `notes` | `notes` | direct — same, added by 011 |
| `is_active` | `is_active` | direct |
| *(none — implicit)* | `created_at` | backfill from old row's own `created_at` if present |

### Structural changes
None — this is a **complete, clean 1:1 mapping** once migration 011 is
accounted for. No JSON blobs, no dropped fields, no reshaping needed.

### Type/constraint differences
None identified — straightforward direct copy.

---

## 9. `diver_notes`

### Old columns
From `addDiverNote()` (diver-form.html):

`dive_center_id, diver_id, author_user_id, author_name, note`

(plus `created_at`, read-only/implicit, used for sort order)

### New columns (001, unchanged by any later migration)
`id, dive_center_id, diver_id, note, created_by, created_at`

### Field-by-field mapping

| Old `diver_notes` column | New `diver_notes` column | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | remap |
| `diver_id` | `diver_id` | remap |
| `author_user_id` | `created_by` | rename only |
| `note` | `note` | direct |
| `author_name` | *(none)* | **dropped, no new-schema equivalent** — see Structural changes below |
| `created_at` | `created_at` | direct |

### Structural changes
- **Old `author_name` was a write-time text snapshot of the staff member's
  display name** (`role==='owner' ? dive_centers.name : users.full_name`,
  captured once at note-creation time — so it correctly preserves what a
  now-renamed or now-deleted user was called *at the time*). **New schema
  drops this column entirely and resolves the author via a live join to
  `users.full_name` at render time instead** (per CLAUDE.md's own
  documented design — "author resolved via join to users.full_name at
  render time, not write-time snapshot"). This is a genuine, deliberate
  behavior change, not just a rename: **a migrated note's displayed
  author name can now change later if that user's name is edited**,
  whereas the old app's note would have stayed frozen. If `created_by`
  can't be resolved to a real new-schema `users.id` (e.g. the original
  author's user account isn't being migrated), the note will display with
  no author or a fallback — old `author_name` text is otherwise
  unrecoverable once dropped, so decide before migration whether that
  loss is acceptable.

### Type/constraint differences
None beyond the above structural note.

---

## 10. `visit_rate_selections`

Package-mode pricing memory (which package/custom price was chosen for a
given site combination on a visit, so "Apply Charges" doesn't re-ask).

### Old columns
From `saveVisitRateSelection()`/`saveRateSelection()` (both divers.html and
diver-form.html use the identical shape):

`dive_center_id, visit_id, site_key, package_id, custom_price`

### New columns (001, unchanged by any later migration)
`id, dive_center_id, visit_id, site_key, package_id, custom_price`,
`unique (visit_id, site_key)`

### Field-by-field mapping

| Old column | New column | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | remap |
| `visit_id` | `visit_id` | remap |
| `site_key` | `site_key` | direct (a normalized, sorted, comma-joined site-name string — an app-computed cache key, not a FK; copy as-is, it's derived the same way on both sides per the package-pricing session notes in CLAUDE.md) |
| `package_id` | `package_id` | remap to new `packages.id` |
| `custom_price` | `custom_price` | direct |

### Structural changes
None — complete 1:1 mapping.

### Type/constraint differences
`unique(visit_id, site_key)` on both sides — the old app's own
`onConflict:'visit_id,site_key'` upsert confirms this was already the
invariant in the old schema too.

---

## 11. `audit_logs`

Only one diver-facing write site touches this table in these three files:
diver-form.html's bill-unlock action.

### Old columns
`dive_center_id, action, performed_by, target_type, target_id, notes`
(action seen: `'bill_unlocked'`; target_type seen: `'visit'`)

### New columns (001, unchanged by any later migration)
`id, dive_center_id, action, target_type, target_id, performed_by, notes,
created_at`

### Field-by-field mapping

| Old column | New column | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | remap — **note: no FK enforced on either side** (both schemas deliberately leave this unconstrained so audit rows survive deletion of their subject — new schema's own 001 comment confirms this reasoning explicitly) |
| `action` | `action` | direct (free text, not an enum, in the new schema too) |
| `performed_by` | `performed_by` | remap to new `users.id` (also unconstrained/no FK — same audit-survives-deletion reasoning) |
| `target_type` | `target_type` | direct |
| `target_id` | `target_id` | remap (polymorphic — the id's meaning depends on `target_type`; for `'visit'` rows, remap to new `visits.id`) |
| `notes` | `notes` | direct |

### Structural changes
None — complete 1:1 mapping. This is historical/audit data; migrating it
is optional depending on whether the new dive center needs old audit
history at all (worth confirming with the user — audit logs are usually
lower priority than live operational data for a cutover).

### Type/constraint differences
None identified.

---

## 12. `diver_staff_defaults` (in scope per the task list, but not actually touched by these three files)

Grepped all three old files — **zero references** to this table in
`diver-form.html`, `divers.html`, or `register.html`. It's written by
`scheduling.html` instead (outside this document's file scope).

### New columns (001, unchanged by any later migration)
`id, dive_center_id, diver_id, staff_id, created_at`,
`unique (dive_center_id, diver_id)`

Provided here for completeness since the task listed this table
explicitly — but its old-schema column list and exact write semantics
should be confirmed against `scheduling.html` specifically, not assumed
from this document. If `scheduling.html` isn't in scope for a later pass
of this migration-mapping effort, flag `diver_staff_defaults` as
unmapped/unverified rather than guessing its old shape.

---

## 13. `schedule_divers` (out of primary scope, but touched by two of the three files)

Appears as a **read** in `diver-form.html` (checking whether a diver has
an active schedule assignment, to gate the "change experience type"
action) and as a **full read/insert/update** in `divers.html` (the
push-to-schedule / "Add to Scheduling" flow).

### Old columns actually seen in these three files
`id, dive_center_id, schedule_id, diver_id, experience_type,
is_diving_tomorrow` (plus `staff_id`, `is_15l`, `nitrox_requested`,
implied by the new schema and likely present old-side too, but not
directly observed being written in these three files — `divers.html`'s
own insert only sets `experience_type`/`is_diving_tomorrow` explicitly,
leaving the tank/staff fields to their defaults)

### New columns (001 + 016 + 026)
`id, dive_center_id, schedule_id, diver_id, staff_id, experience_type,
is_15l, is_diving_tomorrow, nitrox_requested, notes, created_at` (001) +
`source_clip_id` (016) + `staff_name` (026), `unique(schedule_id,
diver_id)`

This table is primarily a **scheduling** concern — a full mapping
belongs with a Scheduling-focused migration pass (which will also need
`schedules`, `schedule_sites`, `schedule_team_clips`, etc., none of which
these three files write). Noted here only because `divers.html` is a
genuine write source for it. Recommend a dedicated scheduling-side
migration mapping document before writing ETL code for this table.

---

## Summary of tables with no old-schema equivalent at all (new-only, safe defaults)

- `visits.updated_at` → default `now()`
- `payments.excess_amount` → default `0`
- `activities.discount` → default `0`
- `activities.package_id` → leave `null`
- `diver_registrations.medical_answers_snapshot`,
  `emergency_contact_*`, `last_dive_date`, `food_allergies`,
  `has_dive_insurance`, `insurance_provider`, `insurance_policy_number`,
  `wants_insurance_referral`, `accommodation`, `waiver_opened`,
  `duplicate_email_flag`, `first_name`/`last_name`/`birthday`/
  `nationality`/`email`/`phone`/`whatsapp` → backfill best-effort from
  the linked `divers` row's current values (with the historical-accuracy
  caveat documented in Section 2), not from any old `diver_registrations`
  data
- `invoice_emails.email_sent_at`/`email_sent_by`/`email_delivery_status`
  → business decision needed (see Section 7), default to
  `null`/`null`/`'not_sent'` if undecided

## Summary of old-schema fields with no new-schema equivalent (data loss unless captured elsewhere)

- `divers.waiver_signed/opened/date/signature_url/content_snapshot`,
  `medical_flag/answers/answers_snapshot`, `privacy_notice_snapshot`,
  `privacy_consent_at`, `duplicate_email_flag`, `equipment_preference`,
  `wants_insurance_referral`, `arrival_date`, `departure_date` → **not
  lost**, but must be redirected to `diver_registrations` instead of
  `divers` (see Section 1)
- `diver_notes.author_name` → genuinely dropped, no redirect target (see
  Section 9)
- `activities.notes` (old JSON tank-flag meaning) → redirected to
  `activities.flags`, not lost, but **must not** land in new
  `activities.notes` (see the critical warning at the top of this doc)
- `payments.amount` (old defensive-fallback field, uncertain if real) →
  needs verification against actual old production data before deciding
  if any real rows depend on it
# AquaDesk — Old-to-New Schema Mapping: Scheduling & Staff

Scope: `scheduling.html` and `staff.html` (old live app), mapped against
`database/001_schema_and_rls.sql` plus every later migration that touches a
scheduling/staff/boat table (005, 010, 013, 016–030). `settings.html` was
peeked at only for `staff`/`boats` CRUD field names, since `scheduling.html`/
`staff.html` only ever *read* those two tables, never wrote them.

**The single biggest structural fact driving this whole migration**: the old
app stores nearly all real trip structure — boat type, captain, crew list,
dive site list, departure time components, join-ride/guest-diver info, fuel
liters, closed/cancelled flags, and (per staff group) nitrox/15L dive-index
arrays — as one big JSON object, `JSON.stringify`'d into the single text
column `schedules.notes`. The new schema has a **standing rule against
JSON-blob structural state** and explodes nearly every one of those fields
into real relational columns or child tables. `schedules.notes` in the new
schema means only the free-text trip notes (`t.notesText` in the old blob),
nothing else.

---

## 0. Quick reference: `schedules.notes` (old) → new destination

This is the master map for the JSON-blob restructuring (point 4 of the ask).
`buildTripMeta(t)` (`scheduling.html` line ~1623) is the function that
builds the object that gets `JSON.stringify`'d into `schedules.notes` on
every `saveTrip`/`silentSaveTrip`. Every key below is a property of that one
object (`meta.<key>` in the old JS), one JSON blob per `schedules` row.

| Old JSON key (`meta.<key>`) | Old shape | New destination | Notes |
|---|---|---|---|
| `boatType` | `'own'\|'join'\|'rental'` | `schedules.is_joiner` (boolean) + client-side boat-mode enum (`own_boat`/`join_ride`/`rental` in app code, not persisted as a 3-way column) | New schema only persists a 2-way split (`is_joiner`); `join` vs `rental` distinction is **not stored** in the new schema at all — see §1 "Dropped / no new equivalent." |
| `boatName` | text | `schedules.boat_id` (FK, own-boat) **or** `schedules.joiner_boat_name` (free text, join/rental) | Own-boat: resolve old free-text `boatName` to a real `boats.id` by name match. Join/rental: goes to `joiner_boat_name` directly. |
| `captain` | text | `schedules.captain` (real column, migration 018) | Own-boat only; new schema nulls this for joiner trips. |
| `crews` | `string[]` (3 default slots) | `schedule_crew` rows (migration 018) — one row per non-blank name, `crew_name` + `sort_order` | Delete-and-reinsert semantics; blank slots dropped, not migrated as empty rows. |
| `joinDC` | text | **Dropped, no new equivalent** | Old "Dive Center" field shown only when `boatType==='join'`. New schema's `is_joiner`/`joiner_boat_name` pair has no dive-center-name field. See known gap below. |
| `owner` | text | **Dropped, no new equivalent** | Old "Owner" field shown only when `boatType==='rental'`. No new column. |
| `tripType` | free-text key into hardcoded `tripTypeDurations` object | `schedules.trip_type_id` (FK to new `trip_types` table, migration 025) | See §12 — needs a name-to-id lookup per dive center, with net-new per-DC `trip_types` rows to migrate/seed first. |
| `sites` | `string[]` (dive site **names**, slots incl. blanks) | `schedule_sites` rows (`dive_site_id`, `sort_order`) | One row per **slot** (not deduped), migration 019 explicitly allows repeats. Resolve each name → `dive_sites.id`; blank slots dropped. |
| `hour`/`minute`/`ampm` | 3 separate strings | `schedules.departure_time` (real `time`, 24h) | Old app already derives a 24h string (`time24(t)`) for its own real `schedules.departure_time` write — the 3-part breakdown is UI-only, not itself a separate persisted field distinct from what old `schedules.departure_time` already holds. ETL can read old `schedules.departure_time` directly and skip the blob's hour/minute/ampm entirely. |
| `notesText` | free text | `schedules.notes` (new, real column) | The **only** blob key that maps 1:1 onto the new column of the same name. |
| `joinerDivers` | integer | `schedules.guest_divers_count` (migration 013) | Despite the name, this is the "**another** dive center's divers rode along on **our** boat" count — not related to `boatType==='join'`/`is_joiner` (which means the reverse: we joined someone else). See the dedicated callout in §1. |
| `joinerDC` | text | `schedules.guest_dive_center_name` (migration 013) | |
| `joinerNotes` | text | `schedules.guest_notes` (migration 013) | |
| `fuelConsumedLiters` | number\|null | `schedules.fuel_consumed_liters` (already a real column pre-migration, unchanged shape) | Also already duplicated onto the real column by the old app's own `payload.fuel_consumed_liters` at save time — read the real column, not the blob copy. |
| `closed` | boolean | `schedules.closed` (already a real column) | Old app **also** duplicates this into the blob (`markTripClosed` only ever updates the blob's `closed` flag, confirm real `schedules.closed` boolean was already true at insert or is set by other code — see caveat in §1). Read the real column; ignore the blob's copy. |
| `cancelled` | boolean | `schedules.cancelled` (already a real column) | Old app's `cancelled` flag in the blob was dead — no old UI ever sets it true. Real `schedules.cancelled` column exists in both schemas but the old app never had a Cancel button; expect this to always be `false` in migrated data. |
| `staffGroups` | `Array<{name, diverIds[], groupIds[], excludedDiverIds[], nitrox:{diverId:[idx]}, staffNitrox:[idx], tank15l:{diverId:[idx]}, is15l:{diverId:true}, isFreelancer}>` | Explodes into **five** different new tables: `schedule_divers`, `schedule_diver_dive_tanks`, `schedule_staff_dive_tanks`, and (only if the old app had already separately persisted the clip — see below) `schedule_team_clips`/`schedule_team_clip_divers` | The single largest, riskiest piece of this migration — see §5–§8 below for the full per-field breakdown. |
| *(no old key)* | — | `schedules.trip_type_id`, `schedule_spare_tanks` | New-only, no old-blob equivalent at all — see §11/§12. |
| *(no old key)* | — | `schedule_divers.staff_name`, `schedule_divers.source_clip_id` | New-only convenience columns not present in the old blob shape at all — see §5. |

---

## 1. `schedules`

### Old (live app)

Read via `client.from('schedules').select(...)` (multiple shapes across
`scheduling.html`/`staff.html`); written via `saveTrip`/`silentSaveTrip`
(`scheduling.html` ~line 1256) and `markTripClosed` (~line 696).

Real (non-blob) old columns actually referenced in the JS:
`id`, `dive_center_id`, `boat_id`, `schedule_date`, `departure_time`,
`dive_site` (flat text — see below), `is_joiner`, `joiner_boat_name`,
`fuel_consumed_liters`, `notes` (the JSON blob), `created_at` (implicit).
No `captain`/`guest_*`/`trip_type_id`/`cancelled`-as-a-real-signal/
`updated_at` columns exist in the old app's writes — those are exactly the
columns the new schema adds for real.

`dive_site` (old, flat text): `meta.sites.join(' / ')` — a **display-only**
derived string, e.g. `"Kimud / Monad"`. Never itself the source of truth;
`staff.html` falls back to parsing it only when `meta.sites` is missing
(`(s.dive_site || '').split('/').map(x=>x.trim())`).

### New (`001_schema_and_rls.sql` + migrations 013, 018, 025)

```
id, dive_center_id, boat_id, schedule_date, departure_time,
is_joiner, joiner_boat_name, fuel_consumed_liters,
closed, cancelled, notes, created_by, created_at, updated_at,
guest_divers_count, guest_dive_center_name, guest_notes,   -- migration 013
captain,                                                     -- migration 018
trip_type_id                                                 -- migration 025
```

### Field-by-field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | Same PK, carry over as-is. |
| `dive_center_id` | `dive_center_id` | Direct. |
| `boat_id` | `boat_id` | Direct **only for own-boat trips**. For join/rental trips the old app already writes `boat_id: boatIdFromName(t.boatName)` regardless of boat type in some code paths — re-derive from `meta.boatType`: if `boatType !== 'own'`, new `boat_id` should be `null` (matches `createTrip`'s own `isJoiner ? null : input.boatId` logic) even if the old row happened to have a non-null `boat_id`. |
| `schedule_date` | `schedule_date` | Direct. |
| `departure_time` | `departure_time` | Direct — already a real `time` column in both schemas, don't re-derive from the blob's hour/minute/ampm. |
| `dive_site` (flat, derived text) | *dropped* — superseded by `schedule_sites` | Do not migrate this column's value anywhere; regenerate the site list from `meta.sites` (or the column itself as a last-resort fallback if `meta.sites` is empty — see §2). |
| `is_joiner` | `is_joiner` | Direct. **Means "we joined another boat,"** i.e. old `boatType === 'join'` (also true for `'rental'`, since the old app's `createTrip`-equivalent write is `is_joiner: t.boatType==='join'` but `rental` also sets `joiner_boat_name`; confirm against the actual stored boolean, don't re-derive from `boatType` blindly since old and new "rental" semantics don't perfectly line up — see the boat-mode caveat below). |
| `joiner_boat_name` | `joiner_boat_name` | Direct, only meaningful when `is_joiner = true`. |
| `fuel_consumed_liters` | `fuel_consumed_liters` | Direct. |
| *(blob `closed`)* / real `closed`? | `closed` | The old app has **no real `schedules.closed` column at all in its writes** — `saveTrip`'s payload never includes `closed`, and `markTripClosed` only patches the JSON blob's `closed` key, not a real column. **If the live DB genuinely has no real `closed` column either** (need to confirm against the live schema, not assumed), the only source of truth for "was this trip's boat returned" is `meta.closed` inside the blob — parse it out during ETL. If the live DB *does* have a real `closed` column that's simply never referenced in this JS (possible, since Boat Manifest / other old pages might set it), prefer the real column. |
| *(blob `cancelled`)* | `cancelled` | Same caveat as above — no old UI path ever sets this to `true` in either the real column or the blob (`schedules.cancelled` is functionally dead in the old app). Expect `false` for every migrated row. |
| — | `guest_divers_count` | From `meta.joinerDivers`. |
| — | `guest_dive_center_name` | From `meta.joinerDC`. |
| — | `guest_notes` | From `meta.joinerNotes`. |
| — | `captain` | From `meta.captain`, **own-boat trips only** — null for joiner trips (matches `createTrip`'s `isJoiner ? null : input.captain.trim() || null`). |
| — | `trip_type_id` | From `meta.tripType` (a free-text name like `"Local Dive"`) — resolve to a `trip_types.id` for that dive center. See §12: this requires first seeding real `trip_types` rows per dive center (the old app's `tripTypeDurations` names/values are hardcoded JS, not per-tenant data — there is nothing to "migrate" here except *seeding*, and only for dive centers that actually used named trip types; a dive center that never touched the Trip Type dropdown will have `tripType: ''` and should get `trip_type_id = null`). |
| — | `notes` (repurposed) | From `meta.notesText` — **not** the raw old `schedules.notes` JSON string. Overwriting new `notes` with the raw old JSON blob would be a serious ETL bug (it would show a wall of JSON as "trip notes" in the UI) — extract just `notesText`. |
| *(none)* | `created_by` | No old equivalent captured anywhere in `scheduling.html`'s writes (the old `saveTrip` payload has no `created_by`/user-id field at all). Leave `null` for migrated rows, or backfill with a placeholder "migration" system user if the new schema's NOT NULL-ness (it isn't NOT NULL) requires a value — it doesn't, so `null` is fine. |
| *(none)* | `updated_at` | No old equivalent (old app has no updated-at concept) — default to `created_at` or migration-run time; not load-bearing since new schema uses it purely as an optimistic-concurrency token, no historical meaning to preserve. |

### Boat-mode caveat (real ambiguity, flag for manual review)

The new schema's `is_joiner`/`joiner_boat_name` pair is a strict **2-way**
split (own-boat vs. everything else), but the old app's UI is **3-way**
(`own` / `join` / `rental`) with two extra text fields (`joinDC` for join,
`owner` for rental) that have **no new-schema equivalent at all**. Per
`CLAUDE.md`'s own 2026-07-25 session notes, this was a deliberate, accepted
rebuild-time gap: "both just set `is_joiner=true` with a free-text name...
an accepted cosmetic gap since re-opening a Rental trip shows it as Join
Ride." For migration purposes this means:

- `boatType === 'join'` → `is_joiner = true`, `joiner_boat_name = meta.boatName`, `meta.joinDC` is **lost** (no column to put it in).
- `boatType === 'rental'` → `is_joiner = true`, `joiner_boat_name = meta.boatName`, `meta.owner` is **lost** (no column to put it in).
- Once migrated, a rental trip and a join-ride trip are **indistinguishable** in the new schema — both just look like "joined another boat named X." If this loss of the join/rental distinction (and the joinDC/owner free-text values) is unacceptable for real historical data, this is the one place in the whole Scheduling/Staff migration that needs a schema decision **before** running ETL (e.g. a new `schedules.boat_mode` enum + `schedules.external_owner_name`/`external_dive_center_name` columns) rather than a pure data-mapping exercise. Flagging this explicitly since it's real historical data loss, not just a migration nicety.

---

## 2. `schedule_sites` (new-only relational table; old = `meta.sites[]`)

### Old

`meta.sites` — a plain string array of dive-site **names**, always exactly
3 default slots (`sites:['','','']` on trip creation) plus any appended via
"+ Add Dive"; blank strings for unfilled slots. No independent table; lives
entirely inside the `schedules.notes` JSON blob.

### New

```
schedule_sites(id, dive_center_id, schedule_id, dive_site_id, sort_order)
```
`unique(schedule_id, sort_order)` (migration 019 — replaced an earlier
`unique(schedule_id, dive_site_id)` that wrongly forbade revisiting the same
site twice in one trip).

### Mapping / ETL logic

For each `schedules` row, take `meta.sites` (array), and for each **non-blank**
entry at index `i`:
1. Resolve the site name → `dive_sites.id` for that dive center (name match,
   case-sensitive exact match preferred; the old app's own site dropdown is
   populated from `dive_sites.site_name` so an exact match should exist for
   any site actually pickable from the UI — a mismatch signals either a
   renamed/deleted `dive_sites` row or manually-corrupted old data).
2. Insert `{dive_center_id, schedule_id, dive_site_id, sort_order: i}`.

Blank slots are **not** inserted as empty rows — `sort_order` is not
necessarily contiguous from 0 if an early slot was left blank while a later
one was filled (matches the new app's own `replaceScheduleSites`, which
also just filters truthy site IDs before inserting, using the filtered
array's own index as `sort_order` — so **re-index after filtering blanks**,
don't preserve the old array's raw index gaps).

**Fallback**: if `meta.sites` is missing/malformed for some old row (JSON
parse failure, pre-dates the sites feature, etc.), fall back to parsing the
old flat `schedules.dive_site` text column by `/` — matches `staff.html`'s
own defensive fallback (`(s.dive_site||'').split('/').map(x=>x.trim())`) —
though this only recovers site **names**, still needs the same name→id
resolution step.

---

## 3. `schedule_crew` (new-only relational table; old = `meta.crews[]` + `meta.captain`)

### Old

`meta.crews` — string array, 3 default slots (`crews:['','','']`), plus
"+ Add Crew". `meta.captain` is a **separate** single string field, not part
of the crew array (captain has its own dedicated new column, see §1).

### New

```
schedule_crew(id, dive_center_id, schedule_id, crew_name, sort_order)
```

### Mapping / ETL logic

For each **non-blank, trimmed** entry in `meta.crews`, insert one row:
`{dive_center_id, schedule_id, crew_name: name.trim(), sort_order: i}` —
same blank-filtering-then-re-index rule as `schedule_sites` above
(`replaceScheduleCrew`'s real logic: `crew.map(c=>c.trim()).filter(Boolean)`
then indexes the **filtered** array). `meta.captain` is **not** part of this
table — it goes to `schedules.captain` (§1).

Only applies to own-boat trips (`boatType === 'own'`) — join/rental trips
never show or persist a crew list in the old UI (`crews.map` is gated
inside the `t.boatType==='own'` branch of `tripDetailFieldsHTML`), so
migrate `schedule_crew` rows only for `boatType === 'own'` schedules; skip
entirely for join/rental (even if stray crew strings happen to exist in a
joiner trip's blob from before a boat-type switch, don't carry them over —
matches the new app's own `isJoiner ? [] : input.crew` write).

---

## 4. `schedule_team_clips` + `schedule_team_clip_divers`

### Old

**These are real, already-relational tables in the old live app too** — not
part of the `schedules.notes` blob. Confirmed via direct grep of
`scheduling.html`: `persistClipToDb`/`loadSuggestedClipsForDate`/
`carryOverLatestSharedClips`/`deleteClipFromDb` all read/write these tables
directly, independent of any specific trip/schedule row. A "clip" is a
day-scoped (not trip-scoped) grouping of divers under one staff member,
used as a Phase-1 prep concept before divers get placed onto an actual trip.

Old columns actually written (`persistClipToDb`):
```
schedule_team_clips: dive_center_id, schedule_date, staff_id, staff_name,
  is_freelancer, source ('manual'|'returned'|'carryover'), carry_forward,
  created_by, updated_at
schedule_team_clip_divers: dive_center_id, clip_id, diver_id, excluded_on_date
```

### New

Identical shape — `001_schema_and_rls.sql` defines these two tables with
the **exact same column names and types** as the old app already uses
(confirmed the new schema was deliberately designed to mirror this real
live-app mechanism, not invented independently):
```
schedule_team_clips(id, dive_center_id, schedule_date, staff_id, staff_name,
  is_freelancer, source public.clip_source, carry_forward, created_by,
  created_at, updated_at)
schedule_team_clip_divers(id, dive_center_id, clip_id, diver_id, excluded_on_date)
```

### Mapping

| Old column | New column | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | Direct. |
| `schedule_date` | `schedule_date` | Direct. |
| `staff_id` | `staff_id` | Direct (nullable — null for freelancers). |
| `staff_name` | `staff_name` | Direct. |
| `is_freelancer` | `is_freelancer` | Direct. |
| `source` | `source` | Direct — new `clip_source` enum values (`manual`/`returned`/`carryover`) are byte-identical to the old app's own string literals, confirmed from `cleanDbClip`'s `['manual','returned','carryover'].includes(clip.source)`. |
| `carry_forward` | `carry_forward` | Direct. |
| `created_by` | `created_by` | Direct (old app sets `currentUser?.id||null` — same shape as new `users.id`). |
| `updated_at` | `updated_at` | Direct. |
| `clip_id`/`diver_id`/`excluded_on_date` (`schedule_team_clip_divers`) | same | Direct, no transform needed. |

**This is the one table pair in this whole mapping that's essentially a
straight copy** — same table names, same columns, same types, same enum
values. The only real migration risk is `created_by`/`staff_id` FK
integrity (a `users`/`staff` row that existed on the live system must also
exist post-migration with a stable, mapped ID) and `staff_id` resolution
consistency with `schedule_divers.staff_id` (§5).

**New-only addition**: `schedule_divers.source_clip_id` (migration 016) is
a new FK from a placed trip-team back to the clip it came from. The old app
tracks this **only in-memory** as `g.sourceClipId` inside the (never
persisted verbatim) `staffGroups` JS objects — it is **not** written
anywhere in the old app's real `schedule_divers` insert
(`insertScheduleDiverRows`, confirmed no `source_clip_id`-equivalent field
in that insert's payload). **There is no historical data to migrate for
this new column** — leave `null` for every migrated `schedule_divers` row;
it only has meaning going forward once the new app starts writing it.

---

## 5. `schedule_divers`

### Old

Written by `insertScheduleDiverRows` (~line 1227), read by `staff.html`.
Old columns actually written:
```
schedule_id, diver_id, staff_id, is_diving_tomorrow, nitrox_requested,
is_15l, notes (a second, per-diver JSON blob — see §6)
```
`is_diving_tomorrow` is always hardcoded `true` on insert — a vestigial
column name from an earlier feature shape, not a real per-row flag the old
UI ever varies.

**Critically, the old app never wrote `experience_type` or `staff_name` to
this table at all** (confirmed no such fields in `insertScheduleDiverRows`'s
insert payload) — despite `staff.html` reading `experience_type` from it
and `get_crew_schedule` needing it. This was an actual latent gap in the
*old* live app too, not just a rebuild artifact — see the caveat below.

### New

```
schedule_divers(id, dive_center_id, schedule_id, diver_id, staff_id,
  experience_type public.experience_type, is_15l, is_diving_tomorrow,
  nitrox_requested, notes, created_at,
  source_clip_id,   -- migration 016
  staff_name)        -- migration 026
unique(schedule_id, diver_id)
```

### Field-by-field mapping

| Old field | New field | Notes |
|---|---|---|
| `dive_center_id` (implicit, not in old insert — inferred from schedule) | `dive_center_id` | New schema requires this explicitly; derive from the parent `schedules.dive_center_id`. |
| `schedule_id` | `schedule_id` | Direct. |
| `diver_id` | `diver_id` | Direct. |
| `staff_id` | `staff_id` | Direct — resolved old-side via `staffIdFromName(g.name)` (name lookup against `staff`), so already an id at old-insert time; carry straight over, re-mapped through whatever staff-id remapping the overall migration uses. |
| `is_diving_tomorrow` | `is_diving_tomorrow` | Direct, though semantically vestigial in both schemas — always `true` historically, safe to just copy through as-is. |
| `nitrox_requested` | `nitrox_requested` | Direct **derived summary boolean** in both old and new — "at least one dive this trip uses nitrox," computed old-side as `nitroxIndexes.length>0` (from `getNitroxIndexes`). New schema's comment (migration 017) explicitly confirms this stays a derived summary column post-migration, same meaning. |
| `is_15l` | `is_15l` | Same pattern as `nitrox_requested`, for the 15L tank. |
| `notes` (per-diver tank-detail JSON, see §6) | `notes` | **Do not migrate the raw old JSON string into the new `notes` column verbatim** — the new schema's `notes` on this table is a legacy/freeform field, and the *structured* per-dive detail this JSON encoded now belongs in `schedule_diver_dive_tanks` (§6). Parsing this JSON is the only way to reconstruct per-dive index data for the new child table — see §6 for the exact extraction logic. After extracting the structured indexes, either leave new `notes` `null`, or (if some free-text signal is worth preserving) copy over only if the old JSON had a genuine `legacy_note` fallback key (see `activityFlagNotes`'s `legacy_note` handling for the *activities* table — a similar pattern may exist here, but `scheduleDiverTankNotes` (the actual writer for `schedule_divers.notes`) never had a free-text fallback path at all, it's a pure structured-JSON writer with no possibility of a legacy string inside it). |
| *(none, never written by old app)* | `experience_type` | **Real gap in the old live app, not just this schema mapping** — old `insertScheduleDiverRows` never sets this. `staff.html`/`get_crew_schedule` both read it expecting a value, so it was silently always `null` on old-app-created rows too. Migrated rows should therefore also get `null` here, **unless** it can be cross-derived from the diver's own open `visits.experience_type` at the same date (matching how the *rebuild* itself derives it for new writes — `ClipMember.experienceType` is sourced from the diver's open visit, not from `schedule_divers` directly). If historical accuracy matters here, a best-effort backfill join against `visits`/`visit_status='open'`/matching date is the closest available signal, not a guarantee. |
| *(none, never written by old app)* | `staff_name` | Same situation as `experience_type` — old app never wrote a per-schedule_divers staff-name snapshot (migration 026 is a rebuild-only addition, added specifically to fix a *rebuild* freelancer bug that doesn't map to anything the old app persisted this way). Best-effort backfill: resolve `staff_id` → `staff.first_name || ' ' || staff.last_name` at migration time for named-staff rows; for the (probably rare, in historical old-app data) freelancer case where `staff_id` was null, there is **no** recoverable name from `schedule_divers` alone — the freelancer's typed name only ever lived in the transient `staffGroups[].name` JS object, which for **saved/closed trips** is only reconstructable by parsing the parent `schedules.notes` blob's `meta.staffGroups[].name` for the matching (unresolvable-staff-id) group and joining on `diverIds` membership. Worth doing as a real backfill step (the data does still exist in the old blob) rather than leaving every historical freelancer-led row's name blank. |
| *(none)* | `source_clip_id` | No historical equivalent — leave `null` (see §4). |

---

## 6. `schedule_diver_dive_tanks` (new-only; old = `schedule_divers.notes` per-diver JSON)

### Old

The **per-diver** `schedule_divers.notes` column (different from
`schedules.notes` — a second, distinct JSON blob, one per diver-on-trip row)
holds `scheduleDiverTankNotes`'s output:
```json
{
  "source": "scheduling_trip_builder",
  "tank_logic_version": 2,
  "nitrox_requested": bool,
  "is_15l": bool,
  "tank_15l_requested": bool,
  "fifteen_l_requested": bool,
  "nitrox_tank_count": int,
  "tank_15l_count": int,
  "fifteen_l_tank_count": int,
  "nitrox_dive_indexes": [int, ...],
  "tank_15l_dive_indexes": [int, ...],
  "fifteen_l_dive_indexes": [int, ...]
}
```
`nitrox_dive_indexes`/`tank_15l_dive_indexes` are 0-based indexes into that
trip's `meta.sites` array — "this diver used nitrox on dive index 0 and 2,"
etc. (Boat Return, a separate old-app flow not covered by this scheduling/
staff mapping, writes a **third**, differently-shaped tank JSON onto
`activities.notes` via `activityFlagNotes` — don't confuse the two; that one
is out of scope here.)

### New

```
schedule_diver_dive_tanks(id, dive_center_id, schedule_diver_id,
  site_index integer, tank_type text check in ('nitrox','air_15l'))
unique(schedule_diver_id, site_index)
```
One row per (diver, dive-site-index, tank-type) — **not** one row per
index-array entry of both types simultaneously, since a single dive can
only have one tank type. Confirmed from the new app's own writer
(`saveTripTeams`): `d.tanks.map(tk => ({schedule_diver_id, site_index: tk.siteIndex, tank_type: tk.tankType}))`.

### Mapping / ETL logic

For each `schedule_divers` row, parse its old `notes` JSON:
1. For each index `i` in `nitrox_dive_indexes`: insert
   `{dive_center_id, schedule_diver_id: <new row's id>, site_index: i, tank_type: 'nitrox'}`.
2. For each index `i` in `tank_15l_dive_indexes`: insert
   `{dive_center_id, schedule_diver_id: <new row's id>, site_index: i, tank_type: 'air_15l'}`.

`nitrox_tank_count`/`tank_15l_count`/`fifteen_l_*` are **redundant derived
counts already implied by the index arrays' lengths** — don't migrate them
anywhere, they're not real data, just old-app display cache. Same for the
duplicated `fifteen_l_*`/`row_*`/`charge_*` key aliases seen in the
*Boat Return* variant (`activityFlagNotes`, out of scope table) — all
several names for the same two booleans, a sign the old app's JSON shape
accreted ad hoc rather than being designed once.

**Constraint risk**: `unique(schedule_diver_id, site_index)` — if any old
diver-trip row's JSON somehow has the *same* site index in **both**
`nitrox_dive_indexes` and `tank_15l_dive_indexes` (shouldn't be possible
given the old UI's own mutual-exclusion toast check, but old data can be
messier than the current UI allows), the second insert for that
`(schedule_diver_id, site_index)` pair will violate the unique constraint.
Dedup with a clear priority rule (e.g. nitrox wins) if this is ever found in
real data, and log/flag any row where it happens rather than silently
dropping one side.

---

## 7. `schedule_staff_dive_tanks` (new-only; old = `meta.staffGroups[].staffNitrox[]`)

### Old

Inside the `schedules.notes` blob, each `staffGroups[]` entry has
`staffNitrox: [int, ...]` — 0-based dive-site indexes where that staff
member (not a diver) used nitrox. Unlike diver tanks, there's no
"staff 15L" concept in the old app at all — staff are assumed Air 12L or
Nitrox only, never 15L (confirmed: no `staff15l`/`staffTank15l` key
anywhere in `normalizedGroupForMeta`/`buildTripMeta`).

### New

```
schedule_staff_dive_tanks(id, dive_center_id, schedule_id, staff_name text,
  site_index integer)
unique(schedule_id, staff_name, site_index)
```
Every row implicitly means "nitrox" — there's no `tank_type` column here at
all (matches the old app's own nitrox-only staff-tank concept exactly, not
a rebuild simplification).

### Mapping / ETL logic

For each `schedules` row, for each entry in `meta.staffGroups`, for each
index `i` in that group's `staffNitrox` array: insert
`{dive_center_id, schedule_id, staff_name: g.name, site_index: i}`.

`staff_name` here is keyed by the group's **display name string**
(`g.name`), not a `staff_id` FK — matches the new schema exactly (no
`staff_id` column on this table at all, confirmed from both `001`'s table
definition and the new app's own insert, which only ever writes
`staff_name`/`site_index`). No id-resolution needed for this table, unlike
`schedule_divers.staff_id` — just copy the name string through, including
for freelancer groups (where it's the only identity available anyway).

---

## 8. `schedule_day_diver_exclusions`

### Old

Written by `saveDailyDiverExclusion`/`removeDailyDiverExclusion`
(~line 2361), a real relational table already in the old live app (not part
of the JSON blob — this is a **day-scoped**, not trip-scoped, "this diver
isn't diving at all today" flag, distinct from a per-clip
`excluded_on_date` which just means "not diving *this specific clip's
boat*").

Old columns: `dive_center_id, schedule_date, diver_id, created_by`.

### New

```
schedule_day_diver_exclusions(id, dive_center_id, diver_id, schedule_date,
  created_by, created_at)
unique(diver_id, schedule_date)
```

### Mapping

Direct 1:1 column copy — `dive_center_id`, `schedule_date`, `diver_id`,
`created_by` all map straight across with the same names and meanings, same
as `schedule_team_clips` in §4. No transformation needed.

---

## 9. `schedule_spare_tanks` (new-only — no old equivalent at all)

Confirmed via grep of every old reference `*.html` for "spare": **zero
matches** beyond an unrelated placeholder string elsewhere in the codebase.
This is a genuinely new, rebuild-only feature (per-trip repeatable list of
spare tanks by type + quantity, migrations 020/021). There is **no source
data anywhere in the old schema** for this table — every migrated
`schedules` row should simply have **zero** `schedule_spare_tanks` rows.
Nothing to map; flagged here only so the ETL script doesn't waste time
looking for a source.

---

## 10. `boats`

### Old (`settings.html`'s `saveBoat`, ~line 1755 — scheduling.html/staff.html only read this table)

```js
{
  dive_center_id, name,
  boat_type: <'Outrigger'|'Flat Boat'|'Chase Boat'|'Speed Boat'>,  // title case
  fuel_type: <'Gasoline'|'Diesel'>,                                 // title case
  capacity: int,
  captain: text,
  is_active: bool
}
```

### New (`001` + migration 005)

```
boats(id, dive_center_id, name, captain, boat_type public.boat_type,
  fuel_type public.fuel_type, is_active, created_at, capacity)
```
Enum values (migration 001): `boat_type` = `outrigger|flat_boat|chase_boat|speed_boat`;
`fuel_type` = `gasoline|diesel` — all lowercase/snake_case.

### Mapping

| Old field | New field | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | Direct. |
| `name` | `name` | Direct. |
| `boat_type` | `boat_type` | **Transform required**: `"Outrigger"→'outrigger'`, `"Flat Boat"→'flat_boat'`, `"Chase Boat"→'chase_boat'`, `"Speed Boat"→'speed_boat'` (lowercase, spaces→underscores). |
| `fuel_type` | `fuel_type` | **Transform required**: `"Gasoline"→'gasoline'`, `"Diesel"→'diesel'`. |
| `capacity` | `capacity` | Direct — this column exists in *both* old and new schemas as the same real integer (migration 005 only fixed a rebuild-schema gap that never existed in the live app, not an old-app field rename). |
| `captain` | `captain` | Direct — this is the **Fleet-level default captain**, a completely separate concept from `schedules.captain` (§1/§18's per-trip captain). Both exist as distinct fields in old and new; don't conflate them during migration. |
| `is_active` | `is_active` | Direct. |

**Enum constraint risk**: if any live `boats.boat_type`/`fuel_type` value
doesn't match one of the 4/2 known title-case strings exactly (e.g. a typo,
a since-removed dropdown option from an older app version, manual DB
editing), the transform will fail to map it and the new `not null` enum
column has no matching value — decide a fallback (error-and-flag vs. a
default) before running ETL, don't let it silently null out or crash mid-run.

---

## 11. `staff`

### Old (`settings.html`'s `saveStaff`, ~line 1568 — read-only in scheduling.html/staff.html)

```js
{
  dive_center_id,
  first_name, last_name,   // split from one "Full Name" field
  email,
  role: <'Secretary'|'Divemaster'|'Instructor'|'Crew'>,       // title case, DISPLAY-ONLY
  employment_status: <'Full Time'|'Part Time'|'Freelance'>,   // title case
  date_hired, daily_rate,
  phone, whatsapp,
  access_level: <'secretary'|'divemaster'|'instructor'|'crew'>, // lowercase, THE REAL ROLE
  nitrox_certified, is_active,
  auth_user_id   // set separately, when linking a Secretary login
}
```
The old app writes **both** `role` (title case, cosmetic display label) and
`access_level` (lowercase, the value everything else — RLS-equivalent
access checks, badges — actually keys off) for every staff row. This is a
genuine old-app duplication, not a rebuild artifact.

### New (`001` + migration 010)

```
staff(id, dive_center_id, user_id, first_name, last_name, email, phone,
  whatsapp, position public.staff_position, employment_status
  public.staff_employment_status, date_hired, daily_rate, nitrox_certified,
  is_active, created_at,
  emergency_contact_name, emergency_contact_phone,
  emergency_contact_relationship, emergency_contact_whatsapp,
  emergency_contact_email)   -- migration 010
```
`staff_position` enum: `secretary|divemaster|instructor|crew` (lowercase).
`staff_employment_status` enum: `full_time|part_time|freelance` (snake_case).

### Field-by-field mapping

| Old field | New field | Notes |
|---|---|---|
| `dive_center_id` | `dive_center_id` | Direct. |
| `first_name`/`last_name` | `first_name`/`last_name` | Direct — already split old-side. |
| `email` | `email` | Direct. |
| `role` (title case) | *dropped, no new equivalent* | Redundant with `access_level`/new `position` — don't migrate, it was always a cosmetic duplicate. |
| `access_level` (lowercase) | `position` | **Direct value match** — old `access_level`'s lowercase strings (`secretary`/`divemaster`/`instructor`/`crew`) are byte-identical to the new `staff_position` enum's values. This is the field that actually matters, not `role`. |
| `employment_status` | `employment_status` | **Transform required**: `"Full Time"→'full_time'`, `"Part Time"→'part_time'`, `"Freelance"→'freelance'`. |
| `date_hired` | `date_hired` | Direct. |
| `daily_rate` | `daily_rate` | Direct. |
| `phone` | `phone` | Direct. |
| `whatsapp` | `whatsapp` | Direct. |
| `nitrox_certified` | `nitrox_certified` | Direct. |
| `is_active` | `is_active` | Direct. |
| `auth_user_id` | `user_id` | **Column rename**, same semantic (FK to the linked login's user row) — old app's actual auth linkage happens via a separate Edge Function (`createSecretaryAuth`) and a follow-up `staff.update({auth_user_id, is_active:true})`; the *new* `auth.users`/`public.users` id for that same person needs to already exist (from whatever separate auth-migration step handles logins) before this FK can be populated — this table's own migration can't create it. |
| *(none)* | `emergency_contact_*` (5 fields) | **No old-app equivalent anywhere** — confirmed via grep, `settings.html` has no emergency-contact UI for staff at all (this is a rebuild-only addition, migration 010, deliberately modeled on the divers' migration-008 shape). Leave `null` for every migrated staff row. |

---

## 12. `staff_certifications` (new-only — no old equivalent at all)

Confirmed via grep of `settings.html` (case-insensitive `cert` near any
`staff` context): zero hits beyond the `nitrox_certified` badge, which is
already its own dedicated `staff.nitrox_certified` boolean column in both
schemas (§11) — there is no old per-certification list/expiry concept for
staff anywhere in the live app (divers have an equivalent `cert_card_url`
single-image field, staff have nothing). This table has **no source data**
to migrate; every migrated `staff` row should simply have zero
`staff_certifications` rows. Nothing to map.

---

## 13. `trip_types` (new-only per-dive-center table — old = hardcoded JS constant)

### Old

`tripTypeDurations` (`scheduling.html` line 52) — a single, hardcoded,
**app-wide** (not per-dive-center) JS object, not a database table at all:
```js
{
  'Local Dive':          {travelOut:20,  travelBack:20,  dive:60, surface:60},
  'Shark Dive':          {travelOut:60,  travelBack:60,  dive:60, surface:60},
  'Gato':                {travelOut:60,  travelBack:60,  dive:60, surface:60},
  'Outside Malapascua':  {travelOut:180, travelBack:180, dive:60, surface:60}
}
```
These four names/values are specific to one real dive center's own
geography (Malapascua) — hardcoded into the live app's source, not
tenant-configurable data anywhere in the database.

### New

```
trip_types(id, dive_center_id, name, travel_out_minutes, travel_back_minutes,
  dive_minutes, surface_interval_minutes, is_active, created_at)
```
`schedules.trip_type_id` references this per-tenant.

### Mapping / ETL logic

**This is not a data migration in the normal sense — it's a seeding
decision.** There is no per-dive-center source table to read from; the old
"data" is one shared JS constant. Two things need deciding before ETL:

1. **Seed `trip_types` rows.** Per `CLAUDE.md`'s 2026-07-31/08-01 session
   notes, the four real Local Dive/Shark Dive/Gato/Outside Malapascua
   values were manually seeded for the one real dive center that actually
   used those names (Malapascua). For migrating **other** live dive
   centers' historical data, there is no way to know what trip-type names
   (if any) that tenant's secretaries actually typed into the old
   `tripType` dropdown-equivalent unless the ETL script itself scans that
   tenant's own historical `schedules.notes` blobs for distinct
   `meta.tripType` string values used, and seeds one `trip_types` row per
   distinct name found (with the four Malapascua duration values as a
   reasonable default guess, or a generic `{20,20,60,60}` fallback,
   flagged for the dive center's owner to correct post-migration since the
   actual travel times were never really tenant-specific data to begin
   with — they were literally the same 4 numbers hardcoded for every
   dive center on the old platform).
2. **Resolve `schedules.trip_type_id`** for each migrated trip: look up
   `meta.tripType` (a name string, possibly empty) against that tenant's
   newly-seeded `trip_types` rows by name; `''`/unmatched → `null`
   (matches the new schema's own nullable-by-design column, confirmed from
   migration 025's own comment: "existing trips... still work" with no
   trip type set).

---

## 14. `manifests` and `fuel_logs` — brief notes (peripheral to this scope)

- **`manifests`**: not read or written anywhere in `scheduling.html` or
  `staff.html` (confirmed via grep — zero matches in either file). In both
  the old live app and the new rebuild, a `manifests` row is created purely
  by a database-level trigger the instant a `schedules` row is inserted
  (`schedules_create_manifest` — new-side confirmed in
  `001_schema_and_rls.sql`; the equivalent almost certainly exists as a
  live-app trigger too, since the old app's own `boat-manifest.html`, out
  of this scope, never inserts one either). **No ETL action needed for this
  table** beyond making sure the same triggering mechanism exists in the
  new database *before* migrating `schedules` rows, so each migrated
  schedule gets its manifest row for free via the trigger, not via a
  separate explicit insert step. If the new DB's schedule-insert path for
  migrated historical rows bypasses the normal trigger (e.g. a bulk
  `COPY`), the ETL script needs its own explicit `manifests` backfill pass
  afterward.
- **`fuel_logs`**: written once per Boat Return with fuel entered
  (`client.from('fuel_logs').insert(...)`, ~line 643) —
  `dive_center_id, schedule_id, boat_id, fuel_type, liters_consumed,
  diver_count, dive_count`. New schema (`001`) has the identical column
  set and types — a direct 1:1 copy, no transform needed. Only join-ride
  trips are guaranteed to have **zero** fuel_logs rows in both schemas
  (old app never logs fuel for `is_joiner=true` trips); own-boat trips
  with `fuelConsumedLiters` unset/zero also correctly have none.

---

## 15. `groups` — brief note (mostly out of scope; read-only reference here)

`scheduling.html` only ever **reads** `groups` (`select('*')`, whole table
per dive center, used for group-based clip bulk-assignment) — real
create/edit/delete for groups lives in `divers.html`, outside this
mapping's two-file scope. For completeness: old app's group-relevant read
fields are `id`, `group_name` (used in `groupById`/`confirmTeamHTML`, etc.);
new schema (`001` + migration 011) is `groups(id, dive_center_id,
group_name, leader_name, arrival_date, expected_count, is_active,
created_at, departure_date, notes)` — a superset, direct pass-through for
every field `scheduling.html` itself touches. No scheduling-specific
transform needed; the full `groups` CRUD mapping (create/registration-link
flow, `departure_date`/`notes` migration-011 fields) belongs in whatever
migration-mapping document covers `divers.html`, not this one.

---

## 16. `dive_centers.staff_token` / `staff_token_date` (crew-token mechanism)

Not a historical-data migration concern at all — these two columns hold a
**single, ephemeral, currently-live** 5-character token per dive center,
regenerated constantly (`generateToken()`, `refreshStaffToken()`,
`generate_daily_staff_token` RPC). A token minted under the old system has
no meaning once the dive center is running on the new database (new tokens
will be minted fresh from the new app going forward). **Do not migrate
these two column values** — leave them however the new dive center row's
own defaults land (both nullable), and let the first real use of Scheduling
on the new system mint a fresh token normally.

Mechanism confirmed **identical** between old and new (both a single
`dive_centers.staff_token`/`staff_token_date` pair, both scoped to
"whichever schedule date was selected when the token was last generated,"
not real calendar-today) — see `CLAUDE.md` retrospective #51 for the
rebuild's own history of getting this wrong once and then correcting it to
match the old app exactly. No schema-shape gap here at all, just nothing
worth carrying over as *data*.

---

## Summary: enum / constraint gotchas to handle before running ETL

1. **`boats.boat_type`/`fuel_type`**: title-case strings → lowercase/
   snake_case enum values (§10). Any live value that doesn't exactly match
   the known set fails the `not null` enum column outright.
2. **`staff.employment_status`**: title-case strings → snake_case enum
   (§11). Same failure mode as above.
3. **`staff.position`** (old: `access_level`, not `role`): already
   lowercase in the old data, but confirm the migration reads
   `access_level`, not the cosmetic `role` field, or every migrated staff
   member's real position will be wrong even though it "looks" plausible
   (both are English words, easy to confuse silently).
4. **`schedule_diver_dive_tanks.tank_type` check constraint**
   (`nitrox`/`air_15l` only, §6): a diver flagged in *both* the old
   `nitrox_dive_indexes` and `tank_15l_dive_indexes` arrays for the same
   site index will violate `unique(schedule_diver_id, site_index)` on the
   second insert attempt — needs an explicit dedup/priority rule.
5. **`schedule_sites`/`schedule_crew` blank-slot re-indexing**: both old
   arrays keep blank placeholder slots (`['','','']` defaults); the new
   tables must be populated from the **filtered, re-indexed** list, not
   the raw old array with its gaps — `sort_order` needs to be contiguous
   from 0 in the new tables even if the old slot the value came from
   wasn't slot 0.
6. **`schedules.is_joiner` boat-mode collapse**: the old app's 3-way
   `own`/`join`/`rental` boat-type distinction (plus `joinDC`/`owner` free
   text) has no new-schema equivalent beyond a 2-way boolean — real,
   deliberate historical-data loss unless a schema addition is made before
   ETL runs (§1's dedicated callout).
7. **`trip_types` is a seeding decision, not a migration** — there is no
   real per-tenant source table for this at all in the old schema (§13).

---

## Summary: new columns/tables with genuinely no source data (leave empty/null, not a migration bug)

- `schedules.trip_type_id` — null unless a `trip_types` seeding pass is
  done first (§13); not itself missing source data, just needs prep work.
- `schedule_divers.source_clip_id` — always null, no old-app equivalent
  ever persisted (§4).
- `schedule_spare_tanks` — always zero rows per trip, genuinely new
  feature (§9).
- `staff_certifications` — always zero rows per staff member, genuinely
  new feature (§12).
- `staff.emergency_contact_*` (5 columns) — always null, genuinely new
  feature (§11).
- `dive_centers.staff_token`/`staff_token_date` — don't migrate at all,
  ephemeral by design (§16).
# AquaDesk — Reports/Financial Data Migration Mapping (Old → Rebuild)

Source of truth for OLD usage: `D:\Rebuild\reports.html` (grepped every
`.from(`/`.insert(`/`.update(`/`.select(`/`.rpc(` call, read surrounding
payload-construction code for every table in scope).

Source of truth for NEW schema: `D:\Rebuild\database\001_schema_and_rls.sql`
plus every later migration that touches each table (verified by grepping
all 35 files per table name — only `001`, `006`, `007`, `009`, `031`, `035`
ever touch any of the seven in-scope tables; no other migration file
mentions any of them).

**Two tables in this set have a genuinely restructured shape, not just
renamed columns**: `govt_fees` (rate-config → daily log, migration `006`)
and `staff_commission_records` (calendar-month bucket → per-line-item,
migration `007`, extended by `035`). Both are called out in detail below.
`expenses.paid_by` is a confirmed drop with **no new-schema equivalent** —
migration `031` removes it outright.

---

## 1. `expenses`

### Old columns (as used by `reports.html`)
`id`, `dive_center_id`, `date`, `category`, `custom_category`, `amount`,
`paid_by` (free text), `notes`, `created_by`, `created_at` (implicit,
never set explicitly — DB default).

Old app's `EXPENSE_CATEGORIES` (exact strings sent as `category`):
`Fuel`, `Boat Maintenance`, `Equipment Maintenance`,
`Compressor / Fill Station`, `Staff Meals`, `Food Expenses`,
`Office Supplies`, `Utilities`, `Licenses & Permits`, `Marketing`,
`Repairs`, `Other`, `Uncategorized`.

### New columns (`001_schema_and_rls.sql` + `031_expenses_payment_method.sql`)
`id`, `dive_center_id`, `date`, `category` (`public.expense_category` enum),
`custom_category`, `amount` (`check (amount > 0)`), ~~`paid_by`~~ **dropped
by 031**, `payment_method` (`public.payment_method` enum, nullable — added
by 031), `notes`, `created_by`, `created_at`.

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `date` | `date` | same |
| `category` | `category` | **value transform required** — see enum table below |
| `custom_category` | `custom_category` | same, only meaningful when `category = 'other'` |
| `amount` | `amount` | same; new schema adds `check (amount > 0)` — old app already enforces `amount>0` client-side (`saveExpenseRecord`), so real historical rows should already satisfy this, but verify with a pre-migration `select count(*) where amount<=0` |
| `paid_by` | **dropped — no new-schema equivalent** | migration 031 removed this column entirely. ETL must not attempt to write it. Recommended: fold the old free-text value into `notes` (e.g. prefix `"Paid by: {old.paid_by} — "` onto `notes`) so the information isn't silently lost, since `payment_method` is a structured enum that can't represent an arbitrary "who/what funded it" string |
| — (no old field) | `payment_method` | **new field, no old equivalent** — nullable, leave `NULL` on migrated rows (don't try to infer cash/card/online from the old free-text `paid_by`, it's not reliably parseable) |
| `notes` | `notes` | same (see `paid_by` fold-in above) |
| `created_by` | `created_by` | same — old app **already** writes `created_by:currentUser?.id||null` on every save (confirmed in `reports.html` line ~1216), so this is a direct 1:1 copy, not a backfill; new-schema `users.id` values must resolve via whatever user-id remapping the auth migration performs |
| `created_at` | `created_at` | same, DB-defaulted on both sides |

### Category enum value transform (old string → new `expense_category` enum)

| Old (`reports.html` `EXPENSE_CATEGORIES`) | New (`public.expense_category`) |
|---|---|
| `Fuel` | `fuel` |
| `Boat Maintenance` | `boat_maintenance` |
| `Equipment Maintenance` | `equipment_maintenance` |
| `Compressor / Fill Station` | `compressor_fill_station` |
| `Staff Meals` | `staff_meals` |
| `Food Expenses` | `food_expenses` |
| `Office Supplies` | `office_supplies` |
| `Utilities` | `utilities` |
| `Licenses & Permits` | `licenses_permits` |
| `Marketing` | `marketing` |
| `Repairs` | `repairs` |
| `Other` | `other` |
| `Uncategorized` | `uncategorized` |

Not a simple `.toLowerCase()` — three values (`Compressor / Fill Station`,
`Licenses & Permits`, and the space-vs-underscore change generally) need
an explicit lookup table in the ETL, not a mechanical transform.

### Structural changes
None beyond the column-level drop/add above — `expenses` was always a flat
per-row log in both schemas, no month-bucketing or restructuring.

---

## 2. `govt_fees`

**This is the confirmed shape-change case.** The base `001_schema_and_rls.sql`
defines `govt_fees` as a rate-config table (`fee_name text`, `amount
numeric`, `is_active boolean`) — but that was a documented mistake caught
mid-project (see `006_govt_fees_daily_log.sql`'s own comment: "the original
schema shaped this as a rate-config table... but `reports.html`'s real
Government Fees tab is a **daily log**"). **The old app itself never used
the rate-config shape at all** — `reports.html`'s actual `govt_fees` usage
(confirmed by reading the code directly, not assumed) is already the
daily-log shape. So there is no old-schema "rate config" data to migrate
from at all for this table — every real historical row already matches
what migration `006` produces.

### Old columns (as used by `reports.html`)
`id`, `dive_center_id`, `date`, `fee_type` (one of `Marine Fee` / `Shark
Fee` / `Other Fee`), `rate`, `divers`, `total` (`= rate × divers`,
client-computed and sent as-is, not server-recomputed).

### New columns (`006_govt_fees_daily_log.sql`, post-migration)
`id`, `dive_center_id`, `date` (`not null`), `fee_type` (`text not null,
check (fee_type in ('Marine Fee','Shark Fee','Other Fee'))`), `rate`
(`numeric(12,2) not null default 0`), `divers` (`integer not null default
0`), `total` (`numeric(12,2) not null default 0`), `created_at`
(`timestamptz not null default now()` — new, DB-defaulted).

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `date` | `date` | same |
| `fee_type` | `fee_type` | **exact string match, no transform** — both sides use identical title-case values (`Marine Fee`/`Shark Fee`/`Other Fee`); new schema enforces this via a `check` constraint (not a Postgres enum type), same allowed values |
| `rate` | `rate` | same |
| `divers` | `divers` | same |
| `total` | `total` | same — note the old app computes this client-side (`rate*divers`) and the new schema does **not** auto-compute it via trigger either (still a plain stored column), so the ETL should carry the value as-is but a sanity check (`total = rate * divers`) is worth running against real data before trusting it blindly |
| — | `created_at` | new column, no old equivalent — backfill with the row's own `date` at midnight, or `now()` if timestamp precision doesn't matter for this table (Reports only ever queries by `date`, never `created_at`) |

### Structural changes
Old base schema (`fee_name`/`amount`/`is_active`) → new daily-log shape
(`date`/`fee_type`/`rate`/`divers`/`total`) is a full replacement, not an
additive change — those three original columns are dropped outright by
migration `006`. **Since the old live app never wrote to the rate-config
shape, there is nothing to map from those three dropped columns** — this
is a non-issue for the ETL specifically because the "old shape" in `001`
was itself never real production data, just a schema-design mistake that
was corrected before anything used it.

---

## 3. `join_ride_records`

### Old columns (as used by `reports.html`)
`id`, `dive_center_id`, `direction`, `date`, `company`, `number_of_divers`,
`number_of_dives`, `dive_sites`, `total_amount`, `status` (title-case
strings, see below), `balance`, `remarks`, `statement_id` (set via a
follow-up `.update()` when a statement is generated), `updated_at`.

### New columns (`001_schema_and_rls.sql`, unchanged by any later migration)
`id`, `dive_center_id`, `direction` (`public.join_ride_direction` enum),
`date` (`not null`), `company` (`not null`), `number_of_divers`,
`number_of_dives`, `dive_sites`, `total_amount`, `status` (`text not null`,
gated by a `check` constraint per-direction — see below), `balance`,
`remarks`, `statement_id` (FK → `join_ride_statements.id`), `created_at`,
`updated_at`.

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `direction` | `direction` | **exact match, no transform** — old app already writes the enum's real values (`joined_our_boat` / `we_joined_another_boat`) literally, confirmed in `renderJoinRide()`/`saveJoinRecord()` |
| `date` | `date` | same |
| `company` | `company` | same |
| `number_of_divers` | `number_of_divers` | same |
| `number_of_dives` | `number_of_dives` | same |
| `dive_sites` | `dive_sites` | same (free text) |
| `total_amount` | `total_amount` | same |
| `status` | `status` | **value transform required** — see status table below |
| `balance` | `balance` | same |
| `remarks` | `remarks` | same |
| `statement_id` | `statement_id` | same — FK, must migrate **after** `join_ride_statements` so the referenced id already exists |
| — | `created_at` | new column, no old equivalent (old app never selected/set it) — backfill from `date` or `updated_at`, whichever is closer to the real creation time; not read anywhere in Reports so precision doesn't matter |
| `updated_at` | `updated_at` | same |

### Status enum/check-constraint value transform

New schema constraint (from `001`):
```
check (
  (direction = 'joined_our_boat' and status in ('to_collect','statement_printed','collected'))
  or
  (direction = 'we_joined_another_boat' and status in ('expected_to_pay','statement_received','paid'))
)
```

| Old value | New value | Direction |
|---|---|---|
| `To Collect` | `to_collect` | `joined_our_boat` |
| `Statement Printed` | `statement_printed` | `joined_our_boat` |
| `Collected` | `collected` | `joined_our_boat` |
| `Expected To Pay` | `expected_to_pay` | `we_joined_another_boat` |
| `Statement Received` | `statement_received` | `we_joined_another_boat` |
| `Paid` | `paid` | `we_joined_another_boat` |

Not a Postgres enum type (`status` is plain `text`), but the `check`
constraint is just as strict — an ETL insert with the old title-case
string will fail the constraint outright.

### Structural changes
None beyond the status-string casing/format and the direction-gated
`check` constraint (which the old app's own UI logic already respects,
it just never lowercased/underscored the value before sending it).

---

## 4. `join_ride_statements`

### Old columns (as used by `reports.html`, `generateStatement()`)
`id` (returned via `.select().single()` after insert), `dive_center_id`,
`company`, `date_from`, `date_to`, `total_amount`, `status` (literal
`'Statement Printed'`, only ever this one value — no edit/delete path for
statements in the old app), `prepared_by` (free text, `currentUserData?.full_name`),
`printed_at`, `created_at`, `updated_at`.

### New columns (`001_schema_and_rls.sql`, unchanged since)
`id`, `dive_center_id`, `company` (`not null`), `date_from`, `date_to`,
`total_amount` (`not null default 0`), `status` (`text not null default
'statement_printed'`), `prepared_by`, `printed_at`, `created_at`,
`updated_at`.

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `company` | `company` | same |
| `date_from` | `date_from` | same |
| `date_to` | `date_to` | same |
| `total_amount` | `total_amount` | same |
| `status` | `status` | **value transform** — old app only ever writes the single literal `'Statement Printed'`; new schema's default/expected value is `'statement_printed'` (lowercase). No `check` constraint enforces this on `join_ride_statements` (unlike `join_ride_records`), so a mismatched-case value would technically insert without error — but should still be normalized for consistency with the linked `join_ride_records.status` values |
| `prepared_by` | `prepared_by` | same (free text, a user's `full_name` snapshot — not a FK) |
| `printed_at` | `printed_at` | same |
| `created_at` | `created_at` | same |
| `updated_at` | `updated_at` | same |

### Structural changes
None — direct 1:1 table, only the one status-string casing note above.

---

## 5. `rental_gear_records`

### Old columns (as used by `reports.html`)
`id`, `dive_center_id`, `date`, `equipment` (free text — old app's own
`<select>` has a suggestion list but always sends whatever string is in
the field, including a manually-typed "Other" replacement), `company`,
`quantity`, `rate`, `total_amount`, `status` (title-case strings, see
below), `balance`, `remarks`, `updated_at`.

### New columns (`001_schema_and_rls.sql`, unchanged since)
`id`, `dive_center_id`, `date` (`not null`), `equipment` (`not null`),
`company`, `quantity` (`not null default 0`), `rate` (`not null default
0`), `total_amount` (`not null default 0`), `status`
(`public.rental_gear_status` enum), `balance`, `remarks`, `updated_at`,
`created_at`.

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `date` | `date` | same |
| `equipment` | `equipment` | same — free text on both sides, no enum/lookup table involved (this is a deliberate rebuild-side UX improvement over the live app's rigid dropdown, per the project's own notes, but the underlying column stays plain text in both schemas) |
| `company` | `company` | same |
| `quantity` | `quantity` | same |
| `rate` | `rate` | same |
| `total_amount` | `total_amount` | same |
| `status` | `status` | **value transform required** — see enum table below |
| `balance` | `balance` | same |
| `remarks` | `remarks` | same |
| `updated_at` | `updated_at` | same |
| — | `created_at` | new column, no old equivalent — backfill from `date` or `updated_at` |

### Status enum value transform (`public.rental_gear_status`: `to_collect`, `collected`, `to_pay`, `paid`)

| Old value | New value |
|---|---|
| `To Collect` | `to_collect` |
| `Collected` | `collected` |
| `To Pay` | `to_pay` |
| `Paid` | `paid` |

### Structural changes
None beyond the status-string transform — `rental_gear_records` has no
direction column at all (unlike `join_ride_records`); the status value
alone tells you which "direction" a record represents, and that's true
in both old and new shapes identically.

---

## 6. `staff_commission_records`

**This is the second confirmed shape-change case**, and it's a two-step
one: migration `007` first restructures from a calendar-month bucket to
a per-line-item shape, then migration `035` adds a nullable `diver_id`
on top of that for a further per-student (not just per-course-group)
refinement. **Both migrations note explicitly that no real data existed
in this table at the time they ran** — but that's a rebuild-database fact,
not an old-live-app fact. The actual OLD APP data (real historical
commission records) is in the calendar-month-bucket shape below, and
does need real field-level mapping into the new per-line-item shape.

### Old columns (as used by `reports.html`, `saveEducatorRow()`/`saveLeaderRow()`)
`id`, `dive_center_id`, `date` (the specific activity date), `period_month`
(derived client-side as `date.slice(0,7)`, i.e. `YYYY-MM` — a redundant
denormalization of `date`, not independent data), `staff_name`,
`commission_group` (`'dive_educator'` or `'dive_leader'`), `title` (the
course/activity name), `diver_name` (free text, **educator rows only** —
leader rows always send `diver_name: null`), `quantity` (educator rows:
always `1`; leader rows: `numberOfDives` from the session-derived data),
`rate` (the typed "commission" amount — despite the name, this is a flat
typed number, not a per-unit rate multiplied by anything), `additional_rate`
(a second typed flat amount), `commission_amount` (**always equals `rate`**
— old app sets `commission_amount:commission` where `commission` is the
same value written to `rate`; a pure duplicate field, not independent
data), `total_amount` (`= rate + additional_rate`, i.e. `commission_amount
+ additional_rate`), `status` (`'Paid'` / `'Unpaid'`, title case),
`paid_at`, `remarks`, `updated_at`.

### New columns (`007_staff_commission_rates.sql` + `035_staff_commission_diver.sql`)
`id`, `dive_center_id`, ~~`period_month`~~ **dropped by 007**,
`activity_date` (`date not null` — added by 007, replaces `period_month`
as the real per-row date key), `staff_name`, `commission_group`
(`public.commission_group` enum), `title`, `diver_id` (nullable, FK →
`divers.id`, added by 035 — "unused by `dive_leader`-group rows"),
`quantity`, `rate`, `commission_amount`, `status`
(`public.commission_status` enum), `paid_at`, `remarks`, `updated_at`,
`created_at`, plus two columns added by 007 that have **no old-schema
column at all**: `divers` (`integer not null default 0`) and
`bonus_amount` (`numeric(12,2) not null default 0`).

**Important**: the base `001_schema_and_rls.sql` table definition does
**not** have `diver_name` at all (only `title`, `quantity`, `rate`,
`commission_amount`, `status`, `paid_at`, `remarks`) — `diver_name` was
never a real column in any version of the new schema; the closest new
equivalent is the `diver_id` FK added by migration `035`, which is a
structural change (a resolved reference, not free text), not a rename.

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `date` | `activity_date` | rename — this is the real per-row date, now the actual date-range filter key (`reports/data.ts` queries by `activity_date` range) instead of the old month-bucket |
| `period_month` | **dropped, no new equivalent** | was purely derived (`date.slice(0,7)`) in the old app anyway — not independent data, safe to drop with zero information loss since `activity_date` (mapped from `date` above) already carries everything `period_month` ever encoded |
| `staff_name` | `staff_name` | same (free text, not a FK to `staff` in either schema) |
| `commission_group` | `commission_group` | **exact match, no transform** — old app already writes `'dive_educator'`/`'dive_leader'` literally, matching the enum values |
| `title` | `title` | same |
| `diver_name` | `diver_id` | **requires a lookup, not a direct copy** — old `diver_name` is free text (e.g. `"Maria Santos"`); new `diver_id` is a FK to `divers.id`. ETL must resolve each educator-group row's `diver_name` against the migrated `divers` table (by full-name match against the same dive center) and write the matched `id`; if no confident match is found, leave `diver_id` null rather than guessing — this is a real, non-trivial reconciliation step, not a mechanical rename. `dive_leader` rows had `diver_name: null` in the old app already, so those map to `diver_id: null` trivially |
| `quantity` | `quantity` | same |
| `rate` | `rate` | same |
| `additional_rate` | **dropped, no direct new column** | see "Structural changes" below — this value should be folded into `bonus_amount` (a new column with no old equivalent, not a coincidentally-matching name) rather than lost, since both represent "a second flat amount added on top of the base commission" |
| `commission_amount` | `commission_amount` | same — note this was always a duplicate of `rate` in the old app (`commission_amount:commission` where `commission` is the same value as `rate`), so this mapping is safe/lossless either way |
| `total_amount` | **dropped, no new column at all — not even `commission_amount`** | new schema has no `total_amount` column in `staff_commission_records`; the rebuild recomputes total as `rate + bonus_amount` (or equivalent) at read time rather than storing it. Old `total_amount` (`= rate + additional_rate`) is derivable from the mapped `rate`/`bonus_amount` (formerly `additional_rate`) and does not need its own destination column — **do not attempt to insert into a `total_amount` column, it does not exist post-migration** |
| `status` | `status` | **value transform** — old `'Paid'`/`'Unpaid'` (title case) → new enum `'paid'`/`'unpaid'` (lowercase) |
| `paid_at` | `paid_at` | same |
| `remarks` | `remarks` | same |
| `updated_at` | `updated_at` | same |
| — | `divers` (new, added by 007) | **no old equivalent for educator-group rows** (old app's `quantity` was always `1` per student there) — for `dive_leader`-group rows, the old app's `numberOfDives`-derived `quantity` is the closest analog of "how many dive-units this row represents," but the new `divers` column specifically means *diver count*, a different axis than `quantity`/dive-count. Recommend backfilling `divers` from whatever historical diver-count context is available per row (e.g. cross-referencing `activities`/`schedule_divers` for that `staff_name`+`activity_date`+`title` combination), defaulting to `0` if unrecoverable — flag this as a genuine judgment call for whoever builds the ETL script, not a mechanical mapping |
| — | `bonus_amount` (new, added by 007) | maps from old `additional_rate` (see above) — recommended, not purely mechanical, since the two aren't formally the same concept (`bonus_amount` is described in 007's migration comment as tied to the new "ratio bonus" feature, which has zero live-app precedent), but numerically and functionally they're both "a second flat amount on top of the base rate," so carrying the value forward is the safest lossless choice |
| — | `diver_id` (new, added by 035) | see `diver_name` mapping above |

### Structural changes (the two-step restructuring, in full)

1. **Migration 007**: `period_month` (a derived `YYYY-MM` string, calendar-
   month bucketing) is dropped entirely; `activity_date` (a real `date`)
   becomes the new per-row date key. This is the headline change — Reports'
   "mark a date range as paid" feature only works correctly once each row
   has its own real date instead of being bucketed to a shared month, which
   is exactly why this migration exists (see the migration's own comment
   and this project's session history — a previous "whole calendar month"
   version of Staff Activity Summary was fully superseded by this one in
   the same project). `total_amount` is dropped with no replacement column
   (computed at read time from `rate + bonus_amount` instead). `divers` and
   `bonus_amount` are added with no old-schema source column — `bonus_amount`
   has a reasonable source (old `additional_rate`, see mapping above);
   `divers` genuinely has no clean old-schema source and needs a judgment
   call per the note above.
2. **Migration 035**: adds `diver_id` (FK → `divers.id`), moving
   `dive_educator`-group rows from "one row per (staff, date, course)" to
   "one row per (staff, date, course, student)" — matching the old app's
   own already-per-student granularity (`educatorKey` already includes
   `diverName` in its uniqueness key), just replacing the free-text
   `diver_name` with a resolved FK. `dive_leader`-group rows are unaffected
   (`diver_id` stays null for them, matching old `diver_name: null`).

**Net effect for the ETL**: one old `staff_commission_records` row maps to
exactly one new row (no fan-out/fan-in), but four of its old columns
(`period_month`, `additional_rate`, `commission_amount`'s redundancy, and
implicitly `total_amount`) don't carry forward 1:1, and two new columns
(`divers`, `diver_id`) need real reconciliation logic, not a bulk column
rename.

---

## 7. `audit_logs` (bill-unlock entries only, per scope)

### Old usage (`reports.html`, Billing Audit tab — **read-only**)
`reports.html` never inserts into `audit_logs` — it only reads:
```
client.from('audit_logs')
  .select('id,performed_by,target_id,notes,created_at')
  .eq('dive_center_id', diveCenterId)
  .eq('action', 'bill_unlocked')
  .order('created_at', {ascending:false})
```
(plus a follow-up `users` lookup to resolve `performed_by` → `full_name`
for display, purely a join-via-`Map` pattern, not a schema concern).

### New columns (`001_schema_and_rls.sql`, unchanged by any later migration)
`id`, `dive_center_id` (nullable, **no FK** — deliberate, "an audit trail
must survive deletion of the tenant or user it's recording"), `action`
(`text not null`), `target_type` (`text not null`), `target_id` (nullable,
polymorphic — no FK), `performed_by` (nullable, **no FK** to `users`, same
survive-deletion reasoning), `notes`, `created_at`.

### Field mapping

| Old field (read) | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `performed_by` | `performed_by` | same — **no FK on either side is enforced at the DB level, but semantically still a `users.id` value**; when migrating, remap through whatever `auth.users`/`public.users` id-mapping the auth migration produces, same as `expenses.created_by` |
| `target_id` | `target_id` | same — for bill-unlock rows this is a `visits.id` (per `log_bill_unlock`'s `target_type = 'visits'`); remap through the migrated `visits` table's new ids |
| `notes` | `notes` | same |
| `created_at` | `created_at` | same |
| (not selected by Reports, but exists) | `action` | must be the literal string `'bill_unlocked'` for these rows to surface in Billing Audit at all — verify old data actually used this exact string (the new schema's `log_bill_unlock` RPC hardcodes it; confirm the *old* app's own bill-unlock code path, likely in `diver-form.html` not `reports.html`, used the same literal before assuming a 1:1 value match) |
| (not selected by Reports, but exists) | `target_type` | new `log_bill_unlock` RPC hardcodes `'visits'` — check old data for the equivalent value before assuming it matches |
| (not selected by Reports) | `dive_center_id` | needed for the `.eq('dive_center_id', diveCenterId)` filter Reports relies on — must be populated even though old `reports.html` never explicitly selects it back out |

### Structural changes
None in the table shape itself — this is a straightforward 1:1 table for
the columns Reports actually touches. The only real migration risk is
**id remapping** (`performed_by`/`target_id`/`dive_center_id` all need to
point at the *new* schema's regenerated UUIDs for `users`/`visits`/
`dive_centers`, not the old ones) since none of these columns carry a DB
FK to enforce referential integrity automatically — a bad remap would
insert silently, not error.

**Not in scope for this table** (per the task's own framing, and
confirmed by grep): the write side (`log_bill_unlock` RPC) belongs to
Diver Detail, not Reports — `reports.html`'s Billing Audit tab is
read-only for this table.

---

## 8. Cross-check only: `payments` / `deposits` (read-side, Settlement tab)

Per the task's scope, these two tables are primarily owned by the
diver-facing pages (another agent's mapping) — this is only a note on how
`reports.html`'s Settlement tab **reads** them, for cross-reference.

### `payments` (Settlement tab select)
```
select id,created_at,paid_at,diver_id,visit_id,cash_amount,
  cash_amount_foreign,cash_currency_code,cash_exchange_rate,card_amount,
  card_surcharge_amount,online_amount,online_surcharge_amount,total_collected
.eq('dive_center_id', diveCenterId)
.gte('paid_at', dayStart).lte('paid_at', dayEnd)
```
Every one of these column names is confirmed present, unchanged, in
`001_schema_and_rls.sql`'s `payments` table (no later migration alters
any column Reports reads). New-schema-only additions Reports does **not**
read: `total_paid`, `balance`, `discount`, `grand_total_php`,
`card_surcharge_rate`, `online_surcharge_rate`, `total_surcharge`,
`is_paid`, and `excess_amount` (added by migration `034` — "tendered-but-
unbilled amount," e.g. foreign-cash overshoot; genuinely new concept, no
old-schema equivalent, not read by Reports today but worth flagging for
whoever owns the `payments` mapping since it needs a `0` default on
migrated historical rows, not a derived value).

### `deposits` (Settlement tab select)
```
select id,deposit_date,diver_id,amount,method,received_by
.eq('dive_center_id', diveCenterId)
.eq('deposit_date', dateVal)
```
All five selected columns (plus the two filter columns) are present
unchanged in `001_schema_and_rls.sql`'s `deposits` table. New-schema-only
additions Reports does not read: `visit_id`, `recorded_by_user_id`,
`created_at`.

### Other adjacent tables Reports reads only for display (not in the
7-table scope, noted for completeness per the task's "any other table"
instruction)
- `users` (`id, full_name`) — resolves `performed_by`/`sent_by` to a
  display name across Billing Audit and Settlement. Unchanged shape.
- `divers` (`id, first_name, last_name`) — resolves diver names for
  Settlement rows. Unchanged shape.
- `visits` (`id, diver_id, invoice_count`, filtered `gt('invoice_count',0)`)
  — Billing Audit's flagged-bill detection. Unchanged shape.
- `invoice_emails` (`id, visit_id, diver_id, sent_at, sent_by,
  invoice_snapshot`) — Billing Audit's invoice history, and Settlement's
  "Closed By" resolution (`visit_id, sent_by` only). Unchanged base shape;
  note migration `008` (`diver_profile_fields.sql`, outside this table's
  original scope but touches `invoice_emails`) adds `email_sent_at`/
  `email_sent_by`/`email_delivery_status` — none of these are read by
  `reports.html` today, but flag for the ETL since they're new columns
  with no old-schema source.
- `dive_centers` (whole-row via `users` join at page load, `staff` join
  for staff names, `course_rates` for course-rate ids/names, `schedules`,
  `activities`, `groups`) — all loaded once in `loadAll()`'s parallel
  fetch for cross-referencing Overview's charts; none of these are
  Reports-owned tables and are out of scope for this mapping.
# AquaDesk — OLD → NEW schema field mapping: Settings / Config / Admin data

Scope: dive-center settings/config/admin tables only (pricing config, waiver,
equipment/inventory config, fleet, dive sites, access/passwords, profile,
platform admin, auth). Diver-facing and scheduling-operational tables are
intentionally out of scope except where a settings table feeds them.

Sources read: `settings.html` (primary), `office.html`, `login.html`,
`change-password.html`, `reset-password.html`, `dashboard.html`,
`boat-manifest.html`, `register.html`, `scheduling.html` (cross-check only),
`supabase/functions/login-guard/index.ts` (real Edge Function source found on
disk). New schema: `database/001_schema_and_rls.sql` + every later migration
grepped for `alter table`/`create table` touching these tables (004, 005, 006,
007, 010, 012, 014, 025 are the ones that actually touch tables in scope;
013/015/016/017/018/019/020/021/022/023/024/026-035 were checked and do **not**
touch any table in this scope — they're diver/scheduling-only).

---

## 1. `dive_centers`

### Old (as used by settings.html / office.html / login.html)

Read via `client.from('dive_centers').select('*')` and individual
`.update({...})` payloads. Fields actually read/written:

`id, name, email, phone, address, logo_url, subscription_status,
offers_dive_insurance, insurance_referral_link, pricing_mode,
waiver_content, waiver_updated_at, waiver_content_updated_by,
billing_password, owner_password, staff_token, staff_token_date,
fuel_current_level, fuel_low_threshold, fuel_gasoline_level,
fuel_gasoline_threshold, fuel_gasoline_last_reset_at, fuel_diesel_level,
fuel_diesel_threshold, fuel_diesel_last_reset_at, created_at,
billing_due_date, billing_amount, last_payment_date` (last three read/written
only by `office.html`'s Edge Function, observed via office.html's client-side
cache object comment, not a direct `.from()` call — the office console talks
to an `admin-console` Edge Function whose source isn't on disk, only its
observable field names via `office.html`'s own JS).

### New (`001_schema_and_rls.sql` + migration 007)

```
id, name, email, phone, address, logo_url, waiver_content, waiver_updated_at,
waiver_content_updated_by, offers_dive_insurance, insurance_referral_link,
pricing_mode, subscription_status, billing_due_date, billing_amount,
last_payment_date, billing_unlock_hash, owner_unlock_hash, staff_token,
staff_token_date, fuel_current_level, fuel_low_threshold,
fuel_gasoline_level, fuel_gasoline_threshold, fuel_gasoline_last_reset_at,
fuel_diesel_level, fuel_diesel_threshold, fuel_diesel_last_reset_at,
created_at,
-- migration 007 additions:
divemaster_rate_per_dive, ratio_bonus_enabled, ratio_bonus_extra_rate,
join_ride_rate_per_diver_per_dive
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `name` | `name` | same |
| `email` | `email` | same |
| `phone` | `phone` | same |
| `address` | `address` | same |
| `logo_url` | `logo_url` | same, but see Storage note below |
| `subscription_status` | `subscription_status` | same values (`trial`/`active`/`suspended`/`cancelled` — new is a real enum, old was presumably free text; confirm actual old values are exactly these 4 lowercase strings before trusting a direct copy) |
| `offers_dive_insurance` | `offers_dive_insurance` | same |
| `insurance_referral_link` | `insurance_referral_link` | same |
| `pricing_mode` | `pricing_mode` | same (`'package'`/`'tier'`, normalized client-side by `normalizePricingMode()` in the old app — migrate the **normalized** value, not necessarily the raw stored string, in case any old row has a variant spelling like `"Tier Based"`) |
| `waiver_content` | `waiver_content` | same, but re-sanitize on migration (see Structural changes) |
| `waiver_updated_at` | `waiver_updated_at` | same |
| `waiver_content_updated_by` | `waiver_content_updated_by` | FK to `users.id` — must be remapped through the `users` migration (old id → new id), not copied verbatim unless old `auth.users`/`public.users` ids are being preserved 1:1 |
| `staff_token` / `staff_token_date` | `staff_token` / `staff_token_date` | same — but these are daily-rotating and not "config"; not worth migrating, let it regenerate fresh (also true of `fuel_*_last_reset_at`, low-value to migrate) |
| `fuel_current_level` / `fuel_low_threshold` | same columns | **exist in both but are unused by any UI in either app** (only `fuel_gasoline_*`/`fuel_diesel_*` are actually read/written by `settings.html`'s `loadFuelSettings`/`saveFuel`) — confirm before assuming these are live data; likely dead in both schemas |
| `fuel_gasoline_level`/`_threshold`/`_last_reset_at` | same | same, direct copy |
| `fuel_diesel_level`/`_threshold`/`_last_reset_at` | same | same, direct copy |
| **`billing_password`** (plaintext, compared with `===` in `updateBillingPassword()`) | **`billing_unlock_hash`** (bcrypt, via `set_billing_unlock` RPC) | **Structural change — see Auth section.** Do NOT copy the plaintext value into the hash column directly; must be re-hashed via `crypt(old_plaintext, gen_salt('bf'))` in a migration script, or (safer) force every dive center to re-set both unlock secrets post-migration. |
| **`owner_password`** (plaintext) | **`owner_unlock_hash`** (bcrypt, via `set_owner_unlock` RPC) | same treatment as above |
| — (no old equivalent found in settings.html) | `divemaster_rate_per_dive`, `ratio_bonus_enabled`, `ratio_bonus_extra_rate`, `join_ride_rate_per_diver_per_dive` | **New-only fields, no old data to migrate.** Confirmed via this project's own prior grep of all old HTML files — zero live-app precedent. Backfill with schema defaults (`0`, `false`, `0`, `0`) for every migrated dive center; owner configures post-migration. |
| — | `created_at` | old app doesn't appear to display `dive_centers.created_at` in settings.html but `office.html` reads it for the "created this month" stat — direct copy if available in old DB, else use migration-run timestamp |

**Office-console-only fields** (`billing_due_date`, `billing_amount`,
`last_payment_date`) — same names in both, direct copy, but only ever
observed via `office.html`'s client cache comment, not a raw `.from()` call
(they're set via a service-role Edge Function). Treat as low-confidence on
exact old semantics; verify against the live production DB's actual column
values, not just office.html's JS comment, before trusting the mapping.

### Structural changes

- **Billing/owner password mechanism is fundamentally different** (plaintext
  column vs. bcrypt hash + RPC gate). This is the single highest-risk item in
  this whole mapping — see the dedicated Auth section below for the
  recommended approach.
- **Waiver content needs re-sanitization, not a raw copy.** The old app's
  save-time sanitizer (`DOMPurify.sanitize` with the 9-tag/0-attr allow-list)
  runs client-side only — if any old `waiver_content` value predates that
  gate, contains a since-loosened allow-list edit, or was ever written by a
  buggy older version of `settings.html`, a raw copy risks carrying over
  unsanitized HTML into a schema whose only defense is the SAME allow-list
  (now enforced twice: client `sanitizeWaiverHtml.ts` and server
  `sanitizeWaiverHtmlServer.ts`, per this project's own Cloudflare-session
  fix). **Run every migrated `waiver_content` value through the new app's own
  `sanitize-html`-based sanitizer during ETL**, don't trust it byte-for-byte.
- **`dive-center-assets` Storage bucket (migration 012) needs the actual logo
  image files migrated separately from the DB row** — `logo_url` is just a
  public URL string; if it points at the *live* Supabase project's storage
  host, it will 404 once the dive center is live on the new project. Either
  re-upload every dive center's logo file into the new project's
  `dive-center-assets` bucket at the new path convention
  (`logos/{new_dive_center_id}.{ext}`) and rewrite `logo_url`, or leave it
  null and let each owner re-upload post-migration (this project's Storage
  gotchas — bucket SELECT policy, upsert needing all 3 policies — are already
  solved by migration 012's own policies, no new risk there).

### Type/constraint differences

- `subscription_status`: new is a real Postgres enum
  (`'trial'|'active'|'suspended'|'cancelled'`) — verify every distinct old
  value maps cleanly; anything else needs a decision (default to `'active'`
  for anything ambiguous, matching "currently paying" as the safest guess).
- `pricing_mode`: new enum `'tier'|'package'` — old app's own
  `normalizePricingMode()` already handles several old spelling variants
  (`"package based"`, `"tier rate based"`, etc.), confirming the **old** data
  itself is inconsistent free text. Run every old value through equivalent
  normalization logic before insert, don't trust raw equality.

---

## 2. `users` (public.users — app-level profile, not `auth.users`)

### Old (settings.html Access tab, office.html, login.html, change-password.html)

`id, dive_center_id, full_name, email, role, is_active, can_view_revenue,
password_changed, is_platform_admin, failed_login_attempts, locked_until,
created_at`

### New (`001_schema_and_rls.sql` + migration 014)

```
id, dive_center_id, full_name, email, role, can_view_revenue, is_active,
password_changed, created_at,
-- migration 014:
failed_login_attempts, locked_until
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | FK to `auth.users(id)` in both — see Auth section, this is the pivot for the whole account-migration plan |
| `dive_center_id` | `dive_center_id` | same, remap via the `dive_centers` id migration |
| `full_name` | `full_name` | same |
| `email` | `email` | same |
| `role` | `role` | same enum values `'owner'`/`'secretary'` — confirmed identical in both (`role:'secretary'` literal in `settings.html`'s `createSecretaryAccount`) |
| `is_active` | `is_active` | same |
| `can_view_revenue` | `can_view_revenue` | same |
| `password_changed` | `password_changed` | same, confirmed identical semantics in `login.html`/`change-password.html` — force-password-change-on-first-login gate |
| `failed_login_attempts` | `failed_login_attempts` | same — confirmed via `login-guard/index.ts` source, this column already existed in the OLD schema too, not a new-only field |
| `locked_until` | `locked_until` | same, same reasoning |
| **`is_platform_admin`** (boolean column directly on `users`) | **no equivalent column — replaced by a separate `public.platform_admins` table** | **Structural change, see below.** |

### Structural changes

- **Platform admin is modeled completely differently.** Old: a
  `users.is_platform_admin boolean` flag on the same row as a normal
  dive-center user (confirmed via `office.html`'s
  `.select('id, full_name, email, is_platform_admin')` — this implies old
  platform-admin accounts *also* have a `dive_center_id`, i.e. every platform
  admin is nominally "attached" to some dive center row, even though that's
  semantically odd). New: a dedicated `public.platform_admins` table
  (`id, user_id → auth.users(id), full_name, email, is_active, created_at`)
  with **no `dive_center_id` at all** — a platform admin in the new schema is
  NOT required to have a `public.users` row or any dive-center affiliation.
  **Migration approach**: for every old `users` row with
  `is_platform_admin = true`, insert one `public.platform_admins` row
  (`user_id` = the same `auth.users` id, `full_name`/`email` copied) — do
  **not** also try to force-fit that account into a `public.users` row in the
  new schema unless it's also a real dive-center owner/secretary in its own
  right (CLAUDE.md's own note confirms the new schema's platform admin,
  `aquadeskonline@gmail.com`, is "a `platform_admins` row + matching
  `auth.users` row, not a `public.users` row" — this is the intended new
  shape).

### Auth migration considerations (see dedicated section below for full detail)

---

## 3. `staff` (roster — Settings > Staff tab)

### Old (settings.html)

`id, dive_center_id, first_name, last_name, email, phone, whatsapp, role`
(free text: `'Secretary'|'Divemaster'|'Instructor'|'Crew'`), `access_level`
(free text, computed from `role` via a client-side map:
`'secretary'|'divemaster'|'instructor'|'crew'`), `employment_status` (free
text: `'Full Time'|'Part Time'|'Freelance'`), `date_hired`, `daily_rate`,
`nitrox_certified`, `is_active`, **`auth_user_id`** (FK-like column, no
enforced FK visible from client code, references the linked login account).

### New (`001_schema_and_rls.sql` + migration 010)

```
id, dive_center_id, user_id (→ public.users.id, unique, nullable),
first_name, last_name, email, phone, whatsapp,
position (enum: secretary|divemaster|instructor|crew),
employment_status (enum: full_time|part_time|freelance),
date_hired, daily_rate, nitrox_certified, is_active, created_at,
-- migration 010:
emergency_contact_name, emergency_contact_phone,
emergency_contact_relationship, emergency_contact_whatsapp,
emergency_contact_email
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `first_name` | `first_name` | same |
| `last_name` | `last_name` | same |
| `email` | `email` | same |
| `phone` | `phone` | same |
| `whatsapp` | `whatsapp` | same |
| **`role`** (free text, Capitalized: `Secretary`/`Divemaster`/`Instructor`/`Crew`) | **`position`** (enum, lowercase: `secretary`/`divemaster`/`instructor`/`crew`) | **Renamed AND re-typed.** Direct value mapping is `lower(old.role)` for all 4 values — confirmed 1:1, no fifth value observed anywhere. |
| `access_level` (free text, `accessMap[position]` — always redundant with `role` in practice, see below) | *(dropped — no equivalent column)* | **Dead/redundant field, don't migrate.** Old app computes `access_level` purely as a derived lowercase of `role` at save time (`accessMap = {Secretary:'secretary', Divemaster:'divemaster', ...}`) — it never diverges from `role` in any code path found. Confirm via a real DB query that no old row actually has `access_level !== lower(role)` before treating this as safe to drop; if any do diverge, that's a real signal worth investigating before discarding. |
| **`employment_status`** (free text, `Full Time`/`Part Time`/`Freelance`) | **`employment_status`** (enum, `full_time`/`part_time`/`freelance`) | Value mapping: `"Full Time"→"full_time"`, `"Part Time"→"part_time"`, `"Freelance"→"freelance"` (lowercase + underscore) |
| `date_hired` | `date_hired` | same |
| `daily_rate` | `daily_rate` | same |
| `nitrox_certified` | `nitrox_certified` | same |
| `is_active` | `is_active` | same |
| **`auth_user_id`** | **`user_id`** | **Renamed**, and semantically re-scoped: old points at `auth.users.id` directly (login account); new documentation (`010_staff_roster_fields.sql`) says it points at `public.users.id` (which itself equals `auth.users.id` by design in this schema, so the actual UUID value should carry over unchanged once remapped through the auth-migration id mapping) — verify the FK really is `staff.user_id → public.users.id` not `auth.users.id` directly (confirmed in schema: `user_id uuid unique references public.users(id)`) |
| — (no old equivalent — settings.html has no emergency-contact UI for staff) | `emergency_contact_name/_phone/_relationship/_whatsapp/_email` | **New-only fields, no old data.** Backfill null; owner fills in post-migration. |
| — | `created_at` | old app doesn't display it in settings.html; direct copy if present in old DB, else migration-run timestamp |

### Structural changes

- **`user_id` is `unique`** in the new schema (one staff row per login
  account max) — old `auth_user_id` had no client-visible uniqueness
  constraint. Check the old DB for any staff row sharing an `auth_user_id`
  with another (shouldn't happen given the app's own "already has a login,
  no duplicate" checks, but verify before the migration insert hits a
  constraint violation).
- New schema also has `staff_certifications` (migration 010, one-to-many,
  `cert_name`/`expiry_date`) — **confirmed no old-app equivalent anywhere**
  (this project's own build notes call this out as a rebuild-only addition
  beyond the original schema). Nothing to migrate into it; it starts empty.

---

## 4. `boats` (Settings > Fleet tab)

### Old (settings.html)

`id, dive_center_id, name, boat_type` (free text, exact option strings:
`Outrigger`/`Flat Boat`/`Chase Boat`/`Speed Boat`), `fuel_type` (free text:
`Gasoline`/`Diesel`), `captain`, `capacity`, `is_active`.

### New (`001_schema_and_rls.sql` + migration 005)

```
id, dive_center_id, name, captain,
boat_type (enum: outrigger|flat_boat|chase_boat|speed_boat),
fuel_type (enum: gasoline|diesel),
is_active, created_at,
-- migration 005:
capacity
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `name` | `name` | same |
| `captain` | `captain` | same (this is the boat's Fleet-configured captain — a separate concept from `schedules.captain`, the per-trip captain added later in migration 018; not in scope here, just noting so the ETL script doesn't conflate the two) |
| **`boat_type`** (free text, e.g. `"Outrigger"`, `"Flat Boat"`) | **`boat_type`** (enum) | Value mapping: `"Outrigger"→"outrigger"`, `"Flat Boat"→"flat_boat"`, `"Chase Boat"→"chase_boat"`, `"Speed Boat"→"speed_boat"` (lowercase, spaces→underscores). Confirmed via the exact 4 `<option>` strings in `settings.html`'s `#boatType` select — no other values possible from that UI, but check the old DB for any row bypassing the dropdown (e.g. old direct-SQL seed) before assuming clean data. |
| **`fuel_type`** (free text, `"Gasoline"`/`"Diesel"`) | **`fuel_type`** (enum) | Value mapping: `"Gasoline"→"gasoline"`, `"Diesel"→"diesel"` — confirmed independently via `scheduling.html`'s own `.toLowerCase()` call on this exact field before comparing to `'gasoline'`/`'diesel'`, proving the real stored value in production is the capitalized display string, not already-lowercase. |
| `capacity` | `capacity` | same — column added to the NEW schema only via migration 005 (this project's own history: it "didn't exist at all" in the base schema, is a genuine old-app field the first schema pass missed) |
| `is_active` | `is_active` | same |
| — | `created_at` | direct copy if present, else migration timestamp |

### Structural changes

None beyond the enum conversions above — 1:1 table otherwise.

---

## 5. `dive_sites` (Settings > Dive Sites tab)

### Old (settings.html)

`id, dive_center_id, site_name, distance` (free text, e.g. `"30 mins"`),
`fuel_estimate` (free text select: `Low`/`Medium`/`High`), `shark_fee`
(boolean toggle), `linked_package_id` (FK to `packages.id`, nullable),
`is_active`.

### New (`001_schema_and_rls.sql` + migration 005)

```
id, dive_center_id, site_name, is_active,
-- migration 005 (replaced the base schema's wrong shape):
distance (text), fuel_estimate (text, check in 'Low'/'Medium'/'High'),
shark_fee (boolean), linked_package_id (uuid → packages.id)
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `site_name` | `site_name` | same |
| `distance` | `distance` | same, free text, direct copy |
| `fuel_estimate` | `fuel_estimate` | same 3-value check constraint (`Low`/`Medium`/`High`, **title case in both** — confirmed via `settings.html`'s own select default `'High'` and the new schema's `check (fuel_estimate in ('Low','Medium','High'))`) — direct copy, no case transform needed here (unlike `boat_type`/`fuel_type` on `boats`, which DO need a case transform) |
| `shark_fee` | `shark_fee` | same boolean, direct copy — **note this is a Yes/No toggle, NOT a peso amount**, despite the misleading name (this project's own migration-005 comment explicitly documents this distinction; the actual shark-fee charge amount lives in `other_charges`) |
| `linked_package_id` | `linked_package_id` | same, FK — remap through the `packages` id migration |
| `is_active` | `is_active` | same |
| — | `created_at` | **new schema has NO `created_at` on `dive_sites`** (confirmed absent from both the base `create table` and migration 005 — this table genuinely has no timestamp column in either schema) — nothing to map |

### Structural changes

None — this table's real shape was already fixed to match the live app
exactly by migration 005 (this project's own history explicitly documents
this was a wrong-first-guess-then-fixed table, now correct). Confirmed 1:1
with old app's real usage.

---

## 6. `course_rates` (Settings > Courses tab)

### Old (settings.html)

`id, dive_center_id, course_name, price, is_active`.

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, course_name, rate, is_active, created_at
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `course_name` | `course_name` | same |
| **`price`** | **`rate`** | **Renamed** — old app's own payload literally uses `price:c.price` on write; new schema column is `rate numeric(12,2)`. Straight value copy, just a column-name rename. |
| `is_active` | `is_active` | same |
| — | `created_at` | direct copy if present, else migration timestamp |

### Structural changes

None beyond the `price`→`rate` rename.

---

## 7. `rate_tiers` (Settings > Pricing & Rates > Tiered Rates)

### Old (settings.html)

`id, dive_center_id, tier_from, tier_to, base_rate, rate_type` (free text,
one of `base_dive`/`nitrox`/`tank_15l`).

### New (`001_schema_and_rls.sql` + migration 004)

```
id, dive_center_id, base_rate, is_active, created_at,
-- migration 004 (replaced the base schema's wrong shape):
tier_from (int), tier_to (int, nullable), rate_type (text, check in
'base_dive'/'nitrox'/'tank_15l')
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `tier_from` | `tier_from` | same |
| `tier_to` | `tier_to` | same, nullable (open-ended top tier) |
| `base_rate` | `base_rate` | same |
| `rate_type` | `rate_type` | same 3-value set, exact string match confirmed (`'base_dive'`/`'nitrox'`/`'tank_15l'`) |
| — | `is_active` | **new-only column, no old equivalent visible in settings.html's tier CRUD** (the old app's tier rows have no active/inactive toggle in the UI — every row is implicitly active) — backfill `true` for every migrated row |
| — | `created_at` | direct copy if present, else migration timestamp |

### Structural changes

None beyond the already-completed migration-004 shape fix — this table
matches the live app exactly now (confirmed field-for-field against
`settings.html`'s real `saveTiers()`/`renderTierTable()`).

---

## 8. `packages` (Settings > Pricing & Rates > Packages)

### Old (settings.html)

`id, dive_center_id, package_name, dive_site` (free text, comma-joined,
repeatable site-name list — e.g. `"Kimud, Kimud, Monad"`), `price`,
`equipment_included` (boolean), `is_active`.

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, package_name, dive_site, price, equipment_included,
is_active, created_at
```

### Field mapping

1:1, no renames.

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `package_name` | `package_name` | same |
| `dive_site` | `dive_site` | same — **free text, comma-joined, order-and-repeat-sensitive** (confirmed critical to pricing correctness per this project's own migration-019 incident: a package covering the same site twice is a real, intentional shape, not a data-quality issue — do not dedupe or normalize this field during ETL) |
| `price` | `price` | same (note: NOT renamed to `rate` here, unlike `course_rates` — confirm this per-table inconsistency is intentional in the new schema, not an oversight, before "fixing" it during migration) |
| `equipment_included` | `equipment_included` | same |
| `is_active` | `is_active` | same |
| — | `created_at` | direct copy if present, else migration timestamp |

### Structural changes

None — direct 1:1 copy.

---

## 9. `other_charges` (Settings > Pricing & Rates > Other Charges)

### Old (settings.html)

`id, dive_center_id, charge_name, amount, charge_type` (`per_dive`/`per_day`,
derived client-side from a toggle button's text), `sub_type` (free text,
only populated for the two fuel-charge rows: `medium`/`high`), `is_active`.

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, charge_name, amount, charge_type (enum: per_dive|per_day),
sub_type (text, nullable), is_active, created_at
```

### Field mapping

1:1, no renames — direct copy of every field.

| Old field | New field | Notes |
|---|---|---|
| `charge_name` | `charge_name` | same — for default charges, exact strings `Marine Tax`/`Shark Fee`/`Fuel Charge — Medium`/`Fuel Charge — High`/`Dive Computer`/`Torch` (confirmed via `DEFAULT_CHARGES` in settings.html) — **these exact strings are read by name elsewhere** (Diver Detail's pricing engine per CLAUDE.md's own notes: "matched against `other_charges` (`Marine Tax`/`Shark Fee`/`Fuel Charge — Medium`/`Fuel Charge — High`...)") — do not alter capitalization/em-dash during migration, downstream pricing logic string-matches on these exactly. |
| `charge_type` | `charge_type` | enum, same 2 values |
| `sub_type` | `sub_type` | same — only `'medium'`/`'high'` (fuel rows) observed, else null |
| `amount`, `is_active` | same | direct copy |
| — | `created_at` | direct copy if present, else migration timestamp |

### Structural changes

None.

---

## 10. `equipment_rental_rates` (Settings > Equipment Rental tab)

### Old (settings.html)

`id, dive_center_id, item_name, rate, charge_type` (`per_dive`/`per_day`),
`is_active`.

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, item_name, rate, charge_type (enum), is_active,
created_at
```

### Field mapping

1:1 — this is the table this project's own history already flagged as
correctly named `item_name` (not the initially-guessed `equipment_name`),
confirmed matching the live app.

| Old field | New field | Notes |
|---|---|---|
| `item_name` | `item_name` | same — default items `BCD`/`Wetsuit`/`Fins`/`Mask`/`Boots`/`Regulator`/`Weights`/`Full Set`/`Torch`/`Snorkel`/`Dive Computer` plus any custom names — preserve exact strings, some downstream matching may exist |
| `rate`, `charge_type`, `is_active` | same | direct copy |
| — | `created_at` | direct copy if present, else migration timestamp |

### Structural changes

None.

---

## 11. `payment_surcharges` (Settings > Exchange Rates tab, "Payment Surcharges" section)

### Old (settings.html)

`id, dive_center_id, surcharge_type` (free text, matched loosely via
`.includes('card')`/`.includes('credit')`/`.includes('online')` rather than
exact equality — confirms the OLD values are not tightly constrained),
**`percentage`** (numeric, raw percentage value — e.g. `5` meaning 5%,
confirmed via `diver-form.html`'s consumer: `defaultCardSurchargeRate =
Number.isFinite(pct) ? pct : 5`).

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, surcharge_type (enum, check in 'card'/'online'),
rate (numeric(6,4)), is_active
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `surcharge_type` (loose free text, e.g. possibly `"Credit Card"`, `"card"`, `"Card"`) | `surcharge_type` (strict enum, only `'card'`/`'online'`) | **Needs normalization during migration** — old app's own read-side code has to fuzzy-match because the write side never strictly constrained the value; run every old row through the same `.toLowerCase().includes('card'|'credit')`/`.includes('online')` classification the old app itself uses before inserting into the new strict-enum column. Rows that don't classify cleanly need manual review. |
| **`percentage`** (raw number, e.g. `5` = 5%) | **`rate`** (numeric(6,4), fraction, e.g. `0.05` = 5% — confirmed via the rebuild's own `saveSurcharges` action: `rate: percent / 100`) | **Renamed AND rescaled.** `new.rate = old.percentage / 100`. This is the single most important unit-conversion gotcha in this whole document — a raw copy would make every surcharge 100x too large. |
| — | `is_active` | **new-only column** — old app has no active/inactive concept for surcharges (always implicitly active if a row exists). Backfill `true`. |

### Structural changes

- **Rescale required (`/100`) — see above, this is a real ETL correctness
  risk, not just a rename.**
- New schema also enforces `check (surcharge_type in ('card','online'))` —
  the old app's own loose matching logic (`.includes('card')||.includes
  ('credit')`) suggests the live data might have inconsistent free text;
  audit actual distinct values in the live `payment_surcharges.surcharge_type`
  column before writing the ETL's classification logic, don't assume only
  `card`/`online`/`credit card` variants exist.

---

## 12. `exchange_rates` (Settings > Exchange Rates tab, currency table)

### Old (settings.html)

`id, dive_center_id, currency_code, rate_to_php, is_active, updated_at`.

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, currency_code, rate_to_php (numeric(12,6)), is_active,
updated_at, unique(dive_center_id, currency_code)
```

### Field mapping

1:1 — no renames, direct copy of every field.

| Old field | New field | Notes |
|---|---|---|
| `currency_code`, `rate_to_php`, `is_active`, `updated_at` | same | direct copy |

### Structural changes

- New schema adds a `unique(dive_center_id, currency_code)` constraint — the
  old app's own `saveExchangeRates()`/`saveCustomCurrency()` logic already
  looks up an "existing" row by `currency_code` before deciding
  insert-vs-update, strongly implying this uniqueness already holds in
  practice, but **verify no old dive center has duplicate rows for the same
  currency code** before the migration insert hits a constraint violation.

---

## 13. `medical_questions` (Settings > Waiver tab)

### Old (settings.html)

`id, dive_center_id, question_text, is_active` (`created_at` read via
`.order('created_at')` — column exists and is used for ordering).

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, question_text, sort_order (int, default 0), is_active
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id` | `id` | same |
| `dive_center_id` | `dive_center_id` | same |
| `question_text` | `question_text` | same |
| `is_active` | `is_active` | same |
| `created_at` (old, used for display order) | *(no `created_at` column in new schema — replaced by `sort_order`)* | **Structural change.** The new schema has no `created_at` on this table at all — ordering is via an explicit `sort_order integer` instead. Migration must synthesize `sort_order` values from the old rows' `created_at` ordering (e.g. `row_number() over (partition by dive_center_id order by created_at)`), since there's no direct field-to-field copy possible here. |

### Structural changes

- **Ordering mechanism changed from implicit (`created_at`) to explicit
  (`sort_order`)** — the migration script needs to derive one from the
  other, not copy a column that doesn't exist on the new side.

---

## 14. `tanks` (Settings > Inventory tab, tank counts)

### Old (settings.html)

Fixed 3-row set (not a free-form table in practice): `id, dive_center_id,
type` (free text, exact strings `"Air 12L"`/`"Air 15L"`/`"Nitrox"`),
`total_count, available_count, in_use_count, low_alert_threshold`.

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, type (enum: air_12l|air_15l|nitrox), total_count,
available_count, in_use_count, low_alert_threshold,
unique(dive_center_id, type)
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id`, `dive_center_id` | same | same |
| **`type`** (free text `"Air 12L"`/`"Air 15L"`/`"Nitrox"`) | **`type`** (enum `air_12l`/`air_15l`/`nitrox`) | Value mapping: `"Air 12L"→"air_12l"`, `"Air 15L"→"air_15l"`, `"Nitrox"→"nitrox"` (lowercase, space→underscore) |
| `total_count`, `available_count`, `in_use_count`, `low_alert_threshold` | same | direct copy |

### Structural changes

New `unique(dive_center_id, type)` constraint matches the old app's own
implicit "exactly one row per type per dive center" UI model (a fixed
3-row table, `TANK_TYPES = ['Air 12L','Air 15L','Nitrox']`) — should hold
cleanly, but verify no old dive center somehow has duplicate rows for the
same tank type before insert.

---

## 15. `equipment` (Settings > Inventory tab, gear counts)

### Old (settings.html)

`id, dive_center_id, type, name` (both set to the same value on insert —
`{type:item, name:item, ...}`), `total_count, low_alert_threshold`.
Fixed 6-item set: `BCD, Wetsuit, Fins, Boots, Mask, Regulator`
(`GEAR_ITEMS` — note this is a DIFFERENT, shorter list than
`equipment_rental_rates`' 11-item `DEFAULT_EQUIP`, a genuinely separate
concern: gear-rental **pricing** vs. gear **stock counts**).

### New (`001_schema_and_rls.sql`)

```
id, dive_center_id, name, type (text, nullable), total_count,
low_alert_threshold, is_active, created_at
```

### Field mapping

| Old field | New field | Notes |
|---|---|---|
| `id`, `dive_center_id` | same | same |
| `type` AND `name` (old writes the identical string to both columns) | `type`, `name` | Both columns exist in the new schema too — migrate both, copying the same source value into each, matching the old app's own redundant-but-intentional write pattern (`renderGear()`'s read side matches on `e.type===item || e.name===item`, confirming both columns are genuinely read, not just one being dead) |
| `total_count`, `low_alert_threshold` | same | direct copy |
| — | `is_active` | **new-only column** — old app's gear-count UI has no active/inactive toggle (implicitly always active). Backfill `true`. |
| — | `created_at` | direct copy if present, else migration timestamp |

### Structural changes

None beyond the new `is_active` backfill — otherwise a clean 1:1 copy with
intentional column redundancy preserved.

---

## 16. `fuel_logs` (read-only historical data, Settings > Inventory > Fuel section reads it for consumed totals)

### Old / New

Both: `id, dive_center_id, boat_id, schedule_id, fuel_type, liters_consumed,
dive_count, diver_count, created_at`. Confirmed identical shape — this table
is operational/scheduling data (a log written by `scheduling.html`'s Boat
Return step, only *read* by Settings for the fuel-consumed-since-reset
display), not itself a config table, but included here since Settings reads
it. No renames observed. `fuel_type` here IS already lowercase in practice
(`fuel_type:fuelType||null` where `fuelType` was already
`.toLowerCase()`'d before the insert in `scheduling.html`) — unlike
`boats.fuel_type`, this column does NOT need a case transform.

---

## 17. `trip_types` — **new-only table, no old equivalent**

Confirmed via this project's own migration-025 comment: the live app
hardcodes trip-type durations as a JS constant
(`tripTypeDurations` in `scheduling.html`), keyed by free-text names specific
to one dive center's own geography (`"Local Dive"`, `"Shark Dive"`,
`"Gato"`, `"Outside Malapascua"`) — **not a database table at all** in the
old app. Nothing to migrate field-for-field. If historical per-dive-center
trip-type behavior needs to be preserved, it would have to be manually
re-entered per dive center post-migration (there's no automatable
old-DB source), or the four Malapascua-specific values could be seeded as
a starting default for every migrated dive center and edited from there
(matching what this project's own 2026-08-01 session did for the real Demo
Dive Center via direct SQL) — a business decision, not a data-migration one.

---

## 18. `privacy_notice` — platform-wide singleton, not per-dive-center

### Old (register.html reads it; no settings.html write path found — likely
admin-only, matching the new schema's own `is_platform_admin()`-gated write
policy)

`id (boolean, always true), content`. Confirmed via `register.html`'s
`.eq('id', true)` — a single global row, not scoped by `dive_center_id`.

### New (`001_schema_and_rls.sql`)

```
id (boolean primary key, check(id)), content, updated_at
```

### Field mapping

1:1 — `content` copies directly. This is confirmed to be one global row in
BOTH schemas (this project's own retrospective item #9 already validated
this against the old app's real shape) — migrate exactly **one** row, not
per-dive-center, and don't accidentally fan it out during a naive per-tenant
ETL loop.

### Structural changes

None — already correctly modeled as a singleton in both. `updated_at` is
new-only (no old equivalent observed) — backfill with migration-run
timestamp.

---

## 19. `platform_admins` — new-only table, replacing `users.is_platform_admin`

See the `users` section (#2) above for the full structural discussion — this
table has no direct old-schema equivalent, since the old app modeled
platform-admin status as a boolean flag on `users` instead of a dedicated
table.

---

## Auth migration considerations (`auth.users` / `auth.identities`)

Both the live production project and the new rebuild project use Supabase
Auth (GoTrue) — the underlying mechanism is identical infrastructure, just
two separate projects, so the *shape* of `auth.users`/`auth.identities`
should be directly comparable. This section is based on: `login.html`'s real
sign-in flow, `change-password.html`'s first-time-password-set flow,
`reset-password.html`'s recovery flow, `office.html`'s platform-admin
sign-in flow, and this project's own extensively-documented raw-SQL
`auth.users`/`auth.identities` fixture-insertion gotchas (retrospectives
#26, #27, #38 in `CLAUDE.md`).

### Can `encrypted_password` be copied directly?

**Plausibly yes, with real caveats — this is the single highest-value,
highest-risk question in the whole auth migration.**

- Supabase Auth's `encrypted_password` column is a standard bcrypt hash
  (`crypt()`/`gen_salt('bf')`-produced, same as this project's own
  `set_billing_unlock`/`set_owner_unlock` RPCs use for the *other* password
  fields). Bcrypt hashes are self-contained (algorithm + salt + hash all in
  one string) and are NOT tied to a specific Supabase project, instance, or
  any server-side secret — a bcrypt hash produced by GoTrue in the live
  project should verify correctly against the same plaintext password in the
  new project's GoTrue, since both are running the same bcrypt
  implementation with no external key material involved.
- **This means a direct row-copy of `encrypted_password` should let every
  existing owner/secretary log in with their existing password unchanged** —
  a real, valuable migration property (no forced password reset needed for
  every user).
- **However**: GoTrue's schema has evolved across Supabase platform
  versions, and the two projects may be on different GoTrue versions with
  subtly different `auth.users` column sets or defaults. **Do not assume the
  live project's `auth.users` row shape maps 1:1 onto the new project's
  schema** — diff `information_schema.columns` for `auth.users` between the
  two projects (via the Supabase dashboard's SQL editor on each, since this
  session can't connect to the live project directly) before writing the
  ETL insert statement.
- **The known, already-hard-won gotcha from this project's own history
  (retrospective #26) is the real risk here, not the bcrypt portability
  question**: several `auth.users` text columns
  (`confirmation_token`, `recovery_token`, `email_change_token_new`,
  `email_change`, `email_change_token_current`, `phone_change`,
  `phone_change_token`, `reauthentication_token`) **must be `''` (empty
  string), never `null`**, or GoTrue fails login with a generic, misleading
  500 `"Database error querying schema"` that gives zero indication the
  problem is a null token column. If the live project's real `auth.users`
  rows already have these as `''` (which they should, if they were created
  through the live app's normal signup, not a raw insert), a **direct
  column-for-column copy of `auth.users` (not synthesized fresh) is safer
  than trying to reconstruct a fresh row** — reuse the live values verbatim
  rather than regenerating them, specifically to avoid re-introducing this
  exact bug class into freshly-migrated accounts.
- `auth.identities.identity_data` must include `email_verified`/
  `phone_verified` keys (this project's own retrospective #26, confirmed
  necessary for login to work) — again, if copying real live rows verbatim
  (not synthesizing), this should already be correct, since the live app's
  real users signed up through a normal flow that sets these.
- **Recommendation**: migrate `auth.users` and `auth.identities` as a **raw,
  verbatim row copy** (remapping only the `id` UUID if new ids are being
  generated — recommend NOT regenerating ids, keep them identical across
  both projects to avoid every downstream FK remap this document already
  flags), not a re-synthesized insert built field-by-field from scratch.
  This sidesteps the entire "did I set every required column correctly"
  class of risk this project has already been bitten by twice
  (retrospectives #26, #40) — a straight `pg_dump`/`INSERT ... SELECT`-style
  copy of a real, already-working row is safer than reconstructing one.
- **`password_changed` gotcha (retrospective #38, still unresolved as of
  this project's own history)**: a raw-SQL-seeded test user with
  `password_changed = false` failed the real first-time-password-set flow
  with a generic error, for a reason never root-caused. If any migrated
  users are meant to land with `password_changed = false` (forcing a
  first-login password reset, e.g. for a fresh temp password issued during
  migration), **test this flow explicitly against a real migrated account
  before assuming it works** — this is a known open risk, not a solved one.
  Safer alternative: migrate every existing user with
  `password_changed = true` (their real password, copied verbatim per the
  bcrypt discussion above, already satisfies "they've set a real password")
  and skip the forced-reset flow entirely for migrated accounts.

### Platform admin accounts

Old: a `users` row with `is_platform_admin = true` (implying it also has
some `dive_center_id`, an odd shape). New: a `platform_admins` row
(`user_id → auth.users.id`, no `dive_center_id` at all) with **no
corresponding `public.users` row required**. Migration: for each old
platform-admin account, copy its `auth.users`/`auth.identities` rows
verbatim (per the general approach above), then insert exactly one
`platform_admins` row — do **not** also create a `public.users` row for it
unless that same person is independently a real dive-center owner/secretary
too (a person could plausibly be both, which is a legitimate case, not an
error).

### Secretary accounts and the shared hardcoded temp password

**Real, confirmed security gap in the old app, not carried over by
design**: `settings.html`'s `createSecretaryAuth()`/`createSecretaryAccount()`
both send a literal hardcoded string, `'aquadesk123'`, as every new
secretary's temp password via the `create-secretary` Edge Function — the
same password for every secretary account ever created across the old app's
entire lifetime, confirmed via multiple call sites
(`tempPassword:'aquadesk123'` appears 3 times in settings.html). **Do not
carry this pattern into the migration** — this project's own rebuild already
generates a real random temp password per new secretary (per CLAUDE.md's own
notes: "real random temp password, not the live app's shared guessable
one"). For accounts being *migrated* (not newly created), this doesn't
matter — their `encrypted_password` is whatever they've actually since set,
copied verbatim per the section above, not the original temp value (assuming
they logged in at least once and the forced-password-change flow ran) — but
flag this explicitly: **any migrated secretary account whose
`password_changed` is still `false` in the live DB genuinely still has the
password `aquadesk123`**, a real, exploitable, shared credential — these
accounts should be forced through a real password reset during migration,
not silently carried over with a guessable password intact.

### Login lockout state (`failed_login_attempts`/`locked_until`)

Confirmed identical shape and semantics in both schemas (both ported from
the same real `login-guard/index.ts` Edge Function source) — safe to migrate
directly, though low value: recommend resetting both to `0`/`null` for every
migrated account rather than carrying over transient lockout state from the
moment of migration, since a mid-lockout account migrated with
`locked_until` in the past would just silently unlock on first use anyway
(the RPC logic already self-clears an expired lock) and one in the future
would carry over an odd "why am I locked" surprise into a brand-new system.

### Suspended dive centers

`dive_centers.subscription_status = 'suspended'`/`'cancelled'` blocks login
in both apps (old: not observed directly in the settings.html grep pass, but
confirmed as an active new-schema check in `dal.ts`'s `resolveLandingPath`/
`getCurrentUser`, per CLAUDE.md's 2026-07-26 session). If a dive center is
migrated in a suspended state, its users should land suspended in the new
schema too — this falls out naturally from the `dive_centers.subscription_
status` field mapping (§1) as long as that value transfers correctly, no
separate auth-side handling needed.
