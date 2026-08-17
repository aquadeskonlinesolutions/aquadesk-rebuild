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

## Current State (as of 2026-08-17 session end)

**The rebuild has been feature-complete and in an ongoing feedback-
response + new-feature phase since 2026-07-25** (all originally-planned
pages built; work since then is bug fixes, polish, and new scoped
features the user brings). `aquadesk.online` has served the rebuild
(not the old app) since the 2026-08-08 cutover. Six real dive centers
exist: Test Dive Center, Package Test Dive Center (a shared, persistent
*test* fixture other sessions reuse — reset to a clean baseline after
every testing pass, see below), Atlas Divers Malapascua, Divergems
Diving Center, Dive Nation Malapascua (the one real actively-operating
paying client), and Demo Dive Center. Migrations run through **039**.

### Today's session: Paddle subscription billing, built and shipped

A full self-serve billing integration was built, hardened, verified,
and deployed live — but **deliberately kept invisible to real users**
until the live Paddle account is verified (see kill switch below).

- **Settings > Subscription tab** (`settings/subscription/`): shows
  current `subscription_status`, lets an owner pick Monthly
  ($65/mo, `pri_01m05n3arvpxce4d910jpbqxn6`) or Annual ($733/yr,
  `pri_01m05n3av5d8bgbsdwpn8q781j`) — both under Paddle sandbox product
  `pro_01m05n3aqpdaf5n62txw4aqdbp` — and opens Paddle checkout. Also
  displays the full AquaDesk Service Agreement (`constants.ts`) in a
  scrollable box between the status row and the plan picker.
- **Checkout is security-hardened**: the Paddle transaction is created
  **server-side** (`createSubscriptionCheckoutTransaction` in
  `actions.ts`, calling `paddle.transactions.create()`), with
  `customData.aquadesk_dive_center_id`/`aquadesk_user_id` derived from
  the authenticated session (`requireOwner()`) — never from anything the
  browser sends. The client only ever receives an opaque `transactionId`
  and calls `Checkout.open({ transactionId })`. This closes a real
  cross-tenant hijack hole the first version had — see Lessons below,
  item 1.
- **Webhook route** (`src/app/api/webhooks/paddle/route.ts` +
  `src/lib/paddle/{server,process-webhook}.ts`): verifies
  `Paddle-Signature` via `paddle.webhooks.unmarshal()` before trusting
  anything. Handles `transaction.completed`/`subscription.created`
  (activate, matched via `customData` — the only events that carry it),
  `subscription.canceled` → `cancelled`, `subscription.past_due` →
  `suspended`, and `subscription.updated`/`subscription.activated` →
  back to `active` when the event's own status says so (recovers a
  dive center once a failed-payment retry succeeds). Every lifecycle
  event after the first activation is matched by the stored
  `paddle_subscription_id`, not `customData` (renewals never carry it).
  `proxy.ts`'s `PUBLIC_ROUTES` had to gain `/api/webhooks/paddle` — a
  real bug (same class as an earlier `/crew`/`/reset-password` miss)
  that would have silently redirected every real Paddle delivery to
  `/login`.
- **Migration 038**: `dive_centers.paddle_subscription_id`/
  `paddle_customer_id`, partial unique index on the former.
- **`/office`**: shows each dive center's Paddle IDs via a "Paddle-
  managed" badge next to the (already-existing) manual status override
  dropdown, and hides the manual Start Billing/Mark as Paid buttons
  (replaced with "Managed by Paddle") whenever a Paddle subscription is
  attached — so a platform admin can't accidentally run a parallel
  manual billing cycle on top of live Paddle autopay.
