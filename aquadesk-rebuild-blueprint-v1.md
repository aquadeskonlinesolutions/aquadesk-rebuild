# AquaDesk Rebuild — Blueprint Working Doc (v1)

Status: Phase 0 (reverse-engineering the current system). This is a living document — it will grow into the full handover-ready spec (schema + RLS + functions + architecture) as we go. Old files are reference-only and untouched; nothing here changes the live system.

---

## 1. Table Inventory (41 tables found)

Grouped by function. Columns listed are the ones confirmed in use today (from reads and writes across all pages) — not final; the rebuilt schema will be cleaner and may rename/merge/drop some of these.

### Core tenant & identity
- **dive_centers** — the tenant record. `name, logo_url, waiver_content, waiver_updated_at, insurance_referral_link, offers_dive_insurance, staff_token, staff_token_date, pricing_mode`, plus fuel-tracking fields (`fuel_current_level`, `fuel_diesel_level`, `fuel_gasoline_level`, thresholds) — and two flagged fields, see Findings below.
- **users** — login accounts. `dive_center_id, full_name, email, role, can_view_revenue, is_active, password_changed`
- **staff** — operational staff profiles (may or may not have a login). `dive_center_id, first_name, last_name, email, role, access_level, is_active, auth_user_id`

### Divers & registration
- **divers** — `first_name, last_name, age, birthday, nationality, certification_level, logged_dives, group_id, needs_equipment, equipment_requested, medical_acknowledged, medical_acknowledged_at, medical_acknowledged_by, notes`
- **diver_registrations** — versioned registration/waiver records per diver. `diver_id, dive_center_id, group_id, arrival_date, departure_date, certification_level, equipment_preference, equipment_requested, needs_equipment, medical_answers, medical_answers_snapshot, medical_flag, privacy_consent_at, privacy_notice_snapshot, waiver_content_snapshot, waiver_date, waiver_signature_url, waiver_signed`
- **diver_notes** — free-text notes tied to a diver (insert-only pattern seen)
- **diver_staff_defaults** — default staff assignment per diver (`diver_id, staff_id, dive_center_id`)
- **groups** — travel groups/parties. `dive_center_id, group_name, leader_name, arrival_date, expected_count, is_active`
- **medical_questions** — configurable medical questionnaire. `question_text, sort_order`
- **privacy_notice** — privacy consent text shown at registration

### Scheduling & operations
- **schedules** — dive trips/sessions. `notes` (+ more, thin data — needs deeper look)
- **schedule_divers** — join table, diver↔schedule. `diver_id, schedule_id, staff_id, dive_center_id, experience_type, is_15l, is_diving_tomorrow, nitrox_requested, notes`
- **schedule_day_diver_exclusions** — divers excluded from a given day. `diver_id, schedule_date, dive_center_id, created_by`
- **schedule_team_clips / schedule_team_clip_divers** — team/boat grouping structures (needs deeper look)
- **boats** — `name, captain, fuel_type`
- **manifests** — boat manifest per trip. `district, port, last_edited_at`
- **dive_sites** — `site_name, shark_fee, fuel_estimate`
- **fuel_logs** — `boat_id, schedule_id, dive_center_id, fuel_type, liters_consumed, dive_count, diver_count`
- **activities** — per-diver charge/line-item record for a visit. `diver_id, visit_id, schedule_id, date, dive_site, dive_rate, addons, discount, equipment_rental, fee_15l, fifteen_l_fee, fuel_surcharge, marine_tax, nitrox_fee, shark_fee, staff_name, status, total`
- **visits** — a diver's stay/booking window. `diver_id, dive_center_id, course_rate_id, experience_type, visit_start, visit_end, visit_status, is_active, is_paid, invoice_count`

### Pricing & rates
- **course_rates, equipment_rental_rates, other_charges, packages, rate_tiers** — pricing tables (dive_center_id-scoped, `is_active` flags). `packages` and `other_charges` need a deeper column pass — currently only seen via `select('*')`.
- **payment_surcharges** — `dive_center_id, surcharge_type`
- **exchange_rates** — `dive_center_id, currency_code, rate_to_php, is_active, updated_at`
- **govt_fees** — government fee line items

### Money
- **payments, deposits** — `deposits`: `diver_id, amount, deposit_date, method, received_by`
- **expenses** — dive center operating expenses, has full CRUD (`date` range filter, insert/update/delete)
- **invoice_emails** — sent-invoice log. `diver_id, visit_id, invoice_snapshot, sent_at, sent_by`
- **join_ride_records / join_ride_statements** — third-party "join ride" billing/statement workflow. `join_ride_statements`: `company, date_from, date_to, total_amount, status, prepared_by, printed_at`
- **staff_commission_records, rental_gear_records** — reporting-only tables, thin data so far

