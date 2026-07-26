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

## Current state (as of 2026-07-26 session — Profile tab, reverse Join-Ride alert, login security, office console)

**Both originally-requested gaps are closed, and the scope grew
significantly beyond them** — see the full write-up below this section
header (search "Session 2026-07-26" for the detailed account). Short
version: Settings gained a Profile tab (name/email/phone/address/logo,
migration 012's `dive-center-assets` storage bucket); Scheduling gained
"guest divers" capture (migration 013's `schedules.guest_divers_count`/
`guest_dive_center_name`/`guest_notes`) and Dashboard's Alert 3 ("another
boat joined us") was restored to read it. A live-app audit surfaced a
much bigger gap — **no password reset flow existed at all** — which the
user asked to fully close along with account lockout and a full office
console upgrade, not just patch. All of that shipped too: migration 014
(login lockout columns + RPCs), `/reset-password`, suspended-dive-center
login blocking, and office console search/stats/billing workflow/reset-
link/unlock-login. Three small audit fixes also landed (Dashboard's
over-counted Active Divers, a missing weights-kg field in registration/
equipment, Boat Manifest reading stale accommodation data) plus one
adjacent dead-code bug found and fixed along the way (Dashboard's
equipment-shortage alert never fired — see the retrospective entry).
`KNOWN_GAPS.md` has the newly-tracked smaller findings from this
session's audit that were deliberately *not* built (cosmetic/staff-
reconciliation/preview-modal items). Both repos committed as of session
end — check `git status` before assuming that's still true.

