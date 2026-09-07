# AquaDesk Rebuild — Project Memory

Read this in full before doing anything. It's the continuity file across
sessions — the user does not read or write code themselves, so this file
(and plain-language chat updates) is how decisions and state persist.

**This file was rewritten from scratch on 2026-08-17** to bring it back
under a reasonable size (it had grown to ~455k characters). The complete
prior content — every session's own "Current state as of..." write-up
going back to 2026-07-23, the full 66+-item numbered retrospective, and
every session's dead-code-audit section — is preserved verbatim in
**`PROJECT_HISTORY.md`** (repo root). This file now holds only: what the
project is, the absolute/standing rules, a single up-to-date "Current
State" snapshot, a condensed working-practices list, and a condensed
lessons list. **If you need the exact original reasoning, date, or detail
behind some past decision, check `PROJECT_HISTORY.md` — don't assume
something is lost just because it's not restated here.** Going forward,
new session write-ups belong in *this* file, not the archive.

**Shell note (as of 2026-09-04):** the user is now working from native
Windows PowerShell for this project going forward, not Git Bash/WSL —
use PowerShell syntax for any commands/instructions given to them.

## Resume Checklist (read this first if picking this project back up cold)

The user's Pro plan expired 2026-08-20 and the next session could start
any time after — days, weeks, unknown. Everything below was true/checked
**as of 2026-08-19**; re-verify rather than trust it, especially anything
marked with a date. See "Time-Sensitive" section right after this one for
what's most likely to have gone stale.

1. **Check Paddle account/domain verification status** in the Paddle
   dashboard (Overview or the verification checklist page). As of
   2026-08-19: account verification not yet passed; the checkout-domain
   submission for `aquadesk.online` (`chedom_01m09jyk1m5w7xmj6gt9cb5qgq`)
   was in `pending_review`, confirmed via a live `checkoutDomains.list()`
   API call that day. Re-check status — don't assume either way.
2. **Check Payoneer identity verification status** separately (payout
   provider, unrelated system to Paddle — no API/MCP access to check
   this programmatically, ask the user or have them check directly).
3. **Check whether the live `PADDLE_API_KEY` still exists and hasn't
   expired.** Per the user, it was created in the Paddle dashboard around
   2026-08-18/19 with the default 90-day expiry — **see "Time-Sensitive"
   below for the exact date.** As of 2026-08-19 it was confirmed **still
   blank** in `aquadesk-app/.env.production.local` (checked by reading
   the file directly) — creating it in the dashboard and pasting it into
   the codebase are two separate steps, and only the first had happened.
4. **Reconfirm the live Paddle catalog/token/webhook still exist and are
   active** — don't trust the snapshot below without rechecking, since
   these can be edited or revoked from the dashboard independent of this
   codebase. As of 2026-08-19, a direct Paddle API query confirmed all
   active: product `pro_01m09hht4axrx7hk2srdxk95gk` ("AquaDesk"), price
   `pri_01m09hhte5a3xqf0wbecr5q2jw` ($65.00 USD/mo), price
   `pri_01m09hhtq4h5hcvz6ayesta107` ($733.00 USD/yr), client token
   `ctkn_01m09hhxr3j4ppg16j98f4eq0b`, and notification destination
   `ntfset_01m09hja3yk2cbm1hr61hb5ky6` → `https://aquadesk.online/api/
   webhooks/paddle`, subscribed to the 6 events the webhook handler acts
   on. **Never recreate the notification destination** — doing so
   rotates `endpoint_secret_key` and silently breaks delivery; if it's
   gone, that's a real problem to raise with the user, not something to
   silently fix by recreating it.
