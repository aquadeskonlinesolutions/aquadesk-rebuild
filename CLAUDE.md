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
  001–040), the source of truth for schema/RLS/functions.

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

## Current State (as of 2026-08-19 session)

**What's live on `aquadesk.online` right now** (verified 2026-08-19 —
direct `curl` with a browser User-Agent against the real domain, not
`WebFetch`, which 403s on this domain due to Cloudflare's bot challenge,
not an outage):
- The rebuild itself, serving since the 2026-08-08 cutover.
- Landing page pricing correctly shows $65/mo ≈ ₱4,000/mo and $733/yr ≈
  ₱45,000/yr, no trial-period language — this was actually fixed via
  commit `75957e2` during the 2026-08-18 session; a prior version of
  this file's write-up called it "not yet fixed," which was simply
  stale by the time it was read again on 2026-08-19, not a real gap.
- Public, unauthenticated legal pages: `/terms`, `/privacy`,
  `/refund-policy` — added 2026-08-19, linked from the landing footer.
  Terms and Refund Policy adapted from the "Service Agreement" in
  `settings/subscription/constants.ts`; Privacy Policy is new content
  (data collected, third-party processors: Supabase, Paddle, Cloudflare,
  Resend). Contact email on all three is `aquadeskonline@gmail.com`
  (the landing footer itself still shows `mkbusiness.ai@gmail.com` —
  left as-is, out of scope for that change).
- A working "Request a Free Demo" form on the landing page — wired
  2026-08-19 via a new Server Action (`src/lib/actions/demoRequest.ts`),
  sending to `aquadeskonline@gmail.com` with reply-to set to the
  submitter, an off-screen honeypot field, and required-field/email
  validation. Reuses the *same* Resend setup as invoice emails
  (`getResendClient()`/`RESEND_FROM_EMAIL`) — see the Resend caveat
  below.
- Settings > Subscription tab is **hidden** — `NEXT_PUBLIC_SUBSCRIPTION_
  TAB_ENABLED=false` in `.env.production.local` — so no real customer
  can reach Paddle checkout yet. This is deliberate, not a bug.

**What's built but dormant** (code-complete, not reachable by real
customers):
- The full live Paddle billing stack: catalog, client-side token, Retain
  wiring, webhook IP allowlist, environment-aware price IDs, server-side
  checkout Server Action. Built 2026-08-18, confirmed still active via a
  direct Paddle API query on 2026-08-19 (see Resume Checklist step 4).
  Dormant because (a) the Subscription tab kill switch is off, and (b)
  the live `PADDLE_API_KEY` is still blank in `.env.production.local`.
- Two per-dive-center opt-in flags, both schema-level and wired into
  `/office`: `boat_manifest_enabled` (migration 039) and
  `paddle_billing_enabled` (migration 040, 2026-08-18). The latter has
  no effect on any dive center yet — it's gated behind the tab-level
  kill switch above, so flipping it per-center today does nothing
  observable until that switch also flips.

**What's genuinely pending external parties** (nothing this codebase or
a future session can unblock directly):
- Paddle account verification and the `aquadesk.online` checkout-domain
  review (submitted 2026-08-18 as `chedom_01m09jyk1m5w7xmj6gt9cb5qgq`,
  confirmed still `pending_review` via API on 2026-08-19).
- Payoneer identity verification (payout provider, separate system, no
  programmatic way to check status).
- See "Time-Sensitive" above — the "~3 days" estimate for both is dated
  2026-08-19 and should not be repeated forward as still-current.

**What's fully done, no further action needed**: the public legal pages,
the demo request form, the landing-page pricing fix, migrations 001–040
applied. The six real dive centers (Test Dive Center, Package Test Dive
Center — shared fixture reset after testing, Atlas Divers Malapascua,
Divergems Diving Center, Dive Nation Malapascua — the one real paying
client, Demo Dive Center) were not re-verified this session; carried
forward from the 2026-08-17 write-up in `PROJECT_HISTORY.md` unchanged.

**Resend caveat** (applies to both invoice emails and the new demo
request form): `RESEND_FROM_EMAIL` is Resend's shared sandbox address
(`onboarding@resend.dev`, no custom domain verified on the account) in
*every* environment, including `.env.production.local` — no override
exists there. This works today only because the fixed recipients
(`aquadeskonline@gmail.com` for demo requests; each diver's own address
for invoices) happen to be reachable from that sandbox address — a real
send to `aquadeskonline@gmail.com` was verified via direct Resend API
call on 2026-08-19. Existing code comments flag this as intentionally
deferred pending a real `aquadesk.online` sending subdomain — worth
scoping as its own follow-up (it would fix both use cases at once), not
a today problem.

**Dead-code audit for everything built in the 2026-08-19 session** (demo
request form + legal pages): clean. `requestDemo` has exactly the two
expected call sites (definition + the one call in `DemoModal`); no
stray "not wired up" placeholder text remains anywhere in `src/`; the
three legal page files and the `(legal)` layout are only reachable via
Next.js file-based routing (expected — page files aren't meant to be
imported elsewhere). No orphaned code found.

**A Paddle MCP quirk found this session, worth knowing before next use**:
`.get()`-style methods (`products.get`, `prices.get`, `clientTokens.get`,
`notificationSettings.get`, etc.) take the ID as a **positional string
argument** — `client.products.get("pro_...")` — not an object like
`{ product_id: "pro_..." }`, even though `paddle:search`'s own
documented param shape suggests the latter. Passing an object produces
`"URL called is invalid."` with no clearer hint. This is on top of the
2026-08-18 finding that `notificationSettings.list()`'s returned array
can't be trusted without cross-checking `pagination.estimatedTotal`.

### Prior sessions (condensed further — see `PROJECT_HISTORY.md` for full detail)

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
  `begin;`/`commit;` inside the SQL file itself.
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
