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
  001–039), the source of truth for schema/RLS/functions.

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

## Current State (as of 2026-08-18 session, in progress)

**Update (later same day):** the live Paddle migration described below
is now **code-complete and deployed** — nothing left to build. It's
blocked purely on two external approvals: Paddle domain/account
verification and Payoneer identity verification, both expected within
~3 days. Once they clear, the remaining steps are: paste the live
`PADDLE_API_KEY` into `.env.production.local` (still blank), flip
`NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED` to `true` in that same file, and
then opt individual dive centers into Paddle billing one at a time via
the new `paddle_billing_enabled` toggle in `/office` (migration 040,
shipped this session) rather than turning it on for everyone at once —
see `PROJECT_HISTORY.md` if this file's own write-up of that session
has since been archived.

**The rebuild has been feature-complete and in an ongoing feedback-
response + new-feature phase since 2026-07-25.** `aquadesk.online` has
served the rebuild since the 2026-08-08 cutover. Six real dive centers
exist: Test Dive Center, Package Test Dive Center (shared test fixture,
reset to baseline after every testing pass), Atlas Divers Malapascua,
Divergems Diving Center, Dive Nation Malapascua (the one real paying
client), and Demo Dive Center. Migrations run through **039**. Full
detail on the 2026-08-17 session (Paddle sandbox billing built,
hardened, verified) is in `PROJECT_HISTORY.md`.

### This session: migrating the tested sandbox Paddle integration to live

Goal: get the live Paddle account and code ready for **verification**
(the "Verify your account" / "Test and go live" steps are explicitly
*not* part of this) — additive/code-side only, no live entity deleted
or recreated. **Session paused partway through — resume here.**

**Done:**
- **Live catalog created**: product `pro_01m09hht4axrx7hk2srdxk95gk`
  ("AquaDesk"), prices `pri_01m09hhte5a3xqf0wbecr5q2jw` (Monthly,
  $65 USD) and `pri_01m09hhtq4h5hcvz6ayesta107` (Annual, $733 USD) —
  mirrors the sandbox catalog exactly. No discounts existed in sandbox,
  so none to migrate.
- **Live client-side token created**: `ctkn_01m09hhxr3j4ppg16j98f4eq0b`
  (`live_0b0ec3885c3ac1b33c9562b6634`).