5. **Once Paddle account verification has genuinely passed** (not just
   domain approval — the full "Verify your account"/"Test and go live"
   flow), run the go-live sequence, in order:
   a. If the live `PADDLE_API_KEY` is missing or expired, have the user
      (re)create it in Developer Tools > API keys — no MCP method exists
      to do this (confirmed by search 2026-08-18). Paste it into
      `aquadesk-app/.env.production.local`.
   b. Confirm the remaining dashboard-only items are done: payment
      methods (Checkout > Checkout settings), default payment link
      (same page — needs a real reachable checkout page, see the
      tension noted under "Still outstanding" below), bank details
      (Business account > Payouts).
   c. Flip `NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED=true` in
      `aquadesk-app/.env.production.local` — **never in `.env.local`**,
      that file is local-dev-only and must stay on sandbox values.
   d. Run the full Cloudflare live-deploy sequence (see "Working
      practices" below) to ship the flip.
   e. Do a real, small-value card test end-to-end once live — confirms
      actual billing works, not just that the build deployed.
   f. Opt individual dive centers into Paddle billing one at a time via
      the `paddle_billing_enabled` toggle in `/office` (migration 040)
      — do not flip it for every dive center at once.
6. **Do not** flip the kill switch or deploy a live-pointed build before
   verification has actually passed, no matter how long the gap was.

## Time-Sensitive — don't trust these as still-accurate after a gap

- **Live `PADDLE_API_KEY` expiry: 2026-11-16.** Per the user, created in
  the Paddle dashboard with the default 90-day expiry around
  2026-08-18/19. If resuming after that date, it will need regenerating
  in the dashboard before the go-live sequence above can work at all —
  check this *first*, before assuming step 5a is a quick copy-paste.
- **The "~3 days" Paddle/Payoneer verification estimate is exactly
  that — an estimate the user made on 2026-08-19, not a promise or a
  Paddle-stated SLA.** Don't repeat it forward as if it were still
  current; check actual status instead (Resume Checklist steps 1–2).
- **The sandbox webhook's notification destination
  (`ntfset_01m07mn3fvez2hcj5t2zh8dev4`, in `.env.local`) points at a
  `cloudflared` quick-tunnel URL** — those are ephemeral and expire
  when the tunnel process stops. If resuming local Paddle sandbox
  testing, assume that URL is dead and the destination needs
  `notificationSettings.update()` to a fresh tunnel URL before webhooks
  will arrive locally again. This doesn't affect production.
- Everything under "Current State" below is dated. Treat "as of
  2026-08-19" as the actual claim, not "currently."

## What this project is

Rebuilding AquaDesk, a dive-center management SaaS, from a plain HTML/JS +
Supabase app into a clean Next.js app. The full spec is
`aquadesk-rebuild-blueprint-v1.md` at this root — read its Stage 1a/1b/1c/6
sections for schema, page map, design direction, and migration plan.

**Folder layout:**
- `D:\Rebuild\` (this root) — this file, `PROJECT_HISTORY.md` (the full
  archive), the blueprint doc, the *old* live app's HTML/JS files
  (reference-only, read but never modify, never connect to the project
  they talk to), and `database\` (SQL migration files — see below). Its
  own git repo (`git -C D:\Rebuild ...`).
- `D:\Rebuild\aquadesk-app\` — the actual Next.js rebuild. Its own
  separate git repo (`git -C aquadesk-app ...`) — two independent repos
  in this tree, don't mix up which one a `git` command should target.
- `D:\Rebuild\database\` — tracked SQL migration files (currently
  001–046), the source of truth for schema/RLS/functions.

## Absolute rule: two separate Supabase projects, never confuse them

- **Live production** (never touch, never connect to, never reference
  credentials for): project ref `xaabndtaevwgicibzcqm`, "AquaDesk
  Solutions". The old HTML/JS files in this root talk to it — they are
  behavioral reference only. **Note**: `aquadesk.online`'s DNS no longer
  points at this app at all — it was cut over to the rebuild on
  2026-08-08 (see "Current State" below). "The live app" (old HTML/JS,
  behavioral reference) and "what's reachable at aquadesk.online" (the
  rebuild) are two different things — don't conflate them.
- **New isolated rebuild project** (this is the one we build against):
  ref `vqwrluiikodconwlmwls`, owned by account `aquadeskonline@gmail.com`,
  region `ap-southeast-1`. URL: `https://vqwrluiikodconwlmwls.supabase.co`.
  Direct host resolves IPv6-only and is unreachable from this machine —
  **always use the pooler**: `aws-0-ap-southeast-1.pooler.supabase.com:6543`,
  user `postgres.vqwrluiikodconwlmwls`. DB password: ask the user again if
  not already in this session — deliberately not persisted here. This is
  the **same** Supabase project backing local dev, pre-prod Cloudflare,
  and the live Cloudflare deploy — one shared DB across all three, not
  separate environments.
- The Supabase CLI on this machine authenticates per-account, not
  per-project — **check `supabase projects list` before any `supabase
  link`/CLI work**; it silently shows only whichever account is currently
  logged in.
- Platform admin login for the rebuild: `aquadeskonline@gmail.com`. That
  account is a `platform_admins` row + matching `auth.users` row, not a
  `public.users` row.
- **Cloudflare — two separate accounts, same distinction as Supabase**:
  pre-prod (`quenaii1993@gmail.com`, account `a6d61b5f208adba70d0ddc0acfdff289`,
  worker `aquadesk-preprod`, URL `aquadesk-preprod.quenaii1993.workers.dev`)
  vs. **live** (`aquadeskonline@gmail.com`'s Cloudflare account, account
  `4ec5d01b30db05b278baa0630e421340`, worker `aquadesk`, serving the real
  `aquadesk.online` domain via Workers Routes — not Custom Domains, see
  `PROJECT_HISTORY.md`'s 2026-08-08 entry for why). Both point at the
  **same** rebuild Supabase project — there is no separate "prod DB."

## Credential hygiene note

Postgres pooler password and Supabase/Paddle/Cloudflare/Resend API keys
have been shared directly in chat across sessions (fine — these are the
user's own accounts). Runtime secrets live in `aquadesk-app/.env.local`
(gitignored, confirm before ever assuming otherwise). **Raw secrets are
deliberately never written into this file or `PROJECT_HISTORY.md`** — if
direct DB/API access is needed, ask the user again rather than assuming
a stale copy is still correct or safe to reuse.

## Current State (as of 2026-09-07 session)

**Paddle/billing status is unchanged and NOT re-verified this
session** — nothing Paddle-related was touched today. Everything in
"Resume Checklist" and "Time-Sensitive" above is still exactly as
dated (2026-08-19); re-verify per those sections' own instructions
before trusting it, same as always.

Today's work was a **Billing Audit fix set** (4 explicitly-scoped
tasks, one at a time with go-ahead between each — same working style
as always) **plus three rounds of live-regression cleanup** triggered
by that work along the way. Every deploy today, including the
cleanup ones, was confirmed against the actual Cloudflare deployment
record (`wrangler deployments list`, not just a clean exit code) and
a live-vs-local `BUILD_ID` content match — not just "the command
succeeded."

**Billing Audit fixes (no migration needed for any of this):**
- **Date-scoping**: `loadBillingAuditData()` (`reports/data.ts`) now
  takes `dateFrom`/`dateTo` and scopes the "Invoice History" table's
  `invoice_emails` query to the Reports page's applied date range,
  using the existing `manilaDayBoundsUtcIso()` helper (`sent_at` is a
  `timestamptz`, same Manila-day-to-UTC-instant pattern used
  everywhere else in this file) — verified directly against a real
  flagged visit's two closures that the filtered query genuinely
  excludes out-of-range rows, not just that the code reads right.
  **Deliberately left unfiltered**: the "Flagged Bills" expanded
  invoice list runs its own separate, always-unfiltered query — a
  flagged visit's full closure history must never be hidden by the
  applied date range, or the audit trail defeats its own purpose.
  `getBillingAuditData()` and `ReportsClient.tsx`'s tab-open/
  `applyDateRange` wiring updated to match the existing Expenses/
  Gov't Fees/Staff pattern (so it actually refetches on Apply, not
  just on first tab open).
- **Relabeling** (`BillingAuditTab.tsx`, display-only — `sent_at`/
  `invoice_count` columns themselves untouched): "Sent At" → "Closed
  On" everywhere it appeared (confirmed via migration 008's own
  comment plus a live-row check that `sent_at` already always equals
  bill-close time, never email-send time — separate `email_sent_at`/
  `email_delivery_status` columns already exist for that and are
  unused/`not_sent` on every row); "Invoices Sent" → "Times Closed" in
  the Flagged Bills table, plus matching prose changes found by
  grepping for the same wording elsewhere on the tab.
