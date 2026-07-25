# AquaDesk Rebuild — Project Memory

Read this in full before doing anything. It's the continuity file across
sessions — the user does not read or write code themselves, so this file
(and plain-language chat updates) is how decisions and state persist.

## What this project is

Rebuilding AquaDesk, a dive-center management SaaS, from a plain HTML/JS +
Supabase app into a clean Next.js app. The full spec is
`aquadesk-rebuild-blueprint-v1.md` at this root — read its Stage 1a/1b/1c/6
sections for schema, page map, design direction, and migration plan.

**Folder layout:**
- `D:\Rebuild\` (this root) — the blueprint doc, the *old* live app's HTML/JS
  files (reference-only, read but never modify, never connect to the
  project they talk to), and `database\` (SQL migration files, see below).
  **Now its own git repo** (`git -C D:\Rebuild ...`), initialized
  2026-07-25 — see the former "Known gap" note, now resolved, near the
  end of this file for what's tracked vs. `.gitignore`d.
- `D:\Rebuild\aquadesk-app\` — the actual Next.js rebuild. This is its own
  separate git repo (`git -C aquadesk-app ...`) — two independent repos
  in this tree, don't mix up which one a `git` command should target.
- `D:\Rebuild\database\` — tracked SQL migration files (001–011 so far),
  the source of truth for schema/RLS/functions. Git-tracked as of
  2026-07-25 (previously wasn't — see resolved "Known gap" note).

## Absolute rule: two separate Supabase projects, never confuse them

- **Live production** (never touch, never connect to, never reference
  credentials for): project ref `xaabndtaevwgicibzcqm`, "AquaDesk
  Solutions". The old HTML/JS files in this root talk to it — they are
  behavioral reference only.
- **New isolated rebuild project** (this is the one we build against):
  ref `vqwrluiikodconwlmwls`, owned by account `aquadeskonline@gmail.com`,
  region `ap-southeast-1`. URL: `https://vqwrluiikodconwlmwls.supabase.co`.
  Direct host resolves IPv6-only and is unreachable from this machine —
  **always use the pooler**: `aws-0-ap-southeast-1.pooler.supabase.com:6543`,
  user `postgres.vqwrluiikodconwlmwls`. DB password: ask the user again if
  not already in this session — deliberately not persisted here (see
  credential-hygiene note below). Publishable/secret API keys are in
  `aquadesk-app/.env.local`.
- The Supabase CLI on this machine authenticates per-account, not
  per-project — **check `supabase projects list` before any `supabase
  link`/CLI work**; it silently shows only whichever account is currently
  logged in, and this machine's default login was the *live* account
  (found and fixed once already — see retrospective below).
- Platform admin login for the rebuild: `aquadeskonline@gmail.com` (user
  should have changed the temp password already; if login fails, may need
  a reset — that account is a `platform_admins` row + matching
  `auth.users` row, not a `public.users` row).

## Current state (as of 2026-07-25, continued session — Scheduling, rebuild complete)

**Every page in the originally-agreed build order is now built, verified,
and committed: Settings → Boat Manifest → Reports → Divers → Staff →
Scheduling.** This closes out the multi-session rebuild arc. The
`D:\Rebuild` root is its own git repo (see the folder-layout note above)
with its own commit history tracking `database/*.sql` and the old app's
reference files — `aquadesk-app/` stays a separate repo, excluded via
`.gitignore` in the root repo. Check `git status` in **both** repos
before assuming either is clean, since this file is a snapshot at
write-time, not live state.

**Migration 011** (`database/011_groups_fields.sql`): adds
`departure_date`/`notes` to `groups` — the old app's registration-link
group form collects both, the original schema had neither. See the
Scheduling write-up below for the full design reasoning and how it
absorbed the deferred `divers.html` group/push-to-schedule workflow.

### Not yet built