- **7 real findings from an `/ultrareview` pass, all fixed and
  re-verified end-to-end** (3 `normal`, 4 `nit`): the customData hijack
  hole (see Lessons #1), no duplicate-subscription guard (Lessons #2),
  no recovery path from `suspended` back to `active`, a Supabase
  zero-row update silently "succeeding" instead of retrying, the
  `/office` parallel-billing gap above, and two diagnostic-clarity
  hardenings (missing-webhook-secret and missing-`NEXT_PUBLIC_PADDLE_ENV`
  now fail loudly/distinctly instead of silently misbehaving).
- **Boat Manifest is now optional per dive center** (unrelated to
  Paddle, same session): new `dive_centers.boat_manifest_enabled`
  (migration 039, default `true` — zero disruption to existing
  Malapascua-based dive centers), enforced via a new
  `requireBoatManifestEnabled()` in `dal.ts` (the real boundary — nav
  hiding in `Sidebar.tsx`/`nav.ts` is optimistic UI only), toggled from
  `/office`. Migration 039 also had to extend the
  `enforce_dive_center_update_scope` trigger's platform-admin allowlist
  to permit this column — verified via a real simulated platform-admin
  RLS session (not a service-role bypass) that the toggle works *and*
  that out-of-scope fields are still correctly blocked.
- **Kill switch**: `NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED`
  (`src/lib/featureFlags.ts`'s `isSubscriptionTabEnabled()`) hides the
  Subscription tab from Settings nav and redirects
  `/settings/subscription` → `/settings/pricing` unless this is exactly
  the string `"true"`. **Off by default** (unset = hidden) — the live
  Paddle account isn't verified for real money yet, so this must not be
  reachable by a real customer with a real card. Build-time-only
  (`NEXT_PUBLIC_*`), so flipping it is a rebuild + redeploy, not a
  runtime toggle. Local `.env.local` has it `=true` so dev/testing isn't
  affected. **See Lessons #3 below — this almost shipped enabled to
  production tonight; there is no automated guardrail against that
  happening again, only a manual check.**

### Verification performed today (what's actually proven, not just written)

- Real Paddle sandbox checkout → real webhook delivery → correct
  Supabase write, done **twice**: once against the original (later
  found insecure) checkout shape, and again after the security rewrite
  to the `transactionId` flow — both via a real browser + a `cloudflared`
  tunnel + the Paddle sandbox notification destination
  (`ntfset_01m07mn3fvez2hcj5t2zh8dev4`) pointed at that tunnel's URL.
- Real Paddle sandbox subscription cancellation → real webhook →
  `subscription_status` correctly flipped to `cancelled`, matched
  purely by stored `paddle_subscription_id` with **no** `customData`
  present (proves the post-activation lifecycle-matching design).
- `subscription.past_due`/the new `subscription.updated`/
  `subscription.activated` recovery-to-active path were verified via
  **self-constructed, genuinely-signed** webhook requests (computed the
  real HMAC using the real secret) — **not** via an actual Paddle-
  triggered past-due/retry-success cycle. Paddle's sandbox doesn't have
  a simple one-click "make this fail then retry" dashboard action the
  way cancel is a single API call. **If a future session wants to
  close this gap for real, look at Paddle's simulator's dedicated
  subscription-renewal/past-due scenario config.**
- The `/office` Boat Manifest toggle was verified **only** via a direct
  simulated-RLS-session SQL test (rolled back, confirmed the trigger
  allows it and still blocks out-of-scope fields) — **not** clicked in
  a real browser by the user. Worth a quick visual check next time
  `/office` is touched.
- Live deploy smoke-checked directly against `aquadesk.online` (not
  `workers.dev`): root/`/login` 200, protected routes 307-redirect
  correctly, no errors. Bundle 1868.19 KiB gzipped.
- **This session had no browser/computer-automation tool available at
  all** (confirmed via `ToolSearch` — unlike some earlier sessions'
  documented tooling). Every real-browser step in this list was the
  *user* clicking through live while a background `Monitor` watched the
  dev-server log for the resulting webhook POST — not something this
  session did unassisted. **Check for a browser tool via `ToolSearch`
  early in a new session rather than assuming one is or isn't there.**

### Deployed and committed state as of session end

- **Live**: `aquadesk.online` is running today's build (Subscription
  tab correctly **disabled** in that build — see Lessons #3 for how
  close that came to going wrong).
- **`aquadesk-app`**: 5 commits made and pushed today (`2b2928b`
  Paddle billing base, `8820697` the 7 ultrareview fixes, `636da1c`
  Boat Manifest flag, `67c0bdd` Service Agreement, `6ca9ddc` the kill
  switch). Repo is clean, in sync with `origin/master`.
- **Root repo**: migrations `038`/`039` committed and pushed
  (`ec99a02`, `3b97304`). Clean, in sync with `origin/master`.
- **Package Test Dive Center** (the shared test fixture) — reset to
  its pre-session baseline (`subscription_status: active`,
  `paddle_subscription_id`/`paddle_customer_id: null`) after every
  round of live testing today. Confirmed via direct query: still 6
  real `dive_centers` rows, nothing extra left behind.
- **Local dev environment, likely stale by the next session**: a
  `cloudflared` quick tunnel and its pairing with the Paddle sandbox
  notification destination were set up for today's live-webhook
  testing. The tunnel URL is ephemeral — if that process isn't still
  running (likely not, across a machine restart or new session), the
  notification destination is pointing at a dead URL. **Don't assume
  local webhook testing still works without re-checking/re-pairing a
  fresh tunnel URL first.**

### Suggested next step

Once the live Paddle account is verified for real payments: flip
`NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED=true` for a **production** build
specifically (not by editing local `.env.local`, which only affects
local dev) and redeploy. Otherwise, whatever comes next is most likely
the same feedback-response pattern this project has been in since
2026-07-25 — no other new feature is implied by anything above.

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

3. **`NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED=true` (correct for local dev)
   almost got baked into tonight's live production build.** Next.js
   reads `.env.local` during `next build`, not only `next dev` — this
   project has no `.env.production`/`.env.production.local` override
   file, so whatever `.env.local` currently holds ships as-is. Caught
   only by deliberately reasoning through env-file precedence
   immediately before running `cf:build`, not by any automated check.
   Fixed this one time with a manual flip-to-false → build → deploy →
   flip-back-to-true sequence. **This is a real, still-open process
   gap, not a closed one** — nothing currently prevents the same
   near-miss next time a `NEXT_PUBLIC_*` kill switch exists and someone
   builds for production without checking it first. **Lesson: before
   ANY Cloudflare build/deploy, explicitly check every `NEXT_PUBLIC_*`
   feature-flag/kill-switch's current value in `.env.local` against
   what should actually ship — do not assume local dev's env state is
   deploy-safe.** Worth eventually building a real guardrail (a
   dedicated production env file the build step actually uses, or a
   pre-build assertion script) instead of relying on remembering to
   check by hand every time.

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