- **Date picker mobile/tablet responsiveness**: the From/To/Apply row
  in `ReportsClient.tsx` now stacks into a column below Tailwind's
  `sm` breakpoint (640px, confirmed unmodified default for this
  project) instead of relying on bare `flex-wrap` alone.

**Regression cleanup, three rounds — see Lessons 12-15 below for the
full "what went wrong and why" writeup, don't just read this summary:**
1. A width/flex-basis fix for "date value invisible on mobile" shipped
   live and turned out to be a complete non-fix — the real cause was
   unrelated to width entirely, confirmed by MK's own device testing
   after deploy.
2. Real cause found: `globals.css` had a leftover, never-actually-used
   `@media (prefers-color-scheme: dark)` block (default Next.js
   scaffolding — confirmed zero `dark:` Tailwind-variant usage
   anywhere in this app) flipping the page's inherited text color on
   any dark-mode device, while the date inputs — and, as it turned out,
   every plain login/registration input too — have no explicit
   text-color class and inherit it. The first attempt at the real fix
   (`color-scheme: light` alone) fixed only the native-control-
   *background* half of the problem and **shipped live text-invisible
   on login and diver registration** — worse than the original bug, on
   a day with real paying customers on the site. Fixed for real by
   removing the leftover dark-mode media query entirely — confirmed
   working by MK.
3. A separate "Sign Out sits isolated in its own top bar" report from
   MK turned out, on investigation, to **not be a regression from any
   of today's changes at all** — zero diff in `layout.tsx`/
   `Sidebar.tsx` since before today's work started; it was the app's
   original, always-existing structure. Per MK's direction, fixed
   anyway: Sign Out moved into the sidebar's existing name/role block
   (`Sidebar.tsx`), and the now-empty top `<header>` removed entirely
   from `(app)/layout.tsx` — a genuinely contained 2-file change,
   chosen specifically because no shared page-title-row component
   exists that would have let Sign Out move into each page's own
   title row without touching 8 separate files (see below).

**New fact learned about this codebase, worth remembering for future
page-chrome work**: there is **no shared "page title row" component**
across `(app)/` pages — Dashboard, Reports, Boat Manifest, Diver Form
list, Scheduling, Divers, Settings, and Diver Detail each implement
their own title/subtitle/action-button row independently, with real
structural differences (Scheduling wraps its row in its own bordered
card, unlike everyone else; Divers has no right-side content at all;
Settings has no row at all, just a bare `<h1>`; Diver Detail has no
title-row concept at all, just a "← Back to Divers" link). Don't
assume a shared header exists for future page-chrome work without
checking each page individually, same as this session had to.

**Dead-code audit performed this session** (explicit request, same
habit as 2026-09-05): checked every file touched today (`reports/
data.ts`, `reports/actions.ts`, `reports/BillingAuditTab.tsx`,
`reports/ReportsClient.tsx`, `globals.css`, `(app)/layout.tsx`,
`Sidebar.tsx`) via both `eslint` and a manual variable-usage check —
**clean, nothing left unused**. The Billing Audit query split
(filtered `invoiceEmails` for the main table vs. unfiltered
`allInvoiceEmails` for flagged expansion) both feed one shared
`toInvoiceRow()` helper; no orphaned variables from the several
date-picker markup iterations; `signOut`'s import moved cleanly from
`layout.tsx` to `Sidebar.tsx` with nothing left behind in the old
spot. (`/office`'s separate platform-admin Sign Out implementation is
untouched and intentionally independent — confirmed it's a fully
separate route outside `(app)/`, not a duplicate of anything touched
today.)

**Standing rule set by MK this session, going forward**: before
asking MK to verify any fix live (phone, browser, anywhere outside the
local checkout), confirm and state the actual deployment status —
pushed? what commit is `origin/master` at? what commit/version does
the live Cloudflare deployment record show, checked against the
deployment record and a content-level check (e.g. a `BUILD_ID`
match), not just a clean exit code? — **in that same message**, never
as a separate follow-up. Set after an earlier gap this session where
verification was requested before a fix had even been confirmed
pushed. Also added as a bullet under "Working practices" below.

**Git/environment gotcha found and fixed this session**: this Claude
Code environment's `gh` CLI was authenticated as `usemiraapp-ai` — a
real account of MK's, but tied to a completely different project
(Mira), left over from earlier unrelated use of this same environment.
It has no push access to `aquadeskonlinesolutions/aquadesk-app`, which
silently blocked the first push attempt of the day (403 error). Fixed
by logging that session out; MK re-authenticated as
`aquadeskonlinesolutions` via `gh auth login`. Worth a quick `gh auth
status` sanity check at the start of a future session before the
first push, given this environment has a documented history of being
shared across MK's different projects.