**Nothing** — this was the last page. Known, documented, non-blocking
gaps remain (see "Known gaps" below and the inline call-outs in each
page's write-up) but no page is missing a build. Future work from here
is refinement/gap-closing, not new pages, unless the user opens new scope.

### What's built and verified (in a real browser, not just compiled)

**Foundation (Stage 1a + auth/admin, from the 2026-07-23 session):**
- Full schema + RLS (`database/001_schema_and_rls.sql`): ~43 tables, RLS
  on every one, 3-tier model (platform_admin / owner / secretary)
  enforced in Postgres. Server-side pricing totals via trigger, audit
  logging via triggers, hashed billing/owner unlock secrets, registration
  RPCs. Tested with real simulated sessions, not just "the policy looks
  right."
- Login, forced first-time password set, platform admin console
  (`/office` — create/suspend dive centers via a service-role Server
  Action).
- Public diver registration (`/register?dc=<id>`) — full 9-step wizard,
  4 SECURITY DEFINER RPCs, confirmed anon has zero direct table access.

**Dashboard** — stat cards, boats-today, alerts (5 of the original 6 —
see Known Gaps), payment channels, revenue summary + weekly chart
(owner/`can_view_revenue` only). All "today"/"tomorrow" logic anchored to
Asia/Manila regardless of server timezone.

**Settings — all 5 tabs done:**
- **Pricing & Rates**: pricing mode (package/tier) lock + owner-password-
  gated switch (blocked while open unpaid bills exist), course rates,
  packages, tiered rates (base dive/nitrox/15L tank), other charges,
  equipment rental rates, payment surcharges, exchange rates.
- **Staff Access**: secretary account creation (real random temp
  password, not the live app's shared guessable one), active/revenue-
  visibility toggles, password reset, owner/billing password management
  (first-time set needs no current password; every change after that
  does, verified via `verify_owner_unlock`/`verify_billing_unlock`).
- **Waiver & Registration**: rich-text waiver editor, medical questions
  CRUD. Fixed a real stored-XSS gap in the already-built `/register` page
  along the way (see retrospective/session log below).
- **Equipment**: Fleet (boats), Dive Sites, Tanks, Fuel, Rental Gear
  inventory counts.
- **Integrations**: dive insurance toggle + referral link.

**Boat Manifest** — Bureau of Customs passenger-manifest sheet, pre-filled
from a selected trip's boat/site/roster, District/Port editable and
persisted, print via the browser dialog, padded to 32 rows. Removed two
values hardcoded to the original Malapascua dive center (see session log)
since they'd be wrong for every other tenant.

**Reports — all 8 tabs done: Overview, Staff Activity Summary, Join
Ride, Rental Gears, Expenses, Settlement, Government Fees, and Billing
Audit.** Gated to owner/`can_view_revenue` for the whole page.
- **Overview**: business summary (money in/out/net profit/not-yet-
  settled), hero story sentence, dive site activity bars, money snapshot
  donut, expense breakdown bars, date range picker.
- **Staff Activity Summary** — rebuilt same-session as "Staff Commission
  / Payout Summary" per explicit user spec, replacing an earlier
  calendar-month-bucketed version (see retrospective #16 below). Now
  per-line-item, one row per dive-group or course-group keyed by its real
  `activity_date` (`staff_commission_records.activity_date`, migration
  `007_staff_commission_rates.sql` — dropped the old `period_month`
  column entirely), so marking a custom date range "paid" only affects
  entries actually in that range; a wider view afterward correctly shows
  a paid/unpaid mix. Verified end-to-end: narrowed the range to one day,
  bulk-marked it paid, widened back to the full month, and confirmed via
  direct SQL that the other (already-paid) day's row was untouched.
  - **Leading Our Dives**: dives × rate = base pay, fully automatic. Rate
    defaults from a new dive-center-wide Settings value
    (`dive_centers.divemaster_rate_per_dive`, editable per line as a
    safety valve) — confirmed with the user this is one flat rate per
    dive center, not per staff member, in-house or freelance. Divers
    count is a first-class visible column (not hidden in a drill-down).
    An optional **ratio bonus** (`ratio_bonus_enabled` +
    `ratio_bonus_extra_rate` on `dive_centers`) flags any row with >4
    divers and offers a manual bonus input pre-filled from the configured
    extra rate — deliberately **no formula**; per the user's explicit
    answer, the app's job is only to surface that the ratio was exceeded
    that day and offer the option, never to auto-apply anything.
  - **Our Dive Educators**: tallies students/course per instructor
    automatically, but the payout amount is always typed by hand (never
    quantity × rate) — course pay structures are too inconsistent
    (fixed/percentage/gross/net) to formulaically calculate. Verified an
    entered ₱3,000 persisted exactly as ₱3,000, not recomputed from the
    2-student count.
  - The dive-count reconciliation logic (row-count/diver-count, since
    `activities` is one row per diver per dive) and the clean
    `visits.experience_type` course/fun-dive split both carried over
    unchanged from the first version — see retrospective #16 for what did
    change and why.
  - "Mark All Unpaid as Paid" bulk action per table is a client-side loop
    over the existing single-row save action, scoped to whatever's
    currently displayed for the applied date range — no separate bulk
    server action needed.
  - The "Selected Staff Details" drill-down from the first version was
    removed: once the main tally itself is per-dive (date + site + dives
    + divers), a separate hidden per-date breakdown had nothing left to
    show.
  - New Settings > Pricing & Rates section ("Staff Commission & Join Ride
    Rates") holds all three configurable values plus the join ride rate
    (`join_ride_rate_per_diver_per_dive` — no live-app precedent anywhere,
    confirmed by grepping all old HTML files; the live app hardcodes
    ₱500 directly in reports.html's UI copy).
- **Join Ride**: two directions (They Joined Our Boat / We Joined Another
  Boat) each with their own status flow
  (to_collect→statement_printed→collected /
  expected_to_pay→statement_received→paid), five all-time summary cards
  (not date-range scoped — same "current balance, not a date-bound
  figure" precedent as Overview's Open Diver Bills), a date-filtered
  records table, inline add/edit, and collection-statement generation
  (groups a company's matching records into a `join_ride_statements` row,
  bulk-marks them `statement_printed`, renders a two-copy print view).
  Total is auto-computed (divers × dives × the configurable rate) and
  frozen at save time, matching the live app's behavior but with a real
  Settings-driven rate instead of a hardcoded ₱500. Print uses Boat
  Manifest's established `print:hidden` in-page pattern, not the live
  app's popup-window — and does **not** auto-trigger `window.print()` on
  generation (the live app does); a secondary line of reasoning applies
  here too: an unreviewed auto-print is questionable even for a real
  secretary, not just a testing inconvenience — the statement stays
  visible on-screen with an explicit "Print Statement" button instead.

  **Real bug found and fixed while building this**: both Staff Activity
  Summary and Join Ride tabs manage their own local state after a save
  (patching in place or refetching) rather than round-tripping every
  mutation through `ReportsClient`'s `staffData`/`joinData`. Since these
  tabs were conditionally unmounted/remounted on every tab switch (a
  ternary `{tab === "x" ? <Tab/> : <Tab/> : ...}` chain), switching away
  and back would remount from whatever stale snapshot `ReportsClient`
  last fetched — silently discarding anything saved during the tab's
  previous mount. Fixed by never unmounting these tabs once loaded;
  `ReportsClient` now keeps all loaded tabs mounted permanently and
  toggles visibility with a `hidden` class instead of conditional JSX.
  Any *future* Reports tab built with this same "load once, mutate
  locally" pattern needs the same treatment — see retrospective #18.
- **Rental Gears**: simpler than Join Ride — one flat status enum
  (`to_collect`/`collected`/`to_pay`/`paid`, no direction column, no
  sub-tabs; a record's status alone tells you which direction it is) and
  no statement-generation step, otherwise the same shape (five all-time
  cards including a Net Rental Balance, date-filtered table, inline
  add/edit, quantity × rate = balance auto-computed). Built onto the same
  always-mounted `ReportsClient` block from the start (see the Join Ride
  entry above) rather than needing a follow-up fix.
  - **Equipment field improved over the live app**: the live app uses a
    rigid `<select>` with a fixed item list plus an "Other" option that
    has no accompanying text input — editing a record whose equipment
    name isn't in that list falls back to displaying "Other," and saving
    again overwrites the original name with the literal string "Other,"
    losing it. Replaced with a free-text input backed by a `<datalist>`
    of the same common suggestions (`reports/constants.ts`) — same
    quick-pick convenience, but any custom name now round-trips through
    edit correctly. Verified with a seeded "Underwater Scooter" record
    (deliberately not in the suggestion list): loaded correctly into the
    edit form and persisted unchanged after saving.
- **Expenses**: unlike Join Ride/Rental Gears, this is a plain log with
  no pending-balance concept, so (matching the live app) the fetch is
  date-range scoped server-side rather than fetched once unbounded —
  every figure here is meant to be read within the selected period, and
  expenses can accumulate far more rows over a dive center's lifetime
  than occasional rental/join-ride transactions. Four cards (Total,
  Uncategorized, Top Category, Entries Logged), a category breakdown bar
  list, and a records table with real Edit/Delete (the only Reports tab
  so far with delete — matches the live app, which has one here but not
  on Join Ride/Rental Gears/Staff Activity). Category is a real fixed
  Postgres enum (`expense_category`) plus a `custom_category` text field
  when "Other" is picked — unlike Rental Gears' equipment name, this one
  genuinely has a designed escape hatch already, so the live app's plain
  `<select>` was ported as-is, no datalist fix needed here.
  `expenseGroupLabel` (the "Other – custom" / "Other (unspecified)"
  formatting) was pulled out into one shared helper in `data.ts`, used by
  both this tab and Overview's category bars, instead of staying
  duplicated inline in both places.

  **Second real bug found and fixed, more subtle than the Join Ride
  one**: `ReportsClient`'s `applyDateRange` fetched each tab's fresh data
  with sequential `await`s, calling `setAppliedFrom`/`setAppliedTo`
  (which `StaffTab`/`ExpensesTab` use as their remount `key`) *before*
  awaiting the later tabs' fetches. Widening the date range while
  Expenses was already open would remount `ExpensesTab` — via the
  `key` change — using the *still-stale* `expensesData`, since
  `setExpensesData(freshData)` hadn't been called yet (it was still
  mid-`await`); by the time the fresh fetch resolved, the remount had
  already happened and re-initializing `useState` on an already-mounted
  instance is a no-op, so the fresh data was silently dropped. This is a
  different mechanism from the Join Ride bug (that one was about
  unmounting entirely; this one is about *ordering* the state updates
  that drive a remount `key` against the state updates that feed the
  remounted instance's initial data) — same underlying lesson, new shape.
  Fixed by fetching all three (`getOverviewData`/`getStaffActivityData`/
  `getExpensesData`) via `Promise.all` first, then calling every
  `setState` together afterward so they commit in one batch — the `key`
  change and the fresh data now always land in the same render. Verified
  by widening the range to include a deliberately-out-of-range seeded
  entry and confirming it appeared after Apply (it silently didn't,
  before the fix). See retrospective #20 — **any future Reports tab
  using the `key`-remount pattern for its own date-range refetch must
  have its fetch included in this same `Promise.all`, not bolted on with
  its own sequential `await` afterward.**

- **Settlement**: a single-date cash-drawer reconciliation, not a
  date-range report — its own independent date picker (defaults to
  today, Asia/Manila), separate from the shared Reports date-range at
  the top of the page. One row per payment collected that day plus
  deposit rows (highlighted, with card/online/total-collected columns
  dashed out since a deposit isn't "collected" revenue yet), a grand-
  total footer, Print, and CSV download. "Closed By" resolves through
  `invoice_emails.sent_by → users.full_name`, taking the most recently
  sent invoice per visit — ported directly from the live app's same
  resolution logic. No add/edit/delete (a pure read + reconciliation
  view), so unlike Staff/Expenses it doesn't need the `key`-remount /
  `Promise.all` treatment from retrospectives #18/#20 — it's still kept
  in `ReportsClient`'s always-mounted block for tab-switch UX
  consistency with its siblings, but that's a nice-to-have here, not a
  bug-prevention necessity, since there's no local mutation state that a
  remount could lose. Print follows the established in-page pattern
  (Boat Manifest / Join Ride's `hidden print:block` + explicit button-
  triggered `window.print()`, not the live app's popup-window + auto-
  print) — verified via a seeded test dive center with one payment
  (cash + foreign-currency cash + card + online, all with surcharges)
  and one deposit for "today," confirming every column, the grand
  total, the CSV export content, and the print-only markup matched the
  live app's arithmetic exactly. Test dive center and its auth user
  were deleted afterward; database confirmed back to just the real
  platform admin account.

- **Government Fees**: date-range scoped (the shared Reports From/To
  picker, same as Expenses — the live app's `monthStart()`/`monthEnd()`
  helpers turned out to just be aliases for those same two inputs, not a
  separate range). This tab hit the exact schema trap retrospective #13
  already warned about, live: the base `001_schema_and_rls.sql` still
  defines `govt_fees` as the original wrong rate-config shape
  (`fee_name`, `amount`, `is_active`), but a **prior session already
  fixed this in `database/006_govt_fees_daily_log.sql`**, altering it to
  the live app's real daily-log shape (`date`, `fee_type` — a 3-value
  check constraint of `Marine Fee`/`Shark Fee`/`Other Fee` — `rate`,
  `divers`, `total`). Caught by remembering to check for later
  migrations against the same table before trusting the base schema
  file, rather than rediscovering the same mismatch a third time. The
  UI matches the live app's real interaction model, which is genuinely
  different from Expenses: no per-row edit, only **add draft rows
  in-table → "Save All" bulk-inserts every unsaved row in one call →
  existing rows can only be deleted**, not edited afterward. Total is
  always server-computed from `rate × divers`, never trusted from the
  client (verified via direct SQL after a Save All that the stored
  `total` matched, not just the echoed UI value). One real bug found
  and fixed during testing: the "Government fees saved." message from a
  prior Save All stayed on screen after a subsequent Delete, because
  `removeRecord` never cleared it — fixed by clearing the message at
  the start of the delete handler too. Verified end-to-end with two
  seeded records, one added-then-saved record (including a genuine
  `₱0` rate/divers row, which the live app allows and doesn't
  validate against), and a delete — confirmed against Overview's
  Government Fees money-out total matching too.

- **Billing Audit**: unbounded, not date-range scoped (loaded once per
  tab-open, same "fetch once unbounded" shape as Join Ride/Rental
  Gears — the live app caches it behind its own `auditLoaded` flag).
  Three sections: **Flagged Bills** (any visit with `invoice_count > 1`
  — a sign charges may have changed after a bill was already closed —
  click a row to expand every invoice sent for that visit), **Invoice
  History** (every invoice ever sent, client-side search by diver name
  or email), and **Bill Unlock Log** (`audit_logs` rows where
  `action = 'bill_unlocked'`, joined to `users.full_name` for who
  unlocked it). Per-invoice "View / Print" opens an in-page invoice
  preview — reusing the established `hidden print:block` + explicit
  button-triggered `window.print()` pattern (no popup window, no
  auto-print, same reasoning as Settlement/Join Ride) rather than the
  live app's popup-window-with-auto-print. Every invoice's line items
  and totals are read from `invoice_emails.invoice_snapshot` (a jsonb
  capture taken at send time) using the same defensive multi-name field
  fallbacks the live app uses (`grand_total ?? grandTotal ?? total`,
  etc.) — **there's no rebuild-side checkout/invoice-generation flow
  yet** (that's part of the not-yet-built Divers page), so this stays a
  best-effort read against an unsettled shape until that flow exists
  and actually pins down what a real snapshot looks like; revisit this
  tab's field-name fallbacks once Divers/checkout ships a real one.
  Verified end-to-end with a seeded flagged visit (2 invoices, one with
  two activity line items, cash + card + surcharge), one clean
  single-invoice visit (correctly *not* flagged), and one unlock log
  entry — flagging logic, the expand-to-see-all-invoices view, the
  search filter (scoped only to Invoice History, not the other two
  sections, matching the live app), and the invoice preview's line
  items/totals/footer all matched the seeded data exactly.

**Divers + Diver Detail** — built end-to-end this session, all 12
stages from the approved plan, each verified in a real browser against
a seeded test dive center before moving to the next (`git status`
shows everything still uncommitted, see the flag at the top of this
file).

Scope decision made with the user before starting: the old app's
`divers.html` isn't a diver directory at all — it's a scheduling-prep
triage tool (group creation, gear prep, "push to schedule"), which
writes to `schedule_divers`/`visits`, not diver records. That workflow
is **deferred to when Scheduling is built**. What got built now is a
clean **Divers list/search** page plus **Diver Detail** (profile,
notes, equipment, activity logging, a full three-mode pricing engine,
billing, checkout/invoicing, bill unlock, and a read-only signed-
documents history) — comparable in scope to the entire Reports build.

- **Migration 008** (`database/008_diver_profile_fields.sql`): added
  `accommodation`, `emergency_contact_*` (5 fields), `food_allergies`,
  `has_dive_insurance`, `insurance_provider`, `insurance_policy_number`,
  and `is_minor` to `divers` — edited directly on the diver's evergreen
  profile via Diver Detail's Edit form, **not** by mutating
  `diver_registrations` (which stays exactly as designed: the
  permanent, immutable record of what was actually signed — enforced
  at the DB level by `enforce_registration_immutability`, not just by
  convention). Also updated `submit_diver_registration` to copy all of
  these (plus `is_minor`) onto `divers` on both the insert-new-diver and
  update-existing-diver branches — every one of these fields was
  already in `RegistrationWizard.tsx`'s submitted payload, just never
  written to `divers` before. Added `invoice_emails.email_sent_at` /
  `email_sent_by` / `email_delivery_status` for the separate "send the
  invoice" step (see checkout below) — kept distinct from the existing
  `sent_at`/`sent_by`, which already mean "invoice generated / bill
  closed by" and are what Billing Audit already reads that way.
- **`is_minor` bug fixed**: `RegistrationWizard.tsx` computed `isMinor`
  (used it for the confirmation screen) but never sent it to
  `submit_diver_registration` — confirmed by reading the actual payload
  object, not assumed. One-line fix, verified via a real registration
  through the actual wizard UI (not just direct SQL) that `divers.
  is_minor` ends up correct.
- **Divers list/search**: search across name/email/whatsapp/phone/
  accommodation (2-char minimum), each result's "latest arrival" pulled
  from their most recent `diver_registrations` row via a join-via-`Map`
  (same pattern as `reports/data.ts`), since `arrival_date` now lives
  only on registrations, not the evergreen `divers` row. Default view
  (no query) shows the 20 most recently registered divers.
- **Diver Detail profile**: display + edit (the migration-008 fields),
  minor/medical flag banners (medical ack standardized on
  `medical_acknowledged_at`/`_by`, never the plain boolean also on that
  table), cert card viewer (reuses the already-working `cert-cards`
  Storage bucket/RLS from `003_cert_card_storage.sql` — no schema
  change needed), notes (insert + owner-only delete per existing RLS,
  author resolved via join to `users.full_name` at render time, not a
  write-time text snapshot — matches Settlement's "Closed By" pattern),
  equipment editing (`divers.needs_equipment` +
  `equipment_requested` — confirmed the REAL shape by reading
  `RegistrationWizard.tsx` directly (`{items:[{name,size}], computer}`)
  rather than trusting the old app's different `{type,items}` shape).
- **Pricing engine** (`divers/[id]/pricing.ts`) — the largest, riskiest
  piece, built in TypeScript not a Postgres function (the only existing
  server-side "pricing" logic, `compute_activity_total`/
  `calculate_visit_total`, are confirmed-trivial sums with zero rate
  lookup — no precedent anywhere in this codebase for non-trivial
  pricing logic in SQL). All three modes read the **already-shipped**
  Settings > Pricing & Rates / Equipment tables, no new config:
  - **Course mode**: a course is selected once at visit-creation time
    (`visits.course_rate_id`), every activity row's dive rate = that
    course's flat rate, everything else zeroed.
  - **Package mode**: real mechanism turned out simpler than the plan
    assumed — `dive_sites.linked_package_id` (an already-shipped
    Settings > Equipment > Dive Sites field, confirmed by reading that
    section's actual code) is a direct FK from site → package, so
    there's no fuzzy site-key text matching or "which package?"
    ambiguity to resolve; `visit_rate_selections` stays unused by this
    pass. Package-mode nitrox/15L add-ons are a **known, documented
    gap** — no equally clean dedicated mechanism exists for them (unlike
    tier mode) and no default Settings item to match against, so they
    stay manual entry in package mode.
  - **Tier mode**: dive rate from `rate_tiers` by cumulative non-
    cancelled dive count on the visit; nitrox/15L fees from the same
    table's `nitrox`/`tank_15l` rate types, gated by two per-row
    checkboxes (initialized from whether the saved fee is already > 0,
    not a separate schema column).
  - **Other charges** (fuel/marine tax/shark fee): resolved from the
    activity row's dive-site text → `dive_sites.fuel_estimate`/
    `shark_fee` → matched against `other_charges` (`Marine Tax`/
    `Shark Fee`/`Fuel Charge — Medium`/`Fuel Charge — High`, the real
    configured names, confirmed from `settings/pricing/constants.ts`),
    respecting each charge's own `per_dive`/`per_day` cadence — a
    `per_day` charge already present on another non-cancelled row for
    the same calendar date in the same visit is zeroed on the new row.
  - Verified end-to-end in all three modes against real seeded Settings
    data, including the per-day cadence dedup (added a second same-day
    dive at the same site and confirmed fuel/shark zeroed while the
    per-dive marine tax and tier-based dive rate both still applied
    correctly) and a course-mode flat-rate check.
  - `equipment_rental` is a **known gap**: neither Auto-Price nor the
    equipment-save action computes it from a diver's saved equipment
    selection — it's plain manual entry on the activity row. Matching
    `equipment_requested` items against `equipment_rental_rates` (same
    per_dive/per_day shape as the other_charges lookups already built)
    is real, scoped-out follow-up work.
- **Bill summary / deposits**: a local `billing.ts` (not
  `src/lib/payments.ts`, which reads already-saved rows — this
  computes a live in-progress breakdown from form inputs, a genuinely
  different shape). "Save (keep open)" upserts `payments` without
  closing the visit. **Real bug found and fixed**: the persisted
  `payments.balance` column didn't subtract deposits (only
  `grandTotal - discount - totalCollected`), while the UI's live
  display correctly did — caught by comparing the saved SQL value
  against what the screen showed after a ₱1,000 deposit + full cash/
  card payment (UI said ₱0 balance, DB said ₱1,000). Fixed by passing
  `depositsTotal` into `savePaymentOnly` too.
- **Checkout**: gated on balance ≤ 0 and every activity Completed or
  Cancelled. Closes the visit, upserts the final `payments` row,
  writes the `invoice_emails` snapshot in the exact spec shape (now
  the real, confirmed shape, not a guess — see the Billing Audit note
  below), increments `invoice_count`. **No email sent on checkout** —
  matches this app's established anti-auto-trigger convention (same
  reasoning as no auto-print anywhere). "Send Invoice" is a separate,
  explicit, user-clicked action that only sets the migration-008
  `email_sent_at`/`_by`/`_delivery_status` columns — actual delivery is
  a stub (`TODO: wire to Resend`); the user will set up a real provider
  separately later, by their own explicit choice mid-session (not
  something to revisit without asking).
  - **This closes a real loop**: Billing Audit's Reports tab (built
    earlier this session) was reading `invoice_snapshot` defensively
    against an unknown shape (`grand_total ?? grandTotal ?? total`).
    Now that Diver Detail's checkout is the only writer and always
    writes `grand_total` (snake_case), that fallback chain has been
    simplified to just `snap.grand_total` — verified Billing Audit
    still displays the real checked-out invoice correctly after the
    simplification.
- **Bill unlock**: calls the already-shipped `verify_billing_unlock`
  RPC (same pattern as Settings > Staff Access / Pricing & Rates) —
  never a plaintext password comparison. **Real bug found and fixed,
  the more serious one this session**: the unlock action's first
  version inserted directly into `audit_logs` from the client — but
  that table deliberately has **no client insert policy at all**
  (confirmed in `001_schema_and_rls.sql`: "rows are written only by the
  SECURITY DEFINER `log_audit_event()` trigger function"). The insert
  silently failed (RLS rejection, and the code wasn't even checking the
  returned error), so the unlock itself worked but left zero audit
  trail — caught by checking `audit_logs` directly after unlocking and
  finding no new row. Fixed properly with **migration 009**
  (`database/009_bill_unlock_audit_rpc.sql`): a new `log_bill_unlock`
  SECURITY DEFINER RPC, since the generic trigger can't produce a
  custom `action = 'bill_unlocked'` row with a real notes message
  anyway (it only logs raw `insert`/`update`/`delete`). Verified by
  checking out the same visit twice (unlock → re-checkout), which
  organically triggered Billing Audit's "flagged bill" (>1 invoice)
  logic for real, not synthetic seed data, and confirmed the unlock
  entry appears correctly in Billing Audit's Bill Unlock Log with the
  real notes text.
- **Signed documents viewer**: read-only, selectable by registration
  event, `diver_registrations` columns already correctly shaped (no
  schema change). Verified the core correctness property directly:
  switched to the diver's original registration and confirmed
  `accommodation` still showed the real value submitted at
  registration time ("Test Resort"), completely unaffected by a later
  edit to `divers.accommodation` via the Diver Detail profile form
  ("Coral Bay Resort (Updated)") — `diver_registrations` genuinely
  stayed immutable through every earlier stage's profile edits.
- **UI simplification used throughout**: "Add Activity" (and a few
  other multi-state-affecting actions like bill unlock) call
  `window.location.reload()` rather than patching local state — a
  deliberate simplification once `visit`/`activities` state was lifted
  from `VisitPanel` up to `DiverDetailClient` (needed so `BillSummary`
  always sees the same activities total, not a stale local copy) so
  that Save/Delete on individual rows stay instant while these
  rarer, multi-field-affecting actions just reload for guaranteed
  consistency instead of hand-syncing five different pieces of state.

**Staff (roster) + public Crew schedule view** — built end-to-end
2026-07-25, same session as the Divers close-out, per four scope
decisions confirmed with the user before starting (see `EnterPlanMode`
plan used for this build): build the crew schedule view now rather than
deferring to Scheduling (with token generation kept as its own reusable
piece); secretary "view own profile" means read-only, own row only;
add certifications + emergency contact fields beyond the original
schema; and staff `daily_rate` stays fully separate from Reports'
per-dive commission rate.

Research first established that `staff.html` (old app) is **not** a
roster page — it's a token-gated, no-login mobile view crew use to
check today's trips, with the token generated by Scheduling (which
doesn't exist yet). The real precedent for a roster page was
`settings.html`'s "Staff" tab. `public.staff` already existed from the
original Stage 1a schema pass (position/employment_status enums, RLS) —
this build was mostly new pages, not a big schema build.

- **Migration 010** (`database/010_staff_roster_fields.sql`): five
  `emergency_contact_*` text fields on `staff` (identical shape to
  divers' migration 008); new `staff_certifications` table
  (`staff_id`, `cert_name`, `expiry_date`, own `dive_center_id` —
  denormalized, matching this schema's established child-table
  convention rather than a join-based RLS check); a replaced
  `staff_select` policy — previously any tenant user could read every
  staff row, now split so a secretary only sees the row where
  `staff.user_id = auth.uid()` (owner still sees everything;
  `staff_owner_write` stays owner-only, unchanged, confirming the
  read-only-self-view answer); `generate_daily_staff_token` (SECURITY
  DEFINER, not owner-gated — any authenticated tenant user can trigger
  it, matching the old app's secretary-driven flow); `get_crew_schedule`
  (SECURITY DEFINER, `anon`-callable — the only anon-facing piece of
  this whole feature, mirroring the registration RPCs' "anon has zero
  direct table access, only a narrow gateway" pattern). Both new RPCs
  anchor "today" to Asia/Manila via `(now() at time zone 'Asia/Manila')`
  rather than trusting `current_date`/server timezone, matching every
  other day-boundary check in this app.
- **Staff page** (`src/app/(app)/staff/`): roster table (owner: full
  CRUD — add/edit/deactivate/delete; secretary: their own row only, no
  controls, matching the RLS split exactly), an inline expandable
  certifications section per staff member (add/list/delete, with an
  "Expired"/"Expires soon" badge within 30 days — same surfaced-signal
  style as Divers' medical/minor banners), and a Crew Code section
  (generate/regenerate today's 5-character token, visible and usable by
  owner or secretary alike). Adding/editing a `position = secretary` row
  offers a picker of existing secretary logins with no staff row yet
  (`loadUnlinkedSecretaryUsers`-style query) to link `staff.user_id` —
  this is what makes "secretary sees own profile" resolve to something
  real; Settings > Staff Access still owns creating the login itself,
  unchanged. `RELATIONSHIP_OPTIONS` is deliberately duplicated from
  `divers/[id]/constants.ts` rather than shared, matching this
  codebase's established small-helper-duplication precedent.
- **Public Crew schedule view** (`src/app/crew/`, outside `(app)/`,
  mirroring `src/app/register/`'s anon-accessible pattern): a token
  entry form, then trip cards assembled from the real (already-existing)
  Stage 1a scheduling schema — `schedules` → `boats` (name/captain),
  `schedule_sites` → `dive_sites` (a trip can have multiple sites, via
  the real join table — not the old app's single flat `dive_site` text
  field), `schedule_divers` grouped by `staff_id` → `staff` +
  `divers` (name/nationality/cert level/dives/age/group), a computed
  12L/15L/nitrox tank tally, and `schedules.is_joiner`/`joiner_boat_name`
  (already on the schema directly, so "we joined another boat" renders
  for free — the reverse direction, "another boat joined us," still has
  no signal anywhere, unchanged known gap). **Expected limitation**:
  since Scheduling isn't built, `schedules`/`schedule_divers` have no
  real writer yet, so this view shows nothing until either Scheduling
  ships or rows are seeded directly for testing (done for verification,
  see below) — not a bug.
- Verified end-to-end against a seeded test dive center: RLS confirmed
  via rolled-back simulated sessions (owner sees all staff/certs, a
  linked secretary sees only their own row/certs, an unlinked secretary
  sees nothing, a secretary's direct write attempt affects 0 rows) —
  then re-confirmed in a real browser: created a staff member with
  emergency contact + nitrox cert, added an expired certification
  (correctly badged), generated a crew code, logged in as an unlinked
  secretary (correctly saw "no profile linked" with no controls),
  linked a secretary via the owner UI, logged back in as that secretary
  (correctly saw only their own row, read-only), seeded a full day's
  schedule (multi-site trip, joiner info, two divers with different
  tank/nitrox flags) directly via SQL, hit `/crew` with the real code
  (rendered every field correctly, including the multi-site list and
  tank tally), and confirmed a wrong code correctly shows "invalid or
  expired." Test dive center, staff, schedule data, and both auth users
  deleted afterward — database confirmed back to just the real platform
  admin account.

**Real, non-code finding worth recording — a Supabase Auth (GoTrue)
gotcha, not a bug in this feature**: raw-SQL-inserting a test
`auth.users` row (the established `createAuthUser()`-style pattern this
project already relies on) failed to log in with a generic
`{"code":500,"error_code":"unexpected_failure","msg":"Database error
querying schema"}` — while a wrong password against a real, long-
standing account correctly returned a normal 400 `invalid_credentials`,
proving GoTrue itself was reachable and working, and the problem was
specific to the newly-inserted rows. Root cause, found by a full
column-by-column diff against a real working `auth.users` row: several
text columns (`confirmation_token`, `recovery_token`,
`email_change_token_new`, `email_change`, plus a few others) were left
`null` in the raw insert, but are `''` (empty string) on every real
row — GoTrue's own user-scanning query can't handle `null` there and
fails with that same generic 500, which looks nothing like a
null-column problem from the error message alone. **Lesson for any
future raw-SQL `auth.users` test-fixture insert**: explicitly set
`confirmation_token`, `recovery_token`, `email_change_token_new`,
`email_change`, `email_change_token_current`, `phone_change`,
`phone_change_token`, and `reauthentication_token` to `''`, never leave
them `null` — and make sure `identity_data` on the matching
`auth.identities` row includes `email_verified`/`phone_verified` keys
(also missing from a real row's shape otherwise). If a freshly-seeded
test login mysteriously 500s instead of just failing normally, diff
every column against a real user row before assuming the password hash
is wrong.

**Scheduling** — built end-to-end 2026-07-25, the last page in the
rebuild's agreed order and the one deliberately saved for hardest/last.
Absorbs the old app's `divers.html` group-creation/push-to-schedule
workflow, deferred there during the Divers build. Four scope decisions
confirmed with the user before designing this (see the approved plan):
skip the old app's separate staff/diver "clips" prep phase entirely
(assign directly per trip instead — `diver_staff_defaults` still
pre-fills a diver's usual staff as a one-off suggestion, not a whole
prepped-team carry-over); Boat Return writes zero-priced `activities`
rows only, no pricing logic in Scheduling at all (pricing happens later
via Diver Detail's existing Auto-Price flow); both group-creation flows
are in scope (pre-arrival registration-link groups and ad-hoc grouping);
migration 011 adds `groups.departure_date`/`notes`. The blueprint itself
barely specs this page ("Trip/schedule builder, boat & staff
assignment," Full/Full permissions) — almost everything concrete came
from reading `scheduling.html` (3,600 lines) and `divers.html`'s
group/push workflow in full this session, not from the blueprint.

Good news going in: **every scheduling table already existed in the
Stage 1a schema with full RLS** — `schedules`, `schedule_sites`,
`schedule_divers`, `groups`, `diver_staff_defaults`, `fuel_logs`,
`boats.capacity` were all real and simply unused by any writer yet. This
was genuinely greenfield application code, not a schema-risk build.

- **The rebuild does NOT replicate the old app's JSON-blob-in-
  `schedules.notes` pattern** — trip structure lives in the real,
  already-existing columns/joins (`schedule_sites` for multi-site,
  `schedule_divers` columns for per-diver staff/experience_type/is_15l/
  nitrox_requested); `schedules.notes` is free-text notes only, matching
  this project's standing "no JSON-blob structural state" rule.
- **`schedules.cancelled` is implemented for real** this time (a real
  column, unlike the old app's dead flag that had no Cancel button
  anywhere) — Cancel sets `cancelled=true`, keeps the row/assignment
  history, gated only on `!closed` (no zero-activities requirement,
  unlike Delete). Delete stays gated on `!closed AND zero activities
  rows`, same guard as the old app. Verified both: cancel persisted
  correctly and disappeared from `/crew` (which already filters
  `cancelled=false`) while staying visible in Scheduling's own day view;
  delete correctly blocked by a seeded `activities` row with the right
  error message, then succeeded once the blocker was removed, with
  `schedule_sites`/`manifests` confirmed cascade-deleted via direct SQL.
- **Trip builder** (`schedules.data.ts`/`actions.ts`, `TripBuilderPanel`):
  date picker (defaults to `todayManila()`), boat mode (Own Boat / Join
  Ride / Rental — the latter two both just set `is_joiner=true` with a
  free-text name, an accepted cosmetic gap since re-opening a Rental
  trip shows it as Join Ride; confirmed with the user this doesn't need
  a schema change since neither currently drives different behavior),
  multi-site selection, departure time, notes. `schedule_sites` is
  deleted-and-reinserted fresh on every save (no independent identity to
  preserve, same reasoning as `schedule_divers`) — verified a multi-site
  edit doesn't orphan old rows. The `schedules_create_manifest` trigger
  (already existed from Stage 1a) fires correctly on every new trip —
  confirmed a matching `manifests` row exists after insert, without
  Scheduling ever inserting into `manifests` itself.
- **Diver assignment — the core loop** (`DiverAssignmentPanel`,
  `ExperienceTypeModal`): search divers by name or bulk-pick a whole
  group, tag `experience_type`(+course) only for divers who don't
  already have a qualifying open `visits` row (reuses the exact insert
  shape from `divers/[id]/actions.ts`'s `createVisit`, written fresh
  here per this codebase's established no-cross-page-action-imports
  convention), assign staff/15L/nitrox per diver, `schedule_divers`
  deleted-and-reinserted fresh on every save. `diver_staff_defaults`
  upserts or clears per an explicit per-diver "remember this pairing"
  toggle. Verified: a diver with an existing open visit auto-adds using
  that visit's real experience type (no modal); a diver with none
  triggers the tag modal; a second save doesn't duplicate/orphan
  `schedule_divers`; `diver_staff_defaults` upserts/clears correctly.
- **Non-blocking warnings** (`WarningsBanner`) — capacity (skipped if
  `boats.capacity` is null), 1:4 staff:diver ratio (green/orange/red),
  same-day double-booking (diver/staff/boat — necessarily date-level
  only, since `schedules` has no trip-duration column for true
  time-range overlap detection), mixed cert-level/nitrox within one
  staff group. Verified all four render at the right thresholds and
  never block Save — confirmed by seeding 5 divers onto a
  capacity-4 boat under one staff member (correctly showed "5/4" and the
  capacity warning) and cross-referencing a diver/boat already booked on
  a second same-day trip (correctly flagged on both).
- **Confirm recap** (`ConfirmPanel`) — read-only tank tally + per-staff
  diver groupings, plus a link out to `/staff` for crew-code generation
  (no separate token-generation trigger built here — Staff's existing
  "Generate Today's Crew Code" button already covers it, confirmed
  working end-to-end against a real Scheduling-created trip).
- **Boat Returned** (`markBoatReturned`) — gated on `!closed && !cancelled
  && departure time has passed` (Manila-anchored comparison, same
  day-boundary convention as everywhere else in this app). Per diver
  with a resolvable open visit, inserts one zero-priced `activities` row
  per dive site (`status:"completed"`, pre-filling `dive_site`/
  `staff_name`/`schedule_id` — all already-known at this point, unlike
  Diver Detail's blank-slate manual-entry flow) — confirmed these rows
  are visible and Auto-Priceable from Diver Detail afterward. If a
  diver's open visit can't be resolved (e.g. closed out via Diver Detail
  between assignment and return), that diver is skipped and named in a
  warning rather than silently dropped or auto-creating a visit outside
  the established explicit-creation pattern. For non-joiner trips with
  liters entered: one `fuel_logs` row (matching Settings > Equipment's
  existing summing semantics) plus a real decrement of
  `dive_centers.fuel_gasoline_level`/`fuel_diesel_level` — verified the
  level went from 100→80 after a 20-liter return, and confirmed
  join-ride trips never write `fuel_logs` even when liters are entered.
  Sets `schedules.closed=true` (a real column, not a JSON flag).
- **Groups** (`GroupsPanel`) — both flows built. Registration-link
  groups (`group_name`, `leader_name`, `arrival_date`, `departure_date`,
  `expected_count`, `notes` — the last two via migration 011) generate a
  real `/register?dc=<id>&group=<groupId>` link; verified the link opens
  the actual registration wizard pre-associated with the group ("0/6
  registered"). Ad-hoc grouping (name + 2+ existing divers) bulk-sets
  `divers.group_id`; verified via direct SQL. Deletion re-checks
  blockers **server-side** (schedule_divers rows / open unpaid visit /
  activities rows, named per diver) — never trusts a client-only
  pre-check — verified a group with two divers holding open unpaid
  visits was correctly blocked with both names and reasons listed, then
  succeeded once a clean group (0 members) was deleted instead.
- **Cross-page regression pass, and one real bug found doing it**:
  Dashboard's "Boats Today" widget, Boat Manifest's trip
  dropdown/District/Port editing, and `/crew`'s full render (multi-site,
  staff groupings, tank tally) were all confirmed working against real
  Scheduling-created data — but `boat-manifest/data.ts`'s
  `loadTripsForDate` and two of `dashboard/data.ts`'s `schedules`
  queries **had no `cancelled` filter at all**, because `cancelled` was
  a dead, never-written column before this session. Once Scheduling
  made it real, a cancelled trip was still showing up in Boat Manifest's
  trip picker and Dashboard's "Boats Today"/join-ride-alert queries.
  Fixed in place (`.eq("cancelled", false)` added to all three queries)
  and re-verified — the cancelled test trip disappeared from both pages
  immediately, the two real trips still showed correctly. `/crew`'s
  `get_crew_schedule` RPC already filtered `cancelled=false` from when
  it was built during the Staff session, so it needed no fix.
- **Dead-code audit finding**: `getStaffOptions`/`getCourseRateOptions`
  (thin `actions.ts` wrappers around the `data.ts` loaders, written
  anticipating a client-side refetch need) were never actually called —
  `staffOptions`/`courseRates` end up loaded once server-side in
  `page.tsx` and passed down as static props instead, since neither
  changes mid-session often enough to need live refetching. Found by the
  usage-count pass (retrospective #25's lesson), removed along with
  their now-unused `loadStaffOptions`/`loadCourseRateOptions` imports.

**Testing-technique note, not a bug**: cleaning up the test dive center
hit `schedules_created_by_fkey` (a plain FK, no cascade, from
`schedules.created_by` to `users.id`) when deleting `dive_centers` in
one transaction — even after explicitly nulling `created_by` earlier in
the *same* transaction, the delete still failed against that FK.
Running the `update ... set created_by = null` as its own committed
statement first, then deleting `dive_centers` separately, worked cleanly.
Root cause not fully pinned down (possibly how Postgres orders
multi-table cascades triggered by one parent delete), but confirmed as a
cleanup-script-ordering quirk, not a schema or application bug — no
production code path ever deletes a `dive_centers` row this way. Worth
remembering for any future test cleanup: if a delete inside a dive
center hits an unexpected FK from a column that references `users`
directly (not just `dive_center_id` cascades), null it out in its own
prior transaction, not the same one as the final delete.

### Known gaps (tracked in `aquadesk-app/KNOWN_GAPS.md`, none blocking)

1. Dashboard's "another boat joined us today" alert — still no signal
   captured anywhere for that direction; Scheduling's `schedules` table
   has `is_joiner`/`joiner_boat_name` for "we joined them," confirmed
   during this build, but nothing for the reverse direction. Would need
   a real design call (a new column/flow) to close, not something to
   invent unilaterally.
2. Settings has no page to edit a dive center's name/phone/address/logo
   after creation — needs a real design call (which tab? logo needs its
   own Storage bucket) not made unilaterally.
3. Boat Manifest has no offline support, unlike the blueprint's stated
   requirement — the live app doesn't have it either (no reference to
   match), and building it for real is a whole-app architecture decision.

### Suggested next step

**The rebuild's originally-agreed page-by-page build order is complete**:
Settings → Boat Manifest → Reports → Divers → Staff → Scheduling, all
built, verified in a real browser, and committed. There is no next page
implied by prior planning — whatever comes next is either a refinement
of what's already built, closing one of the documented known gaps below,
or new scope the user brings, not something to assume unilaterally.

Known, documented gaps worth revisiting whenever a future session
touches these areas: package-mode nitrox/15L add-on pricing (Divers, no
dedicated mechanism, stays manual entry), `equipment_rental` never
auto-computed from a diver's saved equipment selection (Divers, also
manual entry), Diver Detail only ever shows the diver's single most
recent visit (no full multi-visit history browser), the Crew schedule
view's join-ride info is limited to `schedules.is_joiner`/
`joiner_boat_name` (the "we joined them" direction only — "another boat
joined us" still has no signal anywhere), and Join-Ride/Rental boats
have no persisted distinction from each other (Scheduling, accepted
cosmetic gap) — none of these were blocking for their respective
builds, all called out inline in the write-ups above.

Implementation rules that governed Reports, Divers, Staff, and
Scheduling across this multi-session arc, worth carrying forward into
any future page/feature with similar shape:
1. Any tab/panel with its own local add/edit/status-transition state
   that a parent could conditionally unmount needs to either never be
   unmounted (the always-mounted-with-`hidden`-class pattern every
   Reports tab used) or propagate every mutation back up to the
   parent's copy — never mix "child owns the state" with "parent
   conditionally unmounts the child." Diver Detail took this further:
   `VisitPanel`'s `visit`/`activities` state was lifted all the way up
   to `DiverDetailClient` (not just kept mounted) because `BillSummary`
   needed to read the exact same activities total live, not a stale
   local copy one level down — lift shared derived state to the lowest
   common ancestor that actually needs it, don't just keep components
   mounted and hope they stay in sync.
2. Whenever a `key` prop is derived from state that a function also uses
   to conditionally update other state, gather every fetch with
   `Promise.all` and apply every resulting `setState` back-to-back —
   never let a key-changing `setState` sit in the same function as a
   slower `await` for data that same key change will cause to be read.
3. Before inserting into any RLS-protected table directly from a Server
   Action, check whether that table actually has a client insert policy
   at all — some tables (like `audit_logs`) are deliberately
   insert-only-via-trigger-or-RPC, and a rejected insert fails silently
   unless the returned `error` is actually checked. Grep the table's RLS
   policies in `001_schema_and_rls.sql` (and later migrations) before
   writing the insert, not after it silently does nothing.
4. **New this session**: turning on a previously-dead/never-written
   column (like `schedules.cancelled`, inert since Stage 1a) can break
   *other* pages that read the same table without expecting that column
   to ever be non-default — always grep every existing consumer of a
   table before shipping the first real writer for a column that used
   to be a no-op, not just the page you're actively building.

**Standing constraint for every remaining page** (see memory:
future-live-data-migration): this is multi-tenant and every dive
center's live production data will eventually be migrated in. Don't
design schema or pages only for what a fresh test dive center would
produce — think about whether real historical data from every live dive
center could actually fit.

## Working practices established (cumulative, apply from session start)

- **Every schema/RLS claim gets tested with a real simulated session**
  (`SET LOCAL ROLE authenticated; SET LOCAL request.jwt.claim.sub = '<uuid>'`
  inside a rolled-back transaction), not just "the policy looks right."
  `postgres`/service-role bypasses RLS entirely — never trust a check run
  as that role as evidence a policy works for real users.
- **Test data is always cleaned up after verification** — create a test
  dive center, run the flow, delete it (`dive_centers` cascade-deletes
  almost everything; `auth.users` needs explicit cleanup since it's
  outside the `public` schema cascade). The DB should be empty except
  real accounts between sessions — confirmed clean as of this session end
  (only the `aquadeskonline@gmail.com` platform admin remains).
- **Direct SQL access pattern**: a small Node + `pg` script in the scratch
  tooling dir (`AQUADESK_DB_URL=<pooler connection string> node run-sql.js
  <file.sql>`), wrapped in `begin`/`commit` inside the SQL file itself so a
  failed migration never leaves partial state. Reuse this pattern rather
  than re-deriving it — a `createAuthUser()` helper (raw SQL insert into
  `auth.users` + `auth.identities`, bcrypt via `crypt()`/`gen_salt('bf')`)
  is also worth reusing verbatim; the Admin API (`auth.admin.createUser`)
  is unreliable when called from a standalone script (see retrospective).
- **Browser testing in this environment**: the Browser pane does not
  actually composite frames in this sandbox — `computer.left_click` by
  coordinate is unreliable and `screenshot` always fails ("pane not
  displayed"). Use `javascript_tool` to call `.click()` on elements
  directly, and the `form_input` tool for filling fields — both work
  reliably. For anything that needs a genuine `blur` event (onBlur-
  triggered saves), a raw `.blur()`/`dispatchEvent('blur')` call does
  **not** reliably reach React's handler — use the `computer` tool to
  click a different focusable element instead (see retrospective).
- **First navigation to a freshly-touched route** can eat a click event
  due to Next.js dev-server Fast Refresh remounting the component
  mid-navigation. If a click seems to silently do nothing on the very
  first hit of a route this session, retry once before assuming a bug.
- **Client components need pure constants in their own `constants.ts`
  file, never in the `server-only` data-fetching file** — even a value
  that never touches cookies still poisons the whole module for any
  client import. Do this from the start of every new tab/page, not just
  after hitting the build error once (see retrospective — this recurred).
- **Before writing any insert/update against an existing table, verify
  its real column names and types** (`select column_name, data_type from
  information_schema.columns where table_name = 'x'`, or read the
  migration file directly) — don't trust a table's apparent shape at
  face value. This has now caught real mismatches on `rate_tiers`,
  `dive_sites`, `boats`, `course_rates`, `expenses.category`,
  `rental_gear_records.status`, `join_ride_records.status`, and
  `govt_fees` — six-plus separate instances of the same root cause (the
  Stage 1a schema pass named fields from the blueprint's shallow
  inventory, not the live app's real usage). Treat this as the default
  assumption for every remaining table, not a surprise each time.
- **Before concluding "this table/feature has no live-app precedent" and
  designing one from scratch, grep *all* the old HTML reference files for
  that table/column name** (`grep -rln "table_name" D:\Rebuild\*.html`),
  not just the one page currently being built. A table's real owner page
  is not always the one its name suggests — `govt_fees` looked like a
  Settings concern and was actually a Reports one (see retrospective).
- **A Reports tab that manages its own post-load mutation state locally
  (row edits, refetch-after-save) must never be conditionally
  unmounted/remounted by its parent** (e.g. on tab switch) — `Overview`/
  `Staff`/`Join Ride` are all kept permanently mounted in
  `ReportsClient.tsx` once loaded, visibility toggled via a `hidden`
  class, specifically to prevent this. Any new Reports tab built the
  same way (own local state, not lifted to `ReportsClient`) needs to go
  in that same always-mounted block (see retrospective #18).
- **A dead-code audit needs a usage-count pass per exported symbol/type
  field, not just a grep for removed/renamed symbol names.** Grepping
  for old symbol names (the method used through most of this project)
  only catches leftover references to things that no longer exist — it
  gives false confidence about a field that's still correctly defined
  and populated but never actually *read* by any consuming code, since
  the symbol name genuinely does appear at its definition/population
  site. Before declaring a feature's dead-code audit clean, run
  `grep -rl "\bsymbolName\b" <dir> | wc -l` for every exported
  function/type/constant added that session and look closely at
  anything at or near 1 (only its own definition references it) — see
  retrospective #25, which found three real instances this way after a
  symbol-grep-only pass had already declared the same feature clean.
- **Before writing any client-side insert against an RLS-protected
  table, check whether that table actually has an insert policy at
  all** — some tables (`audit_logs` is a confirmed example) are
  deliberately insert-only-via-trigger-or-RPC by design, and a
  Supabase insert rejected by RLS fails silently unless the returned
  `.error` is actually checked. Grep the table's policies in
  `001_schema_and_rls.sql` and later migrations before writing the
  insert, not after discovering it silently did nothing (see
  retrospective #23).

## Retrospective — mistakes made, so they aren't repeated

The point isn't the fix (already applied) — it's recognizing the
*pattern* early next time, in whichever session encounters it.

### Session 1 (2026-07-23)

1. **A SECURITY DEFINER function's own internal queries are not exempt
   from RLS on the tables they touch unless the function itself is
   SECURITY DEFINER — but a raw subquery *inside an RLS policy* is a
   different thing and is NOT automatically protected.** The first cert-
   card Storage policy did
   `exists (select 1 from public.divers d where ...)` directly inside a
   `storage.objects` policy's `WITH CHECK`. That subquery runs as the
   *calling* role (anon), so it was itself blocked by `divers`' own RLS —
   the existence check silently always returned false for anon, no matter
   what. Symptom looked like "the diver doesn't exist" when it obviously
   did. **Lesson: any RLS policy that needs to check another RLS-protected
   table must go through a `SECURITY DEFINER` helper function — never a
   raw subquery against a table with its own RLS.**

2. **`storage.buckets` has RLS enabled by default with zero policies out
   of the box.** Creating a bucket via `insert into storage.buckets` does
   not make it visible to anon/authenticated — the Storage API can't even
   resolve the bucket's existence, and the resulting error
   (`"new row violates row-level security policy"`) is **identical** to
   an `objects`-table RLS rejection, with nothing pointing at buckets as
   the actual cause. This cost the most debugging time that session.
   **Lesson: every new Storage bucket needs an explicit `storage.buckets`
   SELECT policy before anything else will work for non-service-role
   callers — check this first, not last, next time a bucket doesn't
   work.**

3. **`upsert: true` on a Storage upload needs an UPDATE *and* a SELECT
   policy on `storage.objects`, not just INSERT — even when no row
   actually conflicts.** Postgres/Storage's upsert path apparently
   validates against both regardless of whether a conflict occurs.
   Diagnosed by testing the identical upload without `upsert` (worked with
   INSERT alone), which isolated the variable. **Lesson: if an anon
   upsert-capable Storage flow is needed again, write all three policies
   (INSERT/UPDATE/SELECT) up front instead of discovering the gap one
   policy at a time.**

4. **A generic trigger that assumes every table shares a column shape will
   break on the one table that doesn't.** The audit-log trigger assumed
   every audited table has a `dive_center_id` column — `dive_centers`
   itself only has `id`. Caught immediately by the RLS test harness
   inserting a test dive center. **Lesson: when writing one trigger
   function to cover multiple tables, explicitly check for the table(s)
   that don't fit the general pattern rather than assuming uniformity.**

5. **An audit trail must never have a hard foreign key to the things it
   records.** `audit_logs.performed_by → users.id` broke the moment a
   platform admin (who has no `users` row by design) performed an audited
   action. `audit_logs.dive_center_id → dive_centers.id` broke the moment
   a dive center was deleted (its own delete's audit entry couldn't
   reference the now-gone row). Fixed by dropping both FKs entirely —
   audit logs are a historical record and must survive the deletion of
   their subjects. **Lesson: audit/history tables should generally not
   have enforced FKs to mutable/deletable entities.**

6. **A test harness's own transaction-rollback helper silently invalidated
   part of a test.** The RLS test script's `asUser()` helper always rolled
   back afterward (correct, for testing without leaving residue) — but it
   was reused to *create* a fixture row that a later test then tried to
   verify immutability on. The row was never actually committed, so the
   "immutability" test passed for the wrong reason (0 rows matched, not
   "correctly blocked"). Caught by adding diagnostic row-count logging
   when a result looked suspicious. **Lesson: never use a
   rollback-wrapped test helper to create fixtures another test depends
   on — commit fixtures directly, only wrap the actual assertion under
   test.**

7. **The old live app has its own real bugs — don't silently reproduce
   them.** `register.html` collects an emergency contact WhatsApp number
   (required field) but never actually includes it in the submitted
   payload — a genuine bug in production, found only by checking the
   actual field list saved to the database, not just the schema doc.
   Replicated it once by accident (missing column entirely), caught it,
   fixed it properly (added the column, the RPC parameter, and the
   client-side payload field). **Lesson: when the live app is the
   "behavioral reference," match its intent and visible behavior — not
   verbatim bugs it happens to have. When in doubt about whether
   something is a bug vs. intentional, it usually shows up as "the UI
   collects X but X is never read again anywhere."**

8. **Nested-object React state updates from a plain closure go stale
   under rapid input.** `setField("medicalAnswers", {...form.medicalAnswers,
   [id]: value})` reads `form` from the render closure — two such calls
   firing in the same batch (e.g., answering two medical questions
   quickly) both read the same stale snapshot, so the second call's
   result silently overwrites-and-loses the first. Caught by scripting a
   rapid double-click in the browser test rather than clicking slowly by
   hand. Fixed with dedicated `setMedicalAnswer`/`setEquipmentSelection`
   helpers using the functional `setForm(f => ...)` form. **Lesson: any
   state update that merges into a nested object/map (not a flat field)
   must use the functional updater form, always — a plain closure read is
   only safe for flat, independent fields.** (See session 2, item 11 below
   — this lesson turned out to be scoped too narrowly.)

9. **First-pass schema design from the blueprint's inventory alone had
   real gaps and one wrong assumption** — not caught until actually
   reading `register.html`'s real field list: `privacy_notice` was
   assumed per-dive-center, it's actually one global singleton row (`id
   boolean primary key, check(id)`); `equipment_rental_rates`'s real
   column is `item_name` not the guessed `equipment_name`; and
   `divers`/`diver_registrations` were missing `email`, `phone`,
   `whatsapp`, all four emergency-contact fields, all four insurance
   fields, `food_allergies`, `nitrox_certified`, `last_dive_date`,
   `waiver_opened`, `duplicate_email_flag` entirely. **Lesson: the
   blueprint's table inventory is a starting sketch, not a source of
   truth — always cross-check against the actual live-app field list
   (insert/update payloads, not just `select('*')` calls) before treating
   a table's schema as final, especially for any table the blueprint
   flagged as "needs deeper look."** (This pattern recurred constantly in
   session 2 — see the "Working practices" section above, now promoted
   to a standing default rather than a one-off lesson.)

### Session 2 (2026-07-24)

10. **A lesson written down after the first time it bit didn't get
    applied to this session's own very next task.** After hitting the
    client/server-only import build error in Settings > Pricing & Rates
    (a client component importing a runtime constant from a `server-only`
    data file) and writing the fix into this file, the identical error
    was hit again in Settings > Equipment (`TanksSection.tsx` importing
    `TANK_TYPES` from `data.ts`) before remembering to split constants out
    from the start. **Lesson: a lesson recorded for "next time" must also
    be applied to the *rest of the current session* — re-read this file's
    own recent entries before starting each new tab/page within the same
    session, don't just write for a future session.**

11. **An established lesson about stale closures was scoped too narrowly
    and didn't prevent a new instance of the same root cause in a
    different shape.** Session 1's lesson (item 8 above) was about merged
    *object* state updates specifically. Session 2 hit the same underlying
    bug — a handler reading state from a stale render closure — in a
    completely different shape: Settings > Integrations' toggle-then-Save
    flow, where clicking "Yes" and "Save" in quick succession let Save's
    closure read the pre-toggle boolean value, silently saving the wrong
    thing with no error. Fixed with refs mirrored alongside the state
    setters. **Lesson: the real rule is broader than "use functional
    updates for merged objects" — *any* handler that might fire before
    React commits a preceding state update (rapid clicks, a toggle
    immediately followed by Save) needs either a functional state update
    or a ref mirror, for any field type, not just nested objects. Treat
    every "toggle/type then immediately Save" UI pattern as needing this
    defensively, not just after a bug shows up in testing.**

12. **Wrote a real "fix" for a bug that didn't exist, because the current
    schema's own infrastructure wasn't checked first.** While building
    Boat Manifest, the live app's code appears to never insert a
    `manifests` row anywhere — matching that, the assumption was that
    District/Port edits would silently no-op the first time a trip's
    manifest was opened, so an upsert was written to "fix" it. Testing
    then revealed a database trigger from the *earlier* session
    (`create_manifest_for_schedule()`, `001_schema_and_rls.sql`) already
    auto-creates a `manifests` row the instant a schedule is created —
    specifically *because* the live app never does. The upsert was solving
    a non-problem; the real bug was elsewhere (the trigger's
    `last_edited_at` defaulting to `now()` at creation made an "edited"
    indicator fire for every trip, not just genuinely-edited ones).
    **Lesson: before writing a workaround for something "the live app
    doesn't do" (an insert path, a computed field, a default), grep the
    *current* schema/migrations for triggers, defaults, and functions
    that might already cover it from a prior session — this project has
    accumulated real infrastructure across sessions that isn't always
    obvious from re-reading the old app alone.**

13. **Shipped a wrong feature because a "no live-app precedent" search
    only checked the page being built, not the other reference files.**
    `govt_fees` had no UI anywhere in `settings.html`, so a rate/config UI
    was designed and built from scratch for it in Settings > Pricing &
    Rates, reasoning that the table existed and needed *some* management
    path. Its real usage was sitting in `reports.html` the entire time — a
    daily collection log, not a rate config — not discovered until
    building Reports later the same session, by which point the wrong
    Settings feature had already been reported as done and had to be
    reversed (with the user's explicit confirmation first, since it meant
    undoing shipped work). **Lesson: before concluding "this table has no
    live-app precedent, I'll design a UI from scratch," grep *all* old
    HTML files for that table/column name
    (`grep -rln "table_name" D:\Rebuild\*.html`), not just the page
    currently being built. A table's real owner page is not always the
    one its name suggests.**

14. **(Testing technique, not a code defect) Synthetic `.blur()` /
    `dispatchEvent('blur')` calls via `javascript_tool` don't reliably
    trigger React's `onBlur` handler in this browser environment** — blur
    doesn't bubble, and React's delegated listener setup needs a genuine
    focus-change sequence, which a same-tick scripted `.focus()` +
    `.blur()` doesn't reliably produce. Cost three attempts (raw
    dispatchEvent, direct `.blur()` call, finally a real `computer` click
    on a different element) before landing on what actually works while
    verifying Boat Manifest's District/Port autosave. **Lesson: for
    verifying any onBlur-triggered save, use the `computer` tool to click
    a genuinely different focusable element — don't reach for a scripted
    blur call, same category as the already-documented click/form_input
    guidance for this environment.**

### Session 3 (2026-07-25)

15. **(Testing technique, not a code defect) A page read immediately after
    triggering a client-side state update/remount can return a stale
    snapshot even though the server round-trip already completed
    correctly.** While verifying the date-range-scoped paid-marking
    behavior, narrowing the date range and re-reading the page
    immediately afterward repeatedly showed the *previous* (wider-range)
    rows — even though `read_network_requests` confirmed the server had
    already returned the correctly narrowed data. Switching to a
    different Reports tab and back made the correct data appear
    immediately. Root cause was never pinned down precisely (most likely
    just needed one more paint cycle than the immediate next tool call
    allowed for), but it was confirmed to be a read-timing artifact, not
    a real bug — the underlying data was verified correct via direct SQL
    at every step. **Lesson: if a page read right after a client-side
    state change looks stale, don't conclude there's a data bug from that
    alone — switch tabs (or otherwise force a remount) and re-read before
    trusting the result; confirm real bugs against the actual persisted
    data (SQL), not just a single DOM snapshot taken immediately after
    the triggering action.**

16. **A feature can get fully redesigned by the user in the same session
    it first ships, and that's a normal part of the workflow, not a sign
    the first version was wasted.** Staff Activity Summary shipped once
    against the live app's own model (whole-calendar-month buckets, one
    aggregated row per staff), then the user came back with a detailed
    written spec (automatic divemaster pay, a configurable no-formula
    ratio bonus, manual-only instructor pay, real date-range-scoped
    paid-marking) that superseded it entirely within the same session —
    explicitly because the live app's model has exactly those
    limitations. Handled via `EnterPlanMode` (schema migration + Settings
    + Reports all touched) rather than editing ad hoc, since the second
    version needed a real migration (`007_staff_commission_rates.sql`,
    dropping `period_month` for per-line `activity_date`) and two
    genuinely ambiguous business-logic calls (flat vs. per-staff rate;
    bonus formula vs. manual) that only the user could answer — confirmed
    via `AskUserQuestion` before writing any code. **Lesson: don't treat
    "the user is asking me to change something I just built minutes ago"
    as a signal something went wrong — it's normal iteration. What
    matters is still applying the same rigor (plan mode for real
    architectural changes, ask when a business rule is genuinely
    ambiguous) as any other feature, not rushing to preserve the earlier
    version's shape out of sunk-cost.**

17. **Dropping a column from a table that more than one page reads
    silently breaks the *other* pages, and a Supabase query error on a
    dropped column doesn't surface as a visible crash — the destructured
    `{ data }` just comes back `null`/`undefined` and every existing
    `?? []`/`?? 0` fallback quietly swallows it.** Migration `007` dropped
    `staff_commission_records.period_month`, but `reports/data.ts`'s
    `loadOverviewData` (a *different* function in the same file from the
    Overview tab, not touched by the Staff Activity Summary rewrite) had
    its own separate query still filtering `.eq("period_month", ...)`.
    Every manual Staff Activity Summary test that session looked correct
    in isolation — this only surfaced because the routine post-change
    grep for leftover references to removed symbols (a standing practice,
    see the "Working practices" section above) turned up `periodMonth`
    still in use, one function away from the one actually being edited.
    Fixed by switching that query to the same `activity_date` range
    filter and re-verified via a fresh seed that "Staff Commissions
    (Paid)" on Overview reflected the real number instead of a silently
    swallowed ₱0. **Lesson: after any migration that drops or renames a
    column, grep the *whole* codebase for that column/field name — not
    just the files intentionally being rewritten — since Supabase query
    errors on a bad column name fail silently into empty-looking data
    rather than a visible error, and a plausible-looking ₱0 is easy to
    mistake for "no data yet" rather than "the query is broken."**

18. **A tab component that manages its own local state after a mutation
    (patch-in-place or refetch) will silently lose that state if its
    parent conditionally unmounts/remounts it on tab switch.**
    `ReportsClient.tsx` rendered each Reports tab via a ternary chain
    (`tab === "staff" ? <StaffTab/> : tab === "join" ? <JoinRideTab/> :
    ...`), so switching to a different tab and back was a real
    unmount+remount, not just a visibility change. Both `StaffTab` (row
    edits patched via local `setRows`) and `JoinRideTab` (a `refresh()`
    that refetches and calls local `setRecords`) update their *own*
    state directly and never call back up to update `ReportsClient`'s
    `staffData`/`joinData`. So a remount re-initializes from whatever
    `ReportsClient` last fetched — silently reverting a just-saved change
    the instant the secretary switched tabs and switched back. Caught by
    adding a Join Ride record, confirming it persisted via direct SQL,
    but seeing it vanish from the UI after an Overview→Join Ride tab
    round-trip. Fixed by never unmounting a tab once it's loaded data —
    `ReportsClient` now keeps `OverviewTab`/`StaffTab`/`JoinRideTab`
    permanently mounted and toggles visibility with a `hidden` class
    instead of conditional JSX. **Lesson: for any tab that owns
    post-load mutation state locally rather than lifting it to the
    parent, either (a) never let the parent unmount it, or (b) always
    propagate every mutation back up to the parent's copy too. Don't
    mix "child owns the state" with "parent conditionally unmounts the
    child" — pick one.**

19. **(Testing technique, not a code defect) Two more read/observe
    pitfalls in this browser environment, on top of the ones already
    documented (items 14–15).** First: `read_console_messages` appears
    to return an accumulated buffer across page navigations within the
    same tab, not just the current page's live console — a genuinely
    stale compile-error message (from *before* a dev-server restart that
    had already fixed it) kept reappearing on every check, long after the
    server logs (`preview_logs`) confirmed the error no longer occurred.
    When a console error contradicts what the UI is visibly doing
    correctly, trust the functional behavior and `preview_logs` over
    `read_console_messages`. Second: auto-triggering `window.print()`
    from a Server Action's success callback opens a native, blocking
    print dialog that hangs the whole automated browser pane (not just
    that tab) until dismissed with Escape — avoid auto-print in any flow
    that will be exercised by browser automation; even setting that
    aside, an unreviewed auto-print is arguably bad UX for a real user
    too (see the Join Ride entry above), so prefer an explicit "Print"
    button the user clicks once they've reviewed the generated content.

20. **A `key`-based remount and the state update that feeds the remounted
    instance's initial data must commit in the same render batch — if
    the `key` changes first, the remount grabs stale data and the fresh
    data arriving a moment later is silently ignored.** `ReportsClient`'s
    `applyDateRange` called `setAppliedFrom`/`setAppliedTo` (which
    `StaffTab`/`ExpensesTab` use as `key={appliedFrom|appliedTo}` to
    force a clean remount on date-range change) partway through a chain
    of sequential `await`s — for tabs fetched *after* that point in the
    function, the remount had already happened by the time their fresh
    data arrived, and `useState`'s initializer only runs once per mount,
    so the fresh prop was dropped without any error. This looks identical
    in symptom to item 18's tab-unmount bug (data that was clearly saved
    server-side just doesn't show up in the UI) but is a genuinely
    different mechanism — item 18 was about a component unmounting
    entirely and losing its own locally-patched state; this one is about
    *state-update ordering* inside a single async function, where the
    component never unmounts unexpectedly, but the remount it deliberately
    triggers races against its own data fetch. Caught by widening the
    date range to include a deliberately-out-of-range seeded expense and
    watching it not appear after Apply — confirmed via `read_network_requests`
    that the server response *did* include it, proving the bug was
    purely client-side ordering, not a query bug (same diagnostic
    approach as item 18). Fixed by switching `applyDateRange` to
    `Promise.all` every tab's fetch first, then calling every `setState`
    together afterward in one synchronous batch. **Lesson: whenever a
    `key` prop is derived from state that a function also uses to
    conditionally update other state, gather every fetch with
    `Promise.all` (or otherwise ensure no `await` sits between them) and
    apply every resulting `setState` back-to-back — never let a
    key-changing `setState` sit in the same function as a slower `await`
    for data that same key change will cause to be read.**

21. **(Testing technique, not a code defect) `read_page` with
    `filter: "interactive"` can fail to enumerate plain `<input>` /
    `<select>` / `<textarea>` elements even though they're genuinely
    present and rendered.** While testing Join Ride's "Add Join Ride
    Record" form, clicking the button to open it left `read_page`
    showing only the surrounding buttons — no date/company/quantity
    fields at all, looking exactly like the form had silently failed to
    open. `get_page_text` immediately after showed every label and
    field correctly, and a direct `document.querySelectorAll('input,
    textarea, select')` via `javascript_tool` returned all eleven form
    elements with correct values. The form was never broken — `read_page`
    just didn't surface those specific elements under the `interactive`
    filter that time. **Lesson: if `read_page` (interactive) comes back
    missing form fields you expect to see, don't conclude the UI failed
    to render — cross-check with `get_page_text` or a direct
    `javascript_tool` DOM query before treating it as a bug. This is a
    distinct failure mode from the already-documented click-timing and
    console-buffering quirks (items 14, 19) — same family of "don't
    trust the first read in this environment," different tool.**

### Session 3, continued (2026-07-25 — Divers + Diver Detail)

22. **A persisted total and its live on-screen equivalent must be
    computed from the exact same inputs, or they'll silently diverge.**
    Diver Detail's Bill Summary correctly showed `balance = grandTotal -
    discount - depositsTotal - collected` on screen, but the Server
    Action that persisted it (`savePaymentOnly`) computed `balance =
    grandTotal - discount - collected` — forgetting `depositsTotal`
    entirely, since deposits were added to the component after the
    balance formula was first written and the persisted-value formula
    was never revisited. Caught immediately by comparing the saved SQL
    row against the on-screen value after a real ₱1,000 deposit + full
    payment (screen: ₱0 balance; DB: ₱1,000) — not by code review, by
    the standing practice of verifying persisted values via direct SQL
    rather than trusting the UI alone. **Lesson: whenever a value is
    both computed for live display AND persisted separately, treat them
    as one formula that must be threaded through both call sites
    identically — don't let the persisted version silently fall behind
    when the display version gains a new input.**

23. **A table can have RLS enabled with zero client insert policy at
    all, by deliberate design — and a Supabase client insert against it
    fails silently unless the caller actually checks the returned
    error.** Diver Detail's bill-unlock action's first version inserted
    directly into `audit_logs` to log the unlock — the unlock itself
    worked (visit reopened correctly), but the insert silently failed
    because `audit_logs` has no insert policy at all (by design — see
    the comment already in `001_schema_and_rls.sql`: "rows are written
    only by the SECURITY DEFINER `log_audit_event()` trigger function"),
    and the calling code wasn't checking `.error` on the insert result.
    Caught by checking `audit_logs` directly after unlocking and finding
    no new row, not by any error surfacing anywhere. Fixed with a
    dedicated SECURITY DEFINER RPC (`log_bill_unlock`,
    `database/009_bill_unlock_audit_rpc.sql`) rather than trying to
    force a client-side insert to work, since the generic trigger can't
    produce a custom `action = 'bill_unlocked'` row with a real notes
    message anyway. **Lesson: before writing any client-side insert
    against an RLS-protected table, check whether that table actually
    has an insert policy — grep its policies in `001_schema_and_rls.sql`
    and later migrations first. And separately: always check the
    `.error` field on a Supabase mutation's result — a silently-rejected
    write and a genuinely-successful one look identical unless you do.**

24. **(Testing technique, not a code defect) A Postgres CTE containing a
    data-modifying function call, referenced through multiple correlated
    subqueries in the same outer SELECT, can produce misleading results
    that look like the function silently failed — even when it worked
    correctly.** The first direct-SQL test of the updated
    `submit_diver_registration` RPC (migration 008) wrapped the function
    call in one CTE, then read fields back via several separate
    `(select ... from divers where id = (cte.result->>'diver_id')::uuid)`
    subqueries in the SELECT list — every one of those fields came back
    `null`, looking exactly like the RPC had silently dropped the new
    columns (the actual bug this migration was supposed to fix). The RPC
    was actually fine — rewriting the test as one plain `insert`/`select`
    statement pair (function call once, real columns read directly, no
    nested correlated subqueries re-deriving the same CTE result) showed
    every field populated correctly. Root cause was never pinned down
    precisely (most likely Postgres re-evaluating the CTE's contents once
    per correlated-subquery reference under some query-planning path, even
    though a single data-modifying CTE is documented to execute exactly
    once), but confirmed as a test-construction artifact, not a real bug,
    by the simpler rewrite. **Lesson: when hand-writing a one-off SQL test
    for a data-modifying function (RPC, `insert ... returning`, etc.),
    keep it to one `insert`/`call` followed by one plain `select` of the
    real table — don't wrap the call in a CTE and read its result back
    through multiple separate correlated subqueries in the same query. If
    a test like that shows unexpected nulls, suspect the test's own
    construction before concluding the function is broken.**

25. **A "grep for leftover references to removed/renamed symbols" dead-
    code audit (the kind this project has done after every past feature)
    does not catch a *field* that's fetched into a type and populated at
    the query site but never actually read by any consuming code** — the
    field name still appears in both the type definition and the query,
    so a symbol-name grep finds it "in use" and gives false confidence.
    The Stage 12 audit for this session's Divers + Diver Detail build
    (immediately below) declared everything clean using exactly that
    grep-for-symbol-name method — but a closer end-of-session pass,
    prompted by the user explicitly asking for a dead-code check, found
    three real instances: an entire unused exported function
    (`loadPricingMode`, written during Stage 7 planning, superseded when
    `autoPriceActivityRow` ended up querying `pricing_mode` inline
    instead, never removed) and two unused struct fields (`Visit.isPaid`,
    `ExistingPayment.isPaid` — both fetched and threaded through, but
    every actual UI branch used `visitStatus`/`isActive` instead, never
    `isPaid`). Found by checking usage *count* per symbol
    (`grep -rl "\bsymbol\b" dir | wc -l`, looking for anything at or near
    1 — meaning only the definition site references it) rather than just
    confirming a symbol still resolves. **Lesson: a real dead-code audit
    needs both checks — grep for removed/renamed symbols (catches leftover
    references to things that no longer exist) *and* a usage-count pass
    per remaining exported symbol/type field (catches things that still
    exist correctly but are never actually consumed). The first alone,
    the method used through most of this project so far, isn't sufficient
    on its own.**

### Session 3, continued (2026-07-25 — Staff + Crew Schedule View)

26. **(Testing technique, not a code defect) A raw-SQL-inserted
    `auth.users` test row that leaves certain text columns `null`
    instead of `''` makes Supabase Auth (GoTrue) fail login with a
    generic 500 `"Database error querying schema"` — indistinguishable
    from a real outage or a wrong password hash from the error message
    alone.** Seeding a test owner/secretary login for Staff's RLS/browser
    verification via the same raw-SQL `auth.users`/`auth.identities`
    insert pattern this project already uses produced that exact 500 on
    every login attempt, even though the bcrypt hash was independently
    confirmed correct via `encrypted_password = crypt(password,
    encrypted_password)`. Ruled out a general outage by testing a wrong
    password against a real, long-standing account (`aquadeskonline@
    gmail.com`), which correctly returned a normal 400
    `invalid_credentials` — proving GoTrue itself was healthy and the
    problem was specific to the newly-inserted rows. Root cause found
    only by a full column-by-column diff (`select * from auth.users
    where email in (...)`) against that same real working row:
    `confirmation_token`, `recovery_token`, `email_change_token_new`,
    `email_change`, `email_change_token_current`, `phone_change`,
    `phone_change_token`, and `reauthentication_token` were `null` in
    the test row but `''` on the real one — GoTrue's Go code apparently
    can't scan `null` into whatever it expects there. Also needed:
    `identity_data` on the matching `auth.identities` row must include
    `email_verified`/`phone_verified` keys, and `raw_user_meta_data`
    should be `{"email_verified": true}`, not `{}` — both present on
    every real row and initially missing from the test insert. **Lesson:
    for any future raw-SQL `auth.users` test-fixture insert, explicitly
    set all eight of those token columns to `''` (never leave them at
    their nullable default) and match the real `identity_data`/
    `raw_user_meta_data` shape — and if a freshly-seeded login
    mysteriously 500s instead of failing normally, diff every column
    against a real user row before assuming the password hash itself is
    wrong.**

## Dead-code audit (2026-07-23 session)

- `npm run lint` — clean, no unused-var/import warnings.
- Grepped for the old flat `phone`/`whatsapp`/`ecPhone`/`ecWhatsapp`
  string fields after refactoring them to `{dialCode, number}` pairs —
  zero leftover references; the refactor fully replaced them in place.
- `PagePlaceholder` usage checked — only the pages still genuinely
  unbuilt import it.
- Live Storage policies on `storage.objects`/`storage.buckets` compared
  against the tracked `database/003_cert_card_storage.sql` — exact match,
  no leftover diagnostic policies from the debugging session.
- Tracked SQL files (001/002/003) spot-checked against live schema — in
  sync, no drift between what's tracked and what's actually deployed.

**Nothing found that needed fixing.**

## Dead-code audit (2026-07-24 session)

- `npm run lint` and full `tsc --noEmit` — both clean.
- `git status` in `aquadesk-app` — clean working tree, nothing
  uncommitted or stray, after every commit made this session.
- Grepped for `GovtFee`/`fee_name` (the removed Settings section's type
  and its old column name) across `src/` — zero references remain; the
  removal was complete, not left alongside the replacement.
- Grepped for duplicate `getPaidAmount`/`safeNum` definitions after
  extracting them from Dashboard's `data.ts` into the new shared
  `src/lib/payments.ts` — defined exactly once, Dashboard now imports
  rather than redefining.
- `PagePlaceholder` usage re-checked — only `divers/page.tsx`,
  `divers/[id]/page.tsx`, `scheduling/page.tsx`, `staff/page.tsx` still
  import it (the four genuinely-unbuilt pages); Boat Manifest and Reports
  no longer appear in that list.
- Live schema spot-checked against tracked migrations (`rate_tiers`,
  `dive_sites`, `boats`, `govt_fees` column lists queried directly via
  `information_schema`) — exact match with `004`/`005`/`006`, no drift.
- Database confirmed empty of test data — only the real
  `aquadeskonline@gmail.com` platform admin account remains in
  `auth.users`, `dive_centers` count is 0.

**Nothing found that needed fixing.** Everything today was either edited
in place or fully removed when superseded (see retrospective items 10–14
above for the two cases — Equipment's constants split, and the Settings
Government Fees section removal — where something had to be corrected
mid-session; both were fixed completely, not left alongside a
replacement).

## Dead-code audit (2026-07-25 session — Staff Commission / Payout Summary)

- `npm run lint` and full `tsc --noEmit` — both clean.
- Grepped for every symbol removed in the Staff Activity Summary rewrite
  (`periodMonth`, `CommissionGroup`, `GuideDetailRow`/`CourseDetailRow`,
  `guideDetails`/`instructorDetails`/`guideNames`/`instructorNames`, the
  old single `saveStaffCommission`) — this is what caught the one real
  bug found this pass: `reports/data.ts`'s `loadOverviewData` (a
  different function, not part of the rewrite) still filtered
  `staff_commission_records` by the now-dropped `period_month` column.
  Fixed in place (switched to the `activity_date` range filter) and
  re-verified against a fresh seed that "Staff Commissions (Paid)" on
  Overview reflects the real number — see retrospective #17.
- Grepped for every remaining `staff_commission_records` reference across
  `src/` — all three call sites (`reports/data.ts`,
  `reports/actions.ts` ×2) now consistently use the new per-line-item
  shape (`activity_date`, `divers`, `bonus_amount`), no leftover
  `period_month` usage anywhere.
- Database confirmed empty of test data after cleanup — only the real
  `aquadeskonline@gmail.com` platform admin account remains.

## Dead-code audit (2026-07-25 session, continued — Join Ride)

- `npm run lint` and full `tsc --noEmit` — both clean.
- The one real bug found this pass wasn't a leftover-symbol issue — it
  was the tab-remount state loss covered in retrospective #18, caught by
  functional testing (a saved record disappearing after a tab
  round-trip), not by grep. Fixed in `ReportsClient.tsx`.
- Grepped for `saveStaffCommission` (the pre-rewrite Staff Activity
  Summary function name) — a stale compiled reference briefly surfaced
  in browser console output after this session's dev-server restart, but
  confirmed via direct source grep that no file on disk actually
  references it; the browser console tool was returning buffered history
  from before the restart (see retrospective #19), not a real error.
- Database confirmed empty of test data after cleanup — only the real
  `aquadeskonline@gmail.com` platform admin account remains.

## Dead-code audit (2026-07-25 session, continued — Rental Gears)

- `npm run lint` and full `tsc --noEmit` — both clean.
- Grepped for `rental_gear_records` across `src/` — all references
  (`reports/data.ts` ×2, `reports/actions.ts` ×3) use consistent column
  names; Overview's existing unbounded read and the new tab's read don't
  conflict or duplicate logic.
- No leftover-symbol risk this pass — built onto the already-fixed
  always-mounted `ReportsClient` pattern from the start rather than
  needing a follow-up correction.
- Database confirmed empty of test data after cleanup — only the real
  `aquadeskonline@gmail.com` platform admin account remains.

## Dead-code audit (2026-07-25 session, continued — Expenses)

- `npm run lint` and full `tsc --noEmit` — both clean.
- Grepped for `expenses` table references across `src/` — `reports/
  data.ts` ×2 (Overview's category totals, the new tab's full load) and
  `reports/actions.ts` ×2 (save, delete), all consistent.
- Refactored `EXPENSE_CATEGORY_LABELS` out of `data.ts` (where it was
  private to Overview) into `reports/constants.ts` so the new tab's
  category `<select>` could reuse the exact same value→label mapping
  instead of redefining it — grepped afterward to confirm the old
  in-file definition has exactly one remaining definition, not two.
  Same for the "Other – custom" / "Other (unspecified)" label logic,
  pulled into a shared `expenseGroupLabel` helper used by both Overview
  and the new tab.
- The real bug found this pass (retrospective #20, the `applyDateRange`
  state-update-ordering race) was caught by functional testing — a
  deliberately out-of-range seeded expense not appearing after widening
  the date range — not by grep, same as retrospective #18's discovery
  method.
- Database confirmed empty of test data after cleanup — only the real
  `aquadeskonline@gmail.com` platform admin account remains.

## Dead-code audit (2026-07-25 session, continued — end-of-session full sweep)

Requested explicitly by the user before closing out, covering everything
built this session (Staff Commission / Payout Summary, Join Ride, Rental
Gears, Expenses), not just the most recent feature:

- `npx tsc --noEmit` and `npm run lint` — both clean, run fresh at
  session end (not just trusted from earlier in the session).
- Grepped the whole of `src/` for every symbol retired this session —
  `periodMonth`, `CommissionGroup`, `GuideDetailRow`/`CourseDetailRow`,
  `guideDetails`/`instructorDetails`/`guideNames`/`instructorNames`, the
  old single-signature `saveStaffCommission` — zero remaining references.
- Checked for a stray `./client-refresh` module: while writing
  `ExpensesTab.tsx`'s save/delete handlers, a first draft referenced a
  `getExpensesDataForRange` helper via `await import("./client-refresh")`
  that was never actually created — a self-authored placeholder that
  should have just called the already-imported `getExpensesData` action
  directly. Caught and fixed in the same editing pass, before any
  `tsc`/lint run ever saw it, so it never reached a committed or even
  saved-and-tested state — confirmed no `client-refresh.ts` file exists
  anywhere on disk. Recorded here only because the user explicitly asked
  for the audit to check for exactly this kind of thing, not because it
  ever actually shipped.
- Confirmed `EXPENSE_CATEGORY_LABELS`, `EQUIPMENT_SUGGESTIONS`,
  `expenseGroupLabel`, and `isSettledStatus` are each defined exactly
  once and imported everywhere else that uses them — no duplicate
  definitions drifting apart. (`ExpensesTab.tsx` has its own small
  client-side `categoryLabel`, logically identical to `data.ts`'s
  `expenseGroupLabel` — this duplication is real but necessary, the
  same server/client-boundary reason `peso()` is duplicated across ~6
  files already in this codebase; not something to "fix" by forcing a
  shared import across that boundary.)
- `git status` in `aquadesk-app` — **not** clean: Expenses' changes are
  uncommitted (see the flag at the top of this file). Everything else
  from this session (Staff Commission / Payout Summary, Join Ride,
  Rental Gears) is already committed. This is the one open item at
  session end, and it's a commit-timing decision for the user, not
  leftover/dead code.
- Database confirmed empty of test data — only the real
  `aquadeskonline@gmail.com` platform admin remains in `auth.users`,
  `dive_centers` count is 0.

**Nothing found that needed fixing beyond what's already noted above.**

## Dead-code audit (2026-07-25 session, continued — Settlement)

- `npx tsc --noEmit` and `npm run lint` — both clean.
- Grepped for `SettlementRow`/`SettlementData`/`getSettlementData`/
  `loadSettlementData` across `src/` — each defined exactly once
  (`reports/data.ts`, `reports/actions.ts`) and imported consistently by
  `SettlementTab.tsx` and `ReportsClient.tsx`, no duplicate definitions.
- `todayManila()` is now duplicated a third time (boat-manifest/page.tsx,
  ReportsClient.tsx, SettlementTab.tsx) — deliberate, matching the
  existing `peso()`-style small-pure-helper duplication precedent
  already established across ~6 files in this codebase, not something to
  centralize.
- No real bug found this pass — verified end-to-end against a seeded
  test dive center (one payment with cash + foreign-currency cash + card
  + online amounts and surcharges, one deposit) via direct browser
  testing: on-screen table, grand-total row, the `hidden print:block`
  print markup, and the CSV export's exact cell values and escaping all
  matched hand-computed expected values. Test dive center and its
  `auth.users` row deleted afterward.
- Database confirmed empty of test data — only the real
  `aquadeskonline@gmail.com` platform admin remains in `auth.users`,
  `dive_centers` count is 0.

**Nothing found that needed fixing.**

## Dead-code audit (2026-07-25 session, continued — Government Fees)

- `npx tsc --noEmit` and `npm run lint` — both clean.
- Grepped for `GovtFeeRecord`/`GovtFeesData`/`GovtFeeType`/
  `getGovtFeesData`/`loadGovtFeesData`/`saveGovtFeeRows`/
  `deleteGovtFeeRecord` across `src/` — each defined exactly once
  (`reports/data.ts`, `reports/actions.ts`) and imported consistently by
  `GovtFeesTab.tsx` and `ReportsClient.tsx`.
- Confirmed no leftover `fee_name`/`amount`/`is_active` (the old,
  already-fixed-in-migration-006 column names) anywhere in the new code
  — the new loader/action only ever reference the current real columns
  (`date`, `fee_type`, `rate`, `divers`, `total`).
- One real bug found and fixed this pass (functional testing, not
  grep): the "Government fees saved." message persisted on screen after
  a subsequent Delete, since `removeRecord` never cleared it. Fixed by
  calling `setMessage(null)` at the start of `removeRecord`, same as
  `saveAll` already did at its own start.
- Verified end-to-end: two seeded records displayed and totaled
  correctly, an added draft row's live total and grand total updated
  correctly pre-save, Save All bulk-inserted with a server-computed
  total (confirmed via direct SQL, not just the echoed UI value), a
  ₱0-rate/₱0-divers row saved without validation error (matching the
  live app's own lack of validation there), Delete removed the correct
  row and recomputed the grand total, and Overview's "Government Fees"
  money-out line matched the same ₱1,400 total independently. Test dive
  center and its `auth.users` row deleted afterward.
- Database confirmed empty of test data — only the real
  `aquadeskonline@gmail.com` platform admin remains in `auth.users`,
  `dive_centers` count is 0.

**Nothing else found that needed fixing.**

## Dead-code audit (2026-07-25 session, continued — Billing Audit, Reports complete)

- `npx tsc --noEmit` and `npm run lint` — both clean.
- Grepped for `AuditInvoiceRow`/`AuditFlaggedVisit`/`AuditUnlockLog`/
  `BillingAuditData`/`getBillingAuditData`/`loadBillingAuditData` across
  `src/` — each defined exactly once (`reports/data.ts`,
  `reports/actions.ts`) and imported consistently by
  `BillingAuditTab.tsx` and `ReportsClient.tsx`.
- Removed `ReportsClient.tsx`'s `{tab !== "overview" && ... && "not
  built yet"}` fallback block entirely now that all 8 tabs are wired up
  — nothing left that could ever hit it, so it would have been dead
  code if left in place.
- No real bug found this pass — verified end-to-end against a seeded
  test dive center: a flagged visit (2 invoices, one with two activity
  line items and a card surcharge) correctly flagged and expandable, a
  single-invoice visit correctly *not* flagged, the Invoice History
  search filter scoped only to that section (not Flagged Bills or the
  Unlock Log, matching the live app), the Bill Unlock Log's
  notes-splitting label logic, and the per-invoice print preview's line
  items/payment breakdown/grand total/footer all matched hand-seeded
  values exactly. Deliberately did not click the actual "Print / Save as
  PDF" button in the automated browser pane (confirmed present and
  correctly wired instead) — same `window.print()`-hangs-automation
  caution as retrospective #19.
- Database confirmed empty of test data — only the real
  `aquadeskonline@gmail.com` platform admin remains in `auth.users`,
  `dive_centers` count is 0.

**Nothing found that needed fixing.** This closes out Reports — all 8
tabs built, verified in a real browser against seeded data, and audited
for dead code across every tab built this multi-session arc.

## Dead-code audit (2026-07-25 session, continued — Divers + Diver Detail, all 12 stages)

- `npx tsc --noEmit` and `npm run lint` — both clean, run fresh after
  every stage and again at the end.
- Grepped for `TODO`/`FIXME`/`XXX` across `src/app/(app)/divers/` —
  found one genuinely stale TODO (`saveDiverEquipment`'s comment said
  "once the pricing engine exists" — Stage 7 had since shipped by the
  time this grep ran) and rewrote it to accurately describe the real,
  still-open gap (equipment_rental isn't auto-priced by anything, not
  even Auto-Price) instead of leaving a comment describing a
  now-finished dependency as still pending. The Send Invoice stub's
  `TODO: wire to Resend` is real and intentional, left as-is.
  `EquipmentModal.tsx`'s `XXS`/`XXL` clothing-size strings matched the
  same grep pattern — false positive, not a marker.
- Confirmed the small-helper duplication (`peso`, `fmtDate`,
  `todayManila` each redefined per-file across the new `divers/[id]/`
  components) matches this codebase's already-established precedent
  (same as Reports) — not something to centralize.
- Billing Audit's `invoice_snapshot` fallback chain
  (`snap.grand_total ?? snap.grandTotal ?? snap.total`) simplified to
  just `snap.grand_total` now that Diver Detail's `checkoutVisit` is
  the only writer and the real shape is confirmed, not guessed —
  re-verified Billing Audit still displays the real checked-out
  invoice correctly after the simplification (see the Divers write-up
  above for the two real bugs found and fixed this pass — the
  deposits-balance formula and the `audit_logs` insert-policy gap).
- Database confirmed empty of test data at session end — only the real
  `aquadeskonline@gmail.com` platform admin remains in `auth.users`,
  `dive_centers` count is 0. (One test dive center, "TEST Divers DC",
  was kept alive across all 12 stages this pass — seeding once and
  reusing it stage-to-stage was far more efficient than a fresh dive
  center per stage, given how much state depends on state from earlier
  stages here: a diver, pricing config, a visit, activities, a
  payment, an invoice. Deleted at the very end, same as every other
  session's practice.)

**Nothing found that needed fixing beyond the two real bugs already
documented in retrospectives #22 and #23 above.**

## Dead-code audit (2026-07-25 session, final end-of-session pass)

Requested explicitly by the user at session close, specifically to
check whether anything built today left old code unused instead of
being replaced in place — a closer, second pass beyond the Stage 12
audit immediately above, which turned out to be insufficient on its
own (see retrospective #25 for why: grepping for removed/renamed
symbols doesn't catch a field that's fetched and populated but never
actually read anywhere).

- `npx tsc --noEmit` and `npm run lint` — both clean, run fresh again.
- Ran a usage-count check (`grep -rl "\bsymbol\b" dir | wc -l`) across
  every exported function, type, and constant added under
  `src/app/(app)/divers/` this session. Found three real instances of
  unused code, all fixed in place, none left for a future session:
  - `loadPricingMode` (`divers/[id]/data.ts`) — written during Stage 7
    planning, never actually called; `autoPriceActivityRow` ended up
    querying `dive_centers.pricing_mode` inline instead. Deleted.
  - `Visit.isPaid` (`divers/[id]/data.ts`) — fetched from
    `visits.is_paid` and threaded through `loadLatestVisit`, but every
    actual UI branch (`isEditable`, which tab shows) used
    `visitStatus`/`isActive` instead. Removed the field, the query
    column, and the one place a fresh `Visit` object was constructed
    with `isPaid: false` after starting a new visit
    (`VisitPanel.tsx`).
  - `ExistingPayment.isPaid` (`divers/[id]/data.ts`) — same pattern,
    fetched from `payments.is_paid` in `loadExistingPayment` but never
    read; also structurally redundant even if it had been read, since
    `BillSummary` (the only consumer of this type) only ever renders
    while a visit is open, and checkout — the only thing that sets
    `is_paid = true` — closes the visit in the same transaction, so a
    read value would always have come back `false` in the one context
    this type is used anyway. Removed the field and the query column;
    left a one-line comment explaining why, so a future session doesn't
    wonder why it's missing and add it back.
  - All three were TypeScript-layer removals only — the underlying
    `visits.is_paid`/`payments.is_paid` **database columns** are still
    real, still written correctly by `checkoutVisit`/`unlockBill`, and
    still needed by other features (Dashboard/Reports read them for
    their own purposes). Nothing was removed from the schema.
- Re-ran `tsc`/lint after each removal — stayed clean throughout, no
  cascading breakage.
- No test data existed to re-clean (this pass touched only source
  files, no database writes) — confirmed via the same clean-database
  check as the Stage 12 pass, unchanged.

**Two real, if minor, dead-code items found and fixed** (one unused
function, two unused struct fields) that the earlier same-session audit
missed by relying on symbol-grep alone. See retrospective #25 for the
methodology gap this exposed — worth applying the usage-count check to
every future feature's audit from now on, not just when explicitly
asked twice in one session.

## Dead-code audit (2026-07-25 session, continued — Staff + Crew Schedule View)

- `npx tsc --noEmit` and `npm run lint` — both clean, run fresh at the
  end (both checks applied from the start this time, per the
  retrospective #25 lesson, not bolted on afterward).
- Ran the usage-count check
  (`grep -rl "\bsymbol\b" src/app | wc -l`) for every exported
  function/type/constant added under `src/app/(app)/staff/` and
  `src/app/crew/` this pass. One symbol came back at count 1
  (`StaffPageData`, `staff/data.ts`) — checked closely per retrospective
  #25's warning, but confirmed this is a false positive of the blunt
  heuristic, not a real instance of the pattern: every field it types
  (`roster`, `certifications`, `unlinkedSecretaries`, `crewTokenToday`)
  is actually destructured and passed as a prop in `staff/page.tsx` —
  unlike `loadPricingMode`/`Visit.isPaid` (retrospective #25's real
  finds), nothing here is fetched-but-never-read. No fix needed; the
  type just isn't imported by name anywhere else, which is normal for a
  function's own return type.
- Grepped for `TODO`/`FIXME`/`XXX` under both new directories — none
  found (no stale placeholders left behind this pass).
- Confirmed `RELATIONSHIP_OPTIONS`'s duplication (`staff/constants.ts`
  vs. `divers/[id]/constants.ts`) is deliberate, matching this
  codebase's established small-helper-duplication precedent — not
  something to centralize.
- Database confirmed empty of test data at session end — only the real
  `aquadeskonline@gmail.com` platform admin remains in `auth.users`,
  `dive_centers` count is 0.

**Nothing found that needed fixing.** The one real, valuable finding
this pass (the GoTrue raw-insert null-vs-empty-string gotcha) was a
testing-environment issue, not a defect in the shipped feature — see
retrospective #26 above.

## Dead-code audit (2026-07-25 session, continued — Scheduling, rebuild complete)

- `npx tsc --noEmit` and `npm run lint` — both clean, run fresh at the
  end.
- Usage-count pass (`grep -rl "\bsymbol\b" src/app | wc -l`) across
  every exported function/type/constant added under
  `src/app/(app)/scheduling/`. Found two real dead exports:
  `getStaffOptions` and `getCourseRateOptions` (thin `actions.ts`
  wrappers around `data.ts` loaders, written anticipating a client-side
  refetch need that never materialized — `staffOptions`/`courseRates`
  are loaded once server-side in `page.tsx` and passed down as static
  props instead). Removed both, along with their now-unused
  `loadStaffOptions`/`loadCourseRateOptions` imports in `actions.ts`
  (the loaders themselves stay real and used — `page.tsx` calls them
  directly). Re-ran `tsc`/lint clean after the removal.
- Grepped for `TODO`/`FIXME`/`XXX` under `scheduling/` — none found.
- Cross-page regression pass (Dashboard, Boat Manifest, `/crew`) found
  one real bug, already detailed above and fixed in place: three
  `schedules` queries outside `scheduling/` had no `cancelled` filter,
  since that column was dead before this session. Fixed in
  `boat-manifest/data.ts` and `dashboard/data.ts` (two spots).
- Database confirmed empty of test data at session end — only the real
  `aquadeskonline@gmail.com` platform admin remains in `auth.users`,
  `dive_centers` count is 0.

**One real, if minor, dead-code item found and fixed** beyond the
cross-page bug (two unused exported functions). Nothing else needed
fixing. This closes out the rebuild's originally-agreed build order —
Settings, Boat Manifest, Reports, Divers, Staff, and Scheduling are all
now built, verified, and committed.

## Resolved gap: root folder git history (was: "Known gap")

**Fixed 2026-07-25.** `D:\Rebuild` (this root) is now its own git repo,
separate from `aquadesk-app/`'s. Initial commit tracks `database/*.sql`
(all migrations, source of truth for the live schema), the blueprint
doc, and the old app's reference HTML/JS/`logo.png` (turned out to be
only ~175KB, not the 20MB+ this note previously assumed — worth
correcting since that earlier figure was stale/wrong). `.gitignore`
excludes `aquadesk-app/` (its own separate repo — avoids a nested-repo
gitlink), `supabase/.temp/` (Supabase CLI cache, regenerates on
`supabase link`), and `.claude/settings.local.json` (machine-local
permission state). Every `database/*.sql` migration from here forward
should get committed to this root repo, not just applied to the live
DB — check `git status` in `D:\Rebuild` (not just `aquadesk-app/`)
before assuming migration history is up to date.

## Credential hygiene note

The Postgres pooler password and Supabase secret/publishable keys have
been shared directly in chat across sessions (that's fine, it's the
user's own new isolated project). The publishable/secret API keys are
persisted in `aquadesk-app/.env.local` (gitignored) since the app needs
them at runtime. The raw **Postgres superuser password is deliberately
not** copied into any tracked file, including this one — if direct SQL
access is needed in a future session, ask the user for it again rather
than assuming a stale copy is still correct or safe to have lying around.
