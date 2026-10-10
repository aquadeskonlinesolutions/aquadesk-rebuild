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
  001–055), the source of truth for schema/RLS/functions.

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

## Where things stand (end of 2026-10-10 session — read this first)

**Live:** aquadesk-app `master` = `origin/master` = `3a0bd37` (Boat
Manifest rentals, see next section), Cloudflare version
`236715ac-71ea-4cf2-9547-5f43addcdbd0`, `BUILD_ID kIJKVKw1E0kTPzUz-Eqiw`. Root repo `master` = latest "Update CLAUDE.md"
commit (pushed). Latest migration: **055** (all of 047–055 are applied on
production). Nothing uncommitted, nothing half-done. Branch
`fix/invoice-deposit-surcharge` is merged (can be deleted).

**Done today:** the invoice fix (next section). Nothing else.

**Not re-verified since 2026-08-19:** Paddle/Payoneer verification (see
Resume Checklist). Live `PADDLE_API_KEY` expires **2026-11-16** and was
still blank in `.env.production.local`. Resend still sends from the
shared sandbox address (see "Resend caveat").

**What's next — open items, none started (MK decides the order):**
Money/security:
1. Owner/billing password change trusts the browser's "already has a
   password" flag (`settings/passwords/actions.ts`); `set_*_unlock` don't
   check the current password. MK skipped this once (2026-10-04).
2. Payment channels can be deleted through the direct API by any
   signed-in user of the centre (`payment_channels_write` policy, 046).
3. Billing/owner password hashes are bcrypt cost 6 (needs passwords
   re-set to strengthen).
4. Checkout's subtotal ignores a per-activity `discount` while the screen
   and Save subtract it (no UI sets one today).
Invoice/reports:
5. Reports > Billing Audit "View / Print" never shows payment lines
   (reads top-level keys; snapshots nest them under `payment`).
6. Invoice email doesn't HTML-escape diver name / dive site / staff name.
7. Old-app foreign-cash overpayment invoices show Grand Total = amount
   due, lower than the old app's recorded collection (no excess stored).
8. Pre-`628515b` rebuild invoices still show the surcharge as Excess
   (Change) — stored, not rewritten by MK's choice.
9. Invoice figures display rounded to whole pesos.
UI:
10. Settlement's table scrolls sideways inside its card on phones; the
    diver form scrolls sideways on desktops 1024–~1475px (kept on purpose).
11. Scheduling: Copy Preview/Download Image omit a dive-centre-only
    "Joining us" line; Download Image doesn't wrap long notes; Phase 2
    "Confirm Schedule" doesn't block unsaved edits to existing trips.
12. Group-link form: inputs other than the dates have no labels, and the
    grid doesn't stack on phones.
Process: no automated test suite exists; testing = tsc + eslint (baseline
1 error + 6 warnings) + build + the local stand-in (Working practices).

## Latest update: Boat Manifest includes rental-boat trips (2026-10-10)

**Shipped:** aquadesk-app `master` = `3a0bd37` (branch
`feat/manifest-rental-boats`, fast-forwarded, pushed). **No migration, no
stored-data change.** Live Cloudflare version
`236715ac-71ea-4cf2-9547-5f43addcdbd0`, `BUILD_ID kIJKVKw1E0kTPzUz-Eqiw`
(BUILD_ID match confirmed on aquadesk.online; no logged-in checks by
Claude). Rollback target: `3a609093-d828-49a5-88b6-976b7cc4a013`
(`BUILD_ID 7T3bKyn1darxhL0p8KNRe`) — or revert `3a0bd37` and redeploy.
- **Data facts:** `is_joiner` is true for BOTH rental and join ride;
  `schedules.boat_mode` (036: own_boat/join_ride/rental) is what tells
  them apart. Rental boat name lives in `joiner_boat_name`. Before this
  change a rental's captain was never captured (forced null). Rentals
  created before 036 were backfilled as `join_ride` and can't be told
  apart. Real data 2026-10-10: 64 own, 27 join_ride, 2 rental.
- **Manifest (`boat-manifest/data.ts`):** filters `boat_mode in
  (own_boat, rental)` instead of `is_joiner = false`; the detail load
  refuses a join ride server-side. Rental: name + captain from the trip,
  missing = blank (the `mbca()` prefix returns "" for an empty name).
  Own boat unchanged: **Fleet** boat name and **Fleet `boats.captain`**
  (not the trip's captain — only 5/19 boats have one, so most own-boat
  manifests print the blank captain line; kept as-is on purpose).
- **Scheduling:** rental trips have an optional "Boat Captain" input,
  saved to `schedules.captain`; join rides still save none. Server now
  also requires a boat name for rental/join-ride (same as the form).
- **Side effects (reviewed):** the staff crew page now shows "Captain:"
  for rental trips that have one (`get_crew_schedule` reads
  `s.captain`). Dashboard/fuel/is_joiner readers untouched.
- **Open (not changed):** Phase 3 / Copy Preview don't show a rental's
  captain (`PhaseThreePanel.tsx` hides captain when `isJoiner`); Dashboard
  "log join rides" reminder and the staff page's "Joining:" label still
  treat rentals as join rides (they key on `is_joiner`).

## Earlier update: invoice shows deposits + real Grand Total (2026-10-04, ~09:00 Manila)

**Shipped:** aquadesk-app `master` = `c0c47ad` (branch
`fix/invoice-deposit-surcharge`, fast-forwarded and pushed). **No
migration, no stored-data change.** Live Cloudflare version
`3a609093-d828-49a5-88b6-976b7cc4a013`, `BUILD_ID 7T3bKyn1darxhL0p8KNRe`
(deployed 2026-10-04 01:00 UTC; BUILD_ID match confirmed on
aquadesk.online, old BUILD_ID gone; no logged-in checks by Claude).
Previous live version (rollback target): `c7688a1f-31fa-4e19-8450-cab8edc3682e`,
`BUILD_ID COBLvUPgxfTP6phld1wiM`. Backup:
`D:\aquadesk-backups\payments-backup-2026-10-04T00-54-50-274Z.json`
(210 rows) + `baseline-2026-10-04T00-54-50-274Z.json`; deposits 31,
visits 218, payments 210, audit_logs 2311 and both sums unchanged after
the deploy.
- **What changed (display only):** the invoice's print/PDF view
  (`InvoicePanel.tsx`; there is no separate on-screen invoice, it only
  shows when printing) and the emailed invoice (`invoiceEmailHtml.ts`,
  `sendInvoice`) share one totals block in the new
  `diver-form/[id]/invoiceSummary.ts`: Subtotal → Discount → Less:
  Deposit → Amount Due (only with a discount/deposit) → Cash / Cash
  (USD …@ ₱rate = ₱…) / Card ₱X (surcharge ₱Y) / Online ₱X (surcharge ₱Y)
  → Excess (Change) → Grand Total. The email previously showed no
  surcharge, excess or deposits; neither view showed foreign cash.