### Prior sessions (condensed further — see `PROJECT_HISTORY.md` for full detail)

**2026-09-05**: shipped three rounds of live work in one day (each
confirmed via User-Agent smoke-check, same method as always): (1) a
`payment_channel` "Online" sub-field (E-Wallet/PayPal/Wise/Bank)
required wherever Online is selected — Bill Summary, Deposits,
Expenses, plus first-time payment-method tracking added to Join Ride/
Rental Gear/Staff Commission settlement (migration 043); a new shared
`SettlePaymentDialog` component; Reports > "Export Raw Data" (a 6-CSV
ZIP via `fflate`, chosen specifically because it's Workers-runtime-safe
with no Node `fs`/stream dependency); a Settlement report channel
display; a Bill Summary notes field (migration 044). (2) Expense
Category "+ Add Category" (migration 045: `custom` enum value + a
per-dive-center `expense_categories` table). (3) a real bug fix —
`addDeposit` was stamping `deposit_date` from raw UTC instead of
Manila-local time, making early-morning deposits vanish from that
day's Settlement report — plus a Settlement "Deposit" tag, and the
same "+ Add Channel" pattern extended to payment channels (migration
046, shared `resolveOnlineChannel()` resolver in
`src/lib/paymentChannels.ts`). Established the "grandfathering"
pattern that session (a new required sub-field on an existing value
only applies going forward, never retroactively — see "Working
practices" below, still in force). A same-session dead-code audit
found and fixed one real bug (`rawExport.ts`'s Expenses CSV showing
the literal word "custom" instead of the resolved channel label) plus
three populated-but-never-read fields removed. A Round 4 fix (found by
MK after the session had "ended" once already) discovered deposits
were never copied into `payments`, so Reports > Overview's "Collected
from Divers," the monthly revenue chart, and "Not Yet Settled" all
silently ignored deposit money — fixed in `reports/data.ts`'s
`loadOverviewData`/`loadMonthlyFinancials`/`openDiverBills`.

**2026-09-04**: Settlement report gained an "Open Form" button per row
(matching Dashboard/Divers). Scheduling gained a "Print Roster" button
(dive-center-wide active-diver roster, reusing `divers/visibility.ts`'s
active-diver definition rather than Scheduling's own narrower check).
Built the full diver trace-number feature: a permanent, human-readable
`{CODE}-{NNNN}` identifier (e.g. `DN-0001`) assigned once at creation,
shown on the Diver Form header. Migrations 041 (`dive_centers.
dive_center_code`, `divers.trace_number`, `dive_center_trace_counters`
for atomic per-dive-center numbering via a single `UPDATE ... RETURNING`)
and 042 (backfilled all 123 existing divers, oldest-`created_at`-first
per dive center). Both migrations were run directly by Claude that
session as an explicit one-time exception to the standing "migrations
run manually by the user" rule — not a standing change. The only
diver-creation path in the whole app is the SECURITY DEFINER
`submit_diver_registration(jsonb)` function, confirmed by grepping
every insert/rpc call site. Three lessons from that session (default
"secondary" UI text sized too small, a schema-dependent-code-is-safe
claim that wasn't actually verified against what `.select()` does with
an unknown column, and a live `wrangler deploy` blocked once by Claude
Code's own permission classifier) are recorded as Lessons 6–8 below.

**2026-08-17**: Paddle sandbox billing built, hardened, and verified
end-to-end (checkout, webhook sync, Retain, office visibility).

**2026-08-18**: migrated the sandbox integration toward live —
created the live catalog/token/webhook (see above), made price-ID
selection environment-aware via `NEXT_PUBLIC_PADDLE_ENV`, wired Paddle
Retain, added the webhook IP allowlist, closed the `.env.production.local`
gap (Lesson #3 below), added `paddle_billing_enabled` (migration 040),
fixed the landing-page pricing copy (`75957e2`), and submitted the
`aquadesk.online` checkout domain for approval. Session paused with the
account still needing full Paddle verification + Payoneer — see Resume
Checklist above for the up-to-date status and full go-live sequence.
Two outstanding items *without* a corresponding MCP method (confirmed
by search): creating a live `PADDLE_API_KEY`, and submitting a checkout
domain for review (the latter is now done — see above — the MCP still
can't submit new ones, only read/delete/verify existing ones).

Still outstanding from that session, dashboard-only, unconfirmed as of
2026-08-19 (no MCP method exists for any of these):
1. **Payment methods** (Checkout > Checkout settings > Payment methods).
2. **Default payment link** (Checkout > Checkout settings) — must be a
   real approved domain, not localhost. **Tension**: the only page that
   would serve as that link (`/settings/subscription`) redirects away
   in every real deployed build (live or pre-prod) while the kill switch
   is off — so there's no publicly reachable live checkout page to point
   the default link at yet. Worth deciding whether to temporarily flip
   the *pre-prod* build's flag on for this purpose before assuming the
   dashboard step is simple.
3. **Bank details** (Business account > Payouts > Payout settings).

**2026-08-19**: added public unauthenticated legal pages (`/terms`,
`/privacy`, `/refund-policy`, linked from the landing footer — Terms/
Refund Policy adapted from the Service Agreement in `settings/
subscription/constants.ts`, Privacy Policy new content, contact email
`aquadeskonline@gmail.com` on all three); wired a working "Request a
Free Demo" form on the landing page (`src/lib/actions/demoRequest.ts`,
reusing the same Resend sandbox setup as invoice emails — see the
Resend caveat below); confirmed the landing-page pricing fix from
`75957e2` (2026-08-18) was actually live. Dead-code audit that session
came back clean. Two Paddle MCP quirks found and noted: `.get()`-style
methods take the ID as a positional string argument, not `{ id }`; and
`notificationSettings.list()`'s array can't be trusted without
cross-checking `pagination.estimatedTotal`.

**Resend caveat** (still applies, unchanged since 2026-08-19 — applies
to both invoice emails and the demo request form): `RESEND_FROM_EMAIL`
is Resend's shared sandbox address (`onboarding@resend.dev`, no custom
domain verified on the account) in *every* environment, including
`.env.production.local` — no override exists there. Works today only
because the fixed recipients (`aquadeskonline@gmail.com` for demo
requests; each diver's own address for invoices) happen to be
reachable from that sandbox address. Worth scoping as its own
follow-up (a real `aquadesk.online` sending subdomain would fix both
use cases at once), not a today problem.

## Working practices (condensed — see `PROJECT_HISTORY.md` for full original detail)

- **Every schema/RLS claim gets tested with a real simulated session**
  (`SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '<uuid>', true)`
  inside a rolled-back transaction), never trust a check run as
  `postgres`/service-role as evidence a policy works for real users.
- **Test data is always cleaned up after verification** — seed a test
  dive center or use the shared `Package Test Dive Center` fixture,
  run the flow, restore to baseline. Confirm via a direct row-count
  query that only real accounts remain.
- **Direct SQL access pattern**: a small Node + `pg` script (using the
  pooler connection string), run from `database/migration/` (which
  already has `pg` installed) so `require("pg")` resolves — a script
  placed elsewhere needs its own `node_modules`. Wrap migrations in
  `begin;`/`commit;` inside the SQL file itself. **Always delete the
  scratch runner/inspection script immediately after use** —
  `database/migration/` is meant to stay just `etl.js`/`preflight.js`/
  `transforms.js`/`verify.js` between sessions, not accumulate one-off
  `check_*.js`/`run_*.js`/`seed_*.js` files.
- **The standing rule is: migrations are written by Claude, reviewed
  and run manually by the user in the Supabase SQL Editor — not run by
  Claude.** On 2026-09-04 the user explicitly overrode this, in the
  moment, for that session's two migrations specifically ("run it
  yourself now, permission approved" — after Claude initially declined
  and explained the standing rule). **This was a one-time,
  session-specific authorization, not a change to the standing
  default.** A future session should still write the migration file,
  explain it in plain language, and wait for the user to run it or to
  explicitly say otherwise *in that session* — don't assume blanket
  permission carries forward from this one instance.
- **Before writing any insert/update against an existing table, verify
  its real column names/types/allowed-check-constraint-values** — this
  schema was originally named from the blueprint's shallow inventory,
  not the live app's real usage, and mismatches have been found
  repeatedly. Query `information_schema.columns` or read the migration
  file directly; for check constraints, query `pg_constraint`/
  `pg_get_constraintdef` since `information_schema` won't show literal
  allowed values.
- **Before using `create or replace function` to change an existing SQL
  function, grep `database/*.sql` for every prior `create or replace
  function` of that same name and base the edit on the chronologically
  latest one** — never reconstruct from memory or from an earlier
  write-up (including this file), even one quoted verbatim. This has
  caused a real production crash once already.
- **`alter type ... add value` cannot be *used* (cast to, compared
  against, inserted) within the same transaction that adds it** —
  fine to include in the same `begin;`/`commit;` migration as other
  unrelated statements (confirmed safe twice: migrations 045/046's new
  `custom` enum values), just never write a later statement in that
  same file that references the new value. If a future migration
  needs to both add an enum value *and* immediately use it, split it
  into two separate migration files.
- **The "+ Add X" pattern (custom expense categories, migration 045;
  custom payment channels, migration 046) is now established and
  reusable**: one new fixed enum sentinel value (`custom`), one new
  per-dive-center lookup table with a `label`/`normalized_label` pair
  and a unique constraint on `(dive_center_id, normalized_label)`, one
  shared server-side resolver doing case-insensitive/trimmed
  dedup-match-against-base-values-then-existing-custom-values-then-create,
  and a nullable `custom_*_id` FK column on whatever table stores the
  choice. Reach for this exact shape again rather than reinventing it
  for the next "let people add their own X" request.
- **A dead-code audit needs a usage-count pass per exported symbol**
  (`grep -rl "\bsymbolName\b" <dir> | wc -l`), not just a grep for
  removed/renamed symbol names — the latter only catches stale
  references to things that no longer exist, not a field that's still
  correctly defined/populated but never actually read anywhere.
- **Before writing a client-side insert/update against an RLS-protected
  table, check whether that table actually has a policy permitting
  it** — some tables are deliberately insert-only-via-trigger/RPC, and
  a rejected write fails silently unless `.error` is actually checked.
- **A Supabase `UPDATE` that matches zero rows returns `{error: null}`,
  not an error** — if a handler needs to know whether it actually found
  something, chain `.select("id")` and check the returned array length,
  don't just check `.error`.
- **This sandbox environment has real UI-testing quirks** (documented
  in full in `PROJECT_HISTORY.md`'s retrospective, items 14/19/21/35/
  39/41/48/60/61): coordinate clicks and native `<select>` changes can
  be unreliable, console/log output can be stale/buffered across
  navigations, and a UI read taken in the same tool call immediately
  after a mutation can show pre-mutation state even though the DB
  already committed — reload or switch tabs before trusting a read
  like that. **Also: check whether a browser tool exists at all via
  `ToolSearch` before assuming — several sessions since 2026-08-17 have
  had none.** When no browser tool is available, say so explicitly
  rather than claiming a UI flow was tested when only `tsc`/build/dev-
  server-render was actually checked.
- **Never test a short-interval timeout/expiry feature using a
  threshold near this sandbox's own per-request latency** (multi-
  second, especially right after a cache-clearing restart) — pick a
  threshold generously larger than that latency.
- **After running `cf:build` (or any `next build`), delete `.next`
  before the next `next dev` start in the same directory** — a stale
  shared build-output directory can leave the dev server reporting
  "Ready" while every route 404s.
- **Standing rule (set 2026-09-07): before asking MK to verify any fix
  live** (phone, browser, anywhere outside the local checkout), state
  the actual deployment status in that same message — pushed? what
  commit is `origin/master` at? what commit/version does the live
  Cloudflare deployment record show, confirmed with a content-level
  check (e.g. a `BUILD_ID` match against the local build), not just a
  clean exit code? Never ask for verification and let deployment
  status turn up as a separate, later surprise.
- **Cloudflare deploy sequence** (`aquadesk-app`): stop the local dev
  server → clear `.next` → **check every `NEXT_PUBLIC_*` kill-switch/
  feature-flag's current value in `.env.production.local` (not
  `.env.local`) against what should actually ship** (see Lessons #3 —
  this is not yet automated) → rename `src/proxy.ts` out of the way
  (Node.js middleware isn't supported by the installed OpenNext adapter
  version) → `npm run cf:build` → restore `src/proxy.ts` immediately →
  `wrangler deploy --config wrangler.live.jsonc` (or the pre-prod
  config) with that account's `CLOUDFLARE_API_TOKEN`/
  `CLOUDFLARE_ACCOUNT_ID` — **check which Cloudflare account's
  credentials are in hand, live and pre-prod are separate accounts,
  matching the Supabase live/rebuild distinction above** → smoke-check
  the real domain directly (`curl` with a browser User-Agent — plain
  `WebFetch` 403s on `aquadesk.online` due to Cloudflare's bot
  challenge, not a real failure), not `workers.dev`.

## Lessons (condensed — full 66+-item numbered retrospective in `PROJECT_HISTORY.md`)

**Read these before touching Paddle billing, the build/deploy pipeline,
or this file's own "Current State" claims again:**

1. **The original Paddle checkout trusted client-supplied `customData`
   to decide which dive center got credited — a real cross-tenant
   security hole.** `Checkout.open({ items, customData })` sends
   `customData` straight from the browser; Paddle's webhook signature
   only proves the payload wasn't tampered with in transit, it says
   nothing about whether `customData` was truthful. Anyone could edit
   `aquadesk_dive_center_id` in DevTools before paying and hijack
   another dive center's billing record. **Fixed by creating the Paddle
   transaction server-side** (`paddle.transactions.create()` in a
   Server Action, `customData` derived from `requireOwner()`'s
   authenticated session) and handing the client only an opaque
   `transactionId`. **Lesson: any metadata passed to a third-party
   checkout/payment SDK that a server will later trust for a privileged
   write must be set server-side from the authenticated session —
   never from anything the client echoes back, no matter how deep in
   the SDK's own options object it's buried.**

2. **The Subscribe button had no check for an existing active
   subscription — could create a duplicate Paddle subscription.** It
   only checked `disabled={!paddle}` (SDK loaded or not); the page copy
   even invited an already-active owner to re-checkout to "change
   billing cycle," which Paddle doesn't support that way — it just
   creates a second concurrent subscription, silently orphaning the
   first (whose future cancel/past-due events would then match zero
   stored rows). **Fixed by hiding the plan picker entirely once
   `subscriptionStatus === "active"`.** **Lesson: a purchase/checkout UI
   must gate on current entitlement state, not just SDK-readiness —
   "do they already have one" is as important a precondition as "can
   they start one."**

3. **RESOLVED 2026-08-18** — `NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED=true`
   (correct for local dev) almost got baked into the 2026-08-17 live
   production build, because Next.js reads `.env.local` during `next
   build`, not only `next dev`, and this project had no
   `.env.production`/`.env.production.local` override file — so
   whatever `.env.local` held shipped as-is. Fixed that night with a
   manual flip-false/build/deploy/flip-true sequence, but flagged as a
   still-open process gap. **Closed 2026-08-18**: `aquadesk-app/
   .env.production.local` now exists (gitignored) and is what a real
   `cf:build`/`cf:deploy` picks up automatically for
   production-specific values (verified against how
   `opennextjs-cloudflare build` actually invokes `next build` — a real
   subprocess, standard Next.js env precedence applies), leaving
   `.env.local` as local-dev-only. **Lesson, now about maintenance
   rather than absence**: before any Cloudflare build/deploy, check
   `.env.production.local`'s current values (not `.env.local`'s)
   against what should actually ship — the guardrail only works if its
   contents are kept correct.