**Session continued the same day, twice more** (search "Session
2026-07-26, continued" for each): first, Resend was wired up for real
invoice email delivery (a test/isolated Resend account, separate from
the live app's connected one — sandbox-limited to the account's own
inbox until a domain is verified, tracked in `KNOWN_GAPS.md`). Then,
after the user actually started using the rebuild and compared it
directly against the live app, three real structural mismatches were
found and fixed: **Staff moved from a top-level nav item into
Settings** (matching the live app exactly — roster CRUD is a Settings
tab there, not standalone), **a real "Divers" page was built**
(Group/Individual/Equipment Management, matching `divers.html` — the
rebuild's `/divers` had actually been "Diver Form"'s list view all
along, mislabeled), and **Scheduling's crew-code generation and diver
discovery were fixed** to match the live app's real mechanics. This
was a large, staged rebuild — see the full write-up further down for
the design decisions and verification detail.

**Session continued a fourth time the same day** (search "Session
2026-07-26, continued yet again" for the full account): the user asked
for three specific areas to be treated as the exact behavioral spec —
Divers > Group Management's active-window logic (fixed: groups/divers
now correctly hide/show based on arrival-1/departure/open-bill, matching
`divers.html`'s real `isVisible()` rule), a full rebuild of Scheduling to
mirror `scheduling.html`'s three-phase Prepare/Build/Complete workflow
with clean (non-duplicated) code — migration 016 added
`schedule_divers.source_clip_id`, real `schedule_team_clips`/
`schedule_team_clip_divers`/`schedule_day_diver_exclusions` tables
(already in the schema, unused until now) now back real clip/exclusion/
carryover logic — and a Settings tab audit (confirmed all 12 live-app
tabs' functionality present, just consolidated; one real mismatch fixed:
dive insurance moved from a rebuild-only "Integrations" tab into Profile,
matching the live app). Two real bugs found and fixed during this
build's own verification (a saved trip warning about double-booking
against itself; `markBoatReturned` missing a duplicate-activity guard
entirely) — see the full write-up for both.

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

A final end-of-day dead-code pass (requested explicitly, covering both
today's features together, not just the most recent one) found one more
small real item beyond what each feature's own audit already caught —
an unnecessarily-exported `BOAT_MODE_LABELS` constant in
`scheduling/constants.ts` — fixed in place. See the final dead-code
audit entry near the end of this file for the full methodology and
result; `git status` in both repos is clean as of session end.

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

## Session 2026-07-26 — Profile tab, reverse Join-Ride alert, login security, office console

Started from two explicitly-requested items (both already tracked in
`KNOWN_GAPS.md`): a Settings tab to edit the dive center's profile, and
restoring Dashboard's "another boat joined us" alert. The user also
asked for a fresh cross-check of every live reference page against
what's built. Three research agents ran that audit in parallel; two
came back clean with small findings, a third (login/password/admin
pages) stalled once and was retried. That retry surfaced something
much bigger than expected — **no user-initiated password reset flow
existed anywhere in the rebuild**, no account-lockout protection, and
login didn't block a suspended dive center's users. Asked the user how
far to take it via `AskUserQuestion`; the answer was to build all of
it now, including a full office-console upgrade, not just patch the
two original items. Used `EnterPlanMode` given the scope (three new
migrations, a new route, new RPCs, an architecture decision).

**Architecture decision**: the live app implements login-lockout
tracking and platform-admin billing actions as separate Supabase Edge
Functions using the service-role key. This rebuild has no Edge
Functions deployed and didn't need to start — lockout tracking became
a `SECURITY DEFINER` RPC (this codebase's existing pattern for
anon-callable, narrow-gateway logic, precedented by `get_crew_schedule`),
and the office-console billing actions became ordinary Server Actions
using the already-existing service-role client
(`src/lib/supabase/admin.ts`), matching how create/suspend already
work. The live app's actual `login-guard` Edge Function source was
found on disk (`supabase/functions/login-guard/index.ts`) — gave an
exact, non-speculative spec to port (5 max attempts, 30-minute lockout,
fail-open on errors, anti-enumeration for unknown emails) rather than
guessing at the policy.

- **Migration 012** (`database/012_dive_center_logo_storage.sql`): a
  public `dive-center-assets` Storage bucket + policies scoped to
  `authenticated` + the caller's own dive center via the existing
  `current_dive_center_id()` helper — same three-policy shape
  (INSERT/UPDATE/SELECT) as the cert-cards bucket, for the same
  `upsert:true` reason.
- **Migration 013** (`database/013_schedules_guest_divers.sql`): adds
  `guest_divers_count`/`guest_dive_center_name`/`guest_notes` to
  `schedules` — deliberately distinct names from the existing
  `is_joiner`/`joiner_boat_name` pair, which mean the *opposite*
  direction (we joined them, not them joining us).
- **Migration 014** (`database/014_login_lockout.sql`): adds
  `failed_login_attempts`/`locked_until` to `users`, plus
  `login_guard_check`/`login_guard_fail`/`login_guard_reset` RPCs
  ported directly from the live Edge Function's logic. Verified via a
  real fixture (not just "the policy looks right"): 5 failures locks
  for exactly 1800 seconds, a 6th call while locked stays locked
  without incrementing further, an unknown email behaves identically
  to a known-unlocked one, and reset correctly clears the counter —
  all confirmed via direct RPC calls before ever touching the UI.

**Settings > Profile tab** (`src/app/(app)/settings/profile/`): logo
upload+preview, Name*/Email/Phone/Address, read-only Subscription
Status (the existing `enforce_dive_center_update_scope` trigger already
blocked owner writes to that field — no new restriction needed). Added
as the first tab in `SettingsTabs.tsx`, matching the live app's own tab
order. No schema migration needed for the fields themselves —
`dive_centers` already had all of them from Stage 1a.

**Scheduling guest-divers + Dashboard Alert 3**: three new optional
fields in `TripBuilderPanel.tsx`, rendered **unconditionally** (not
gated by boat mode) — matching the live app's `joinerHTML()`, which
renders regardless of whether the trip is Own Boat/Join Ride/Rental,
since another dive center's divers can ride along on any trip type.
Dashboard's `loadAlerts()` restored the alert (previously just a
comment explaining why it was skipped), modeled exactly on the
existing "we joined another boat" alert's suppress-after-logging
pattern against `join_ride_records`. Verified end-to-end: created a
trip with guest info, confirmed the alert appeared, logged it via
Reports > Join Ride (`direction = 'joined_our_boat'`), confirmed the
alert disappeared — Reports' Join Ride tab already supported both
directions, no changes needed there.

**Password reset** (`requestPasswordReset` in `auth.ts`, new
`/reset-password` route): uses Supabase Auth's own built-in
`resetPasswordForEmail`/`updateUser` — **no separate email provider
needed**, unlike the already-flagged Resend TODO for invoice emails
(unrelated, not touched this session). `/reset-password` has to be a
client component since the recovery token arrives in the URL hash
fragment, which a server component never sees — parses the hash,
tries `verifyOtp` then falls back to `setSession` (matching the live
app's dual-attempt approach for different token formats), then reuses
the *existing* `setPassword` Server Action from `account.ts` rather
than duplicating password validation. Login gained a "Forgot
password?" toggle revealing an email-only mini-form. Verified via a
real browser flow: request → generic "if that email is registered…"
message (anti-enumeration, matches the RPCs' own design) → confirmed
separately that a `.invalid`-TLD address correctly errors (proving
Supabase Auth itself rejects malformed domains, not a bug).

**Suspended dive center blocks login**: `dal.ts`'s `resolveLandingPath`
and `getCurrentUser` both recheck `dive_centers.subscription_status`
now — `getCurrentUser`'s check is defense-in-depth for a session that
was valid at login time but whose dive center gets suspended mid-
session, same "recheck every load" precedent as the existing
`password_changed` check. Verified end-to-end: suspended a test dive
center, confirmed a fresh login attempt with the *correct* password
still gets rejected with a clear message and signed out; reactivated,
confirmed login works again immediately.

**Office console upgrade** (`src/lib/actions/office.ts`,
`src/app/office/`): address field on create (live app collected it,
rebuild had dropped it), client-side search/filter, a stats row
(Total/Active/Suspended/Created this month/Overdue — ported from
`office.html`'s `renderStats()`), the status control extended from
Activate/Suspend-only to the full Trial/Active/Suspended/Cancelled
enum, a full billing workflow (Start Billing sets due date + amount +
flips to active; Mark as Paid advances the cycle by one month —
confirmed monthly, not guessed, by reading the actual Service
Agreement docx: ₱4,000/month, 5-day grace period matching the already-
ported `daysOverdue()` logic), "Reset Link" (reuses the password-reset
flow above), and "Unlock Login" (calls `login_guard_reset`, shown only
when a dive center's owner is currently locked).

**Three real bugs found and fixed during this session's own browser
verification** (not just written and assumed correct):

1. **A PostgREST ambiguous-relationship error was failing silently.**
   `dive_centers` has two FK paths to `users` (the reverse
   `users.dive_center_id` relation, and
   `dive_centers.waiver_content_updated_by → users.id`) — embedding
   `users(...)` in a `dive_centers` select without disambiguating
   returns a PGRST201 error that the destructured `{ data }` alone
   never surfaces (same silent-failure shape as retrospective #17, a
   different root cause). The office console showed "No dive centers
   yet" despite a real seeded row existing. Found by testing the exact
   query directly against the REST endpoint with curl, not by reading
   the code again. Fixed with the explicit relationship hint
   (`users:users!users_dive_center_id_fkey(...)`) and now also checks
   the query's `error` explicitly (console.error’d, per the standing
   "always check `.error`" lesson).
2. **An uncontrolled `<select defaultValue=...>` went stale after a
   different action updated the same field.** The status dropdown used
   `defaultValue={dc.subscription_status}` — after "Start Billing"
   changed the status server-side (and `revalidatePath` refetched),
   the select kept showing the *old* value since `defaultValue` only
   applies at first mount, not on prop change. The underlying data was
   correct (confirmed via the stats row and billing column updating
   correctly) — only the dropdown's own displayed selection was wrong.
   Fixed by switching to a controlled `value={dc.subscription_status}`.
3. **`markPaid`'s one-month advance silently lost a day whenever the
   server's local timezone is ahead of UTC** (true for Asia/Manila,
   UTC+8) — `new Date(dueDateStr).setMonth(+1)` correctly computes the
   *local* next-month date, but `.toISOString().slice(0,10)` converts
   to UTC before truncating, and local midnight is still the previous
   UTC day when local is ahead of UTC. Aug 1 → Sep 1 local silently
   became "2026-08-31" stored. Caught by manually reproducing the
   exact computation in a scratch script and comparing against what
   was actually persisted (not just eyeballing the UI, which itself
   displayed the wrong value consistently and would have looked
   "correct" on its own). Fixed with pure Y-M-D string arithmetic
   (`addOneMonthToDateStr`) that never round-trips through a JS Date's
   local-time fields — the same category of bug as every other
   Manila-anchoring lesson in this file, just hit in a new spot
   (platform-admin billing, not diver-facing "today" logic).

**One adjacent, pre-existing dead-code bug found and fixed while
verifying the weights-kg field** (not part of the original ask, fixed
because directly proven broken while touching the exact same shape):
Dashboard's tomorrow's-arrivals equipment-shortage counter
(`dashboard/data.ts`) checked `eq.type === "partial"` before counting
anything — but the real `equipment_requested` payload
(`RegistrationWizard.tsx`/`EquipmentModal.tsx`) has never had a `type`
field, only `{ items: [...], computer: boolean }`. This condition has
silently never been true since the field existed, meaning the whole
shortage-count block was dead code producing an always-empty result.
Fixed to match the real array shape directly. The weights-kg field
itself: `RegistrationWizard.tsx`'s equipment step and Diver Detail's
`EquipmentModal.tsx` both gained a kg number input (0-20) for the
"weights" item — previously silently uncaptured even though
`dashboard/data.ts` already special-cased a `weights_kg` key that
nothing ever populated.

**Three small audit fixes bundled in**: Dashboard's "Active Divers"
now requires `experience_type` to be set (previously over-counted,
which also inflated "Pending Bills"); Boat Manifest's "Place of
Residence" now reads current `divers.accommodation` directly instead
of the immutable `diver_registrations` snapshot (a diver's
accommodation can change after registration via Diver Detail; the
live app shows the current value, the rebuild was showing the
original).

**Verification approach**: no real platform-admin or dive-center
credentials were available this session, so a temporary test platform
admin + test dive center/owner were created via the established raw-
SQL `auth.users`/`auth.identities` fixture pattern (all 8 token columns
`''`, `identity_data` with `email_verified`/`phone_verified` — see
retrospective #26), exercised through the actual browser UI for every
flow above, then fully deleted afterward (`schedules.created_by` nulled
in its own committed statement first, per retrospective #28). Database
confirmed back to just the real platform admin account at session end.

**Not built this session** (found during the audit, deliberately
deferred — see `aquadesk-app/KNOWN_GAPS.md` for the full entries): no
client-side cert-card image compression, missing name-field/age/date
validations in registration, a smaller country-dial-code list, a dead
"stale last-dive reminder note" RPC parameter nothing populates, no
mid-visit "change experience type" in Diver Detail, no Waiver/Medical
preview modal in Settings, no staff-record reconciliation in Staff
Access (unlinked-secretary banner/create-login shortcut), and no
"remember me"/password-strength-meter on login (cosmetic).

### Known gaps (tracked in `aquadesk-app/KNOWN_GAPS.md`, none blocking)

The two gaps originally listed here (Dashboard's "another boat joined
us" alert, and Settings having no dive-center-profile tab) were closed
early in the 2026-07-26 session. The nav/Staff/Divers/Scheduling
rebuild later the same day closed the Staff-placement and missing-
Divers-page structural mismatches, but also added two new **smaller**
gaps of its own (deliberately scoped out to keep that rebuild a
reasonable size — see that session's write-up above). Remaining, all
tracked in full in `aquadesk-app/KNOWN_GAPS.md`:

1. Boat Manifest has no offline support, unlike the blueprint's stated
   requirement — the live app doesn't have it either (no reference to
   match), and building it for real is a whole-app architecture decision.
2. Divers > Group Management has no bulk "Review & Apply Charges"
   billing flow (the live app's `divers.html` bulk-pricing-review
   feature) — per-diver pricing via Diver Detail's Auto-Price still
   works individually for every group member in the meantime.
3. Settings > Staff has no reverse-direction "unlinked secretary" banner
   on the Staff Access side (Staff's own form can link an existing
   secretary login when editing a staff row, but Staff Access doesn't
   flag the other direction).
4. A handful of smaller live-app-parity gaps found during the earlier
   2026-07-26 audit (cert-card image compression, registration field
   validations, country-dial-code list size, a dead reminder-note RPC
   parameter, no mid-visit experience-type change in Diver Detail, no
   Waiver/Medical preview modal, no "remember me"/password-strength
   meter) — see `aquadesk-app/KNOWN_GAPS.md` for full entries on each.

### Suggested next step

**The rebuild's originally-agreed page-by-page build order is complete**,
and as of the 2026-07-26 session so is a large follow-up arc closing
every gap found once the user actually started using the app and
compared it to the live app directly: Settings Profile tab, the reverse
Join-Ride Dashboard alert, a full login-security build (password reset,
account lockout, suspended-account blocking), an office console
upgrade, real Resend-backed invoice email delivery (sandbox-limited
until a domain is verified), and a full nav/Staff/Divers/Scheduling
rebuild to match the live app's real page layout and behavior (Staff
moved into Settings, a real "Divers" triage-tool page was built,
Scheduling's diver discovery and crew-code generation were fixed).
**The rebuilt pages have not yet been reviewed by the user** — no chat
message has confirmed the nav/Staff/Divers/Scheduling changes actually
match expectations; that's the natural next checkpoint, not a new
feature to build unprompted. Beyond that, whatever comes next is either
a refinement of what's already built, closing one of the documented
known gaps below, or new scope the user brings.

Known, documented gaps worth revisiting whenever a future session
touches these areas: package-mode nitrox/15L add-on pricing (Divers, no
dedicated mechanism, stays manual entry), `equipment_rental` never
auto-computed from a diver's saved equipment selection (Divers, also
manual entry), Diver Detail only ever shows the diver's single most
recent visit (no full multi-visit history browser), Join-Ride/Rental
boats have no persisted distinction from each other (Scheduling,
accepted cosmetic gap), no bulk group-billing review (Divers > Group
Management, new 2026-07-26 gap), and no unlinked-secretary banner on
Staff Access (new 2026-07-26 gap) — none of these were blocking for
their respective builds, all called out inline in the write-ups above.
Plus the smaller earlier-2026-07-26-session findings tracked in
`aquadesk-app/KNOWN_GAPS.md` (cert-card compression, registration
validations, Waiver/Medical preview, Diver Detail mid-visit experience-
type change, login cosmetics).

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
  `auth.users` + `auth.identities`, bcrypt via `crypt()`/`gen_salt('bf')`,
  with all eight token columns set to `''` never `null` and
  `identity_data` including `email_verified`/`phone_verified` — see
  retrospective #26 for exactly why) is also worth reusing verbatim.
  **Don't attempt `auth.admin.*` Admin API calls from a standalone
  script at all** — confirmed (retrospective #27) this project's
  new-style `sb_secret_...` key is structurally incompatible with what
  GoTrue's Admin endpoints expect (a legacy JWT-based service-role key),
  not just "unreliable"; it will fail with a JWT/`kid` error every time.
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

27. **(Testing technique, not a code defect) The Admin API
    (`auth.admin.createUser`) failed from a standalone Node script with
    `"invalid JWT: unable to parse or verify signature... unrecognized
    JWT kid for algorithm ES256"` — a completely different failure mode
    from retrospective #26's null-token issue, hit as the *first* attempt
    at seeding Staff's test logins, before falling back to the raw-SQL
    `auth.users` insert pattern that #26 is about.** This project's own
    working practices note already said "the Admin API is unreliable
    when called from a standalone script" from a prior session, but
    didn't say why — now it's confirmed: this project's Supabase keys are
    the newer `sb_publishable_.../sb_secret_...`-style API keys (see
    `aquadesk-app/.env.local`), not the legacy JWT-based
    `service_role`/`anon` keys GoTrue's Admin endpoints expect for
    signature verification. Passing the new-style secret key as the
    Admin API's service-role credential produces exactly this JWT/`kid`
    error — it's not a transient/script-specific flakiness as the vague
    prior note implied, it's a structural key-format mismatch that will
    recur every time. **Lesson: don't attempt `auth.admin.*` calls from
    a standalone script with this project's keys at all — go straight to
    the raw-SQL `auth.users`/`auth.identities` insert pattern (see
    retrospective #26 for the exact column gotchas that pattern itself
    needs) rather than losing time on the Admin API first.**

28. **(Testing technique, not a code defect) Deleting a test
    `dive_centers` row failed against `schedules_created_by_fkey`
    (`schedules.created_by → users.id`, a plain FK with no cascade) even
    after explicitly nulling `created_by` earlier in the *same*
    transaction, immediately before the `dive_centers` delete.** Splitting
    the `update schedules set created_by = null ...` into its own
    separately-committed statement, then deleting `dive_centers` in a
    follow-up call, worked cleanly. Root cause not fully pinned down
    (most likely how Postgres orders/validates multiple cascade paths —
    `dive_centers → users` and `dive_centers → schedules` — triggered by
    one parent delete when a non-cascading cross-reference like
    `created_by` sits between them), but confirmed as a cleanup-script
    ordering quirk, not a schema or application bug — no real code path
    ever deletes a `dive_centers` row this way. **Lesson: for any future
    test-data cleanup that deletes a `dive_centers` row, if a table has a
    plain (non-`dive_center_id`-cascade) FK pointing at `users` — like
    `schedules.created_by` — null that column out in its own prior
    *committed* statement, not the same transaction as the final
    cascade-triggering delete.**

### Session 2026-07-26 — Profile tab, reverse Join-Ride alert, login security, office console

29. **A PostgREST embedded-relationship query can fail with a specific,
    named error (`PGRST201`, "more than one relationship was found")
    when a table has two FK paths to the one being embedded — and, like
    every other Supabase query error in this codebase, the destructured
    `{ data }` alone never surfaces it.** `dive_centers` has two paths to
    `users`: the reverse `users.dive_center_id` relation (the one
    actually wanted) and `dive_centers.waiver_content_updated_by →
    users.id` (an unrelated audit-trail column). Embedding
    `users(id, full_name, ...)` in a `dive_centers` select without
    disambiguating produced this exact error — the office console
    rendered "No dive centers yet." despite a real seeded row existing,
    identical in symptom to retrospective #17's silent-failure shape but
    a completely different root cause (ambiguous embed, not a bad column
    name). Found by testing the exact query directly against the
    PostgREST REST endpoint with curl and reading the JSON error body,
    not by re-reading the TypeScript. Fixed with PostgREST's explicit
    relationship-hint syntax (`users:users!users_dive_center_id_fkey(...)`)
    and by finally checking `.error` on this query too. **Lesson: any
    embedded/nested `.select()` on a table with more than one FK to the
    embedded table needs an explicit relationship hint — don't assume
    the "obvious" one will be inferred; test the exact query via curl
    against the REST endpoint (or check Supabase's own query error, not
    just the UI) if a query with an embed silently returns nothing.**

30. **An uncontrolled `<select defaultValue={...}>` renders the value
    from its *first* mount forever, even after the underlying prop
    changes on a later render — a different mechanism from every other
    "stale closure" bug in this file, but the same symptom (UI shows
    old data even though the real data is already correct).** The
    office console's status dropdown used `defaultValue={dc.
    subscription_status}`; after "Start Billing" flipped the status
    server-side and `revalidatePath` refetched the page, the stats row
    and billing column both updated correctly, but the dropdown itself
    kept showing the pre-update value, because `defaultValue` only
    seeds an uncontrolled input at mount and React doesn't reset it on
    a prop change without a `key` change forcing a remount. Caught
    immediately by comparing the dropdown's displayed selection against
    the stats row's own count in the same screenshot/text-dump, not by
    trusting either alone. Fixed by switching to a controlled
    `value={dc.subscription_status}` (there was no reason for this
    particular field to be uncontrolled — the onChange handler already
    fires the update immediately, no local multi-field draft state to
    preserve). **Lesson: prefer a controlled input over
    `defaultValue`/`key`-remount for any field whose true value can
    change from an action *other than* the one attached to that exact
    input — `defaultValue` is only safe when nothing else on the page
    can invalidate it.**

31. **Advancing a plain calendar-date string (no time/timezone
    component at all) by round-tripping it through a JS `Date`'s local
    fields and back out via `.toISOString()` silently loses a day
    whenever the server's local timezone is ahead of UTC — true for
    this app's own Asia/Manila anchor.** `markPaid`'s billing-cycle
    advance did `new Date(dueDateStr).setMonth(getMonth()+1)` (correct:
    computes the right local next-month date) then
    `.toISOString().slice(0,10)` (wrong: converts to UTC *before*
    truncating to a date, and local midnight in Manila is still the
    previous calendar day in UTC) — Aug 1 → Sep 1 local silently
    persisted as `2026-08-31`. This is the same root-cause family as
    every Manila-anchoring lesson already in this file (naive UTC
    conversion crossing a timezone boundary), just hit in a genuinely
    new spot: platform-admin billing math, not diver-facing "today"
    logic, so it wasn't code covered by any existing `manilaDateStr`-
    style helper. Caught by reproducing the exact computation in an
    isolated scratch script and diffing against what actually
    persisted (`2026-08-31` vs. the expected `2026-09-01`) — the UI
    alone would have looked internally consistent (it displays exactly
    what's stored) and given no signal anything was wrong. **Lesson:
    any date-only (no time component) value that needs calendar
    arithmetic — add N months/days — should use pure Y-M-D string/
    integer math, never a round-trip through a JS `Date` object's local
    fields and back out via `.toISOString()`. This applies even outside
    the already-covered "what is today in Manila" pattern — anywhere a
    stored date gets advanced by a fixed calendar interval is the same
    risk.**

32. **A guard condition can reference a payload shape that was never
    real, making an entire code block permanently dead without ever
    throwing an error or looking obviously broken.** Dashboard's
    tomorrow's-arrivals equipment-shortage counter
    (`dashboard/data.ts`) gated its whole counting block on
    `eq.type === "partial"` — but `equipment_requested`'s real,
    confirmed shape (`RegistrationWizard.tsx`, `EquipmentModal.tsx`) has
    never had a `type` field, only `{ items: [...], computer: boolean }`.
    This condition has therefore been false on every single record
    since the feature existed, silently producing an always-empty
    shortage list with no error, no warning, nothing — a shape mismatch
    exactly like the "table's real shape isn't what a field name
    suggests" class of bug this project has hit repeatedly (see the
    "Before writing any insert/update..." working practice), except
    here it was a *read*-side guard condition, not a write, so there
    was no RLS rejection or constraint violation to surface it either.
    Found only because this session was independently re-confirming the
    exact same `equipment_requested` shape while adding the weights-kg
    field, and noticed the dashboard code's assumed shape didn't match.
    Fixed to read the real array shape directly. **Lesson: when
    re-confirming a payload shape for one purpose (adding a field),
    check every *other* consumer of that same payload for the same
    assumption — a guard condition checking a field that was never
    really set is just as silently broken as a query selecting a
    column that doesn't exist, and won't be caught by `tsc`, lint, or
    even normal functional testing of the feature whose shape you're
    confirming, since the dead consumer is a completely different
    feature (Dashboard, not Registration).**

33. **(Testing technique, not a code defect) An always-mounted tab
    (the established `hidden`-class pattern used to prevent state loss
    on tab switch, see retrospective #18) only fixes losing state on
    remount — it does nothing to keep that tab's data fresh when a
    *different*, sibling tab is the one that changes the underlying
    data.** Group Management's `groups` list fetched once at mount and
    never again; creating a group from the Individual Management tab
    (a sibling, also always-mounted) left Group Management showing "No
    groups yet" until a full page reload, since nothing ever told it to
    refetch on becoming visible again. This is the mirror image of
    retrospective #18: #18 was about a component unmounting and losing
    its own locally-patched state; this is about a component that
    correctly *never* unmounts, so it also never gets a second initial
    fetch. Caught by creating a group in one tab, switching to the
    sibling tab, and finding it not there — a straightforward functional
    test, not a code-review catch. Fixed by adding an `active` prop
    (derived from the parent's current mode/tab state) to both tabs and
    refetching inside a `useEffect` keyed on that prop becoming true.
    **Lesson: "keep it always-mounted" solves exactly one problem (state
    loss on remount) and introduces a new one (staleness from sibling-
    tab actions) — any always-mounted tab whose data can be invalidated
    by something happening in a *different* tab needs an explicit
    active-triggered refetch, not just a mount-time fetch. Don't treat
    "always-mounted" as a complete fix; it's half of one.**

34. **A tab/nav "is this active?" check based on `pathname.startsWith
    (tab.href)` — a pattern already used in multiple places in this
    codebase — silently breaks the moment a new tab's URL happens to be
    a prefix of an existing one's.** Adding a `/settings/staff` tab
    alongside the pre-existing `/settings/staff-access` tab meant
    `"/settings/staff-access".startsWith("/settings/staff")` evaluates
    `true`, so visiting Staff Access would show *both* tabs highlighted
    as active. Caught proactively, before shipping, by checking the
    actual computed class names via `javascript_tool` right after
    wiring up the new tab — not by visual inspection, which can be easy
    to miss at a glance when both tabs are adjacent and the highlight
    color is subtle. Fixed by changing the check to
    `pathname === tab.href || pathname.startsWith(`${tab.href}/`)`
    everywhere a tab bar does this kind of matching. **Lesson: any
    naive `startsWith`-based active-route check is a latent bug waiting
    for the day two routes in the same nav/tab group happen to share a
    prefix — when adding a new nav item or tab, check whether its URL
    is a prefix of (or has as a prefix) any sibling's URL, and use an
    exact-match-or-trailing-slash check instead of bare `startsWith`
    from the start, not just after it collides.**

35. **(Testing technique, not a code defect) Confirms and extends
    retrospective #19's console/log-buffering finding to a new specific
    symptom: a stale "module export doesn't exist" error can keep
    reappearing in dev-server logs/console across multiple page loads
    even after the referenced file is confirmed correct on disk and
    `tsc --noEmit` passes clean** — this recurred during the nav/Staff/
    Divers/Scheduling rebuild (`Export loadReadyPool doesn't exist in
    target module`) under a new wrinkle: the dev server being edited was
    the *same shared server* the user's own separate browser session
    was actively using (confirmed by the user's own real actions —
    `createTrip`, `getAllGroups` — appearing interleaved in
    `preview_logs`). A scary module-not-found error in that shared
    server's logs doesn't necessarily mean the current code state is
    broken; it can be Turbopack's own stale/buffered output from a
    moment the module genuinely didn't exist yet (mid-edit) that never
    got cleared. Confirmed non-issue both times by checking actual
    rendered output (`get_page_text`) rather than trusting the log.
    **Lesson: when a `tsc`-clean file still throws a module-not-found
    error in dev-server logs or browser console, especially on a dev
    server shared with another active user/tab, verify against real
    rendered page output before concluding something regressed — this
    is now a confirmed recurring pattern in this environment, not a
    one-off.**

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

## Dead-code audit (2026-07-25 session, final end-of-day pass — Staff + Scheduling together)

Requested explicitly by the user at session close, covering **both**
features built today (Staff + Crew, and Scheduling), not just the most
recent one — same "closer second pass" spirit as retrospective #25's
original finding that a single symbol-grep pass isn't sufficient on its
own.

- `npx tsc --noEmit` and `npm run lint` — both clean, run fresh again.
- Extracted every exported function/type/constant from both features'
  diffs (`git diff --stat cfc5b85^ 42f4623 -- src`, the two feature
  commits) — 74 symbols total — and ran the usage-count check
  (`grep -rl "\bsymbol\b" src/app | wc -l`) on all of them together in
  one pass. Two came back at or near 1:
  - **`BOAT_MODE_LABELS`** (`scheduling/constants.ts`) — a real find:
    exported but never imported anywhere outside its own file, only used
    internally to derive `BOAT_MODE_OPTIONS` (which *is* genuinely
    consumed by `TripBuilderPanel`). Unlike `POSITION_LABELS`/
    `EMPLOYMENT_STATUS_LABELS`/`EXPERIENCE_TYPE_LABELS` (all directly
    indexed elsewhere for display, e.g. `POSITION_LABELS[s.position]` in
    `StaffClient.tsx`), nothing ever needs a standalone boat-mode label
    lookup — Scheduling's UI shows the boat's real name, not a mode
    label. Fixed by dropping the `export` keyword, keeping it as a
    module-private const — `BOAT_MODE_OPTIONS` stays the only exported
    symbol from that pair.
  - `StaffPageData` (`staff/data.ts`) — re-checked, still a confirmed
    false positive (same finding as the original Staff-session audit):
    it's `loadStaffPageData`'s return type, and every field it describes
    (`roster`, `certifications`, `unlinkedSecretaries`, `crewTokenToday`)
    is genuinely destructured and used in `page.tsx` — the type name
    just isn't imported anywhere by name, which is normal for a
    function's own inferred return shape, not a sign of an unread field.
- Grepped for `TODO`/`FIXME`/`XXX` across both `staff/` and
  `scheduling/` — none found.
- Confirmed `getStaffOptions`/`getCourseRateOptions` (removed in the
  earlier same-day Scheduling audit) don't reappear and have zero
  remaining references anywhere.
- Database confirmed empty of test data — only the real
  `aquadeskonline@gmail.com` platform admin remains in `auth.users`,
  `dive_centers` count is 0.

**One additional real (if minor) dead-code item found**:
`BOAT_MODE_LABELS`'s unnecessary export, fixed in place. Everything else
from today's two features checks out clean under both the symbol-grep
and usage-count methods.

## Session 2026-07-26, continued — Invoice email sending wired to Resend

Closed the last standing TODO from the Divers build: `sendInvoice`
(`divers/[id]/actions.ts`) previously only marked an invoice as sent in
the data model, with a comment explaining delivery was deferred until
the user set up a real email provider. Now it actually sends.

**Deliberately a separate, test/isolated Resend account** — not the
live app's already-connected one. The user was explicit about this and
asked what to do about `aquadesk.online` (the real domain the live
app's Resend account may already have configured) without risking it.
Recommendation given and accepted: don't verify the root domain in this
second account at all — SPF is a single-record-per-domain concern, and
a second account adding its own SPF entry to the same root domain risks
breaking the live account's mail authentication. Plan is a subdomain
(e.g. `dev.aquadesk.online`) later, verified independently with its own
DNS records that can't collide with whatever the live account already
has. For now, sending uses Resend's shared `onboarding@resend.dev`
address — zero domain setup, zero risk to the live domain, good enough
to prove the pipeline works end-to-end.

- `RESEND_API_KEY`/`RESEND_FROM_EMAIL` added to `aquadesk-app/.env.local`
  (gitignored, confirmed before this note was written — never committed).
- New `src/lib/email/resend.ts` (thin client factory, mirrors
  `lib/supabase/admin.ts`'s shape) and
  `divers/[id]/invoiceEmailHtml.ts` (builds the email body from the same
  `invoice_snapshot` shape `InvoicePanel.tsx` already renders for print
  — genuinely inline-styled HTML, not shared Tailwind classes, since
  email clients never load the compiled stylesheet at all).
- `sendInvoice` now fetches the diver's email + snapshot + dive center
  name, calls Resend, and **only** marks `email_delivery_status = 'sent'`
  on a real successful send — a failed send sets `'failed'` and surfaces
  the actual Resend error message in the UI (the existing `error` state
  `InvoicePanel.tsx` already had), never silently marks something sent
  that wasn't.
- Verified end-to-end with a seeded invoice (hand-built snapshot matching
  the real shape, not a live checkout — the checkout/pricing computation
  itself was already proven in the Divers session, only the email-sending
  path is new code worth re-testing): a send to an address other than the
  Resend account's own signup email failed with Resend's real API error
  (confirming the sandbox-recipient limit below is real, not assumed),
  correctly surfaced in the UI with `email_delivery_status` set to
  `'failed'`. Retried after pointing the test diver's email at the
  Resend account's own signup address — sent successfully,
  `email_sent_at`/`email_delivery_status = 'sent'` confirmed via direct
  query, and the UI's Send Invoice button correctly flipped to a
  disabled "Sent" state.

**Real, non-code finding**: Resend's shared `onboarding@resend.dev`
sender can only deliver to the Resend **account's own signup email** —
not to arbitrary recipients, contrary to the initial assumption that a
shared test sender would work for any recipient during testing. This is
a hard limit until a domain is verified, tracked in
`aquadesk-app/KNOWN_GAPS.md` — invoices can't reach real divers yet, only
prove the pipeline works. Revisit once the `dev.aquadesk.online`
subdomain is verified.

## Session 2026-07-26, continued again — Nav/Staff/Divers/Scheduling rebuilt to mirror the live app

The user started actually using the rebuild for the first time this
session and compared it directly against the live app, which they
consider the functional reference — the whole point of the new tech
stack is scalability/security/efficiency/tidiness, not different
behavior or page layout. Direct feedback surfaced real structural
mismatches, confirmed by reading the live app's actual code (not
memory or the blueprint) rather than guessed at:

1. **"Staff" wasn't supposed to be a top-level nav item.** Confirmed:
   `settings.html` has a real Staff tab; token generation lives in
   `scheduling.html`'s `generateToken()`, `staff.html` only ever reads
   the token. The rebuild had a full top-level `/staff` page doing both
   roster CRUD and token generation — neither belonged there.
2. **"Divers" in the nav was the wrong page.** The live app has two
   separate nav items — "Divers" (`divers.html`: a triage tool with
   Group/Individual/Equipment Management tabs, diver cards, group
   creation, and the "push to schedule" flow) and "Diver Form"
   (`diver-form.html`: the profile/billing workspace — confirmed to be
   exactly what `divers/[id]/page.tsx` already correctly was). The
   rebuild's `/divers` was actually "Diver Form"'s list view,
   mislabeled — the real "Divers" triage tool had never been built;
   its group/push-to-schedule pieces were absorbed into Scheduling
   instead during an earlier session, a deliberate scope call the user
   now wanted reversed to match the live app's real page layout.
3. **Scheduling couldn't discover divers well**, following directly
   from #2 — a name-search box with no browsable pool, unlike the live
   app's card-grid of already-"readied" divers.

Used `EnterPlanMode` given the size (comparable to the original
Scheduling or Divers builds) — two Explore agents researched the live
app's `scheduling.html` (every `schedule_divers` write, the sidebar/
hamburger CSS+JS) and the rebuild's current code (Sidebar, Staff, the
Scheduling group/diver-assignment components, the old Divers list) in
parallel before any plan was written.

**Key research finding that shaped the whole design**: `schedule_divers`
rows with a null `schedule_id` (written by `divers.html`'s "push to
schedule") are **confirmed dead data in the live app itself** — grepped
every `schedule_divers` reference in `scheduling.html`; it never
queries, updates, or reads them. The real "readiness" signal
`scheduling.html` actually uses is an open+unpaid `visits` row with
`experience_type` tagged, reconciled from Supabase on every load — the
`localStorage` ready-list and the null-`schedule_id` rows are both
orphaned in practice. The rebuild replicates the live app's real
*functional* behavior (tag via `visits`), not its literal dead write
path — consistent with this project's standing rule to match intent,
not verbatim bugs. This single finding meant the "can't add divers to
scheduling" complaint was fixable without reintroducing the live app's
own two-phase clips/ready-pool table plumbing at all.

**Scope decisions**, confirmed via `AskUserQuestion` where genuinely
ambiguous (only one came up: whether to keep a rebuild-only addition —
secretary self-view of their own staff profile — now that Staff moves
under Settings' owner-only gate; user chose to drop it and match the
live app exactly):

- **Route rename**: the new "Divers" triage tool took over the
  `/divers` route; the existing list+detail feature moved to
  `/diver-form` + `/diver-form/[id]` (a mechanical `git mv`-equivalent
  — `git mv` itself failed with a Windows file-lock permission error
  against the live shared dev server, `Move-Item` in PowerShell worked
  where Bash's `mv`/`git mv` didn't). Every internal link
  (`/divers/${id}` in Dashboard's `DiversTable.tsx`, the old list's own
  "Open Form" links, all ~16 `revalidatePath` calls in the detail
  page's actions.ts) was greped and fixed — verified via `tsc` (broken
  imports would fail) plus a live browser click-through afterward.
- **Push-to-schedule**: select divers (Group or Individual mode) → "Add
  to Schedule" → Experience Tagging modal (fresh copy of the same UI
  pattern Scheduling's own tagging modal already used) → for each
  diver, ensure/update an open `visits` row with `experience_type`/
  `course_rate_id` set. No `schedule_divers` write happens at this
  stage — only when a diver is actually assigned to a specific trip in
  Scheduling, exactly as before.
- **Scheduling's `DiverAssignmentPanel`** kept its existing name search
  (a genuine rebuild improvement, not something the user complained
  about) and **gained** a browsable card-grid pool alongside it — every
  diver with an open+unpaid `visits` row for today, not yet assigned to
  this trip (`loadReadyPool` in `scheduling/data.ts`, reusing the
  already-existing `buildDiverPickResults` helper) — matching the live
  app's actual card-click interaction model.
- **Crew-code generation** moved from Staff to Scheduling's
  `ConfirmPanel.tsx` (fresh `getCrewTokenToday`/`generateCrewToken`
  actions in `scheduling/actions.ts`, same `generate_daily_staff_token`
  RPC — matching `scheduling.html`'s `generateToken()`, not
  `staff.html`, which only ever reads the token).
- **Staff roster CRUD** moved into `settings/staff/` (new Settings tab,
  owner-only via the layout's existing guard — matching the live
  app's `settings.html` Staff tab exactly). `/staff` and its secretary
  self-view were removed entirely; `/crew` (public token view) untouched.
- **Group management** (`GroupsPanel.tsx`, both flows + deletion
  blockers) relocated wholesale from Scheduling to the new Divers page
  — confirmed via full-file read this was the *only* group-management
  implementation anywhere in the rebuild, a relocation not a
  duplication.

**Build order** (10 stages, `tsc`/lint clean after every one, browser-
verified against one persistent seeded test dive center reused across
all stages — same discipline as the original Scheduling/Divers builds):
nav+Sidebar rebuild → route rename → new `/divers` skeleton (3 tabs,
matching `divers.html`'s `setMode()` pattern) → Group Management →
Individual Management (diver cards: name, cert level, arrival, a
day-by-day bill-stack for group members vs. running-bill+balance for
individual view, medical/minor flag badges, "Remove" = full diver
delete matching the live app's own confirmation copy, "+Group" ad-hoc
selection) → push-to-schedule → Equipment Management (per-arrival-date
checklist, needed a new `divers.equipment_notes` column — migration
015, since the live app's equivalent field literally has a space in its
name and nothing in this schema matched it) → Scheduling cleanup →
Staff→Settings → full regression pass.

**Real bugs found and fixed during this build's own verification**:

1. **A tab kept correctly mounted (per the established Reports-tab
   lesson) can go stale in the *opposite* direction** — Group
   Management's `groups` list only fetched once at mount; creating a
   group from Individual Management (a sibling always-mounted tab)
   left Group Management showing "No groups yet" until the page was
   fully reloaded, since nothing told it to refetch on becoming visible
   again. This is the mirror-image of retrospective #18 (which was
   about losing state on remount) — here the component never
   *unmounted*, so it never got a fresh initial fetch either. Fixed by
   adding an `active` prop (`mode === "group"`) to both Group and
   Individual Management, refetching in a `useEffect` keyed on it.
   **New lesson for this codebase's "keep tabs always-mounted" pattern**:
   always-mounted also means "never re-fetches on its own" unless
   something explicitly tells it to — any tab whose data can be
   invalidated by a *sibling* tab's actions needs an explicit
   active-triggered refetch, not just once-at-mount.
2. **`pathname.startsWith(tab.href)` — the exact active-tab-highlighting
   pattern already used everywhere in this app — breaks the moment two
   tabs' URLs share a prefix.** Adding `/settings/staff` alongside the
   already-existing `/settings/staff-access` meant
   `"/settings/staff-access".startsWith("/settings/staff")` is `true`,
   so both tabs would show active on the Staff Access page. Caught by
   checking computed class names via `javascript_tool` after adding the
   new tab, not by visual inspection. Fixed by changing the check to
   `pathname === tab.href || pathname.startsWith(`${tab.href}/`)`
   everywhere this pattern is used for tab bars (the main Sidebar's nav
   items don't currently collide this way, but the same fix should be
   applied there too if a future nav item's URL ever becomes a prefix
   of another's).

**Testing-technique note, not a code defect**: the Next.js dev server
being edited was the **same shared server the user's own browser was
live-testing against** (confirmed by seeing the user's own real actions
— `createTrip`, `getAllGroups` calls — appear in `preview_logs` output).
A module-export error (`Export loadReadyPool doesn't exist in target
module`) appeared repeatedly in logs/console across multiple page loads
even after the file was confirmed correct on disk and `tsc` passed
clean — this was **stale/buffered log output**, the same category as
retrospective #19's console-buffering finding, confirmed by checking
actual rendered page content (`get_page_text`) rather than trusting the
error log, which showed the page working correctly the whole time.
**Lesson: when editing a dev server another party (the user, or a
different browser tab) is actively using, a scary-looking module-not-
found error in logs/console doesn't necessarily mean the current state
is broken — verify against real rendered output before concluding
something regressed, especially if `tsc --noEmit` already passed clean
on the exact file in question.**

Verified end-to-end in a real browser against one seeded test dive
center (owner + 2 divers + 1 boat/site + 1 ad-hoc group), reused across
all 10 stages: nav items correct (no Staff, Divers/Diver Form
separate), sidebar hover-collapse + hamburger toggle work, ad-hoc group
creation correctly sets `divers.group_id`, push-to-schedule correctly
writes/updates `visits` (verified via direct query), the same two
divers correctly appear in Scheduling's new ready-pool grid *and* the
pre-existing name search (proving the `visits`-based signal design
decision was sound), crew-code generation works from Scheduling and the
generated code correctly loads `/crew`, Dashboard's Active Divers count
and "Open Form" links both correctly reflect the new state and route,
Settings > Staff correctly creates a roster member end-to-end. Database
confirmed back to just the real platform admin and the user's own real
"Demo Dive Center" (never touched) at session end — the test dive
center and its owner account fully deleted.

## Dead-code audit (2026-07-26 session — Profile tab, reverse Join-Ride alert, login security, office console)

- `npx tsc --noEmit` and `npm run lint` — both clean, run after every
  feature and again at session end.
- Grepped for `TODO`/`FIXME`/`XXX` across every new/edited file this
  session (`settings/profile/`, `scheduling/`, `dashboard/data.ts`,
  `login/`, `reset-password/`, `office/`, `lib/actions/auth.ts`,
  `lib/actions/office.ts`, `lib/dal.ts`) — none found.
- Usage-count pass on every new exported symbol
  (`updateProfile`, `StartBillingForm`, `startBilling`, `markPaid`,
  `sendOwnerResetLink`, `unlockOwnerLogin`, `requestPasswordReset`,
  `isWeightsItem`, and the private `manilaTodayStr`/
  `addOneMonthToDateStr` helpers) — all resolve to exactly their
  definition site plus their real call site(s), no orphans. `markPaid`
  initially looked suspicious at 4 files, but the other two
  (`reports/actions.ts`, `reports/StaffTab.tsx`) turned out to be an
  unrelated, pre-existing, identically-named function for staff
  commission payouts — a naming collision across separate modules, not
  a duplicate or dead definition; confirmed both are genuinely used
  within their own features.
- The three real bugs found this session (PostgREST ambiguous-embed
  silent failure, the uncontrolled-`defaultValue` stale dropdown, and
  `markPaid`'s timezone-truncation date bug) were all caught by
  functional browser testing and direct-query/direct-SQL comparison,
  not by static analysis — see retrospective items 29-31 for the full
  account of each.
- The one pre-existing dead-code bug found and fixed (Dashboard's
  equipment-shortage counter checking a `type` field that was never
  real) — see retrospective item 32.
- Test platform admin, test dive center, test owner, and all associated
  `auth.users`/`auth.identities` rows deleted after verification
  (`schedules.created_by` nulled in its own committed statement first,
  per retrospective #28). Database confirmed back to just the real
  `aquadeskonline@gmail.com` platform admin account.

**Nothing else found that needed fixing.** Both repos' `git status`
checked at session end.

## Dead-code audit (2026-07-26 session, continued — Nav/Staff/Divers/Scheduling rebuild)

- `npx tsc --noEmit` and `npm run lint` — both clean, run after every
  stage and again at the end (per retrospective #25's lesson, applied
  from the start rather than bolted on afterward).
- Grepped for `/staff` (the removed top-level route) and `divers/[id]`
  (the pre-rename path) across all of `src/` — zero remaining
  references to either; the route rename and the Staff relocation were
  both complete replacements, not left alongside the old path.
- Usage-count pass (`grep -rl "\bsymbol\b" src/app | wc -l`) across
  every exported function/type/constant added under the new
  `src/app/(app)/divers/` (the triage tool, not to be confused with the
  renamed `diver-form/`), `settings/staff/`, and the touched
  `scheduling/` files. Found two real dead exports, both removed:
  - `getStaffOptions`/`getCourseRateOptions`-style leftover risk was
    already closed by the earlier same-day Scheduling audit — re-
    confirmed zero reappearance.
  - `checkGroupDeletionBlockers`'s Scheduling-side re-export
    (`scheduling/actions.ts` briefly kept a thin re-export forwarding
    to the relocated `divers/actions.ts` version, written defensively
    during the mid-migration stage in case another Scheduling file
    still imported it) — grepped after the relocation was complete and
    found nothing else in `scheduling/` still importing it. Removed the
    re-export.
- Confirmed `GroupsPanel.tsx`'s relocation from `scheduling/components/`
  to `divers/components/GroupManagementTab.tsx` was a genuine move, not
  a duplication — the old file path no longer exists
  (`Get-ChildItem`/`Glob` confirmed), and its logic (registration-link
  groups, ad-hoc groups, server-rechecked deletion blockers) lives in
  exactly one place now.
- Confirmed the small-helper duplication pattern already established
  across this codebase (`peso`, `fmtDate`, `todayManila`,
  `CERT_LEVEL_LABELS`) continues correctly into the new Divers page's
  own files — each redefined per-file rather than cross-imported,
  matching precedent, not something to centralize.
- The two real bugs found this pass (Group Management's stale-sibling-
  tab data, and the `SettingsTabs` prefix collision) were both caught
  by functional/computed-value testing, not by grep — see retrospective
  items 33-34 for the full account of each.
- Test dive center (owner + 2 divers + 1 boat/site + 1 ad-hoc group)
  and its `auth.users` rows deleted after verification, confirmed via
  direct query the user's own real "Demo Dive Center" was never
  touched at any point. Database confirmed back to just the real
  `aquadeskonline@gmail.com` platform admin account plus the user's own
  real dive center at session end.

**Two real dead-code items found and fixed** (a leftover re-export from
the mid-migration stage, confirmed fully cleaned up) beyond the two
functional bugs already covered in the session write-up and
retrospective items 33-34. Nothing else found. Both `git status` checks
pending the user's explicit go-ahead to commit, per this project's
standing "never commit unless asked" rule.

## Session 2026-07-26, continued yet again — Group Management active window, full Scheduling phase rebuild, Settings audit

The user came back with three explicit "treat the live app as the exact
behavioral spec" requests, all in one message: fix Divers > Group
Management's active-window logic, fully rebuild Scheduling to mirror
`scheduling.html`'s three-phase workflow (Prepare/Build/Complete) with
clean code (not the live app's own duplication — cited as *the* reason
this rebuild exists), and audit Settings' 12 live-app tabs against the
rebuild to confirm nothing was silently dropped. Researched with two
Explore agents (full reads of `scheduling.html`, `divers.html`'s group
code, `settings.html`) before planning, then `EnterPlanMode` given the
size — the Scheduling piece alone is comparable to the original
Scheduling/Divers builds.

**Part A — Group + Individual Management active window.** The create-
group field set already matched the live app exactly
(Group Name/Arrival/Departure/Expected Count/Leader/Notes) — the real gap
was that `loadGroups()` showed every group unconditionally. Implemented
the live app's actual `isVisible()`/`groupIsVisible()` rule (not just the
"arrival minus one day through departure" shorthand): a diver is invisible
until `today >= arrival-1`, then visible through departure inclusive, **and
visible indefinitely past departure if their bill isn't fully closed** — a
detail the shorthand omits. A group with members is visible iff any member
is; an empty group uses the date window directly. New
`divers/visibility.ts` (`isDiverActive`/`isGroupActive`, pure, UTC-anchored
date-string math to avoid the timezone-truncation bug class already
documented in this file). `buildDiverCards` extended with `departureDate`
(pulled from the same latest-registration lookup that already fed
`arrivalDate`) and `billFullyClosed`. Individual Management's default/
browse list and search both now scope to `!groupId && isDiverActive`,
matching `isIndividualCandidate` — a judgment call, since the live app's
exact search-vs-browse distinction wasn't independently confirmed, but the
rebuild's search already scoped to ungrouped-only before this session, so
extending it with the same active-window condition follows the existing
precedent rather than introducing a new one. Verified in a real browser
with four seeded divers spanning every boundary (not-yet-active,
currently active, departed-with-open-bill, departed-and-paid) — exactly
the two expected divers showed in Individual Management, and a seeded
future-dated empty group was correctly hidden while a currently-active
one showed.

**Part B — Scheduling: full phase-based rebuild.** The old implementation
(`DaySelector`/`TripListPanel`/`TripBuilderPanel`/`DiverAssignmentPanel`/
`ConfirmPanel`) had no per-day phase concept at all — pick a date
(defaulting to today), click a trip, edit it in one column. Replaced
entirely with a blank-by-default date picker, a past-date read-only
History view, and three real phases:

- **Migration 016** (`database/016_schedule_divers_source_clip.sql`):
  adds `schedule_divers.source_clip_id`, tracing a trip's placed team back
  to the shared clip it came from — the relational equivalent of the live
  app's in-memory `sourceClipId` tag, needed because this rebuild
  (correctly) keeps trip structure in real columns/join tables rather than
  reviving the live app's `schedules.notes` JSON-blob pattern that this
  project has a standing rule against.
- **Phase 1 (Prepare)**: loose divers (the already-correct `loadReadyPool`
  signal — open+unpaid visit today — confirmed by research to be exactly
  what the live app's `getReadyPool()` reduces to once you account for its
  own dead `readyIds`-union code) minus anyone clipped or excluded for the
  day. "Clips" are real rows in `schedule_team_clips`/
  `schedule_team_clip_divers` — both tables already existed from the
  original Stage 1a schema pass, unused by any writer until now, already
  RLS'd via the generic operational-tables policy, so this was
  application-code work, not schema-risk work. Carryover
  (`carryOverLatestSharedClips` in `scheduling/data.ts`) replicates the
  live app's real `carryOverLatestSharedClips()` mechanism exactly
  (look back — bounded, like the live app's 80-row limit — for the most
  recent prior date with carry-forward-eligible clips, copy that whole
  date's clips forward as real new rows, dropping any diver no longer
  schedulable) — not its dead `carryOverPreviousAssignments()`
  alternative, confirmed dead by the research pass. Exclusion uses the
  real `schedule_day_diver_exclusions` table, not the live app's dead
  `ignoredReadyByDate` localStorage mechanism.
- **Phase 2 (Build)**: trip cards (boat-mode tabs, multi-site "+ Add
  Dive", guest-diver fields — all carried over from the old
  `TripBuilderPanel`) gain a "+ Add Team" picker that assigns a whole clip
  onto the boat at once — matching the live app's real mechanism; there's
  no "assign one loose diver directly" control in either version, a loose
  diver must become a clip first. Reused `WarningsBanner.tsx` unchanged
  (capacity/double-booking/ratio/mixed-cert logic already matched the live
  app from the original build). Collapsed the live app's duplicate
  `saveTrip`/`silentSaveTrip` pair into one `saveTripTeams` action.
- **Phase 3 (Complete/History)**: saved-trip summary cards, Boat Returned
  (extended `markBoatReturned` with a real duplicate-activity check the
  old version was missing entirely — see the bug below), crew token
  display (reused unchanged from the Staff-relocation build), Copy
  Preview and Download Image (a simplified canvas-PNG export, not
  pixel-matched to the live app's exact layout — scoped as workflow
  parity, not visual parity).
- Deleted `TripBuilderPanel`/`DiverAssignmentPanel`/`ConfirmPanel`/
  `DaySelector`/`TripListPanel`/`ExperienceTypeModal` outright rather than
  leaving them alongside the replacement.

**Two real bugs found during this build's own browser verification, both
fixed before calling it done:**

1. **A saved trip warned about being "double-booked" against itself.**
   `SchedulingClient` fetches one shared whole-day `dayContext` for every
   trip card (a single query, not one per card) — but the original
   `DayAssignment` shape had no `scheduleId` field, so a `TripCard`
   couldn't tell which rows were its own once it had just saved. Confirmed
   live: saving a fresh trip immediately showed "2 divers are also
   assigned to another trip today" pointing at itself. Fixed by adding
   `scheduleId` to `DayAssignment` (`loadDayAssignmentsForWarnings`) and
   filtering it out client-side per card (`dayContext.filter(d =>
   d.scheduleId !== scheduleId)`) before handing it to `WarningsBanner`.
2. **`markBoatReturned` had no duplicate-activity guard at all** — the
   live app's real "Activities already added" check (protecting against
   double-charging when a diver already has an `activities` row for the
   date, e.g. entered manually via Diver Detail) was never ported in the
   original Stage 8 build. Added it: query existing `activities` for the
   date/candidate divers before inserting; if any exist, return the
   conflict list instead of writing, and the UI offers Proceed Anyway /
   Exclude Divers (matching the live app's choice, not its exact modal
   copy). Verified end-to-end with a pre-seeded conflicting activity —
   the check correctly flagged only the one diver, "Exclude Divers"
   correctly skipped just that diver's new activity row while the other
   diver's was written normally, and the schedule closed correctly either
   way.

**Dead-code audit found two more real items**, both from features
speced but never fully wired to a UI:

- `addDiversToClip` (an action for adding more loose divers to an
  *existing* clip) — designed in the plan, but Phase 1's actual UI only
  ever creates new clips, consolidating via the already-built "Move"
  action instead. Zero call sites; deleted.
- `includeDiverForDay` — the reverse of "Not diving today," written but
  never given a UI, meaning excluding a diver for the day was a one-way
  trip with no fix in the product. This one was a genuine gap, not just
  leftover code, so it was wired up properly instead of deleted: extended
  `PhaseOneData` with `excludedDivers`, added a "Not Diving Today" section
  to `PhaseOnePanel` with an "Include" button. Verified round-trip in a
  real browser: excluding a diver moved them out of Loose Divers into the
  new section, clicking Include moved them back.

**Part C — Settings tab audit.** Read `settings.html` in full and
compared against every rebuild Settings tab's source. **All 12 of the
user's named live-app tabs (Profile, Access, Passwords, Staff, Courses,
Rates, Equipment, Inventory, Dive Sites, Fleet, Exchange Rates, Waiver)
have their functionality present** — confirmed field-by-field in the
higher-risk spots (`DEFAULT_EQUIPMENT_ITEMS`/`GEAR_ITEMS` in the rebuild
match the live app's 11 rental-rate items and 6 stock items exactly) —
just consolidated into 7 rebuild tabs instead of 12. **One real
mismatch**: dive insurance/referral link lived in the live app's Profile
tab, but the rebuild had built it as a separate "Integrations" tab with
no live-app precedent. Fixed: moved `InsuranceSection` into
`settings/profile/`, deleted the `settings/integrations/` route, removed
its `SettingsTabs` entry — 7 rebuild tabs → 6, still covering all 12.

**Verification**: `tsc --noEmit`/`npm run lint` clean throughout, not just
at the end. Two rounds of real-browser verification against seeded test
dive centers (a 4-diver boundary-spanning set for Part A/B, plus a
second minimal one specifically to exercise the Include-button fix) —
every flow above was exercised live, not just written and assumed
correct, including the two bugs' before/after states. All test data
(both dive centers, both auth users, `schedules.created_by` nulled in
its own committed statement first per the established cleanup-ordering
lesson) deleted afterward — database confirmed back to just the two
real accounts (`aquadeskonline@gmail.com`, `demodivecenter@gmail.com`)
and one real `dive_centers` row.

## Dead-code audit (2026-07-26 session, continued yet again — Group Management, Scheduling rebuild, Settings audit)

- `npx tsc --noEmit` and `npm run lint` — both clean, run after every part
  and again at the end.
- Usage-count pass (`grep -rl "\bsymbol\b" src/app | wc -l`) across every
  exported function/type/constant added under `divers/visibility.ts` and
  the reworked `scheduling/`. Found two real dead exports, both handled
  (not just deleted where a real gap existed — see the session write-up
  above for the full account):
  - `addDiversToClip` — designed but never wired to a UI (Phase 1 only
    creates new clips; consolidation goes through the already-built
    "Move" action instead). Deleted.
  - `includeDiverForDay` — a genuine missing feature, not leftover code:
    "Not diving today" had no undo anywhere in the UI. Wired up properly
    (new "Not Diving Today" section + Include button in `PhaseOnePanel`)
    rather than deleted.
  - Also checked `ClipMember`, `loadExcludedDiverIds`,
    `filterActiveIndividualCards` (each showed at or near 1 file under the
    blunt grep heuristic) — confirmed false positives, same pattern as
    `StaffPageData` in an earlier session: each is genuinely consumed
    within its own defining file, just never imported by name elsewhere.
- Removed the now-fully-dead `searchDivers`/`getActiveGroups`/
  `getGroupMembers`/`getReadyPoolDivers` action wrappers and their
  `searchDiversForAssignment`/`loadActiveGroups`/
  `loadGroupMembersForAssignment`/`GroupOption` data-layer counterparts —
  all confined to `scheduling/actions.ts` + `scheduling/data.ts` with zero
  UI consumers once `DiverAssignmentPanel` was deleted (name-collision
  false positives `searchDivers`/`getGroupMembers` in `divers/`/
  `diver-form/` ruled out by checking exact file lists, not just counts).
  Also removed the now-unused `CourseRateOption`/`loadCourseRateOptions`
  (Scheduling no longer tags experience type — that moved fully to the
  Divers page's push-to-schedule action in the prior session).
- The one real bug found *after* the initial "clean" pass (the
  self-double-booking warning) was caught by functional browser testing,
  not by grep — see the session write-up above for the fix
  (`DayAssignment` gained a `scheduleId` field so each `TripCard` can
  filter out its own rows from the shared whole-day context).
- Database confirmed empty of test data at session end — only the real
  `aquadeskonline@gmail.com` and `demodivecenter@gmail.com` accounts
  remain in `auth.users`, `dive_centers` count is 1 (the user's own real
  dive center).

**Two real dead-code items found, one deleted and one turned into a real
fix** (see above), plus four confirmed-dead action/data-layer pairs
removed as a direct consequence of deleting `DiverAssignmentPanel`.
Nothing else found.

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