- **Grand Total** = amount due after discount and deposits + card/online
  surcharges (what the diver actually paid). Before, "Grand Total" was
  the activity subtotal.
- **Deposits** are read at print/send time (the visit's active deposits —
  same sum as Bill Summary's Deposits Applied; cancelled never shown).
  The invoice snapshot has never stored deposits (rebuild or old app).
  A closed bill's deposits can't change without Unlock Bill, and
  re-closing writes a new invoice, so the latest invoice is accurate.
  MK chose this over adding deposits to the snapshot.
- **Subtotal** = sum of the snapshot's own activity rows, because the
  snapshot's `grand_total` means different things: rebuild = activity
  subtotal; **old app = total collected incl. surcharge**
  (`grand_total_php: p.totalCollected`). Empty `{}` snapshots render ₱0.
- **Testing:** local stand-in, checkout through the UI + Send Invoice
  captured by a fake Resend (`RESEND_BASE_URL` process env): 14 cases
  incl. old-app, empty and pre-fix snapshots, 147/147 checks; Grand Total
  = stored total_collected + total_surcharge for every new checkout.
  Dashboard, Bill Summary, Reports Overview, Settlement and Billing Audit
  text identical between old and new code. tsc clean, eslint at baseline
  (1 error + 6 warnings), build OK.
- **Rollback:** revert `c0c47ad` and redeploy. Nothing to undo in the DB.
- **Out-of-scope findings (open):**
  1. Old-app invoices paid with foreign cash above the bill: the old app
     stored no excess, so the invoice shows Grand Total = amount due
     (e.g. ₱5,500) while the old app recorded more collected (₱5,600);
     no Excess line is invented.
  2. Rebuild invoices closed before `628515b` (incl. the two production
     payments of 2026-10-01) still show the card surcharge as "Excess
     (Change)" — stored values, not rewritten (MK).
  3. The invoice email doesn't HTML-escape diver name, dive site or
     staff name (pre-existing).
  4. Reports > Billing Audit "View / Print" still never shows the
     payment lines (unchanged, see the surcharge entry below).
  5. Invoice figures are rounded to whole pesos for display (e.g. a
     ₱231.21 surcharge shows ₱231); Grand Total rounds the exact sum.
- **Wrong turns this session** are written up as Lessons 16–22 (old-app
  `grand_total` meaning, path-casing 404s, PowerShell re-encoding,
  PostgREST DLL, harness mismatches, BUILD_ID lookup). How to run the
  stand-in is under "Working practices".
- **Dead-code audit (end of session): clean.** Every new export in
  `invoiceSummary.ts` is used by both the print view and the email; the
  old inline totals in `InvoicePanel.tsx`/`invoiceEmailHtml.ts` were
  replaced in place (no leftover `grandTotal`/`discount`/`payment`
  locals; the email's inline activity-row sum now calls
  `activityRowTotal`). `InvoiceSummary` (type) is exported but only used
  as the exported function's return type — intentional. `InvoicePanel`
  keeps its own small `num()` for the activity table, matching the
  project's duplicate-small-helpers convention. Nothing to revisit.

## Earlier update: Dashboard cash + three small fixes, migration 055 (2026-10-04, ~01:45 Manila)

**Shipped (one commit per fix):** aquadesk-app `master` = `9998a24`
(`32464f7`, `4a6647f`, `9998a24`); root repo `2ca23a3` (migration 055).
Live Cloudflare version `c7688a1f-31fa-4e19-8450-cab8edc3682e`, `BUILD_ID
COBLvUPgxfTP6phld1wiM` (deployed 2026-10-03 17:41 UTC; BUILD_ID match
confirmed — the edge served the old BUILD_ID for a few seconds after the
deploy before switching; no logged-in checks by Claude). Previous live
version (rollback target): `ba016f27-ff54-40c1-acc9-1f0f29018f70`,
`BUILD_ID Nbjs4EabvQikmpMIU5l5F`. Backups:
`D:\aquadesk-backups\{deposits,payments}-backup-2026-10-03T17-35-53-464Z.json`
(+ fresh baseline `baseline-2026-10-03T17-39-27-954Z.json`). Counts and
sums unchanged after 055 and after the deploy (audit_logs +2 between the
first baseline and 055 was a live bill save at 01:36 Manila, not 055).
1. **Dashboard Cash (`32464f7`, `dashboard/data.ts`):** today's Cash no
   longer has the card/online surcharge taken off it (side effect of
   `47ec005`, 2026-08-02). Cash ₱2,000 + card ₱3,000 (+₱120) now shows
   Cash ₱2,000 / Card ₱3,120 / Total Today ₱5,120 (= revenue +
   surcharges; Settlement's Total Collected stays ₱5,000). Foreign-cash
   overpayment cap unchanged. Dashboard is today-only; past days and
   Settlement/Reports unaffected.
2. **Item 2 (owner/billing password change needs the current password):
   SKIPPED by MK** — nothing changed, see open findings.
3. **Migration 055 (`055_cancelled_deposit_reference_delete.sql`):**
   047's guard trigger blocked deleting a payment channel or user that a
   cancelled deposit references (the FK "set null" counted as an edit).
   055 replaces `guard_deposit_cancellation()` with 047's body plus one
   allowance: a nested FK set-null (`pg_trigger_depth() > 1`) that only
   turns `custom_channel_id` / `refund_custom_channel_id` / `cancelled_by`
   into NULL, every other column unchanged. All other edits of a cancelled
   deposit are still refused; RLS policies untouched. A user who recorded
   any deposit still can't be deleted (`recorded_by_user_id` has no ON
   DELETE action — unchanged).
4. **`payments.excess_amount` rounded to 2 decimals on write (`4a6647f`,
   `actions.ts`)** — Save, Checkout and the invoice snapshot. No backfill;
   old unrounded rows stay as they are.
5. **Last Dive Date server-side format check (`9998a24`, `saveDiverProfile`):**
   anything that isn't a real YYYY-MM-DD date (Feb 30, free text, loose
   formats) is refused with "Enter a valid last dive date."; empty clears;
   the Manila future-date rule is unchanged.
- **Deploy order:** 055 before the code (old code was verified working with
  055 applied). The app commits don't depend on 055.