4. **This file's own 2026-08-18 write-up went stale within the same
   session it was written**, in two separate ways caught only by a
   direct re-check on 2026-08-19: it called the landing-page pricing
   mismatch "found, not yet fixed" when a later commit that same
   session (`75957e2`) had already fixed it; and it said the
   `aquadesk.online` checkout-domain approval "needs submitting" when
   it had already been submitted (confirmed `pending_review` via a live
   `checkoutDomains.list()` call). Neither was wrong when first written
   — both were simply overtaken by later work in the same session
   without the write-up being updated. **Lesson: treat this file's own
   prose as a starting hypothesis, not ground truth, for anything
   independently checkable — a commit, a live API resource, a deployed
   page. Re-verify before repeating a "still outstanding" claim
   forward, especially across a session boundary.**

5. **Almost lost the 2026-08-19 session's detail while writing this
   file's 2026-09-04 update, right after Lesson #4 above was written
   about exactly this class of mistake.** This file's design keeps one
   "Current State" section that gets replaced each session — but
   2026-08-19's content had never been archived to `PROJECT_HISTORY.md`
   (that archive stops at 2026-08-17), so replacing the section
   wholesale would have deleted it with no copy anywhere. Caught before
   finishing the edit, and a condensed version was added to "Prior
   sessions" first. **Lesson: before replacing this file's "Current
   State" section, check whether its current content already exists
   elsewhere (`PROJECT_HISTORY.md`, a "Prior sessions" entry) — if not,
   condense it into "Prior sessions" as part of the *same* edit, not
   as an afterthought.**