### Equipment/inventory
- **equipment, tanks** — `equipment`: `name, total_count, type, low_alert_threshold, dive_center_id`

### System
- **audit_logs** — `action, target_type, target_id, performed_by, notes, dive_center_id, created_at` — exists but usage looks limited (only referenced in 2 pages); needs review for coverage.

### RPCs (server-side functions) found
- `check_returning_diver`
- `get_diver_prefill`
- `update_returning_diver_registration`
- `set_diver_cert_card_url`

These four are the only server-side logic found — everything else (pricing calculations, totals, role checks) currently runs in client-side JavaScript. That's a rebuild priority: move business logic server-side.

---

## 2. Findings So Far (to fix in the rebuild, not on live files)

| # | Finding | Why it matters | Rebuild fix |
|---|---------|----------------|--------------|
| 1 | **`dive_centers.billing_password` and `owner_password` stored as plain text, compared in client-side JS** (`current !== dcData.owner_password`) | Anyone with browser devtools can read these passwords directly; they gate billing/owner-level actions — real privilege escalation risk | Never store raw passwords in a data table. Use Supabase Auth properly (or a hashed secret checked via a server-side RPC/Edge Function), never compare secrets in the browser |
| 2 | **Business logic (pricing, totals, surcharges, role gating) lives almost entirely client-side**, only 4 RPCs exist | A user can, in principle, alter calculations or bypass role checks via devtools/API calls directly, since enforcement isn't guaranteed server-side | Move pricing calculations and authorization-sensitive logic into Postgres functions / RLS policies, so the server is the source of truth regardless of what the client sends |
| 3 | **`audit_logs` exists but is only referenced in 2 of 15 pages** | Inconsistent audit trail — most sensitive actions (payments, registration edits, settings changes) aren't logged | Rebuild with systematic audit logging (ideally via DB triggers, not per-page JS calls that are easy to forget) |
| 4 | **No RLS visibility from the frontend files** (expected — RLS lives in the DB, not in these files) | Can't yet confirm tenant isolation (`dive_center_id` scoping) is airtight | Full RLS policy definition is part of the blueprint — every table will get an explicit, tested policy tied to `dive_center_id` and role |
| 5 | **Several tables only ever queried with `select('*')`** (`packages`, `other_charges`, `manifests`, `expenses`, etc.) | Can't yet fully document their schema from usage alone | Will need either a read-only look at the live DB schema (if you're willing to share that access) or continued inference from insert/update payloads |

---

## 3. Role & Logic Inventory

The system actually runs on **three tiers**, not clearly formalized anywhere — this needs to become an explicit, documented model in the rebuild:

1. **Platform Admin (you / AquaDesk itself)** — `office.html` is a separate super-admin panel: create dive centers, suspend/unlock accounts, manage billing status per tenant. This is AquaDesk managing its *customers*, distinct from any one dive center's own users.
2. **Dive Center Owner** (`role === 'owner'`) — full access within their own dive center: revenue visibility, settings, passwords, all pages.
3. **Secretary / Operational Staff** (everyone else) — day-to-day work (scheduling, registration, boat manifest), gated away from revenue and settings by default. `can_view_revenue` is a separate granular flag layered on top of this tier — an operational user can be individually granted revenue visibility without becoming an owner.

**Finding:** Role classification logic in `settings.html` (`normalizeAccessRole`, `isSecretaryStaffRow`) is inference-based, with comments literally flagging it as a workaround — e.g. treating "any non-owner as operational," and guessing whether a `staff` record counts as a login-capable "secretary" based on whether it happens to be linked to a user account. This is a direct symptom of the pivots: role modeling grew organically instead of being designed once. **Rebuild fix:** one explicit `role` enum per tier (`platform_admin`, `owner`, `secretary`, and operational sub-roles like `divemaster`/`instructor`/`crew` as a separate non-authorizing "position" field), no inference needed.