- **Rollback:** revert the relevant app commit (`32464f7`, `4a6647f` or
  `9998a24`) and redeploy. 055's rollback block at the bottom of the file
  restores 047's function exactly and is safe any time.
- **Open findings (not fixed):**
  1. Owner/billing password change still trusts the browser's "already
     has a password" flag (`settings/passwords/actions.ts` ~25–31 and
     ~53–59); `set_owner_unlock`/`set_billing_unlock` (001) don't check the
     current password either. Item 2, skipped by MK.
  2. A saved-but-not-checked-out payment doesn't appear in Dashboard
     "Today's Payment Channels" (it counts payments with a `paid_at`) —
     **correct by design (MK)**.
  3. Payment channels can be deleted through the direct API by any
     signed-in user of the centre (`payment_channels_write` policy,
     `046_custom_payment_channels.sql` line 31); the app has no delete UI.

## Earlier update: card/online surcharge no longer "Excess (Change)" (2026-10-04, ~01:00 Manila)

**Shipped:** aquadesk-app `master` = `628515b` (no root-repo change, **no
migration**). Live Cloudflare version `ba016f27-ff54-40c1-acc9-1f0f29018f70`,
`BUILD_ID Nbjs4EabvQikmpMIU5l5F` (deployed 2026-10-03 16:59 UTC, BUILD_ID
match confirmed; no logged-in checks by Claude). Previous live version
(rollback target): `abab606e-c8a9-43a6-8f85-0a38d4b9275f`, `BUILD_ID
ZvZnG17hAqPyV57E0umSK`. Backup: `D:\aquadesk-backups\payments-backup-
2026-10-03T16-58-01-512Z.json` (210 rows) + `baseline-…` file; counts and
sums unchanged after deploy.
- **Background (investigated with evidence first):** since `6f457d5`
  (2026-08-02) `computePaymentBreakdown` counted the card/online surcharge
  as money paid toward the bill, so paying exactly the amount due by
  card/online showed the surcharge as Excess (and a surcharge could cover
  a small shortfall). Not caused by the 2026-10-02/03 sessions (pre-session
  commit `17ee0c1` reproduced identically); it only became visible when the
  first surcharged rebuild payments happened (2026-10-01). The old app never
  had "excess" and stored total_collected = bill + surcharge.
- **MK's rule:** surcharges are NOT revenue; the Card/Online field means
  "amount before surcharge" and the app adds the surcharge on top;
  Excess (Change) = 0 when the diver pays exactly due + surcharge.
- **Fix (`billing.ts`):** only cash + foreign + card + online count against
  the bill; the surcharge stays separate (never revenue, never excess).
  Cash/foreign overpayment excess unchanged. A card/online amount below due
  now leaves a balance (server refuses checkout). Save and Checkout share
  the function. **Invoice (`InvoicePanel.tsx`):** "Card ₱5,000 + surcharge
  ₱200" instead of "Card (incl. surcharge ₱200) ₱5,000" (same for Online).
- **Historical rows not rewritten (MK):** the two production payments of
  2026-10-01 (`3962e152`, `5bf21a4c`, excess ₱231.21 each) keep their stored
  excess. Old-app (pre-2026-08-08) rows keep total_collected incl. surcharge.
- **Rollback:** revert `628515b` and redeploy. Payments saved while the fix
  was live keep Excess 0.
- **Open findings (not fixed):**
  1. Reports > Billing Audit "View / Print" never shows the payment lines
     (Cash/Card/Online): `BillingAuditTab.tsx` reads top-level snapshot keys,
     but every invoice snapshot (old app and rebuild) nests them under
     `payment`; it also looks for a `card_surcharge` key that doesn't exist.
  2. Dashboard cash undercount in mixed payments (Part C, **undecided by
     MK**): `dashboard/data.ts` ~644–648 subtracts the card/online surcharge
     from cash, so cash ₱2,000 + card ₱3,000 (+₱120) shows Cash ₱1,880,
     Card ₱3,120, Total Today ₱5,000.
  3. A card payment below due that is saved (Save, keep open) but not
     checked out did not appear in Dashboard "Today's Payment Channels" in
     local testing — not investigated.

## Earlier update: Asia/Manila timezone sweep (2026-10-04, ~00:15 Manila)

**Shipped:** every "today", date boundary and date display now uses the
Asia/Manila date, whatever the device or server timezone. aquadesk-app
`master` = `9657794`; root repo `6e65dfa` (migration 054). Live
Cloudflare version `abab606e-c8a9-43a6-8f85-0a38d4b9275f`, `BUILD_ID
ZvZnG17hAqPyV57E0umSK` (deployed 2026-10-03 16:14 UTC, BUILD_ID match
confirmed; no logged-in checks by Claude). Previous live version
(rollback target): `257dbb1a-0d4b-4387-804b-52fbf05b0a13`, `BUILD_ID
IzrjmURWA0EtjESO6Ei_n`. Backups: `D:\aquadesk-backups\{deposits,visits}-
backup-2026-10-03T15-55-00-017Z.json` (+ `baseline-…` file); counts and
sums matched the baseline after 054.
- **Shared helper: `src/lib/manila.ts`** (re-exports `manilaTodayStr` from
  `age.ts`; adds `addDaysToDateStr`, `manilaMonthRange`, `MANILA_TZ`).
  **This is the single place to change if timezones ever become
  per-centre** (there's no timezone column today, so Asia/Manila is
  hardcoded). The label component is `src/components/ManilaDateNote.tsx`
  ("Dates in Manila time (PHT)"), shown next to the date pickers on
  registration (Birthday, Departure, Last Dive Date), Edit Diver Info
  (Birthday, Last Dive Date), Settlement, Reports and Scheduling.
- **What was fixed:** registration age and Birthday/Last Dive Date limits
  (a future date is now refused at the step), Scheduling and Boat
  Manifest ages, checkout `visit_end`, Reports default month,
  Expenses/Rental Gears/Join Ride default dates and the Join Ride
  statement date, Equipment "tomorrow", office overdue days and "this
  month", and timestamp displays (Billing Audit, flags, documents, notes,
  invoices on screen + email, waiver versions, "Printed:" lines) now
  format with `timeZone: "Asia/Manila"`. Stored timestamps stay UTC.
  Settlement/Reports day boundaries, Dashboard and the SQL functions were
  already Manila and were not changed — money screens identical.
- **Migration 054** (`054_manila_date_defaults.sql`): the column defaults
  of `visits.visit_start` and `deposits.deposit_date` changed from
  `current_date` (UTC) to `(now() at time zone 'Asia/Manila')::date`.
  Only the defaults; nothing else touched. `govt_fees.date` has no default.