6. **A commit message claimed a schema-dependent code change was "safe
   to ship ahead of its migration" because it null-checked gracefully
   — but the real risk wasn't the null case.** `diver-form/[id]/data.ts`
   added `trace_number` to a `.select(...)` string before migration 041
   (which adds that column) had actually been run against the DB.
   Supabase/PostgREST rejects a `.select()` naming an unknown column as
   a hard query error, not a silently-ignored field — so deploying at
   that point would have broken *every* `/diver-form/[id]` page load
   entirely, not just shown a blank trace number. Caught by rechecking
   the live DB schema directly before deploying, but the commit message
   itself had already asserted the wrong thing. **Lesson: before
   claiming a schema-dependent code change is safe to ship ahead of its
   own migration, verify what a `.select()` naming a not-yet-existing
   column actually does — assume PostgREST hard-fails the whole query,
   not that it degrades gracefully, unless checked otherwise.**

7. **Default "muted/secondary" UI text undershot readability for this
   app's actual users.** The Diver Form's new trace-number display
   started at `text-xs text-gray-400` — a literal reading of "keep it
   visually secondary" — and needed two separate rounds of user
   feedback (darker, then bigger) before it was actually legible.
   **Lesson: AquaDesk's users are dive-shop secretaries, not
   necessarily young or especially tech-fluent — default any new
   "secondary" text to at least `text-sm`/`text-gray-600`, and treat
   "visually secondary" as *smaller/lighter than the primary element
   next to it*, not *as small/light as Tailwind's defaults allow*.**