**Staff vs. Users distinction:** the current system has two overlapping tables — `staff` (operational profile: divemaster, instructor, crew — may or may not log in) and `users` (login accounts). A staff member *may* have a linked login. This dual-table pattern is reasonable in principle (not everyone who works at a dive shop needs a login) but the linking logic between them is currently the fragile "legacy safety" heuristic above. **Rebuild fix:** keep the two-table split (it's the right model), but make the link explicit and required — a `staff` row either has a `user_id` or it doesn't, no guessing.

---

## 4. Next Steps

---

## 5. Stage 1a — Target Schema & Security Model

### Design principles for the rebuild
- **`dive_center_id` is the tenant boundary on every tenant-scoped table**, enforced by RLS — never trusted from the client.
- **No secrets in data tables.** Passwords go through Supabase Auth only; anything else sensitive (e.g. billing unlock) is a hashed value checked server-side, never sent to the browser for comparison.
- **Role checks live in RLS policies and Postgres functions, not in page JavaScript.** Client-side role logic is allowed only to decide what to *show* in the UI — never the last line of defense.
- **One explicit `role` enum, not inferred.** `platform_admin`, `owner`, `secretary` — plus a non-authorizing `position` field (`divemaster`, `instructor`, `crew`, etc.) for display/scheduling purposes only.
- **Money-affecting calculations (pricing, surcharges, totals) computed server-side** in Postgres functions, so a modified client request can't change what gets charged.
- **Every insert/update/delete on sensitive tables logged automatically via trigger**, not via per-page JS calls that are easy to forget.

### Table groups (target schema — v1 draft)

**Platform layer**
- `dive_centers` — tenant record. Drop `billing_password`/`owner_password` entirely; replace with Supabase Auth + a `platform_admin`-only unlock flow if a secondary confirmation step is still wanted.
- `platform_admins` — separate table from `users`, so platform-level access is never confusable with a dive center's own owner role.

**Identity**
- `users` — one row per login, `dive_center_id`, `role` enum, `is_active`.
- `staff` — operational profile, `user_id` nullable FK (explicit link, no inference), `position` (display-only), `is_active`.

**Divers & registration**
- `divers`, `diver_registrations` (versioned, immutable once signed — waiver snapshots should never be editable after signing), `diver_notes`, `groups`, `medical_questions`, `privacy_notice`.

**Scheduling & operations**
- `schedules`, `schedule_divers`, `schedule_day_diver_exclusions`, `schedule_team_clips` (+ divers), `boats`, `manifests`, `dive_sites`, `fuel_logs`, `diver_staff_defaults`.

**Pricing (config tables — owner-writable, secretary-readable)**
- `course_rates`, `equipment_rental_rates`, `other_charges`, `packages`, `rate_tiers`, `payment_surcharges`, `exchange_rates`, `govt_fees`.

**Money & transactions**
- `visits`, `activities` (line items — computed server-side via function, not written raw from the client), `payments`, `deposits`, `expenses`, `invoice_emails`, `join_ride_records`/`join_ride_statements`, `staff_commission_records`, `rental_gear_records`.

**Inventory**
- `equipment`, `tanks`.

**System**
- `audit_logs` — trigger-populated on every sensitive table, not manually called per page.

### RLS policy pattern (applies per table, adjusted per tier)

| Tier | Read | Write |
|---|---|---|
| Platform Admin | own `dive_centers`/billing data only, not diver/operational data | tenant status, billing fields only |
| Owner | everything within their `dive_center_id` | everything within their `dive_center_id` |
| Secretary | everything within their `dive_center_id` **except** revenue-tagged fields, unless `can_view_revenue = true` | operational tables (scheduling, registration, manifest) — not settings/pricing/staff-management tables |

This becomes a literal policy per table in Stage 2 (e.g. "secretary can INSERT into `schedule_divers` where `dive_center_id` = their own, cannot INSERT into `course_rates`") — the table above is the general rule; exceptions get called out explicitly per table before we build.

### Server-side functions to add (beyond today's 4 RPCs)
- `calculate_visit_total(visit_id)` — replaces client-side pricing math
- `verify_billing_unlock(dive_center_id, attempt)` — replaces plaintext password comparison
- Audit-logging triggers on: `payments`, `diver_registrations`, `visits`, `dive_centers`, `users`, `staff`
- Existing 4 (`check_returning_diver`, `get_diver_prefill`, `update_returning_diver_registration`, `set_diver_cert_card_url`) carry over as-is unless review finds issues

---

## 7. Stage 1b — Page Map (New App)

Current app is 15 flat HTML files. Rebuilt as routed sections with shared layout/nav/auth per tier, instead of each page reinventing it. Grouped by who uses them.

### Public (no login)
| Page | Purpose | Notes |
|---|---|---|
| Marketing site | `index.html` equivalent | Could reasonably live outside the app entirely (its own simple site) since it shares nothing functional with the product — worth deciding later, doesn't block the build |
| Diver Registration | `register.html` | Public link shared with divers before arrival — fills waiver, medical questions, equipment prefs |
| Login | `login.html` | Single login, redirects by role after auth |
| Set/Reset Password | `change-password.html`, `reset-password.html` | Merge into one flow with two entry states (first-time set vs. reset) — same screen, different trigger |

### Platform Admin (you)
| Page | Purpose | Notes |
|---|---|---|
| Admin Console | `office.html` | Manage dive centers: create, suspend, billing status. Stays fully separate from the dive-center-facing app — different login, different domain/subdomain even |

### Dive Center App (owner + secretary, permission-gated per screen)
| Page | Purpose | Owner | Secretary |
|---|---|---|---|
| Dashboard | Daily overview, activity feed, revenue snapshot | Full | Full, minus revenue unless flagged |
| Scheduling | Trip/schedule builder, boat & staff assignment | Full | Full |
| Divers | Diver list/search, visit & payment history | Full | Full |
| Diver Detail/Form | Registration detail, charges, payments for one diver | Full | Full |
| Boat Manifest | Per-trip manifest, offline-cacheable | Full | Full |
| Staff | Staff roster, roles, positions | Full | View own profile only |
| Reports | Revenue, expenses, commissions, join-ride statements | Full | Hidden unless `can_view_revenue` |
| Settings | Pricing, rates, dive sites, equipment, waiver text, staff access, integrations | Full | Hidden entirely |

### Consolidation opportunities (flagged for your call, not decided yet)
- **`change-password.html` + `reset-password.html` → one screen.** No functional reason to keep separate; today they're separate only because they were built at different times.
- **Divers + Diver Form** could stay separate (list vs. detail is a normal pattern) or become list+drawer on one page — a UX call for Stage 1c, not urgent.
- **Settings is currently one 168KB file covering ~8 unrelated things** (pricing, staff access, waiver text, gear, integrations). Rebuild should split it into sub-sections (tabs or sub-routes) — same page conceptually, but not one monolith.

---

---

## 9. Stage 1c — Design Direction

**Decision: keep AquaDesk's existing visual identity, don't redesign it.** The current design tokens are deliberate and consistent across all 15 pages already — this is one of the few areas that wasn't a casualty of the pivots.

**Carried forward as-is, unified into one shared source (Tailwind config) instead of redefined per file:**
- Palette: navy `#1A3C5E` + teal `#00A8AB` (ocean/dive theme), semantic light/dark pairs for success/warning/error states
- Typography: `DM Serif Display` (headings) + `DM Sans` (body)
- 12px corner radius, existing shadow tokens

**What the rebuild adds (gaps that come from moving off static HTML, not a redesign):**
- Shared component library (buttons, forms, tables, modals) with consistent states — hover/focus/disabled/loading — instead of each page implementing its own
- `settings` split into tabbed sub-sections instead of one 168KB monolith (structural, not visual)
- Real mobile/tablet responsiveness audit — likely used at a counter on a tablet day-to-day

**Explicitly rejected:** a new visual identity / rebrand. Consistency and intentionality read as more professional to a future buyer than novelty for its own sake.

---

## 11. Stage 6 — Data Migration & Cutover

**Goal:** move every dive center from the live system to the rebuilt one, with zero disruption and zero action required from users — no forced password resets, no downtime, no risk to the live system during the build.

**Why a separate Supabase project, and it stays that way through migration:** the rebuild happens in total isolation from the live database for the entire build period (months). No schema change, test, or mistake made during Stage 2/3 can ever touch the system currently running paying customers. This is non-negotiable given the build timeline may cross a high season.

**How full migration without user disruption is possible:**
- Supabase Auth is standard Postgres underneath (`auth.users`), storing properly hashed passwords — not proprietary or locked in.
- At cutover time, credentials are copied **at the database level** (hashed values transferred directly, never seen or reset), alongside each dive center's transformed data (per the Stage 1a schema mapping).
- Result: a user logs in on their normal day, same email + password, and is transparently on the new system. No email, no "activate your account," no visible change.

**Cutover model: gradual, per-dive-center, never a mass event.**
1. Finish and fully validate the rebuild in the isolated project — no live customers involved yet.
2. Build and test the migration script (data transform + credential copy) against copies of real data — dry runs only, never against production directly.
3. Migrate one low-risk/test dive center first. Verify thoroughly (especially payment history and signed waivers/registrations — zero tolerance for data loss there).
4. Migrate remaining dive centers one at a time, on a schedule that avoids each customer's high season — never a single big-bang cutover for everyone at once.
5. Old system stays live and untouched as a fallback until every customer is confirmed stable on the new one.

**What Claude Code needs to build for this stage:** a migration script per table (old schema → new schema transform), a credential-copy step for `auth.users`, a dry-run/validation mode, and a rollback plan per dive center in case a migrated customer needs to fall back to the old system temporarily.

---

## Blueprint Status: COMPLETE (Stages 0, 1, 6 planned — build stages 2–5 to follow in Claude Code)

## 12. Next Steps

1. Open a Claude Code session (separate from this chat) and hand it this document as the build spec.
2. Stage 2 — new isolated Supabase project, schema + RLS built exactly to this spec.
3. Stage 3 — Next.js app build, page by page, using the current live app as behavioral reference.
4. Stage 4 — testing and polish against the design direction above.
5. Stage 5 — final handover documentation package (schema doc, RLS doc, architecture overview, README).
6. Stage 6 — migration script (data + credentials), dry runs, then gradual per-dive-center cutover as described above. Live system stays untouched and available as fallback throughout.