- **Deploy order:** 054 before the code. Old code verified working with
  054 applied.
- **Rollback:** revert `9657794` and redeploy. 054's rollback SQL (in the
  file) is safe any time.
- **Testing:** local stand-in with the server on `TZ=UTC` and a faked
  clock at 00:30/07:59/08:01/23:59 Manila, browsers on UTC and
  America/Los_Angeles: 140/140. The crew page's SQL age was not re-tested
  with a faked DB clock (formula covered by the 053 tests).
- **Out-of-scope findings (open):** `payments.excess_amount` stored
  unrounded (`diver-form/[id]/actions.ts` ~1154/1418/1473); checkout's
  `grandTotal` ignores per-activity `discount` (`actions.ts` ~1315);
  surcharges count toward paying the bill (`billing.ts`
  `computePaymentBreakdown`); registration Arrival/Departure have no
  Manila-based limits (probably fine); Last Dive Date has no server-side
  format check; Settlement's table scrolls sideways inside its card on
  phones. The earlier findings about registration pickers and
  Scheduling/Boat Manifest ages using UTC (below) are now **fixed**.

## Earlier update: crew-page live age + Last Dive Date "today" (2026-10-03, late night)

**Shipped (two small fixes):** aquadesk-app `master` = `70f8e7a`; root repo
`9a8385a` (migration 053). Live Cloudflare version
`257dbb1a-0d4b-4387-804b-52fbf05b0a13`, `BUILD_ID IzrjmURWA0EtjESO6Ei_n`
(deployed 2026-10-03 14:44 UTC, BUILD_ID match confirmed; no logged-in
checks by Claude). Previous live version (rollback target):
`dafee31b-6a24-4b57-bdf2-65fe2db25ea3`. Backups:
`D:\aquadesk-backups\{deposits,payments}-backup-2026-10-03T14-32-54-844Z.json`.
1. **Staff crew page age (migration 053, no app code):**
   `get_crew_schedule` (030's body verbatim) now returns the existing
   `age` key as the age calculated from `divers.birthday` with the
   Asia/Manila date (same rule as `src/lib/age.ts`, Feb 29 → Mar 1),
   falling back to the stored `divers.age` when there's no birthday.
   **The birthday never leaves the database** — `/staff` is public
   (anyone with the day's crew code), so MK chose an SQL-side age over
   sending birthdays to the page. No key added/removed/renamed; grants
   unchanged. Verified on production after 053: same fields and counts
   for all 4 centres with a crew code, no birthday in the response.
2. **Last Dive Date "today" (`EditProfileModal.tsx`, `actions.ts`):**
   the picker's limit uses the Manila date (today selectable 00:00–08:00
   Manila), and a future Last Dive Date is now refused in the browser
   and in `saveDiverProfile` (MK; before, a typed future date was saved).
- **Deploy order:** 053 before the code. The old code was verified
  working with 053 applied (it already shows the live age).
- **Rollback:** revert `70f8e7a` and redeploy. For 053, re-run
  `030_crew_schedule_guest_divers.sql` in full (restores the old body
  exactly — tested locally).
- **Out-of-scope findings (open):**
  - Registration's Birthday and Last Dive Date pickers use the UTC date
    (`RegistrationWizard.tsx` lines 654 and 927) — today isn't selectable
    between 00:00 and 08:00 Manila.
  - Scheduling and Boat Manifest calculate age with the server clock
    (`scheduling/data.ts` line 14, `boat-manifest/data.ts` line 105) — on
    Cloudflare that's UTC, so on a diver's birthday between 00:00 and
    08:00 Manila they show one year less than the crew page.
  - Last Dive Date has no server-side format check (only the database
    rejects an invalid date).

## Earlier update: server-side payment totals (2026-10-03, night)

**Shipped:** Save (`savePaymentOnly`) and Checkout (`checkoutVisit`) no
longer trust money values from the browser. aquadesk-app `master` =
`203f51f`; root repo `c536192` (migration 052). Live Cloudflare version
`dafee31b-6a24-4b57-bdf2-65fe2db25ea3`, `BUILD_ID Aro5Us8hn0nJGbg4icluc`
(deployed 2026-10-03 13:06 UTC, BUILD_ID match confirmed; no logged-in
checks by Claude). Previous live version (rollback target):
`71a464f9-2a77-4eeb-ba84-b48b7bc72b83`. Backups:
`D:\aquadesk-backups\{deposits,payments}-backup-2026-10-03T12-18-44-293Z.json`.
- **What changed:** Save calculates the grand total from the visit's
  stored activities (sum of non-cancelled `activities.total`, exactly
  what Bill Summary shows); the browser's figure is only compared, and a
  mismatch returns "totals changed — reload" (audit-logged). Save and
  Checkout validate discount (≥ 0, 2 decimals, ≤ subtotal — MK: no other
  rule or role cap), amounts (≥ 0, 2 decimals, within numeric(12,2)) and
  exchange rate (≥ 0, 6 decimals, within numeric(12,6)). **Any typed
  exchange rate is accepted (MK)**, but one that differs from the stored
  rate is audit-logged (`payment_rate_override`, once per new rate).
  Every rejection is audit-logged (`payment_rejected`). The Online-channel
  check now runs after validation. Unaltered inputs give results
  identical to the old code (10-case old-vs-new matrix + 8 money screens).
- **Migration 052** (`052_payment_audit_log.sql`): `log_payment_event()`,
  SECURITY DEFINER, only those two actions, only for the caller's own
  dive center's visit. Additive.
- **Deploy order:** 052 before the code (the new code refuses to save a
  differing exchange rate if it can't write the audit entry). Old code
  was verified working with 052 applied.
- **Rollback:** revert `203f51f` and redeploy. 052 can stay in place
  (or drop it with its rollback block once the code is back).
- **Out-of-scope findings (open):**
  1. Checkout's subtotal ignores each activity's own `discount` field
     (`checkoutVisit`'s `grandTotal` reduce) while the screen and Save
     subtract it — only matters if a per-row discount is ever non-zero,
     and the app has no input for one.
  2. `payments.excess_amount` is stored unrounded (e.g.
     `292.4935999999998`); Settlement rounds it for display.
  3. Card/online surcharges count toward paying the bill
     (`billing.ts` `computePaymentBreakdown` adds them to the amount
     tendered, not the amount owed), so paying the full bill by card
     shows the surcharge as "excess". Pre-existing; confirm the intent.

## Earlier update: diver birthday & age (2026-10-03, evening)

**Shipped:** the diver form's info grid shows **Birthday** (or "Not set")
and **Age**, and Edit Diver Info has a Birthday date field (with Clear).
aquadesk-app `master` = `b992566`; live Cloudflare version
`71a464f9-2a77-4eeb-ba84-b48b7bc72b83`, `BUILD_ID UVBb7r46x4H9cQqCGQKKz`
(deployed 2026-10-03 11:01 UTC, BUILD_ID match confirmed; logged-in
checks not done by Claude — no test login). Previous live version:
`5af7e3c5-8519-4cda-be26-20663d96d2f9`.
- **No migration.** `divers.birthday` (date, set by registration) is the
  single source of truth. Age is always calculated from it with the
  Asia/Manila date (`src/lib/age.ts`; Feb 29 counts on Mar 1 in non-leap
  years). Server-side validation in `saveDiverProfile`: real date, not in
  the future, not more than 120 years ago.
- **MK's choices:** when the birthday changes, the stored `divers.age` and
  `divers.is_minor` are recalculated in the same save (on clear: age
  cleared, is_minor kept). Documents show the diver's **current** birthday;
  signed `diver_registrations` rows are never modified (waiver lock intact).
- **Rollback:** revert `b992566` and redeploy. No database change to undo.
- **Out-of-scope findings (open):** stored `divers.age` goes stale over
  time — the staff crew page (`get_crew_schedule`, migration 030) shows it
  instead of calculating; Edit Diver Info's Last Dive Date limit uses the
  UTC date (can't pick today between 00:00–08:00 Manila); three separate
  age calculations exist (registration wizard, `scheduling/data.ts`,
  `boat-manifest/data.ts`).

## Earlier update: hardening batch (2026-10-03, later the same day)

Six fixes on top of deposit cancellation, shipped one commit per fix.
Live: Cloudflare version `5af7e3c5-8519-4cda-be26-20663d96d2f9`,
`BUILD_ID TUkfQ1ZuhmczgcT2yoMjk` (deployed 2026-10-03 ~10:13 UTC,
BUILD_ID match confirmed). `master` = aquadesk-app `e03ffc5`, root repo
`4c00801`. Code-rollback target: `1d6a7de9-926d-4f8e-b587-707c62384323`
(the deposit-cancellation deploy). MK ran all four migrations in the
SQL Editor; Claude verified each through the API against a fresh backup
(`D:\aquadesk-backups\deposits-backup-2026-10-03T10-04-26-318Z.json`,
30 rows) — counts and deposit sum unchanged throughout. MK did the
logged-in checks on production ("all good").

**The six fixes:**
1. **Unlock Bill lockout** (migration 048, `actions.ts` `unlockBill`):
   new `unlock_bill()` RPC checks the billing password through the
   internal `billing_password_gate()` — 5 wrong tries → 30-minute lock,
   "N attempt(s) left", reset on success — then reopens the visit and
   writes the `bill_unlocked` audit row in one transaction. **One shared
   counter per user** (MK's choice) across Cancel Deposit, Unlock Bill
   and the Settings password checks, stored in
   `billing_password_attempts` (from 047).
2. **Server-calculated deposits total** (code only): `savePaymentOnly`
   sums the visit's active deposits itself; the client no longer sends
   a deposits total (parameter removed, `BillSummary` updated).
3. **Direct deposit edits blocked** (migration 049, no code): two
   restrictive RLS policies (`deposits_no_client_update`,
   `deposits_no_client_delete`, both `false`) stop any direct API
   UPDATE/DELETE on deposits. Add (insert), Cancel (`cancel_deposit`,
   SECURITY DEFINER as table owner), Void Visit (FK cascade) and the
   service-role ETL are unaffected.
4. **Manila date on a just-added deposit** (code only,
   `DepositsPanel.tsx`): the row shown right after Add Deposit uses the
   Asia/Manila date instead of UTC. Stored data unchanged.
5. **Phone layout** (layout classes only): below `lg` (1024px) the app's
   main column can shrink (`min-w-0`, `p-4` on phones), the page-level
   grids use `grid-cols-1`, and Bill Summary's payment fields stack under
   `sm`. Wide tables scroll inside their cards. `lg:min-w-auto` /
   `lg:grid-cols-none` restore the defaults, so desktop (1280/1440/1920)
   is pixel-identical — MK chose to keep desktop exactly as it was.
6. **Lockout bypass closed** (migrations 050 + 051, Settings > Passwords
   and Settings > Pricing code): staff could read the bcrypt hashes from
   `dive_centers` and call `verify_billing_unlock`/`verify_owner_unlock`
   directly with unlimited guesses. 050 added `password_status()`
   (booleans only) and `check_unlock_password(kind, password)` (through
   the same gate; the owner password is owner-only). 051 hides
   `billing_unlock_hash`/`owner_unlock_hash` from anon/authenticated
   (table-level SELECT replaced by a column-level grant on every other
   column) and revokes direct execute on both `verify_*_unlock`.

**Deposits rule (MK, 2026-10-03):** there is deliberately **no "delete
deposit" button**. A wrong deposit is corrected with Cancel Deposit and a
full refund, which keeps the audit trail. Don't add a delete path.

**Deploy-order lesson — 051 must run only AFTER the new code is live.**
The code before this batch reads `dive_centers.*_unlock_hash` and calls
`verify_*_unlock` directly; with 051 in place, old Unlock Bill fails and
old Settings > Passwords silently shows passwords as "not set" (verified
on the local stand-in). 048, 049 and 050 are additive and were run
before the code deploy; old code was tested working after each.

**Rollback per migration** (SQL is commented at the bottom of each file):
- **051:** rollback restores table-level SELECT on `dive_centers` and
  execute on `verify_*_unlock`; safe any time. **Roll back 051 first if
  old code ever has to go back** — old code breaks while 051 is in place.
- **050:** drop the two functions; only after 051 is rolled back.
- **049:** drop the two policies; safe any time.
- **048:** drop `unlock_bill` and `billing_password_gate`; only after the
  code has gone back to calling `verify_billing_unlock` (and 051 is
  rolled back). Attempt rows are kept.
- Code: revert the fix's commit and redeploy; the six commits are
  independent except Fix 6 code needs 048 + 050.

**Out-of-scope findings still open (noticed, not fixed):**
- `savePaymentOnly` still trusts other client values: the grand total
  (stored and used for the balance), the discount, and the entered
  amounts/exchange rate.
- Billing/owner password hashes use bcrypt cost 6 (weak); they're hidden
  now, but stronger hashing needs the passwords re-set.
- An owner can set a new owner/billing password without the current one
  by sending `hadPassword = false` from the browser (`set_*_unlock` only
  checks the owner role). Owner-only, so low risk.
- 047's guard trigger would block deleting a custom payment channel or a
  user that a cancelled deposit references (the FK "set null" counts as
  an edit of a cancelled deposit).
- The diver form still scrolls sideways on desktops between 1024px and
  ~1475px wide (activities table), kept on purpose so desktop is unchanged.

## Current State (as of 2026-10-03 session)

**Paddle/billing status is unchanged and NOT re-verified this session**
(nothing Paddle-related touched) — same caveats as the 2026-10-02 entry
below; live `PADDLE_API_KEY` expiry 2026-11-16 is ~6 weeks out.

**Shipped: deposit cancellation** (urgent, a live user needed it). Both
repos fast-forwarded to `master` and pushed: aquadesk-app `bb90fa7`,
root repo `6c21213` (migration). Live Cloudflare version
`1d6a7de9-926d-4f8e-b587-707c62384323`, `BUILD_ID -cl44wkeSmGYA7kkOKePq`
(deployed 2026-10-03 08:30 UTC, BUILD_ID match confirmed). Previous live
version, the code-rollback target: `48ec32d6-86c1-44e8-896d-2044e12c0492`.
- **Feature:** "Cancel deposit" on each deposit in the diver form's
  Deposits panel (`CancelDepositModal.tsx`): refund amount (Full/No
  refund quick-fill, max = whole deposit), live refund/forfeited, payout
  method + channel, required reason, billing password. Cancelled
  deposits stay visible (muted, badge, date/refund/forfeit/reason) and
  are excluded from Deposits Applied, checkout, and open-bill balances.
  `voidVisit` refuses a visit that has a cancelled deposit.
- **Money model (MK chose cash basis):** a deposit stays in Money In on
  the day it was received; the refund is Money Out on the cancel day
  (Manila date); the forfeited part is listed but NOT re-counted.
  Settlement keeps the received-day row (annotated "Cancelled on…") and
  adds a negative "Deposit Refund" row on the cancel day in the payout
  method's column. Overview shows a "Deposit Refunds" Money Out line and
  a "Cancelled Deposits" section only when a cancellation is in range.
  Dashboard's today-by-channel card subtracts today's refunds. Settlement
  "Total Collected" never counted deposits (pre-existing), and a Grand
  Total cell of 0 prints "—" (`SettlementTab.tsx` `fmtPHP`, pre-existing).
- **Migration 047** (`047_deposit_cancellation.sql`, run by MK in the SQL
  Editor; Claude verified it via the API against a backup in
  `D:\aquadesk-backups\`): additive only — `deposits.status`
  (default `'active'`, backfilled all 29 rows) + cancellation columns,
  `cancel_deposit()` SECURITY DEFINER RPC (bcrypt billing-password check,
  5 wrong tries → 30-min lock via new `billing_password_attempts`, row
  lock, audit_logs `deposit_cancelled`), a guard trigger so status/
  cancel fields can only change through the RPC, and a restrictive
  delete policy so cancelled deposits can't be hard-deleted by clients.
  Deposits have no partial application in this schema: a deposit on a
  checked-out (closed) bill can't be cancelled until the bill is unlocked.
- **Rollback rule:** NEVER run 047's rollback SQL once any deposit has
  been cancelled — it drops the cancellation columns and destroys the
  money trail (one real cancellation already exists on production as of
  2026-10-03). To back out, redeploy the previous code version only and
  leave the migration in place. (Old code would credit cancelled
  deposits again on open bills — another reason to roll forward instead.)
- **Testing approach used:** no local Supabase/Docker exists, so tests
  ran on a throwaway embedded Postgres (npm `embedded-postgres`, started
  via `pg_ctl` because `postgres.exe` refuses an admin shell) + local
  PostgREST + a tiny fake GoTrue gateway, with the dev server pointed at
  it via process env overrides (no `.env` edits), driven by Playwright.
  All scratch files lived in the session scratchpad, not the repos.
- **Access facts:** the Supabase CLI on this machine is NOT logged in
  (`projects list` → Unauthorized) and the DB password isn't stored, so
  Claude cannot run SQL on production — migrations go through MK. The
  `.env.local` service-role key allows REST reads/writes only.
- **Not fixed (out of scope, noticed):** Unlock Bill's billing password
  has no rate limit; tenant RLS still lets any user edit/delete an active
  deposit directly; `savePaymentOnly` trusts the client's deposits total;
  a just-added deposit shows the UTC date until reload; diver form and
  Reports overflow horizontally at phone width.

### 2026-10-02 session (previous Current State, kept verbatim)

**Paddle/billing status is unchanged and NOT re-verified this
session** — nothing Paddle-related was touched. Everything in "Resume
Checklist" and "Time-Sensitive" above is still exactly as dated
(2026-08-19); re-verify per those sections' own instructions before
trusting it. Note the live `PADDLE_API_KEY` was still blank in
`.env.production.local` when its variable names were listed this
session (values not read) — the 2026-11-16 expiry date above is now
about six weeks out.

Today's work was a set of small, explicitly-scoped UI improvements
requested by MK under a strict "investigate → report → wait for
approval → implement → validate" process (MK's own prompt; no
migrations, no schema changes, no data touched). Both commits are live.

**Shipped (commits `17ee0c1` + `7a18f56`, `origin/master` =
`7a18f56`, live Cloudflare version `48ec32d6-86c1-44e8-896d-2044e12c0492`,
deployed 2026-10-02 06:40 UTC, confirmed via `wrangler deployments
list` + live/local `BUILD_ID` match `S-3u-t299xyxrsfIKWitE`):**
1. **Group Registration Link date labels** (`divers/components/
   GroupManagementTab.tsx`): the two bare `<input type="date">`s
   (already correctly wired to `arrival_date`/`departure_date` in
   `createRegistrationLinkGroup`) now have "Arrival Date"/"Departure
   Date" labels. Label-only change.
2. **Phase 2 notes visible in Phase 3** (`scheduling/components/
   PhaseThreePanel.tsx`): the trip card header now shows the trip
   `notes` and the "Other Divers Joining" `guestNotes` under the
   dive-site chips (the old app's `confirmTripHTML()` showed
   `notesText` there; the rebuild had dropped it). `getTripDetail()`
   already returned both fields — Phase 3 just never rendered them.
   `tripPreviewText()` (shared by Copy Preview *and* Download Image)
   gained an "Other Divers Joining Notes:" line. Phase 3 shows *saved*
   values only, same as every other Phase 3 field.
3. **Staff page** (`staff/StaffScheduleClient.tsx`): the Join Rides
   block already showed `guest_notes`, but only when a guest count or
   dive center name was also set — now notes alone are enough.
   Migration 030 is confirmed as the latest `get_crew_schedule` and
   already returns `guest_notes`.
4. **Phone/WhatsApp country-code picker** (`components/PhoneInput.tsx`,
   `lib/countryCodes.ts`, `register/RegistrationWizard.tsx` — the
   picker is used *only* on diver registration, 4 fields): options now
   read "🇵🇭 +63 Philippines" (previously flag + code only, and Windows
   renders flag emoji as two letters, so it was nearly unusable);
   list sorted alphabetically with "Other" last; **no default** — MK
   explicitly asked for no preselected country (not even Philippines),
   so every field starts on a disabled "Country code" placeholder and
   step validation requires a code whenever a number is entered;
   United States/Canada merged into one "United States / Canada" `+1`
   entry (they previously collided: same `<option value>`, so picking
   Canada snapped back to US); `DEFAULT_COUNTRY_DIAL_CODE` removed
   entirely; `splitStoredPhone()`'s fallback for a returning diver's
   unmatched stored number is now `""` (forces a pick) instead of
   silently prepending `+63`. Select is fixed-width (`w-36`) so the
   number field keeps its room on phones.
5. **"Partner" relationship option**, after "Spouse", in all three
   separate lists: `register/types.ts` `RELATIONSHIPS`,
   `diver-form/[id]/constants.ts`, `settings/staff/constants.ts`.
   `emergency_contact_relationship` is plain `text` with no check
   constraint, so no migration needed. **These three lists are
   independent copies — any future relationship change must touch all
   three.**

**Considered and deliberately not changed** (MK's call, or reported
only per the strict-scope rule):
- Phase 3's joiner count/company is already shown, in the navy tank-
  tally bar ("Joining us: N (DC)") — MK had missed it; no change wanted.
- Copy Preview/Download Image only include the "Joining us" line when
  `guestDiversCount > 0`, so a dive-center name alone is omitted there
  (staff page shows it). Reported, not fixed.
- `downloadTripImage()` doesn't wrap long lines — anything past ~640px
  (long notes especially) is clipped off the PNG. Pre-existing.
- "Confirm Schedule" in Phase 2 only blocks on *unsaved new* trips, not
  unsaved edits to existing trips — so typed-but-unsaved notes won't
  reach Phase 3.
- The group-link form's other inputs are still placeholder-only (no
  labels), and its `grid-cols-2` doesn't stack on phones.
- Two pre-existing `@next/next/no-img-element` lint warnings in
  `StaffScheduleClient.tsx` (lines ~212/247).
- **No test suite exists in `aquadesk-app` at all** (zero
  `*.test.*`/`*.spec.*` files) — validation is `tsc --noEmit` + `eslint`
  + MK checking on the dev server. No browser tool was available this
  session either; MK verified both rounds visually on the local dev
  server before approving commit/deploy (the Lesson 13 default, now
  followed without being asked).

**Environment facts found this session:**
- `gh` had **three** accounts logged in: `mkbusiness-ai` (active —
  another of MK's accounts, not this project's), `aquadeskonlinesolutions`,
  and `usemiraapp-ai`. Switched with `gh auth switch --hostname
  github.com --user aquadeskonlinesolutions` (no re-login needed —
  all three stay in the keyring). Git's credential helper for
  github.com is `gh auth git-credential` (user `.gitconfig`), so the
  *active gh account* is what git pushes as — being logged in on the
  github.com website is irrelevant. Confirmed push rights via
  `gh api repos/aquadeskonlinesolutions/aquadesk-app --jq .permissions`.
- `wrangler` is logged in via **OAuth** as `aquadeskonline@gmail.com`
  → live account `4ec5d01b30db05b278baa0630e421340` only; no
  `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` env vars were needed
  for the live deploy. (Pre-prod is a different account — this OAuth
  login can't deploy there.) `wrangler whoami` warns about a missing
  `challenge-widgets.write` scope; harmless for deploys.
- PowerShell 5.1 mangles multi-line here-string commit messages passed
  to native `git commit -m`/`-F -` (embedded double quotes split into
  pathspecs — nothing got committed, files were left staged). Use
  `git commit -F <file>` with the message written to a scratch file.
  Added to "Working practices" below.

**Dead-code check this session:** `DEFAULT_COUNTRY_DIAL_CODE` was the
only symbol made unused by today's changes; removed in the same commit
(grep confirms zero remaining references). `tsc --noEmit` clean,
`eslint` clean on all 9 touched files (bar the 2 pre-existing warnings
above).

### Prior sessions (condensed further — see `PROJECT_HISTORY.md` for full detail)

**2026-09-07**: Billing Audit fix set + three rounds of live-regression
cleanup. (1) `loadBillingAuditData()` (`reports/data.ts`) now scopes
the "Invoice History" table's `invoice_emails` query to the Reports
date range via `manilaDayBoundsUtcIso()` — the "Flagged Bills"
expansion deliberately stays unfiltered (a flagged visit's full
closure history must never be hidden). `ReportsClient.tsx` refetches
it on Apply like the other tabs. (2) `BillingAuditTab.tsx` relabeled
"Sent At" → "Closed On" and "Invoices Sent" → "Times Closed"
(`sent_at` always equals bill-close time, never email-send time;
`email_sent_at`/`email_delivery_status` exist separately and are
unused). (3) Reports date-picker row stacks below `sm`. (4) Regression
cleanup: a leftover default-Next.js `@media (prefers-color-scheme:
dark)` block in `globals.css` (zero `dark:` usage anywhere) was
flipping inherited text color on dark-mode devices — a half-fix
(`color-scheme: light` alone) shipped live and broke login/
registration input visibility before the block was removed entirely;
full story in Lessons 12–13. (5) Sign Out moved into `Sidebar.tsx`'s
name/role block and the empty top `<header>` removed from
`(app)/layout.tsx` (not a regression — original structure; MK asked
anyway). **Still-useful fact: there is no shared "page title row"
component across `(app)/` pages** — Dashboard, Reports, Boat Manifest,
Diver Form list, Scheduling, Divers, Settings and Diver Detail each
build their own, with real structural differences; check each page
individually for any page-chrome work. That session also set the
standing "state deployment status in the same message as any live
verification request" rule (in Working practices) and found the
`usemiraapp-ai` gh-account problem (Lesson 15). Dead-code audit of all
touched files came back clean.

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

- **Local stand-in (how UI/money changes are tested — there is no local
  Supabase/Docker).** Latest copy: `C:\Users\MVRTN\AppData\Local\Temp\
  claude\D--rebuild\52c9556f-6253-4144-be72-5a9aaa671ce8\scratchpad\pgtest\`
  (scratchpads are per session and may be cleaned by Windows; copy it into
  the new session's scratchpad with `robocopy /E`, excluding `shots`,
  `hb`, `inv_out`, `emails`, `*.log`). Pieces: embedded Postgres (`node
  db.js start`, port 54329, migrations through 055 + test data; seeds
  `*_seed.js`), PostgREST (`postgrest\postgrest.exe postgrest.conf`,
  port 54330 — **the embedded-postgres `node_modules\@embedded-postgres\
  windows-x64\native\bin` folder must be on PATH**, else it exits
  silently), fake GoTrue + gateway (`node gateway.js`, port 54321, every
  test login's password is `Test1234!`, owner = `owner@test.local`),
  fake Resend (`node fakeresend.js`, port 54340, saves emails to
  `emails\`). Dev server: `devinv.ps1` (process-env overrides only, no
  `.env` edits; sets `RESEND_BASE_URL`) on port 3100, **started from
  `D:\Rebuild\aquadesk-app` (capital R)**. Driven by Playwright scripts
  (`invflow.js`, `regress_inv.js`, …). Regression method: capture page
  text on new code, `git stash` the change, capture on old code with the
  same DB, diff. Stop everything afterwards (`node db.js stop`, kill
  postgrest/gateway/fakeresend/dev) and delete `.next` after any build.

- **Any new column on `public.dive_centers` needs an explicit grant** or
  the app can't read it: `grant select (column) on public.dive_centers
  to anon, authenticated;` in the same migration. Since migration 051
  (2026-10-03) that table has column-level SELECT grants only (the two
  password-hash columns are deliberately excluded), and
  `select('*')` on it fails for app users.
- **Never run migration 047's rollback SQL once any deposit has been
  cancelled** (`select count(*) from deposits where status='cancelled'`
  — already > 0 on production since 2026-10-03). It destroys the
  cancellation money trail. Roll back code only; leave 047 in place.

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
- **Commit messages from PowerShell: always `git commit -F <file>`**
  (write the message to a scratch file first). Passing a multi-line
  here-string via `-m` or `-F -` in Windows PowerShell 5.1 splits on
  embedded double quotes and git treats the fragments as pathspecs —
  hit 2026-10-02; nothing was committed, files were left staged.
  Before the first push of a session, also run `gh auth status` — the
  *active* gh account is what git pushes as (credential helper is
  `gh auth git-credential`), and this machine has several of MK's
  accounts logged in; switch with `gh auth switch --hostname github.com
  --user aquadeskonlinesolutions`.
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

**Lessons 16–22 — wrong turns from the 2026-10-04 invoice session.**
None reached production; all cost time. Don't repeat them.

16. **Same key name, different meaning, across the old app and the
    rebuild.** The invoice snapshot's `grand_total` is the activity
    subtotal in rebuild invoices but **total collected incl. surcharge**
    in old-app invoices (`diver-form.html` `buildPaymentPayload`:
    `grand_total_php: p.totalCollected`). The first plan was to label it
    "Subtotal" everywhere; that would have printed wrong subtotals on
    every migrated invoice. Caught only by reading the old app's writer.
    **Don't:** reuse a stored field's value under a new label because its
    name sounds right. **Do:** for any stored JSON/column that both apps
    wrote, read the *old app's writer code* before deciding what the value
    means, and prefer deriving from raw rows (here: the snapshot's own
    activity lines) over a pre-computed total.

17. **Debugged the data when the router was the problem.** Every
    `/diver-form/[id]` page 404'd on the stand-in. Time went into checking
    divers, RLS and PostgREST queries (all fine) before noticing the dev
    log showed 404 in ~50 ms with the page never compiling. Cause: the dev
    server was started from `D:\rebuild\aquadesk-app`; the real folder is
    `D:\Rebuild`, and Turbopack's route matching for the dynamic segment
    breaks on the casing mismatch. **Don't:** start `next dev` from a
    lowercase `D:\rebuild` path. **Do:** `Set-Location D:\Rebuild\aquadesk-app`,
    and when a page 404s instantly without compiling, suspect routing/
    path before data.

18. **PowerShell silently re-encoded UTF-8 test scripts.** A one-line ID
    fix via `Get-Content -Raw` + `WriteAllText` turned every `₱` in the
    test expectations into `â‚±`, so 0/14 cases "failed" while the app was
    correct. The repair script was itself written with `Set-Content`
    (ANSI), so its own `₱` literal was mangled; it ran, changed nothing,
    and **printed "ok"** because its check only looked for the wrong
    thing. **Don't:** edit files containing non-ASCII text through
    PowerShell `Get-Content`/`Set-Content`, and don't trust a fix script
    whose success check can't detect its own failure. **Do:** use the
    Write/Edit tools, or `\u20B1` / `\u2212` escapes in scripts. When
    every test fails at once, check the harness before the app.

19. **Assumed a copied binary would just run.** The copied
    `postgrest.exe` exited silently (no log). It was exit 0xC0000135, DLL
    not found: PostgREST needs libpq from the embedded-postgres `bin`
    folder on PATH. **Do:** run a copied/unfamiliar exe once in the
    foreground with `--version` and read `$LASTEXITCODE` before wiring it
    into background `Start-Process` calls that hide errors.

20. **Test-harness mismatches produced false failures twice:** a UUID
    builder that produced 10 hex chars in the first group (seed rolled
    back), and the fake Resend saved files with `-` → `_` while the test
    looked up the raw name ("email not captured"). The failed run had
    already marked the invoices "Sent", so the rerun first had to reset
    `email_delivery_status`. **Do:** when a fake service transforms a
    key, share one function for it; make test runs re-runnable (reset
    any state the run itself changes) before the first run.

21. **Looked for the BUILD_ID with a guessed regex.** Next 16 puts it in
    the RSC payload as `"b":"<BUILD_ID>"`, not `buildId`. **Do:** check
    the served HTML for the literal BUILD_ID string (old and new) — no
    pattern guessing.

22. **Rule kept, worth keeping:** before changing the invoice, Step 1
    proved *where* the deposit was lost (not stored + never passed + not
    loaded) instead of assuming "filtered". That choice decided the fix
    (read active deposits at print/send) without touching checkout or
    stored data. Keep doing evidence-first investigation for money bugs.

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