8. **A live (production) `wrangler deploy` can get blocked by Claude
   Code's own auto-mode permission classifier**, separate from any
   Cloudflare/wrangler-level error — happened once on 2026-09-04, on
   the exact same command that had worked minutes earlier for the
   pre-prod deploy. Not a bug to work around; just surface it to the
   user and retry once they confirm (or have them run the command
   directly) — don't try alternate tools/flags to route around a
   classifier block.

9. **A new server-only shared utility module needs its client-visible
   surface planned *before* writing consumer code, not discovered
   mid-implementation.** Building `src/lib/paymentChannels.ts`
   (2026-09-05, the payment-channel "+ Add Channel" feature), the
   plain constants `ADD_CHANNEL_VALUE`/`BASE_PAYMENT_CHANNELS` were
   first placed in that file alongside the real DB-touching functions
   (`resolveOnlineChannel`/`loadCustomChannels`) simply because they
   were channel-related — then, once wiring began on client components
   (`BillSummary`, `DepositsPanel`, `ExpensesTab`,
   `SettlePaymentDialog`), it became clear a `"use client"` file
   cannot import from a module tagged `import "server-only"`, even for
   a plain constant. Caught before it broke a build, but required a
   mid-session split: the plain constants moved to the already
   client-safe `lib/payments.ts`, leaving only genuinely
   server-only functions in `paymentChannels.ts`. **Before writing a
   new server-only module, list which of its exports a client
   component will need by name first — split constants/types into a
   client-safe sibling file from the start if any will.**

10. **Widening a shared enum-like type (adding a new member to a union
    like `PaymentChannel`) silently breaks any direct
    `SOME_LABEL_MAP[value]` lookup against that type's label map,
    without necessarily showing up as a `tsc` error** — if the
    call site's parameter had already been loosened to plain `string`
    for an unrelated reason (as `rawExport.ts`'s
    `expensePaymentMethodCell` had been), indexing with an `as keyof
    typeof` cast still compiles, but returns the map's own `??`
    fallback (in this case the literal string `"custom"`) instead of
    the real value, for the exact new member that was just added. This
    session's own dead-code audit caught it in `rawExport.ts`'s
    Expenses CSV export — found only by manually reviewing every
    consumer, not by `tsc`. **When adding a new member to a shared
    enum-like type, grep for every direct `LABEL_MAP[value]`-style
    lookup against that type project-wide as a deliberate step — don't
    rely on the type checker alone to surface every affected site,
    especially anywhere the value's type had already been loosened.**

11. **A dead-code usage-count grep (`grep -rl "\bsymbolName\b"`) can
    show a field as "used" when it's only ever read as an *input* to a
    helper that computes a different, separate output field — while
    the original field itself is never read by anything downstream.**
    This session's audit found exactly this for `JoinRideRecord`/
    `RentalGearRecord`/`Deposit`'s raw `channel`/`customChannelId`
    fields: each was legitimately passed into `resolveChannelLabel()`
    to compute `channelLabel`, which made a naive grep count them as
    "referenced" — but the raw fields themselves, once exposed on the
    row type, were never read by any consuming component (all three
    flows only ever display `channelLabel`, and none has an edit path
    that needs the raw value back). **When a type gets both a "raw"
    field and a "resolved/derived" field added together, specifically
    check whether the raw field is read by anything *outside* the
    function that computes the derived one** — grep for
    `.fieldName` usage in the actual consuming components, not just
    anywhere in the codebase, before assuming a nonzero match count
    means it's genuinely used.