- **Live notification destination created**: `AquaDesk production
  webhook` (`ntfset_01m09hja3yk2cbm1hr61hb5ky6`), pointed at
  `https://aquadesk.online/api/webhooks/paddle`, subscribed to the same
  6 events the webhook handler acts on (`transaction.completed`,
  `subscription.created/canceled/past_due/updated/activated`). The
  live account genuinely had zero notification destinations before
  this (confirmed with the user directly — see MCP quirk below on why
  the API alone couldn't prove that). **Never recreate this — doing so
  rotates `endpoint_secret_key` and silently breaks every future
  delivery.**
- **Code swapped to be environment-aware, not hardcoded-to-one-env**:
  `actions.ts`'s `PRICE_IDS` is now keyed by `NEXT_PUBLIC_PADDLE_ENV`
  (sandbox vs. production), same var `getPaddleInstance()` already
  gated on — deliberately **not** a literal find-and-replace of the
  sandbox IDs, since that would have broken local sandbox testing
  (asked for in this same request: "verify locally or in staging").
  There was already no `Paddle.Environment.set('sandbox')` anywhere to
  remove — the codebase was built environment-driven from day one.
- **Paddle Retain wired up**: `settings/subscription/page.tsx` now
  selects `paddle_customer_id` and passes it down;
  `SubscriptionClient.tsx` adds `pwCustomer: { id: paddleCustomerId }`
  to `Paddle.Initialize()` when present (omitted entirely pre-first-
  checkout, per Paddle's own requirement that this be a real Paddle
  customer id, never an internal id/email). Verified against the
  installed `@paddle/paddle-js` types (`PaddleSetupBaseOptions.
  pwCustomer`) — `tsc --noEmit` passes clean.
- **Webhook IP allowlist added**: new
  `src/lib/paddle/webhook-ip-allowlist.ts` fetches
  `https://api.paddle.com/ips` (not hardcoded — that endpoint is the
  source of truth), caches 1 hour, fails open only if never once
  successfully fetched. Wired into `route.ts` but **gated to
  `NEXT_PUBLIC_PADDLE_ENV === "production"` only** — a bare `cf-
  connecting-ip` check would otherwise reject local `cloudflared`-
  tunnel sandbox testing, which doesn't carry that header the way
  Cloudflare's own edge does. Defense-in-depth on top of, not instead
  of, `Paddle-Signature` verification.
- **Closed the standing `.env.production.local` gap from 2026-08-17's
  Lesson #3** (a `NEXT_PUBLIC_*` kill switch almost shipped enabled
  because `.env.local` was the only thing `cf:build` ever read):
  `.env.production.local` now exists (gitignored, verified against how
  `opennextjs-cloudflare build` actually invokes `next build` as a
  real subprocess — standard Next.js env-file precedence applies) with
  the live client token, `NEXT_PUBLIC_PADDLE_ENV=production`, the live
  webhook secret, and `NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED=false`
  (deliberately, per this task's explicit "don't open to real
  customers yet"). Local dev (`.env.local`) is completely untouched —
  still sandbox, still `SUBSCRIPTION_TAB_ENABLED=true`. **This means a
  future `cf:build`/`cf:deploy` will pick up live Paddle values
  automatically without anyone hand-editing `.env.local` — check this
  file's own values are still what should ship before ever flipping
  `NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED=true` here for a real go-live
  build.**
- `.env.example` created (blank template, all current keys documented).

**A real MCP tool quirk hit this session — worth knowing about before
trusting `notificationSettings.list()` again**: both the sandbox and
live Paddle MCP connections return an **empty array** from
`client.notificationSettings.list()` while `pagination.estimatedTotal`
reports a non-zero, inconsistent count across repeated identical calls
(seen: 2, then 1, then 2 again on live; 1 on sandbox) — every other
list endpoint tried (`products`, `prices`, `clientTokens`) had counts
that matched their arrays exactly. Given the guardrail against ever
recreating a live notification destination, this session stopped and
asked the user to confirm via the dashboard directly rather than
trust/ignore the count — they confirmed live had zero. **Don't trust
`notificationSettings.list()`'s array as ground truth without cross-
checking `pagination.estimatedTotal` for a mismatch first**, and if
one exists, verify directly in the dashboard rather than guessing.
Separately, the live MCP connection's first attempt at all three
`*.create()` write calls failed with "You aren't permitted to perform
this request" despite correct permissions already being saved — the
user reauthorized the connection fresh and the retry succeeded
immediately. **If a Paddle MCP write is rejected on a permissions
error even though the dashboard-side permissions look correct, try a
full reconnect before assuming the permissions themselves are wrong.**

**Still outstanding — all require either a live API key the MCP can't
create, or dashboard-only actions the MCP doesn't expose:**
1. **Live `PADDLE_API_KEY`**: no API-creation method exists via this
   MCP (confirmed by search) — the user needs to create one in
   Developer Tools > API keys and paste it into
   `.env.production.local` (currently blank there).
2. **Payment methods** (Checkout > Checkout settings > Payment
   methods) — not exposed by this MCP at all, dashboard only.
3. **Default payment link** (Checkout > Checkout settings) — dashboard
   only, must be a real approved domain, not localhost. **Tension to
   flag**: the only page that would serve as that link
   (`/settings/subscription`) currently redirects away in every real
   deployed build, live or pre-prod, because
   `NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED` is off everywhere except
   local dev — so there's no publicly reachable live checkout page to
   point the default link at yet. Worth deciding whether to
   temporarily flip the pre-prod build's flag on for this purpose
   before assuming the dashboard step is simple.
4. **Domain approval** (Checkout > Request domain approval) — the MCP
   only exposes `checkoutDomains.get/list/delete/verify`, no
   create/submit method, confirmed by search. Submit `aquadesk.online`
   (and consider the pre-prod domain too, if live checkout testing is
   wanted there before going fully live — see tension above).
5. **Bank details** (Business account > Payouts > Payout settings) —
   dashboard only.
6. **Pre-verification readiness gaps found, not yet fixed**:
   - **No live Terms & Conditions, Privacy Policy, or Refund/
     Cancellation Policy page exists anywhere publicly.** The only
     related text is the "Service Agreement" in
     `settings/subscription/constants.ts`, rendered inside an
     authenticated page that's currently unreachable. This is a real
     gap for verification, not just a nice-to-have.
   - **Public pricing doesn't match the live Paddle catalog just
     created.** `LandingPage.tsx`'s `#pricing` section advertises
     ₱4,000/month with "14-day free trial · No credit card required."
     The live catalog is $65 USD/mo or $733 USD/yr with no trial
     period configured anywhere in the code. Needs a decision — update
     the landing page copy, or add trial pricing/PHP support to the
     Paddle catalog — before this would pass a reviewer's pricing
     check.
   - Contact (`mkbusiness.ai@gmail.com` in the footer) and product
     description are both fine as-is.
   - `aquadesk.online` itself wasn't re-verified live this session
     (`WebFetch` got a 403, most likely Cloudflare bot-challenge
     rather than a real outage, given the 2026-08-08 cutover and no
     reason to suspect regression — but not actually confirmed, and
     this session had no browser tool per the 2026-08-17 note below).

### Suggested next step

Resume this exact task: once the user has (a) reauthorized/fixed
anything else needed, (b) created the live API key, and (c) made the
dashboard-only decisions above (especially the default-payment-link /
domain-approval tension), finish wiring the live API key into
`.env.production.local`, then move to the pre-verification pricing/
legal-pages gaps before suggesting they proceed to "Verify your
account." Do **not** flip `NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED=true`
anywhere or deploy a live-pointed build until the user explicitly says
verification has passed.

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
  like that. **Also new as of 2026-08-17: check whether a browser tool
  exists at all via `ToolSearch` before assuming — this session had
  none, unlike documented earlier ones.**
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
  feature-flag's current value in `.env.local` against what should
  actually ship** (see Lessons #3 — this is not yet automated) →
  rename `src/proxy.ts` out of the way (Node.js middleware isn't
  supported by the installed OpenNext adapter version) → `npm run
  cf:build` → restore `src/proxy.ts` immediately → `wrangler deploy
  --config wrangler.live.jsonc` (or the pre-prod config) with that
  account's `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` — **check
  which Cloudflare account's credentials are in hand, live and pre-prod
  are separate accounts, matching the Supabase live/rebuild distinction
  above** → smoke-check the real domain directly, not `workers.dev`.

## Lessons (condensed — full 66+-item numbered retrospective in `PROJECT_HISTORY.md`)

**Today's three — read these before touching Paddle billing or the
build/deploy pipeline again:**

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