12. **A native-input-invisible-value bug on mobile was misdiagnosed
    twice before being fixed, and the second wrong attempt made things
    worse and shipped live to a site with real paying customers.**
    First diagnosis: a Tailwind `flex-1`/`flex-basis:0%` layout quirk
    squeezing the date input too narrow for the browser to render its
    value — plausible-sounding, but wrong; the fix deployed cleanly
    (confirmed via `BUILD_ID` match) and changed nothing, because
    width was never the actual cause. Second diagnosis, closer but
    still incomplete: `globals.css` had a leftover, never-actually-
    built-out `@media (prefers-color-scheme: dark)` block (confirmed
    zero `dark:` Tailwind-variant usage anywhere else in the app)
    flipping the page's inherited text color on any dark-mode device;
    the date inputs — and, unnoticed at the time, every plain login/
    registration input too — have no explicit text-color class and
    inherit that flipped color. The fix applied — `color-scheme:
    light`, forcing native control *backgrounds* to stay light — only
    addressed half of a two-part visual pairing: text color still
    flipped independently via the untouched media query. Before the
    fix, a dark-mode device got a browser-auto-dark input background
    paired with light-flipped text (accidentally readable); after the
    half-fix, backgrounds were forced light while text stayed light
    too, breaking visibility everywhere the fix didn't reach — which
    turned out to be every unstyled input in the app, including login
    and diver registration, not just date pickers. Only fixed for real
    by removing the leftover media query entirely, so text color no
    longer flips at all, matching how every other hardcoded-light
    component in this app already behaves. **Lesson: when a native
    form control's *value* is invisible (not missing, not squeezed,
    just not rendered) with no browser tool available to visually
    confirm, check inherited/global color rules (`color`,
    `color-scheme`, `prefers-color-scheme`) before reaching for
    layout/width explanations — and when the mechanism turns out to be
    a two-part visual pairing (foreground vs. background, light vs.
    dark), fix and verify *both* sides in the same change. A fix that
    touches only one half of such a pairing can make the mismatch
    worse, not better.**

13. **Both of the wrong/incomplete fixes above were pushed straight to
    the live, paying-customer production domain with no way to
    visually verify them first** (no browser/device tool available
    this session), based on plausible-sounding reasoning alone, each
    reported with more confidence than the verification actually
    supported. The second one broke login and diver registration in
    production for however long it was live before MK caught it on
    their own phone. **Lesson: for any CSS/behavior change to a live
    production site that cannot be visually verified locally first (no
    browser tool), prefer verifying via the local dev server — or at
    minimum a pre-prod deploy — with the user's own eyes *before*
    pushing to the live domain, not after.** MK ended up imposing
    exactly this process for the later Sign Out fix the same day
    ("verify via dev server before commit/push"); that should be the
    *default* going forward for any user-facing visual change, not
    something that only kicks in after a live breakage has already
    happened once.

14. **Asked MK to verify a fix live on their phone before confirming
    the fix had actually been pushed or deployed at all** — it turned
    out the commit was sitting local-only (this project's standing
    rule is that commits only happen when explicitly asked, and that
    gap hadn't been surfaced before requesting verification).
    **Lesson, now a standing rule MK set explicitly (see "Working
    practices" above)**: before asking MK to verify anything live
    (phone, browser, any environment outside the local checkout),
    state the actual deployment status — pushed? what commit is
    `origin/master` at? what commit/version is the live Cloudflare
    deployment actually serving, checked against the deployment record
    and a content-level check like a `BUILD_ID` match, not just a
    clean exit code? — in the *same* message that asks for
    verification, never as a separate follow-up.

15. **The first git push attempt of the day failed with a 403** — this
    Claude Code environment's `gh` CLI was authenticated as
    `usemiraapp-ai`, a legitimate account of MK's but tied to an
    entirely different project (Mira), left over from this same
    environment having been used for that project at some earlier
    point. It had no push access to `aquadeskonlinesolutions/
    aquadesk-app`. Fixed by logging that session out and having MK
    re-authenticate as the correct `aquadeskonlinesolutions` account.
    **Lesson: this environment has a documented history of being
    shared across MK's different projects — a quick `gh auth status`
    check before the first push of a session is cheap insurance
    against discovering the wrong account mid-task.**

**Older, still-relevant recurring themes** (each of these has multiple
full incident write-ups in `PROJECT_HISTORY.md` — this is an index, not
the complete text):
- RLS/security claims are only proven by a real simulated non-privileged
  session, never a service-role/`postgres` check.
- SQL functions/tables drift silently across migrations — always grep
  for the chronologically latest version before editing, never trust
  memory or an old write-up.
- This sandbox has real, repeated UI-automation-timing quirks (stale
  reads right after a mutation, buffered console output) — reload/
  switch-tabs before trusting a read, and verify against direct SQL
  when a result looks surprising.
- A dead-code audit needs a usage-count pass, not just a removed-symbol
  grep, to catch fields that are defined/populated but never read.
- Raw-SQL `auth.users`/`auth.identities` test fixtures need every
  token column set to `''` (never `null`) or GoTrue 500s with a
  misleading generic error.
- Windows/this-sandbox-specific gotchas: `robocopy`/rename operations
  need PowerShell not Bash; a stray Bash shell `cd`'d into a directory
  can block its own deletion; Windows Defender can false-positive-flag
  a freshly self-updated CLI binary (hit with `ngrok`'s auto-updater
  this session — worked around by switching to `cloudflared`'s quick-
  tunnel mode instead, which needs no account/token at all).

## Resolved gap: root folder git history

Resolved 2026-07-25 — `D:\Rebuild` is its own git repo tracking
`database/*.sql` and the old app's reference files. No longer an open
item; full detail in `PROJECT_HISTORY.md` if needed.
