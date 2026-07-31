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

## Current state (as of 2026-07-31 session — Equipment Management/Group Management/Inventory rename, Scheduling clip-merge + turnaround-time conflict detection, Move-diver fix + app-wide font/color pass)

Four itemized feedback passes in one day, all committed:

**Pass one** (`aquadesk-app@a5612d3`) — Scheduling group-name kicker,
Equipment Management own-gear display + inventory tally, Group
Management UX, Settings > Inventory rename:
- Scheduling Phase 1 diver cards now show group name as a kicker line
  above the name (matching `scheduling.html`'s real `.group-kicker`),
  applied consistently to both the Loose Divers grid and clip-member
  rows — previously inconsistent (a suffix line on one, nothing on the
  other).
- Equipment Management: a diver who registered with their own gear now
  shows "Own" in every gear column (was blank/inconsistent); all
  checkmarks removed per the user's ask (requested items show their
  size/kg value or "Requested"); print preview no longer silently drops
  the Remarks column; added a new gear-shortage cross-check against
  Settings > Inventory stock counts (a genuinely new, rebuild-only
  feature, confirmed no live-app precedent).
- Group Management cards got a permanent distinguishing background and
  an explicit Expand/Collapse button (previously relied on clicking the
  name, no visual cue it was clickable).
- Settings > Inventory's "Rental Gear" section renamed to "Gear
  Inventory" to stop it being confused with the separate Equipment
  Rental (pricing) tab.

**Pass two** (`aquadesk-app@b4af44d`, root repo migration 025
`@0104820`) — fixed a real Scheduling bug (clipping the same staff
member into two clips left them split across both instead of merging,
matching the live app's real auto-merge behavior — see retrospective
below for a similar but distinct Move-button bug found in pass three)
and added real turnaround-time conflict detection:
- `createClip`/`updateClipStaff` now check for an existing clip for
  that staff on the same date and merge into it (matching
  `scheduling.html`'s real `findExistingStaffClip`/`confirmClipMerge`)
  instead of creating a duplicate.
- Added the shared 1:4 ratio badge to Phase 1 clip cards and the live
  app's literal "over the 1:4 ratio" warning text to Phase 3.
- **Migration 025** (`database/025_trip_types.sql`): a new
  `trip_types` table (name + travel-out/travel-back/dive/surface-
  interval minutes per type) and `schedules.trip_type_id`. Ports the
  live app's real `tripWindow()`/`overlaps()` turnaround-conflict math
  (confirmed genuinely present in `scheduling.html`, contrary to this
  file's own earlier "date-level only" documentation of the rebuild's
  limitation) — but since the live app's own trip-type names/durations
  are hardcoded to one dive center's geography, the user chose (via
  `AskUserQuestion`) to recreate Trip Types as a real per-dive-center
  Settings list (new section in Settings > Dive Sites) instead of a
  fixed constant, a flat default, or per-site travel time. New shared
  `scheduling/tripWindow.ts` (`computeTripWindow`/`windowsOverlap`) is
  the single source of truth for window math, used by `WarningsBanner`
  to gate every diver/staff/**and boat** double-booking flag on real
  time overlap instead of same-date-only — falls back to the old
  always-flag behavior only when either trip lacks a departure time.
- Verified end-to-end with a real 7am/9am scenario matching the user's
  own example: two short ("Local" trip-type) trips correctly did NOT
  warn (no overlap); switching one to a long ("Offshore") type made the
  windows genuinely overlap and all three warnings (diver/staff/boat)
  correctly fired.

**Pass three** (`aquadesk-app@8312afa`) — a real Move-diver bug fix
plus an app-wide (not just Scheduling) typography/color pass, scoped
to app-wide after confirming with the user that the same patterns
recur in ~20 files including shared primitives:
- **Root cause of "Move diver not working"**: the destination picker
  only ever showed `allClips` minus the current clip, with no fallback
  — when just one clip exists for the day (an easily-reproduced case),
  the picker opened with nothing but "Cancel," indistinguishable from
  the button doing nothing. The live app's real Move modal always
  offers "Create new team" too. Added the same escape hatch: a new
  `moveDiverToNewClip` action (deletes from the old clip, then reuses
  `createClip`'s existing merge-or-create logic) plus an inline
  StaffPicker in the picker UI. Verified both the new "only one clip"
  path and the original between-two-existing-clips path still work.
- Two research passes inventoried every arbitrary sub-12px font class
  (`text-[10px]`/`text-[11px]`/`text-[0.68rem]`) and every washed-out
  badge/notice color (opacity-tinted saturated colors, or raw non-brand
  Tailwind colors like `amber-100`, instead of this app's solid pastel
  `-light` tokens) across the whole app. Bumped 23 text spots to
  `text-xs` (one genuine uppercase micro-label kicker left alone,
  confirmed to already match the live app's real 0.68rem floor) and
  added `font-size: 15px` to `body` in `globals.css` (the live app's
  real base size, confirmed identical across every reference HTML
  file — the rebuild had no explicit body size at all before this).
  Fixed 8 real color instances (the shared ratio-badge helper plus
  seven individual badges/notices) to the established
  `bg-{color}-light text-{color}` (or `text-teal-mid` for teal)
  pairing, matching the live app's own consistent formula. Deliberately
  left alone: modal scrims, translucent white-on-navy-header overlays,
  and cosmetic border-opacity accents on already-correct fills — all
  confirmed to match the live app's own intentional patterns.

**Pass four** (`aquadesk-app@34c713f`) — end-of-session dead-code audit
(see the dedicated entry further down) found and fixed one real
duplication from pass one: `EquipmentManagementTab.tsx`'s
`findRequestedItem` and `cellValue` independently implemented the same
match predicate; `cellValue` now calls `findRequestedItem` instead of
re-deriving it inline.

All four passes verified live against seeded test dive centers (this
session's own isolated-dev-server + raw-SQL-fixture pattern — see the
new Working Practices entries below for two real environment gotchas
hit while setting this up). Database confirmed back to just the real
accounts and one real `dive_centers` row at session end. Both repos
clean as of this write-up.

## Current state (as of 2026-07-30 session, continued a fifth and sixth time — Scheduling Phase 1/cert-labels/nitrox-UX/preview/boat-return, then a real `/crew` login bug + Diver Form table cleanup, Boat Manifest, Reports, Scheduling Spare Tanks)

Two more same-day passes, both fully committed and pushed by session end
(a change from earlier same-day sessions, which sometimes ended
uncommitted pending the user's go-ahead — this time the user explicitly
asked to commit after each pass).

**Pass five** (`aquadesk-app` commit `b01345e`) — five itemized
Scheduling complaints, all researched against `scheduling.html` before
any code changed:
- **Phase 1 reverted from a side-by-side sticky sidebar back to the live
  app's real two-row layout** (Loose Divers full-width on top, Suggested
  Clips below) — confirmed from `scheduling.html`'s actual
  `.phase-one-shell` (a vertical grid of two `.phase-section` blocks,
  each internally a 4-col responsive card grid), not the sidebar shape a
  *prior* session had deliberately chosen for 50+-diver scannability.
  Explicitly flagged this reversed trade-off to the user in the plan
  rather than silently dropping it — matching the live app was the
  explicit ask.
- **Certification level shown as the raw enum key** (`advanced_open_water`)
  in Scheduling's diver cards and Phase 2 team rows — added
  `CERT_LEVEL_LABELS` to `scheduling/constants.ts` (this codebase's
  established per-page constants-duplication pattern) and used it at
  both display sites.
- **Nitrox/15L selection rebuilt to match the live app's real mechanism.**
  The old rebuild had one ambiguous pill per dive site that cycled
  Air12L→Nitrox→Air15L and never gated on nitrox certification.
  `scheduling.html`'s real `diverFlagsHTML()` is two clearly labeled
  checkbox rows per diver — "Nitrox" (only rendered at all if the diver
  is nitrox-certified; a non-certified diver sees "Not nitrox certified"
  instead) and "15L" (always shown) — with a toast error rejecting any
  attempt to check both for the same dive. Rebuilt `TripCard.tsx` to
  match exactly, using the already-threaded-but-previously-unused
  `TeamDiver.nitroxCertified` field as the gate.
- **Phase 3's trip summary never showed Captain/Crew/Dive Sites on
  screen** — only buried in the clipboard "Copy Preview" text. Rebuilt
  `PhaseThreePanel.tsx`'s `TripSummaryCard` header to include a visible
  meta row (Date/Departure/Captain/Crew/diver count) and a site-chips
  row, matching `scheduling.html`'s real `confirmTripHTML()` structure.
- **Boat Return client-side gating.** `markBoatReturned`'s actual logic
  was already correct (documented in full for the user: time-gated only
  if a departure time was saved at all — a trip with none is returnable
  immediately, a genuine rebuild-specific case since this rebuild, unlike
  the live app, doesn't require a departure time to save a trip; tier
  mode writes one `activities` row per site per diver, package mode
    writes one combined row per diver with aggregated flags; pricing is
  never touched here, only Diver Detail's Auto-Price/Apply Charges do
  that). The only real gap was UX: the button was always clickable and
  only failed server-side. Added a client-side Manila-anchored
  `canReturn` check (mirroring `actions.ts`'s own `nowManilaMinute()`
  pattern) that shows "Available at h:mm AM/PM" instead of an enabled
  button before departure time, matching `scheduling.html`'s real
  `return-bar wait` state.
- Verified live end-to-end: built a two-diver trip (one nitrox-certified,
  one not), confirmed the layout/labels/checkbox-gating/toast, saved it
  with no departure time and confirmed Boat Returned was immediately
  available and produced the correct tier-mode `activities` rows (one
  per site per diver, each row's own nitrox/15L flag), then built a
  second trip with a future departure time and confirmed the button was
  replaced by "Available at 11:59 PM" until that time passed.

**Pass six** (`aquadesk-app` commit `34bd3bb`, root repo commit
`0e32da5`) — six more itemized complaints across Diver Form, Boat
Manifest, Reports, and Scheduling, one of which ("staff.html is not
accessible") turned out to be a real, previously-undiscovered production
bug, not a vague complaint:

- **`/crew` (the rebuilt equivalent of the live app's token-entry
  staff.html) was genuinely redirecting every visitor to `/login`.**
  Diagnosed by first testing on a **completely fresh, separate dev-server
  copy** (this project's established `robocopy`-to-a-temp-directory
  technique, to rule out the shared server being stale before trusting
  the result) — the bug reproduced there too, proving it was real, not a
  stale-server artifact (the opposite of what the initial static-analysis
  pass suggested — see retrospective #41 below for the wrong turn this
  took). **Root cause**: `src/lib/supabase/proxy.ts`'s `PUBLIC_ROUTES`
  allowlist (`["/login", "/register", "/account/password"]`) never
  included `/crew` — so the proxy redirected every unauthenticated
  visitor away from it before the request ever reached
  `crew/page.tsx`, which is exactly backwards for a page whose *entire*
  audience has no login. **Also found and fixed the identical bug on
  `/reset-password`** (same file, same missing-allowlist cause) —
  password-reset links were equally broken for the only audience that
  would ever click one (logged-out users). Fix: added both paths to
  `PUBLIC_ROUTES`. Verified on both the fresh copy and the real shared
  dev server afterward.
- **Diver Form's activities table had three rebuild-only additions with
  no live-app precedent**: a per-row Total column, a per-row Discount
  column, and per-row Auto-Price/Save buttons. Confirmed from
  `diver-form.html`'s real `buildActivityRow()`/`updateActivity()`/
  `saveActivity()`: the live table shows **no per-row total or discount
  at all** (discount is a single whole-bill field — which the rebuild
  *already* has correctly, in `BillSummary.tsx`, entirely separate from
  the per-row `activities.discount` column being removed from the UI
  here) and edits **persist immediately with no manual Save/Auto-Price
  step** — the live app's only recompute mechanism is the already-correct
  bulk "↺ Apply Charges" button. Rebuilt `VisitPanel.tsx`'s `ActivityRow`
  to match: removed the Total/Discount columns and the Auto-Price/Save
  buttons, converted every field to commit on blur (text/number) or
  change (the status select) via a `fieldsRef` mirror (avoiding a stale-
  closure read, this codebase's own established pattern) rather than the
  live app's literal oninput-per-keystroke, and replaced the Action
  column with a bare `✕` (or a `🔒` for Boat-Return-created rows) —
  removed the now-fully-dead `autoPriceActivityRow`/`AutoPriceRequest`
  from `actions.ts` (confirmed via grep this was their only caller).
- **Certification level shown as the raw enum** — this time in Diver
  Form's Signed Documents panel (`DocumentsViewer.tsx`, both the
  on-screen and print views) exactly as the user reported, plus a second
  instance found while verifying (not originally reported): the Diver
  Form list page (`DiversListClient.tsx`) had the same bug. Fixed both;
  added a new `diver-form/constants.ts` (the list page's own level, since
  `diver-form/[id]/constants.ts` is one directory too deep to import from
  cleanly) with the same duplicated `CERT_LEVEL_LABELS` map.
- **Boat Manifest**: confirmed from `boat-manifest.html`'s real
  `displayBoatName()` that every rendered boat name gets an "MBCA "
  prefix (guarded case-insensitively so it's never doubled) — added an
  equivalent `mbca()` helper in `BoatManifestClient.tsx`, applied at all
  three render sites (trip dropdown, lead paragraph, oath paragraph).
  Also confirmed the live app's one-page print fit is achieved entirely
  by a print-only compaction stylesheet (smaller fonts, `height:auto`
  table cells instead of the screen's fixed row height, tightened
  margins, an explicit `@page{size:A4 portrait;margin:8mm}`) — the
  rebuild had zero `@media print` rules anywhere before this. Added an
  equivalent scoped `<style>` block.
- **Reports**: the user's "confusing Rental" complaint turned out to be
  specifically about Overview's "Not Yet Settled" section (the
  `Rental — To Collect`/`Rental — To Pay` lines under Net Profit), not
  the Rental Gears tab itself — confirmed the tab's own label/card
  title/stat-card names already match `reports.html` verbatim and were
  left untouched. Renamed the four bare "Rental ..." strings in
  `OverviewTab.tsx` only to lead with "Gear Rental". Also fixed the
  Money Snapshot donut overflow **again** — a prior session's fix only
  guarded the inner 92px text "hole" with `overflow-hidden`; the outer
  150px ring itself had no clipping ancestor and no responsive cap, so it
  could still visibly escape its card on a narrow column. Added
  `overflow-hidden` to the card/wrapper and changed the ring from a bare
  `w-[150px] h-[150px]` to `w-full max-w-[150px] aspect-square` so it
  scales down instead of overflowing — verified by forcing the card down
  to 100px wide and confirming the ring shrank to fit rather than
  escaping.
- **Scheduling: Spare Tanks** — no live-app precedent anywhere (grepped
  every reference `*.html` for "spare"), a genuinely new, rebuild-only
  feature per the user's explicit ask: a per-trip repeatable list of
  spare tanks, each independently typed (Air 12L / Air 15L / Nitrox — so
  carrying "both" or "all three" is just adding more rows of different
  types), folded directly into the existing tank tally rather than a
  separate breakdown line. **Migration 020**
  (`database/020_schedule_spare_tanks.sql`): new `schedule_spare_tanks`
  table (`dive_center_id`, `schedule_id`, `tank_type` reusing the
  existing `public.tank_type` enum, `sort_order`), same 4-policy RLS
  block as `schedule_crew`. `computeTankTally` (`scheduling/tanks.ts`)
  gained an optional `spareTankTypes` param folded into the same
  air12l/air15l/nitrox totals; `TripCard.tsx` gained a "Spare Tanks"
  `SectionBox` (repeatable type-`<select>` rows, starts empty unlike
  Crew/Sites' 3-slot default); `PhaseThreePanel.tsx`'s two tally call
  sites (the on-screen summary and the Copy Preview/Download Image text)
  both pass the trip's spare tanks through too. Verified end-to-end: two
  spare tanks (one Nitrox, one Air 15L) correctly changed the live
  Build-phase tally, persisted to `schedule_spare_tanks` on save
  (confirmed via direct SQL), and the identical folded-in tally appeared
  in Phase 3.
- Verified all six live end-to-end against a fresh seeded test dive
  center; cleaned up afterward (`schedules.created_by` nulled in its own
  committed statement first, per the established cleanup-ordering
  lesson). Database confirmed back to just the two real accounts and one
  real `dive_centers` row.

**Dead-code audit for both passes**: see the dedicated dead-code-audit
entry further down — nothing found needing a fix beyond what's already
described above (the `autoPriceActivityRow` removal and a stale comment
referencing it, both already fixed in place, not left dangling).

## Current state (as of 2026-07-30 session, continued yet again — on-brand dialogs, package-pricing correctness, Scheduling visual mirror)

A fourth same-day pass. Three pieces of feedback: native browser popups
look off-brand, Diver Form's Apply Charges is wrong for package-mode
pricing (with a concrete real-business example — a "Shark Diving"
package composed of "Kimud, Kimud, Monad"), and Scheduling "doesn't
really look like the live scheduling." Researched `diver-form.html`/
`scheduling.html`/`settings.html`'s real package-matching mechanism and
`scheduling.html`'s real CSS/layout before any code changed, went
through `EnterPlanMode` given the size (comparable to a full visual
redesign). No schema migration was planned for the package-pricing
fix — but live verification surfaced a real, previously-hidden schema
bug that did need one (migration 019, see below).

- **On-brand confirm/alert dialogs.** Inventoried all 10 `window.confirm`/
  `window.alert` call sites across 7 files — no shared dialog/toast
  component existed anywhere; every "Modal" file hand-rolled an
  identical `bg-black/40` overlay shape independently. Built two small
  reusable primitives in the new `src/components/ui/`:
  `ConfirmDialog.tsx` (`ConfirmProvider` + promise-based `useConfirm()`
  — `const ok = await confirm(message, { danger })`, styled with this
  app's real modal chrome and brand tokens) and `Toast.tsx`
  (`ToastProvider` + `useToast()` — `showToast(message, variant)`,
  auto-dismissing top-right, replacing `window.alert` since a blocking
  modal was never the right shape for "Copied."). Both mounted once via
  a new `UIProviders.tsx` client wrapper in `(app)/layout.tsx`. Replaced
  all 10 call sites; also switched `WarningsBanner.tsx`'s plain
  `bg-amber-100` boxes to this app's own `orange`/`orange-light` tokens
  for the same on-brand reason. Verified live: the styled `ConfirmDialog`
  renders (not a native popup, which would have hung the automated
  browser per this project's own documented caution), Cancel truly
  cancels, the danger-styled Confirm truly proceeds, and the `Toast`
  renders with correct text/on-brand teal styling (took ~2.7s to appear
  on a slow multi-fetch path — an early too-short polling window made
  this look broken at first; see retrospective-style note below).
- **Diver Form's package-mode Apply Charges, fixed to match the live
  app's real mechanism.** Confirmed from `settings.html`/`diver-form.html`/
  `scheduling.html`: a package's `dive_site` field (already a real column,
  `packages.dive_site text`, `001_schema_and_rls.sql` — Settings >
  Pricing & Rates > Packages already has full CRUD for it, no schema or
  UI change needed there) is a free-text, ordered, **repeatable** list of
  every real site visit the package covers (e.g. `"Kimud, Kimud, Monad"`
  for "Shark Diving") — matched against the *whole trip's* site
  combination, normalized (split/trim/lowercase/sort/join) the same way
  on both sides, exactly like the live app's real
  `normalizePackageSites()`/`findPackageBySiteKey()`. The rebuild's
  `pricing.ts` was instead resolving package price via
  `dive_sites.linked_package_id` (a per-site FK, only the first
  comma-token, 1 site → 1 package) — a fundamentally different, wrong
  model that could never represent a repeated-site package. Fixed:
  `pricing.ts` gained `normalizeSiteKey`/`resolvePackageBySiteCombo`;
  `autoPricePackageMode` now matches on this instead
  (`resolveSite`/`otherChargesForSite`, the fuel/marine/shark lookup,
  are unrelated and stay unchanged). `linked_package_id` itself is
  untouched — confirmed the live app also keeps its site→package FK as a
  pure Settings-UI cross-reference label, never read for pricing.
  `scheduling/actions.ts`'s `markBoatReturned` had no package-mode branch
  at all — it always wrote the live app's *tier*-mode shape (one
  `activities` row per site per diver). Added a real branch: package
  mode now writes **one combined row per diver for the whole trip**
  (`dive_site = sites.join(", ")`), matching the live app's real
  `boatReturnPackage`; per-dive nitrox/15L flags aggregate across all of
  that diver's site indices onto the one row ("nitrox on *any* dive in
  this package trip"). Diver Form's `applyChargesToVisit`/
  `autoPriceActivityRow` needed no changes — they already branch on
  `pricing_mode` and call `autoPricePackageMode(..., row.dive_site)`,
  which now receives the correct combined string.
  - **Real, previously-hidden schema bug found during this fix's own
    live verification, not part of the original plan**: `schedule_sites`
    had `unique(schedule_id, dive_site_id)` — which makes it *impossible*
    to save a trip that revisits one site twice (exactly what a package
    like "Kimud, Kimud, Monad" requires). `TripCard.tsx`'s
    `replaceScheduleSites` does one bulk insert of every site slot in a
    single call, so picking "Kimud" for both Dive 1 and Dive 2 made the
    *entire* insert fail the unique constraint — silently, since that
    insert never checked `.error` — leaving `schedule_sites` completely
    empty for the trip (confirmed via direct SQL: 0 rows), and
    downstream `markBoatReturned`'s `siteNames` list empty too (the
    combined activity row came back with `dive_site: null` instead of
    the expected string). **Migration 019**
    (`database/019_schedule_sites_allow_repeat.sql`) drops that
    constraint and replaces it with `unique(schedule_id, sort_order)` —
    the real invariant (each *slot* is unique, not each site value).
    Also fixed `replaceScheduleSites` to actually check and surface
    `.error` (per this project's standing "always check `.error`"
    lesson — this insert had silently swallowed failures since it was
    first written, in an earlier session, well before today).
  - **Verified end-to-end against a real seeded package-mode dive
    center**: two sites (Kimud, Monad), one package (`"Shark Diving"`,
    `dive_site: "Kimud, Kimud, Monad"`, ₱5,500). Before the migration
    19 fix, saving the trip silently produced zero `schedule_sites` rows
    and a null-site activity row after Boat Return. After the fix:
    `schedule_sites` correctly has 3 rows (Kimud sort_order 0, Kimud
    sort_order 1, Monad sort_order 2), Boat Return correctly produced
    **exactly one** `activities` row with
    `dive_site = "Kimud, Kimud, Monad"`, and Diver Form's Apply Charges
    correctly resolved `dive_rate = 5500.00` — the exact configured
    package price, matched purely by the normalized site-combo string.
- **Scheduling visual mirror.** Confirmed via a direct CSS diff against
  `scheduling.html` that colors/fonts were *already* correct (same
  navy/teal/red hex values, same DM Serif Display/DM Sans) — the
  "doesn't look like the live app" gap was chrome/density/structure, not
  brand identity. Built two more shared primitives,
  `src/components/ui/Button.tsx` (variant/size scale matching the live
  app's real `.btn`/`.btn-sm` — confirmed the rebuild's buttons had all
  been sized like the live app's smallest variant everywhere) and
  `SectionBox.tsx` (a bordered, uppercase-labeled sub-box, matching
  `.section-block`), then applied them:
  - `TripCard.tsx`: a solid navy header band (title/sub + collapse
    toggle + Delete, matching the live app's real trip-card header,
    including its real collapsible behavior — a saved trip now defaults
    collapsed to a one-line summary, a brand-new one starts expanded);
    the body restructured into `SectionBox`es (Trip Details, Dive Crew,
    Dive Sites, Notes, Team Assignment, Other Divers Joining This Boat)
    instead of one flat form; team cards gained a cyclable left-accent
    color per team index (navy/teal/orange/green, repeating — this
    app's palette has no purple, unlike the live app's own `.c1`-`.c6`);
    the tank tally became a navy strip instead of three neutral gray
    pills; card radius switched from `rounded-2xl` to `rounded-lg`
    (~8px, matching the live app's tighter radius system).
  - `PhaseTabs.tsx`: filled pill tabs (navy when active) with real
    sub-labels ("Prepare divers" / "Build trips" / "Final schedule"),
    replacing a plain underline-tab idiom — confirmed the live app's
    three-phase concept itself was already correct from an earlier
    session, only its tab *style* wasn't.
  - `PhaseThreePanel.tsx`/`PhaseTwoPanel.tsx`/`SchedulingClient.tsx`:
    matching navy-header-card treatment on `TripSummaryCard`, the same
    navy tank-tally strip, `Button`/`SectionBox` swapped in for the
    remaining ad hoc buttons and card radius, page-chrome header
    boxed to match — without changing any already-correct behavior
    (sticky Phase 1 diver sidebar, preview/crew-token logic, Boat
    Return flow all unchanged).
  - Verified live via DOM/computed-style queries (screenshots don't
    composite in this sandbox, per this project's standing note): active
    phase tab confirmed `rgb(26, 60, 94)` (`#1a3c5e`, real navy) fill;
    `SectionBox` labels ("TRIP DETAILS," "DIVE SITES," etc.) render
    correctly; collapsed/expanded trip-card states both confirmed.

**Testing-technique note, not a code defect**: the toast-appearance
check above looked broken on the first two attempts (empty container
after up to 3s of polling) — not a real bug. `copyAllPreview`'s
`Promise.all` over every saved trip's `getTripDetail`/
`getScheduleDivers`/`getStaffDiveTanks` (three server actions per trip)
took ~2.7s end-to-end before `showToast` ever ran; the first test
windows were simply shorter than that. Widening the poll window (and,
separately, confirming via `performance.getEntriesByType('navigation')`
that a suspected `window.location.reload()` override had silently
failed rather than actually blocking the reload) resolved the
confusion. Same family as this project's other documented "don't trust
the first read in this environment" quirks (items 14, 19, 21, 35, 39 in
the retrospective section) — a new specific trap (async-completion
timing, not a DOM-query trap), worth remembering: **give an async
action's own real completion time (checked via `read_network_requests`
if unsure) before concluding a UI effect didn't fire.**

**Verification approach**: a fresh **package-mode** test dive center
(`Package Test DC` — deliberately package mode, not tier, to actually
exercise this session's fix) seeded via the established raw-SQL fixture
pattern — owner, one boat, two dive sites (Kimud, Monad), one package
(Shark Diving), one diver — exercised through the real browser UI for
the full Scheduling → package-price Apply Charges flow, plus every
replaced confirm/alert call site. Database confirmed back to just the
two real accounts and the one real `dive_centers` row at session end
(`schedules.created_by` nulled in its own committed statement first,
per the established cleanup-ordering lesson). Both repos uncommitted as
of this write-up — check `git status` before assuming otherwise.

## Current state (as of 2026-07-30 session, continued — Diver Form Apply Charges + Scheduling captain/crew/UI feedback pass)

A third same-day feedback pass, immediately following the Signed
Documents/Group Management/per-dive-tank session below. The user gave
two more real, concrete pieces of feedback after using the rebuild
against the live app directly: Diver Form was missing its bulk "Apply
Charges" action and had a rebuild-only nitrox/15L checkbox mechanism
with no live-app precedent, and Scheduling had seven more gaps (diver
card scaling, departure-time UI, fuel-capture phase, missing preview
info, dive-site layout, missing captain/crew capture, join-rider
placement). Researched `diver-form.html`'s real `recalculateAllRows()`
and `scheduling.html`'s real crew/captain/fuel/dive-site mechanics
before writing any code, went through `EnterPlanMode` given the size.

- **Migration 018** (`database/018_scheduling_captain_crew.sql`): adds
  `schedules.captain` (a genuine per-trip free-text field, confirmed
  from the live app's real `t.captain` — entered fresh per trip, *not*
  sourced from `boats.captain`, which stays a separate Settings > Fleet
  concern untouched by this session) and a new `schedule_crew` table
  (`schedule_id`, `crew_name`, `sort_order`) — the relational
  equivalent of the live app's `notes.crews` JSON array, matching this
  project's standing anti-JSON-blob rule the same way `schedule_sites`
  already does for multi-site trips. Also updates `get_crew_schedule`
  (from `010_staff_roster_fields.sql`) to surface both fields — this
  closes the "no Crew line" known gap from the earlier same-day session
  by giving the preview/`\/crew` a real schema field to read instead of
  fabricating one.
- **Scheduling — eight items, one already correct:**
  - **"At least one dive site required before saving" was already
    enforced** both client- and server-side — confirmed to the user as
    a non-issue, no code changed for this one.
  - **Fuel Consumed (L) moved from Phase 3 (Complete) to Phase 2
    (Build)** — required to save an own-boat trip now (matching the
    live app's real `validateTrip`), persisted via `createTrip`/
    `updateTrip`'s existing `fuel_consumed_liters` column write.
    `markBoatReturned` no longer takes a fuel-liters parameter — it
    reads the already-saved `schedules.fuel_consumed_liters` for the
    actual deduction/log, matching the live app's real design (captured
    once at trip-build time, deducted later at actual return).
  - **Boat Captain (required, own-boat) and Dive Crew (3 default slots
    + "+ Add Crew") added to `TripCard.tsx`**, writing to the new
    migration-018 fields via `replaceScheduleCrew` (delete-and-reinsert,
    same shape as `replaceScheduleSites`).
  - **Departure Time switched from a native `<input type="time">` to 3
    dropdowns** (Hour 1-12 / Minute / AM-PM), matching
    `scheduling.html`'s real `departureTimeHTML()` — converts to/from
    the stored 24h `HH:MM` at the edges, no schema change.
  - **Dive Sites changed from a vertical stack to a horizontal 3-column
    grid** (`grid grid-cols-3 gap-2`), matching `scheduling.html`'s real
    `.sites-list` layout — reads as one compact row/block, "+ Add Dive
    Site" appends another slot to the same grid.
  - **"Other divers joining this boat" (join-rider fields) moved to the
    bottom of the trip form**, after Notes and the Teams section,
    immediately above the Save/Delete/Cancel footer.
  - **Phase 3 preview (on-screen header, Copy Preview, Download Image)
    now shows Captain + Crew lines**, sourced from the new
    `schedules.captain`/`schedule_crew` fields — verified the exact
    Copy Preview text matches `scheduling.html`'s real `buildPreview()`
    line order (`Captain: X` / `Crew: X` right after Departure, before
    the dive-site line). `/crew`'s `CrewScheduleClient.tsx` also renders
    both lines now, matching `staff.html`'s real `👨‍✈️ Captain:` /
    `🧑‍🤝‍🧑 Crew:` display.
  - **Phase 1's "Loose Divers" list is now a fixed-width (20rem),
    sticky, independently-scrolling sidebar** (`PhaseOnePanel.tsx`,
    `md:grid-cols-[20rem_1fr]` with the divers column
    `md:sticky md:top-4 md:max-h-[calc(100vh-8rem)] md:overflow-y-auto`)
    beside Suggested Clips, matching `scheduling.html`'s real
    `.available-panel` structure — confirmed via research this was the
    actual mechanism that keeps 50+ divers usable, not smaller card
    text (the rebuild's `DiverInfoCard` was already more compact than
    the live app's own two-line cards from an earlier session).
    Verified live with 15 seeded divers: the column stays exactly
    320px wide with `position: sticky` and a 592px `max-height` /
    `overflow-y: auto` — confirmed via direct computed-style query, not
    just visual inspection.
- **Diver Form — Apply Charges + nitrox/15L, matching the live app's
  real mechanism exactly.** Research confirmed `diver-form.html` has
  **no nitrox/15L checkbox anywhere** — `nitrox_fee`/`fifteen_l_fee`
  are always plain editable number fields, auto-filled only by the
  visit-level `recalculateAllRows()` ("↺ Apply Charges," the *only*
  pricing-recompute mechanism in the live app — there's no per-row
  auto-price there at all), which reads per-dive flags set upstream,
  once, by Scheduling's Boat Return step.
  - `scheduling/actions.ts`'s `markBoatReturned` is now the sole writer
    of these flags: extended to look up each diver's
    `schedule_diver_dive_tanks` per site index and write
    `activities.flags = {nitrox_requested: true}` /
    `{tank_15l_requested: true}` on each created activity row (already-
    existing `activities.flags jsonb` column, unused until now —
    "structured replacement for the old JSON-encoded notes blob," per
    its own schema comment).
  - New bulk `applyChargesToVisit(diverId, visitId)` action
    (`diver-form/[id]/actions.ts`), modeled directly on
    `recalculateAllRows()`: walks every non-cancelled activity in
    `date, created_at` order with a real running 1-based cumulative
    dive count (a more correct retroactive tier computation than the
    existing per-row path, which could only ever see a flat sibling
    count), applies per-day marine/shark/fuel cadence dedup via running
    per-date trackers built fresh each pass, and fills nitrox/15L from
    each row's own `flags`. New "↺ Apply Charges" button in
    `VisitPanel.tsx`'s header (next to "+ Add Activity"), reloading
    after — matching this codebase's established multi-row-affecting-
    action pattern (Add Activity, bill unlock).
  - Removed `ActivityRow`'s rebuild-only `wantsNitrox`/`wants15L`
    checkbox UI and local state entirely (confirmed zero checkboxes
    remain in the activities table via a live DOM query). Per-row
    "Auto-Price" stays as a convenience (useful for re-pricing one row
    after manually changing its dive site) but now sources
    `wantsNitrox`/`wants15L` from the row's own stored `flags` server-
    side (`autoPriceActivityRow`) instead of client checkbox state —
    both paths now read the exact same source of truth.
  - **Verified end-to-end against real seeded tier-mode pricing**
    (base_dive ₱1000, nitrox ₱200, tank_15l ₱150): a diver nitrox on
    dive 1 only got Apply Charges → ₱1200/₱1000 per row, ₱2200 visit
    total; a diver 15L on dive 2 only got ₱1000/₱1150, matching
    hand-computed expected values exactly (confirmed via direct SQL,
    not just the UI). A manually-added walk-in activity row (no
    schedule-derived flags) correctly stayed at nitrox/15L = ₱0 after
    Apply Charges, number field still manually editable. Zeroed a
    row's nitrox fee by hand, saved, then re-ran that row's own
    per-row Auto-Price and confirmed it recomputed back to ₱200 purely
    from the stored flag — proving both the bulk and per-row paths
    genuinely share the same flag-driven source of truth.

**Testing-technique note, not a code defect — a new environment
constraint, not previously documented**: this session's dev-server
setup hit two new blockers beyond the ones already catalogued. First,
`preview_start` (both by config name and by explicit non-3000 port)
refused to start, reporting "Port 3000 is in use by another chat's dev
server" even with `autoPort: true` and no hardcoded port flag in
`.claude/launch.json` — tracing it further, Next.js 16's Turbopack dev
server itself refuses a second instance **pointed at the same project
directory**, regardless of port (`⨯ Another next dev server is already
running... Dir: D:\Rebuild\aquadesk-app`), which is what the tool's
own port-conflict message was actually surfacing. Second, attempting to
route around this with a `node_modules` **directory junction** (to
avoid a full reinstall in an isolated copy) made Turbopack fail
outright with `Symlink [project]/node_modules is invalid, it points
out of the filesystem root` — Turbopack's resolver doesn't accept a
junction/symlinked `node_modules`. **Lesson: verifying UI changes while
another session has its own dev server running against the same
project directory needs a genuinely separate directory copy — `git
worktree` only reflects committed state so doesn't help for
uncommitted work-in-progress, and `node_modules` must be a real copy
(`robocopy`, not a junction) for Turbopack to accept it.** Worked
around this session by `robocopy`-copying the whole tree (excluding
`node_modules`/`.next`/`.git`) to `aquadesk-app-verify`, then a full
real copy of `node_modules` into it, running `next dev` there on its
own port; the temporary directory and its dev server were both torn
down after verification completed, confirmed via `Test-Path` that
`aquadesk-app-verify` no longer exists.

**Verification approach**: a fresh test dive center (`Feedback Test DC
2`) seeded via the established raw-SQL fixture pattern — owner, one
boat, two dive sites, tier-mode rate config (base_dive/nitrox/tank_15l),
and 15 divers with open fun-diving visits (for the Phase 1 scale test)
— exercised through the real browser UI for every flow above: Phase 1's
sticky column at 15 divers, a full Phase 2 own-boat trip build
(captain/fuel/crew validation, departure-time dropdowns, horizontal
dive-site grid, join-riders at the bottom, per-dive nitrox/15L tank
pills, tank tally), Phase 3's preview/Copy Preview/`/crew` display, Boat
Return, and Diver Form's Apply Charges (bulk and per-row) against the
resulting per-dive-flagged activity rows. Database confirmed back to
just the two real accounts (`aquadeskonline@gmail.com`,
`demodivecenter@gmail.com`) and the one real `dive_centers` row at
session end (`schedules.created_by` nulled in its own committed
statement first, per the established cleanup-ordering lesson). Both
repos' code is committed... **no — check `git status` before assuming
that**; as of this write-up both repos have this session's changes
staged in the working tree but the user has not yet asked to commit.

## Current state (as of 2026-07-30 session — Signed Documents identity, Group Management visibility, Scheduling per-dive tank overhaul)

A second feedback-pass session, larger than the first. Three areas, all
researched against the actual rebuild code and the old app's real
`scheduling.html`/`diver-form.html` before any code changed — nothing
here was guessed, and one genuine scope fork (whether to track staff
tank consumption per dive, not just divers') was confirmed with the user
via `AskUserQuestion` before building it. Went through `EnterPlanMode`
given the size (the Scheduling piece alone is comparable to a full
Scheduling-rebuild session).

- **Signed Documents now shows who signed — via a real immutable
  snapshot, not a live join.** `diver_registrations` had no identity
  columns of its own (only a `diver_id` FK) — despite already snapshotting
  accommodation/certification/waiver/medical answers specifically so a
  signed record can't drift after a later profile edit. **Migration 017**
  (`database/017_registration_identity_snapshot.sql`) adds
  `first_name`/`last_name`/`birthday`/`nationality`/`email`/`phone`/
  `whatsapp` to `diver_registrations`, and `submit_diver_registration` now
  copies those same fields there too (the wizard already submitted them —
  they were only ever written to `divers`, never snapshotted). Same
  migration also adds the two new Scheduling tables below. `DocumentsViewer.tsx`
  gained an identity block at the top of both the on-screen and print
  views, reading the registration's own frozen fields with a fallback to
  the diver's current profile (already available in `DiverDetailClient.tsx`
  as `diver`, threaded down as a new prop) only for pre-migration rows.
  **Verified the actual legal property, not just that it renders**: edited
  Maria Santos's first name via Edit Diver Info mid-session (profile header
  correctly updated to "MariaEdited Santos"), confirmed Signed Documents'
  identity block — on-screen and in the print-only block — still correctly
  showed "Maria Santos," proving the snapshot genuinely doesn't drift.
- **Divers > Group Management now shows every group regardless of arrival
  date.** `divers/data.ts`'s `loadGroups()` was calling `isGroupActive()`
  and filtering — removed entirely; Individual Management's own logic was
  independently re-verified as already matching the ask exactly (visible
  from arrival−1, hidden after departure only once the bill is fully
  closed) and needed no change. `isGroupActive` in `divers/visibility.ts`
  was dead code once its only call site was removed — deleted, not left
  behind. Verified with two seeded 2099-dated groups (one with a member,
  one empty) — both now show unconditionally where they'd previously have
  been hidden.
- **Scheduling — six fixes, the largest being real per-dive nitrox/15L
  tracking:**
  - **Diver cards made more compact** (`PhaseOnePanel.tsx`'s
    `DiverInfoCard`) — merged the nationality/cert and dives/age lines
    into one smaller-text line, dropped the "Fun Diving" line entirely
    (only course divers get a line now) — same four facts, tighter.
  - **Fixed a real bug**: excluding a diver from a clip
    (`excludeDiverFromClip`) silently returned them to Loose Divers on
    next refresh, because `loadPhaseOneData`'s `clippedIds` and
    `ClipCard`'s rendered member list both filtered out excluded members
    entirely. Confirmed against `scheduling.html`'s real mechanic
    (`clipDiverRowHTML`/`allClipDiverIds`): an excluded member should stay
    visibly attached to the clip (grayed, "Not diving this trip" tag,
    "Include" to undo), never fall back to the pool. Fixed by dropping the
    exclusion filter from `clippedIds` and rendering all `clip.members` in
    `ClipCard`; added the mirror `includeDiverInClip` action. Verified
    live: excluded a clip member, confirmed she stayed in the clip (not
    Loose Divers), clicked Include, confirmed she returned to normal.
  - **Dive Sites is now 3 default dropdown slots ("Dive Site 1/2/3",
    sourced from Settings > Dive Sites) + "+ Add Dive Site"**, replacing
    the old flat multi-select-button UI — confirmed exact match to
    `scheduling.html`'s real `sites:['','','']` seeding and `sitesHTML()`.
    `TripCard.tsx`'s `form.siteIds` became a slot array (empty string =
    unfilled slot), filtered down to real ids only at save time.
  - **Crew token now auto-generates**, no manual click — confirmed the
    live app's `generateToken()`/`refreshStaffToken()` fire automatically
    whenever Phase 3 is viewed, with no "Generate" button anywhere; the
    rebuild's manual button was the deviation. `PhaseThreePanel.tsx`'s
    token `useEffect` now calls `generateCrewToken()` itself when none
    exists yet; the button and its now-dead `readOnly` prop (only ever
    used to gate that button) were removed from both `PhaseThreePanel`
    and its `SchedulingClient.tsx` call site.
  - **Real per-dive nitrox/15L tracking — the biggest single piece.**
    `schedule_divers` had one `is_15l`/`nitrox_requested` boolean per
    diver for the *whole trip*; the live app genuinely supports a diver
    being nitrox on dive 1 and plain air on dive 2 of the same multi-site
    trip (`getNitroxIndexes`/`getTank15lIndexes` — real per-dive index
    arrays), and separately tallies **one tank per staff member per dive
    site** too (confirmed by the user as worth adding, not skipping).
    Migration 017 adds two new additive tables —
    `schedule_diver_dive_tanks` (schedule_diver_id, site_index, tank_type)
    and `schedule_staff_dive_tanks` (schedule_id, staff_name, site_index)
    — both keyed by `schedule_sites.sort_order`'s existing index
    convention, both with the standard 4-policy RLS block copied from
    `schedule_team_clip_divers` (the one-time policy-creation loop in 001
    already ran and can't be re-run for new tables). `schedule_divers.
    is_15l`/`nitrox_requested` stay as real columns — now derived summary
    booleans ("at least one dive uses this tank"), so `/crew`'s
    `get_crew_schedule` RPC and every other existing consumer keep working
    unchanged (confirmed via a whole-codebase grep before considering this
    done, per this project's standing "grep before shipping a column's
    first real writer" lesson). `TripCard.tsx`'s UI replaced the single
    15L/Nitrox checkbox pair per diver with a compact pill button per
    *active* dive site (cycles Air 12L → Nitrox → Air 15L on click,
    functional parity not pixel parity with the old app's checkboxes), plus
    one nitrox-only pill row per team for the staff member. New
    `scheduling/tanks.ts` (`computeTankTally`) is the single shared pure
    function both `TripCard.tsx` (Build-phase live tally) and
    `PhaseThreePanel.tsx` (Complete-phase summary) now call — previously
    each had its own independently-wrong computation that disagreed with
    each other.
  - **Tank tally fixed and repositioned.** The bug: the rebuild counted
    *divers*, not *diver-dives* — a diver on a 2-site trip tallied as 1
    tank instead of 2, and staff tanks were never counted at all. Fixed by
    the new per-dive schema above feeding the shared `computeTankTally`.
    Repositioned in `PhaseThreePanel.tsx` from right after the header
    (before the diver list) to after the per-staff diver groupings,
    matching every rendering context in `scheduling.html`
    (`tankBarHTML`/`tankTallyHTML`/preview text all put it last).
  - **Schedule preview (Copy Preview text + Download Image) reformatted**
    to match `scheduling.html`'s real `buildPreview()`/`tripImageRows()`
    order exactly: boat → date → departure → captain → `Dive 1 - Site |
    Dive 2 - Site` line → blank → per-staff-group divers (course divers
    show `"Name - Course - CourseName"`, fun divers show per-dive tank
    detail like `"Name - Nitrox D1"`) → **Tank Tally line** → join-ride/
    notes; trips separated by `------------------------------`, crew
    token appended once at the very end of the combined multi-trip text
    (already correct, unchanged). `loadScheduleDivers` gained a
    `courseName` field (resolved the same way `fetchClipsRaw` already
    does it) to make the course-diver preview line possible.
  - Verified all six live end-to-end in a real browser: built a 2-site
    trip, set one diver nitrox on dive 1 only and another 15L on dive 2
    only (confirmed via precise per-row DOM queries — an early
    imprecise-selector test script briefly clicked the wrong pills,
    caught and corrected before drawing any conclusion), toggled staff
    nitrox per site, confirmed the live Build-phase tally updated
    correctly at every step (`Air 12L: 5 / Air 15L: 1 / Nitrox: 3`
    matching hand-computed expected values), saved, reached Phase 3 with
    the crew token appearing with no click, confirmed the repositioned
    tally, and confirmed Copy Preview's captured text matched the planned
    format exactly including the per-dive tank tally line and course-diver
    formatting.

**Verification approach**: a fresh test dive center (`Feedback Test DC`)
seeded via the established raw-SQL `auth.users`/`auth.identities` fixture
pattern, extended with staff/boats/two dive sites/three divers (one
full-info, one course-tagged, one for group testing)/a signed registration/
two future-dated groups, exercised through the real browser UI for every
flow above, then fully deleted (`schedules`/`schedule_team_clips`/
`schedule_day_diver_exclusions.created_by` nulled in their own committed
statement first, per the established cleanup-ordering lesson). Database
confirmed back to just the two real accounts and the one real
`dive_centers` row at session end. **Both repos' code is committed** —
the retrospective/dead-code-audit documentation pass that follows this
write-up (see the Retrospective and Dead-code audit sections further
down) may still be uncommitted on top of it; check `git status` in both
repos before assuming either is fully clean in a future session.

## Current state (as of 2026-07-27 session — feedback pass: Settings 12-tab split, Scheduling cards/UI, Diver Form print, Reports charts, Sidebar)

The user started giving direct, itemized feedback after using the rebuild
day-to-day, across six areas in one message. All six were researched
against the actual rebuild code (and the old app's real HTML/JS where
relevant) before any code changed, four genuinely ambiguous points were
resolved via `AskUserQuestion`, and the whole thing went through
`EnterPlanMode` given the size (comparable to a full-page rebuild).

- **Settings split back to the live app's real 12 tabs.** A prior session
  had deliberately consolidated `settings.html`'s 12 tabs into 6 — the
  user disagreed once actually using it, specifically because Fleet and
  Dive Sites had no click target of their own (buried inside a bundled
  "Equipment" tab). Read `settings.html` in full to get the *exact* tab
  boundaries (not guessed) — some splits were non-obvious: "Equipment
  Rental" is rental gear **pricing** (₱ rates), separate from "Inventory"
  (tanks/fuel/rental-gear **stock counts**); "Exchange Rates" bundles
  Payment Surcharges together with the currency table; "Passwords" is
  just Owner/Billing password management, separate from "Access &
  Permissions" (secretary account creation + toggles). New tab folders:
  `settings/fleet/`, `dive-sites/`, `courses/`, `equipment-rental/`,
  `exchange-rates/`, `passwords/`, `access/` — each following this
  codebase's existing per-tab `page.tsx`/`data.ts`/`actions.ts`/section-
  component shape, split mechanically since every section was already
  its own component. `settings/equipment/` renamed to `settings/
  inventory/` (Tanks/Fuel/Gear only now); `settings/staff-access/`
  deleted entirely, split into `passwords/` + `access/`. `settings/
  pricing/` trimmed to just pricing-mode + packages/tiers + other
  charges + the rebuild-only Staff Commission & Join Ride rates section
  (which has no live-app precedent anywhere — kept in Pricing & Rates
  since there's no better home for it). `SettingsTabs.tsx` now lists all
  12 in the live app's real order; its existing `pathname === href ||
  startsWith(href + "/")` active-check (already fixed for a prefix-
  collision bug in an earlier session) needed no further changes since
  none of the 12 new slugs collide. One real cross-folder dependency:
  `confirmPricingMode` (still in `pricing/actions.ts`) auto-seeds
  `DEFAULT_COURSES` when switching into tier mode — that constant now
  lives in `courses/constants.ts`, imported across the folder boundary.
  Verified end-to-end in a real browser against a seeded test dive
  center: all 12 tabs load and render seeded data correctly, and the
  riskiest interaction — actually switching pricing mode package→tier,
  which exercises the cross-folder `DEFAULT_COURSES` import — was
  exercised for real (not just compiled), confirmed via direct SQL that
  the mode flipped and the existing course-rate row wasn't duplicated.
  **Dead-code sweep found one more stale reference than the obvious
  ones**: `settings/staff/components/StaffFormModal.tsx` still said
  "Secretary logins themselves are created on Settings > Staff Access"
  — fixed to "Access & Permissions". Also fixed two stale "Settings >
  Equipment > Dive Sites" references in `diver-form/[id]/pricing.ts`
  (now just "Settings > Dive Sites") and one "Settings > Pricing &
  Rates" in `VisitPanel.tsx`'s empty-courses tooltip (now "Settings >
  Courses") — all found by grepping the whole `src/` tree for the old
  tab names' text, not just code symbols, since these were UI copy
  strings a symbol-rename pass would never catch.
- **Scheduling: richer diver mini-cards, cleaner Delete/Move/Exclude,
  gated guest-divers field.** The user specifically likes the live
  app's Phase 1 diver cards (nationality, cert level, dive count, age,
  fun-diving-vs-course) for seeing at a glance who's compatible to dive
  together — the rebuild's Phase 1 (`PhaseOnePanel.tsx`) only ever
  showed a bare name. `divers.nationality`/`logged_dives`/`birthday`
  already existed in the schema (Stage 1a, unused by Scheduling until
  now) — extended `ClipMember` and `DiverPickResult`
  (`scheduling/data.ts`) with `nationality`/`loggedDives`/`age`
  (computed server-side from `birthday`, plain Y-M-D arithmetic, no
  Date-object timezone risk) and, for clip members only, `courseName`
  (resolved via the diver's open visit's `course_rate_id` →
  `course_rates.course_name`). New `DiverInfoCard` sub-component in
  `PhaseOnePanel.tsx` renders all four lines for both loose divers and
  clip members, with an orange left-border accent for course divers
  (this codebase's palette has no purple, unlike the old app's CSS).
  Delete/Move/Exclude got real UI polish, not a redesign: Move/Exclude
  are now bordered buttons with breathing room instead of bare color-
  only text links; the "Move to:" picker now expands directly under the
  specific diver's own row (labeled "Move Alex Tan to:") instead of a
  generic picker at the bottom of the whole clip card with no link back
  to which diver was clicked; same-named clips are disambiguated by
  appending their `source` ("carried over"/"returned"). `window.confirm`
  stayed for Delete (already this codebase's established pattern in 4
  other places) — not replaced just here. The "Other divers joining this
  boat" block in `TripCard.tsx` (guest-divers count/dive-center/notes)
  rendered unconditionally before, confirmed to match the old app's own
  unconditional `joinerHTML()` — not a rebuild bug, but the user wants
  it changed going forward: now gated to `boatMode === "own_boat" ||
  "rental"` only, hidden (not cleared) on Join Ride. Verified end-to-end
  in a real browser: seeded a full-info diver and a minimal-info diver
  (confirming the "Age not set."-style fallback text), built a clip and
  confirmed the course-name join renders ("Course - Open Water Diver"),
  clicked Move and confirmed the picker anchors under the right diver,
  excluded a diver from a clip and confirmed it returns to Loose Divers,
  and toggled all three boat modes confirming the guest-divers block
  only shows for Own Boat/Rental.
- **Diver Form: Signed Documents print scoped correctly.**
  `DocumentsViewer.tsx`'s print button was a bare `window.print()` with
  no dedicated print markup — and critically, every *other* sibling
  panel on the page (`ProfileHeader`, `VisitPanel`, `BillSummary`,
  `DepositsPanel`, `NotesPanel`) had zero print handling at all, unlike
  `InvoicePanel` (the only one that already had the established
  `print:hidden` on-screen / `hidden print:block` print-only pattern).
  So printing anything from this page — Signed Documents or an Invoice
  — printed the whole workspace: profile buttons, editable billing
  fields, the notes box. Root-cause fix: added `print:hidden` to those
  five panels' outermost wrappers, matching `InvoicePanel`'s existing
  guard — this fixes printing for *both* documents on this page, not
  just Signed Documents. `DocumentsViewer.tsx` gained a real `hidden
  print:block` section: full Arrival/Departure/Accommodation/
  Certification, **every** medical question with its answer (mapping
  the full `medicalAnswersSnapshot`, not the `yesAnswers`-only filter
  used on-screen — confirmed with the user this should print in full),
  Privacy Consent, the complete unclamped waiver HTML, and the
  signature image. On-screen, the previously-always-expanded
  `max-h-48 overflow-y-auto` full waiver dump was replaced with a
  collapsed-by-default `<details><summary>View full waiver
  text</summary>` — reachable with one click, not shown by default
  (medical declaration on-screen was already yes-only, needed no
  change). Verified via direct DOM inspection of the print-only block's
  `innerText` (not an actual `window.print()` call — this project's own
  established caution that auto/triggered print hangs the automated
  browser pane) against a seeded registration with 4 medical questions
  (mixed yes/no) and a long waiver: confirmed all 4 questions with
  correct Yes/No answers and the full unclamped waiver text were
  present, and confirmed exactly 5 `print:hidden` panels via a
  `document.querySelectorAll` count.
- **Reports Overview: fixed the Money Snapshot donut overlap, added
  bars to "Not Yet Settled".** The center peso total inside the donut's
  92px circle had no width guard (`text-xl`, no `overflow-hidden`) — a
  large peso figure (a real seed like ₱9,999,999 was used to reproduce
  it, not assumed) visibly overflowed the circle and into the legend.
  Fixed with conditional font sizing (drops to `text-xs` past 9
  characters) plus `overflow-hidden`/`px-1` as a hard backstop, and
  `min-w-0`/`flex-wrap` on the donut+legend row so narrow viewports
  reflow instead of overlapping. Verified via direct DOM measurement
  (`scrollWidth` vs. `clientWidth`), not a screenshot (unreliable in
  this sandbox per this project's standing note) — confirmed 63px of
  content fits cleanly in the 92px circle with the long figure. "Not
  Yet Settled" (previously a plain 6-row `SummaryRow` list, no chart at
  all) gained a new `SettledBarList` — a horizontal bar per line,
  colored teal for "owed to you" rows and orange for "you owe" rows,
  deliberately reusing the exact color pairing the Money Snapshot donut
  already established rather than inventing a new convention.
- **Sidebar: removed the nav-list scrollbar.** `Sidebar.tsx`'s
  `<nav className="flex-1 py-4 overflow-y-auto">` was the only scroll
  region in the sidebar (header and user-profile footer are both
  fixed) — the live app has no such region at all, and the user
  specifically asked for it gone, not just fixed to not trigger.
  Removed `overflow-y-auto`; confirmed safe since there are only 7 nav
  items today, nowhere near enough to overflow a real viewport (checked
  computed `overflow-y: visible` and `scrollHeight === clientHeight`
  post-fix, not just eyeballed).

**Verification approach**: `npx tsc --noEmit`/`npm run lint` run clean
after every one of the five areas above, not just at the end. A test
platform-admin-free dive center (`Settings Test DC`, raw-SQL-seeded per
this project's established `auth.users`/`auth.identities` fixture
pattern — all 8 token columns `''`, correct `identity_data`) was created,
extended with staff/divers/a registration/a large activity as each
feature needed it, exercised through the real browser UI for every flow
above, then fully deleted (`schedules`/`schedule_team_clips`/
`schedule_day_diver_exclusions.created_by` nulled in their own committed
statement first, per the established cleanup-ordering lesson). Database
confirmed back to just the two real accounts
(`aquadeskonline@gmail.com`, `demodivecenter@gmail.com`) and the one real
`dive_centers` row at session end. **Both repos are uncommitted as of
this session's end** — the user has not yet asked to commit; check `git
status` before assuming otherwise in a future session.

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
entirely) — see the full write-up for both. A final end-of-day audit
pass (requested explicitly before closing out) found one more real
regression beyond those two: the rebuilt trip-save path never wrote
`schedule_divers.experience_type`, silently breaking `/crew`'s
per-diver experience-type badge for any new trip — found via a
cross-page grep, fixed, and verified end-to-end (see retrospective #37).

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
**Resolved same-day**: the "no Crew line in the Scheduling preview" gap
noted after the per-dive-tank session was closed a few hours later the
same day — migration 018 added `schedules.captain`/`schedule_crew`, and
the preview/`/crew` display both read them now. See the "Diver Form
Apply Charges + Scheduling captain/crew/UI feedback pass" write-up
above.

### Suggested next step

**The rebuild's originally-agreed page-by-page build order finished on
2026-07-25.** Since then the project has been in an ongoing
**feedback-response phase**: the user uses the app day-to-day and brings
concrete, itemized feedback; each session researches the actual rebuild
code and the old app's real HTML/JS before changing anything, then
verifies every change live in a real browser against seeded test data
(never the user's real "Demo Dive Center"). Three such passes so far,
each committed at the end:

- **2026-07-26 (four continuations, one day)**: Settings Profile tab,
  reverse Join-Ride Dashboard alert, full login-security build, office
  console upgrade, real Resend-backed invoice email delivery, a full
  nav/Staff/Divers/Scheduling rebuild to match the live app's real page
  layout, then Group/Individual Management's active-window fix, a full
  three-phase Scheduling rebuild, and a Settings tab audit.
- **2026-07-27**: Settings split back to the live app's real 12 tabs,
  Scheduling diver-card/Delete-Move-Exclude UI polish, Diver Form's
  Signed Documents print scope fixed, Reports Overview chart fixes,
  Sidebar scrollbar removed.
- **2026-07-30 (six sessions, same day)**: first, Signed Documents
  identity snapshot (a real legal-record fix, not cosmetic), Group
  Management's date filter removed, and a six-part Scheduling overhaul
  — clip-exclude bug, 3-slot dive sites, auto-generating crew token,
  real per-dive nitrox/15L tracking (two new tables), tank-tally
  correctness + repositioning, and a schedule-preview reformat. Then,
  Diver Form's bulk "Apply Charges" action (matching `diver-form.html`'s
  real `recalculateAllRows()`, replacing a rebuild-only nitrox/15L
  checkbox with the live app's real flag-driven mechanism) plus an
  eight-part Scheduling pass — captain/crew capture (migration 018),
  fuel moved to Phase 2, departure-time dropdowns, a sticky Phase 1
  diver sidebar, a horizontal dive-site grid, join-riders moved to the
  bottom, and Captain/Crew added to the preview and `/crew`. Then,
  on-brand confirm/alert dialogs (two new shared UI primitives,
  replacing all 10 native-popup call sites app-wide), a real
  package-mode Apply Charges fix (matching the live app's real
  site-combination package matching — surfaced and fixed a genuine
  hidden schema bug along the way, migration 019, that silently
  prevented a trip from ever revisiting the same dive site twice), and
  a Scheduling visual mirror pass (navy trip-card headers, collapsible
  cards, section-boxed forms, filled pill phase tabs, a shared
  Button/SectionBox component pair). Then, a fifth pass reverting Phase
  1 to the live app's real two-row layout, fixing certification labels,
  rebuilding nitrox/15L selection to match the live app's real
  certification-gated checkboxes, adding Captain/Crew/Dive Sites to
  Phase 3's on-screen preview, and client-side Boat Return time gating.
  Finally, a sixth pass that found and fixed a real, previously-unknown
  bug (`/crew` and `/reset-password` both silently redirected every
  logged-out visitor to `/login`, since `proxy.ts`'s `PUBLIC_ROUTES`
  allowlist never included either), removed three more rebuild-only
  additions from Diver Form's activities table (Total/Discount columns,
  Auto-Price/Save buttons) in favor of auto-save matching the live app,
  fixed certification labels in two more spots, added the live app's
  real "MBCA " boat-name prefix and a one-page print stylesheet to Boat
  Manifest, renamed Reports Overview's ambiguous "Rental —" labels to
  "Gear Rental —" and fixed the Money Snapshot donut overflow more
  thoroughly, and added a new rebuild-only Spare Tanks feature to
  Scheduling (migration 020).

**Both repos are clean and pushed as of this writing** — all six
same-day passes are committed (the fifth as `aquadesk-app@b01345e`, the
sixth as `aquadesk-app@34bd3bb` + root repo `@0e32da5`), unlike some
earlier same-day passes that ended uncommitted pending the user's
go-ahead. Still always run `git status` in both repos before assuming
either is clean in a future session — this is a snapshot at write-time.

**Nothing is currently known to be broken or half-finished.** The one
genuinely open item from a prior session is retrospective #38 (the
first-time password-set flow failing against a raw-SQL-seeded test
user) — unresolved, not yet known whether it's a real product bug or a
testing-fixture gap; investigate if a future session hits it again or
needs to exercise that flow. **A second, now-resolved production bug**
(retrospective #41 below) was found and fixed this session — `/crew`/
`/reset-password` silently redirecting logged-out visitors to `/login` —
worth a quick sanity check early in a future session if any other
anon-accessible route is ever added (`/office`? no — that's
authenticated-only by design; any *new* public route needs its path
added to `proxy.ts`'s `PUBLIC_ROUTES`, or it will silently 404-equivalent
via a login redirect with no error anywhere in the route's own code).
Today's sessions each closed cleanly with their own dead-code audit (see
those sections above) — nothing left dangling.

Whatever comes next is most likely more of the same: the user brings
direct feedback from actual use, research the real behavior before
changing anything, verify live, commit only when asked. No next page or
feature is implied by prior planning — treat any of the known gaps below
as fair game to close if the user asks, but none are blocking.

Known, documented gaps worth revisiting whenever a future session
touches these areas: package-mode nitrox/15L add-on pricing (Divers, no
dedicated mechanism, stays manual entry — **not** the same thing as
Scheduling's now-real per-dive nitrox/15L tracking added this session),
`equipment_rental` never auto-computed from a diver's saved equipment
selection (Divers, also manual entry), Diver Detail only ever shows the
diver's single most recent visit (no full multi-visit history browser),
Join-Ride/Rental boats have no persisted distinction from each other
(Scheduling, accepted cosmetic gap), no bulk group-billing review
(Divers > Group Management), and no unlinked-secretary banner on Staff
Access — none of these were blocking for their respective builds, all
called out inline in the write-ups above. Plus the smaller
earlier-2026-07-26-session findings tracked in `aquadesk-app/KNOWN_GAPS.md`
(cert-card compression, registration validations, Waiver/Medical preview,
Diver Detail mid-visit experience-type change, login cosmetics).

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
- **Setting up this project's established isolated-verify-server
  pattern** (copying the whole `aquadesk-app` tree to a scratch
  directory to test against a real dev server without colliding with
  another session's shared one): always run `robocopy` via the
  **PowerShell** tool, never Bash (Git Bash/MSYS mangles single-slash
  flags like `/E` into a path); treat `robocopy`'s exit code `1` as
  success (one or more files copied), not a failure, regardless of what
  the calling tool's status label says — verify via actual file counts
  if unsure; always pass `NEXT_TELEMETRY_DISABLED=1` to the `next dev`
  command proactively (a shared global telemetry-config file can crash
  a second, fully isolated dev server with an `EXDEV` rename error
  otherwise); and never retry a port that had *any* startup issue
  earlier in the session — pick a fresh one (see retrospective #43-46).
- **When writing short, ad hoc `javascript_tool` snippets in the
  Browser pane, always wrap them in an IIFE** (`(() => { ... })();`)
  rather than declaring top-level `const`/`let` — the execution context
  persists declared variables across separate tool calls within the
  same tab, so reusing a common name (`btn`, `select`) in two different
  snippets throws a redeclaration error (see retrospective #47).

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

### Session 2026-07-26, continued yet again (Group Management, Scheduling phase rebuild, Settings audit)

36. **A single shared dataset fetched once for N sibling components, with
    no way to identify which row belongs to which sibling, makes any
    "exclude myself" check impossible — and the bug only shows up after
    the first row is saved, not before.** `SchedulingClient` fetches one
    whole-day `DayAssignment[]` (a single query, not N queries) and hands
    it to every `TripCard` for double-booking warnings. The first version
    had no `scheduleId` on each row, so a freshly-saved trip's own
    `TripCard` couldn't tell its own assignments apart from a genuinely
    different trip's — it warned "2 divers are also assigned to another
    trip today" pointing at itself. Caught immediately in browser
    verification (saved a trip, warning appeared instantly) — a case
    where the bug was invisible until the exact moment of testing the
    real save-then-redisplay cycle, not something a code read alone would
    have caught. Fixed by adding `scheduleId` to `DayAssignment` and
    filtering `dayContext.filter(d => d.scheduleId !== scheduleId)`
    client-side per card before handing it to `WarningsBanner`. **Lesson:
    whenever a single fetched collection is shared across multiple
    sibling instances of the same component (to avoid N separate
    queries), each row needs its own owning-entity ID preserved in the
    data — collapsing "the whole day's assignments" into "other trips'
    assignments" server-side (via an exclude parameter) silently breaks
    the moment a sibling needs to reason about its own identity within
    that shared set. Prefer returning the unfiltered set with IDs intact
    and filtering client-side, not filtering server-side and hoping no
    consumer ever needs to exclude itself.**

37. **Replacing a table's writer with a new one, driven by a new UI's own
    local state, silently drops any column the old writer set that the
    new UI never surfaces directly.** The original `saveTripDiverAssignments`
    (now-deleted `DiverAssignmentPanel`) wrote `schedule_divers.experience_type`
    per diver. Its replacement, `saveTripTeams` (driven by the new
    clip-based `Team`/`TeamDiver` client state in `TripCard.tsx`), was
    designed purely from what Phase 2's UI actually displays and edits —
    staff, nitrox/15L flags — and nobody re-checked the old writer's full
    column list against the new one's. The result: every trip built
    through the rebuilt Scheduling flow wrote `schedule_divers.experience_type
    = null`, which is invisible anywhere *in Scheduling itself* (nothing
    there reads that column) but silently broke `/crew`'s per-diver
    experience-type badge, since `get_crew_schedule` (a SQL RPC, migration
    010) reads `sd.experience_type` directly. Not caught by `tsc`/lint
    (the column is nullable, a `null` write is a valid value, not a type
    error) and not caught by the session's own Scheduling verification
    (nothing in Scheduling's own UI displays that column back). Only
    found by a deliberate end-of-session cross-page grep for every other
    reader of `experience_type` across `src/app`, which turned up
    `/crew`'s RPC-fed consumer — the exact "grep the whole codebase, not
    just files being rewritten" practice already documented earlier in
    this file, but this time for a column read by a *database function*,
    not just other TypeScript files. Fixed by threading `experienceType`
    through `ClipMember` (sourced from the diver's current open visit,
    fetched in `fetchClipsRaw`) → `TeamDiver` → `TripTeamInput` →
    `saveTripTeams`'s insert; verified end-to-end by building a real trip
    with a `dive_course` diver and confirming both the persisted
    `schedule_divers.experience_type` value and `/crew`'s rendered badge.
    **Lesson: when a table gets a new writer replacing an old one, diff
    the new writer's full column list against the old writer's — not
    just against what the new UI happens to expose or edit — and
    specifically check for columns read only by a SQL RPC/function, since
    those consumers won't show up in a TypeScript-only grep and won't be
    caught by any type checker.**

38. **(Testing technique, unresolved — flagged for a future session, not
    root-caused this session.)** Setting a first-time password via the
    real `/login` "Set your password" flow failed with "Could not update
    password. Please try again." for a raw-SQL-seeded test owner account
    — even though the exact same `createAuthUser()`-style fixture pattern
    (all 8 token columns `''`, correct `identity_data`, `password_changed`
    left at its default `false`) has worked reliably for *login* testing
    across many past sessions (see retrospective #26). This is a
    different code path (the first-time password-set Server Action, not
    sign-in) and wasn't exercised via this raw-seed pattern before today.
    Worked around by setting `public.users.password_changed = true`
    directly via SQL rather than debugging the real flow, since it was
    tangential to this session's actual work. **Not confirmed whether
    this is a real product bug** (would also affect a genuine new
    secretary/owner's first login) **or another raw-seed-fixture gap**
    (something the real Supabase Auth signup flow sets that this
    session's raw insert doesn't) — genuinely unknown either way. If a
    future session needs to exercise the first-time-password-set UI flow
    against a raw-SQL-seeded user again and hits the same error, treat it
    as a real lead worth root-causing (start by diffing against a
    `password_changed=false` row created through the real signup/create-
    secretary path), not as an already-understood quirk to route around
    again.

### Session 2026-07-30 (Signed Documents identity, Group Management visibility, Scheduling per-dive tanks)

39. **(Testing technique, not a code defect — but a genuinely misleading
    intermediate result, worth flagging clearly.)** While verifying
    per-dive nitrox/15L selection, the first test script located "the
    diver's row" with
    `[...document.querySelectorAll('div')].filter(d =>
    d.textContent.includes(diverName) && d.querySelector('button'))`,
    then clicked the first matching row's site-labeled button. This is
    unsound: `textContent` bubbles up through every ancestor, so *every*
    container `<div>` wrapping that diver's row also "includes" their
    name — including the outer Teams container that wraps the whole
    trip's staff-O2 row and every diver row together. `querySelectorAll`
    returns elements in document order (ancestors before descendants), so
    the filter's first match was consistently the wrong, overly-broad
    ancestor, and the click landed on the **Staff O2** pill instead of
    the intended diver's pill. This didn't crash or error — it silently
    toggled the wrong thing, and the resulting tank tally still looked
    internally self-consistent (numbers added up correctly, just for a
    different underlying state than intended), which is exactly the kind
    of wrong-but-plausible result that's easy to mistake for a real
    application bug. Caught by cross-checking the *actual* per-pill DOM
    state directly (querying the Staff O2 row's own button classes)
    against what the tally implied, not by the tally alone. Fixed the
    test by scoping from a unique per-row anchor instead (each diver row
    has exactly one "Remove" button; `removeButton.closest(...)` reliably
    identifies that specific row) rather than filtering a broad element
    list by substring match. **Lesson: when a browser-automation script
    needs "the element for X," never filter a broad
    `querySelectorAll(commonTag)` list by `textContent.includes(X)` —
    text content bubbles through every ancestor, so the match is
    ambiguous by construction and will silently prefer outer containers
    over the specific target. Anchor from a unique, unambiguous element
    within the target (a button/label that appears exactly once per
    instance) and navigate via `closest()`/`parentElement` instead. This
    is a distinct failure mode from the already-documented click-timing,
    console-buffering, and `read_page`-interactive-filter quirks (items
    14, 19, 21, 35) — same family of "don't trust the first read/query in
    this environment," a different specific trap.**

40. **(Testing technique, not a code defect.)** Hand-writing the raw-SQL
    test-fixture insert for `auth.identities` failed twice before
    running, with two different Postgres type-inference errors: first
    "inconsistent types deduced for parameter $1" (the same `$1`
    parameter was used once as a plain `uuid` column value and once
    inside `jsonb_build_object('sub', $1::text, ...)` without a cast,
    so Postgres couldn't settle on one type for it), then after adding
    one cast, "could not determine data type of parameter $2" (a second
    parameter used only inside `jsonb_build_object(...)` with no cast
    anywhere gives Postgres nothing to infer from at all). Both are
    generic to any parameterized query that reuses the same placeholder
    across differently-typed contexts, not specific to this table.
    **Lesson: when a `$N` parameter is used in more than one place in a
    hand-written parameterized query — especially inside
    `jsonb_build_object(...)`, which erases the inferred type — cast it
    explicitly (`$N::uuid`, `$N::text`) at *every* usage site, not just
    the first. Cheaper to add the casts up front than to iterate through
    Postgres's type-inference errors one at a time.**

### Session 2026-07-30, continued a fifth and sixth time (Scheduling UX fixes, a real `/crew` login bug, Diver Form table cleanup)

41. **A real, reproducible bug was initially misdiagnosed as a stale
    dev-server artifact — the opposite mistake from every prior
    "don't trust the first read" lesson in this file — because the
    search for its cause used the wrong Next.js convention name.** The
    user reported `/crew` (the live app's staff.html equivalent) as
    "not accessible." Testing confirmed a real `GET /login?next=%2Fcrew`
    redirect, but a static-analysis pass found *nothing*: no
    `middleware.ts` anywhere in the repo (confirmed by filesystem search
    and `git log --all` — never tracked, ever), the running server's own
    `.next/dev/server/middleware-manifest.json` genuinely empty
    (`"middleware": {}`), no redirect/rewrite rule in
    `routes-manifest.json`, and `/register` (a known-working anon route)
    loading fine on the exact same server at the same time. This
    combination — reproducible bug, zero source-level cause findable —
    was read as evidence of a **stale/desynced shared dev-server
    process** (this project's own well-documented failure mode from
    prior sessions), and a whole verification plan step was built around
    that hypothesis ("test on a fresh copy; if it reproduces there too,
    it's real; if not, it's stale"). When actually tested on a genuinely
    fresh, separate directory copy, **the bug reproduced identically** —
    disproving the stale-server hypothesis outright, and costing a full
    robocopy-a-directory verification cycle that turned out to prove the
    wrong half of the theory. The real cause was found only by accident,
    reading the fresh server's own startup log line for line: `GET /
    307 in 3.2s (next.js: 2.7s, **proxy.ts: 241ms**, application-code:
    270ms)`. This project's Next.js version (16.2.11, per `AGENTS.md`'s
    own standing warning: *"This is NOT the Next.js you know — APIs,
    conventions, and file structure may all differ from your training
    data. Read the relevant guide in `node_modules/next/dist/docs/`
    before writing any code."*) renamed the middleware-equivalent
    convention from `middleware.ts` to `src/proxy.ts` — a completely
    different file (`src/lib/supabase/proxy.ts`'s `PUBLIC_ROUTES`
    allowlist, missing `/crew` and `/reset-password`) that a
    `middleware.ts`-shaped search would never find, no matter how
    thorough. **Lesson: when a Next.js (or any fast-moving framework)
    convention search comes back completely empty *and* the observed
    behavior looks exactly like something that convention would produce,
    treat "the convention itself may have been renamed in this version"
    as a live hypothesis before falling back to "this must be
    environmental/stale" — especially in a project whose own `AGENTS.md`
    already explicitly warns that this exact category of thing (file
    conventions, APIs) differs from training-data assumptions. A
    `grep -r "proxy\|middleware" node_modules/next/dist/docs/` or just
    reading that referenced docs folder once up front would have found
    this in seconds instead of a full stale-server-artifact detour.**
    Once found, the fix was one line (add `/crew` and `/reset-password`
    to `PUBLIC_ROUTES`) — the wrong turn was entirely in the diagnosis,
    not the fix.

42. **(Testing technique, not a code defect.)** Cleaning up the
    temporary fresh-server verify directory
    (`aquadesk-app-verify`, created for retrospective #41's diagnosis)
    repeatedly failed with `Remove-Item : Cannot remove the item ...
    because it is in use` even after the dev server process running from
    it was confirmed killed and every file inside it was individually
    removable. The actual holder of the lock was the Bash tool's own
    persistent shell — an earlier `cp` command in that same investigation
    had `cd`'d into the verify directory to run a relative-path copy, and
    the shell's working directory was never changed back afterward, so
    the directory itself (not any file in it) stayed "in use" by that
    shell process the whole time. Confirmed via `pwd` and fixed by
    `cd`-ing the shell back to the project root before retrying the
    delete, which then succeeded immediately. **Lesson: before deleting
    a scratch/verify directory, check whether *this session's own*
    persistent shell (Bash tool's cwd persists across calls) still has it
    as its working directory — a `pwd` check costs nothing and this
    exact symptom (every individual file/subfolder removable, but the
    parent directory itself refuses) is the specific signature of that
    cause, distinct from an external process actually holding a file
    handle.**

### Session 2026-07-31 (Equipment/Group Management/Inventory rename, Scheduling clip-merge + turnaround-time, Move-diver + app-wide font/color)

43. **A background-process tool's reported exit status can be
    misleading in a way that costs real time if trusted at face
    value.** `robocopy`'s exit code `1` means "one or more files were
    copied successfully" — a genuinely successful run — but this
    session's background-task harness surfaces any non-zero exit code
    as `status: "failed"`. The very first isolated-verify-server setup
    this session read that "failed" label, and momentarily treated a
    completely successful directory copy as an error before checking
    the actual file counts and confirming it had, in fact, fully
    succeeded. **Lesson: for `robocopy` specifically (and any tool with
    its own non-standard exit-code convention), don't trust a generic
    "failed"/"succeeded" label from the calling layer — check the
    tool's own documented exit-code meaning, or just verify the actual
    result (file counts, file existence) directly.**

44. **Running `robocopy` through the Bash tool (Git Bash/MSYS) mangles
    Windows-style single-slash flags** — `/E` gets interpreted as a
    path and rewritten to `E:/`, producing `ERROR : Invalid Parameter
    #3 : "E:/"` instead of actually copying anything. This is an MSYS
    path-conversion quirk, not a robocopy problem. **Lesson: always run
    `robocopy` (and likely other native Windows tools using single-
    slash flag syntax) via the PowerShell tool, never Bash — this
    project's established isolated-verify-server setup already used
    PowerShell for this in earlier sessions; re-confirmed here after
    briefly forgetting and hitting the exact error a fresh account of
    the pattern would have prevented.**

45. **Next.js/Turbopack's dev server writes to one shared, global
    telemetry config file (`%APPDATA%\nextjs-nodejs\Config\config.json`)
    regardless of project directory or port** — starting a second,
    fully isolated dev server (different directory, different port,
    entirely separate `node_modules`) can still crash immediately after
    printing "✓ Ready" with `Error: EXDEV: cross-device link not
    permitted, rename '...config.json.<tmp>' -> '...config.json'`,
    because both server instances' telemetry writers raced on the same
    global file. Setting `NEXT_TELEMETRY_DISABLED=1` before starting the
    server avoids the write entirely. **Lesson: for this project's
    established isolated-verify-server pattern, set
    `NEXT_TELEMETRY_DISABLED=1` proactively every time, not just after
    hitting this crash once — it's a genuine race condition whenever
    any other Next.js dev server might be running anywhere on the
    machine, not a rare edge case.**

46. **A port that had *any* startup issue earlier in the session — even
    an unrelated one — can still be silently occupied by a lingering
    process from that earlier attempt, causing the next server-start
    attempt on the same port to fail with `EADDRINUSE`.** An earlier
    malformed background-subshell launch attempt this session (using a
    `(cmd &) ; echo done` pattern to try to detach a process) left a
    real `node` process bound to a port that a later, properly-formed
    server-start attempt then collided with. **Lesson: once a port has
    had any kind of startup problem in a session, don't retry that same
    port — pick a fresh one nobody has touched yet, and if a stray
    process needs to be confirmed/killed, check `Get-NetTCPConnection`/
    `Get-CimInstance Win32_Process` for the actual owning process before
    assuming the port is simply free.**

47. **The Browser pane's `javascript_tool` execution context persists
    `const`/`let` declarations across separate tool calls within the
    same tab** — declaring `const btn = ...` in one call and then
    `const btn = ...` again in a later call throws `SyntaxError:
    Identifier 'btn' has already been declared`, even though each call
    looks like an independent script. This happened repeatedly this
    session with short one-off ad hoc DOM-query snippets reusing common
    variable names (`btn`, `select`, `b`). **Lesson: wrap every ad hoc
    `javascript_tool` snippet in an IIFE — `(() => { ... })();` — rather
    than declaring top-level `const`/`let`, so repeated short scripts
    within the same browser tab session never collide with each other's
    leftover scope.**

48. **(Testing technique, not a code defect — reconfirms and adds to
    the already-documented "don't trust the first read after a
    mutation" family, items 15/19/21/35/39/41.)** Both today's clip
    merges and trip saves in Scheduling repeatedly showed pre-mutation
    state on the very next `get_page_text` read immediately after the
    triggering action — even though direct SQL confirmed the write had
    already committed correctly. Each time, either reloading the page
    or switching Scheduling's phase tab and back made the correct state
    appear. **Lesson: this pattern is now confirmed common enough in
    Scheduling specifically (clip creation/merge, trip save) that it
    should be the default expectation, not a surprise each time — verify
    a suspected "didn't work" result against direct SQL before concluding
    a fix is broken, and reload/switch-tabs before trusting a UI read
    taken in the same tool call immediately after a mutation.**

49. **Coordinate-based `computer` clicks and the `form_input` tool on
    `<select>` elements are unreliable in this environment when the DOM
    has just re-rendered or when React's `onChange` needs a real
    `change` event** — several buttons (Sign In, "Add to Clip," "Create
    Clip," clip-merge staff pickers) needed a `javascript_tool`
    `document.querySelector`/`Array.find`-by-text `.click()` instead of
    a coordinate click, and every `<select>` value change needed the
    native-property-setter + `dispatchEvent(new Event('change', {
    bubbles: true }))` pattern rather than the `form_input` tool, to
    reliably reach React's handlers. **Lesson: this extends the
    project's already-documented browser-pane quirks (coordinate clicks
    unreliable, `.blur()` doesn't reach React) to `<select>` elements
    specifically — when a `form_input` change on a `<select>` doesn't
    seem to register (the picked option doesn't visibly take effect),
    switch to the native-setter+dispatchEvent JS pattern rather than
    retrying `form_input` or `computer` clicks at different
    coordinates.**

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

## Dead-code / regression audit (2026-07-26 session, final end-of-day pass)

Requested explicitly by the user before closing out for the day — a
closer pass specifically checking whether anything built earlier the
same day left old functions/code unused instead of being replaced in
place, beyond the audit already done mid-session (immediately above).

- Broad `grep` across the **whole** `src/app` (not just `scheduling/`/
  `divers/`) for every symbol removed or replaced this session
  (`TripBuilderPanel`/`DiverAssignmentPanel`/`ConfirmPanel`/
  `DaySelector`/`TripListPanel`/`ExperienceTypeModal`,
  `saveTripDiverAssignments`, `DiverAssignmentInput`,
  `searchDiversForAssignment`/`loadActiveGroups`/
  `loadGroupMembersForAssignment`/`GroupOption`, the old `settings/
  integrations/` path) — zero stale references found anywhere outside
  the files already fixed. Confirmed the `CourseRateOption`/
  `loadCourseRateOptions` matches in `divers/`/`diver-form/` are the
  already-known naming-collision false positive (separate, still-live
  symbols for the push-to-schedule experience-tagging flow), not leftover
  references to the ones removed from `scheduling/`.
- Fresh usage-count pass (`grep -rl "\bsymbol\b" src/app | wc -l`) across
  every symbol added this session, whole-app scope — all resolved to
  either false positives already explained in the mid-session audit
  (`ClipMember`, `loadExcludedDiverIds`, `filterActiveIndividualCards` —
  each genuinely consumed within its own defining file) or genuine
  multi-file usage. `includeDiverForDay` now correctly shows 2 files
  (definition + real consumer) after being wired up.
- Checked for any other page reading `DayAssignment`,
  `schedule_team_clips`, or `schedule_day_diver_exclusions` outside
  `scheduling/` — none found, confirming the `DayAssignment.scheduleId`
  fix (retrospective #36) and the clip tables are genuinely
  Scheduling-only concerns with no cross-page regression risk.
- **One real, more serious regression found and fixed this pass**:
  cross-page grep for `experience_type` (not scoped to `scheduling/`,
  specifically to catch consumers a code-only review of the rewritten
  files would miss) turned up `/crew`'s `get_crew_schedule` RPC reading
  `schedule_divers.experience_type` directly — a column the rebuilt
  `saveTripTeams` never wrote. See retrospective #37 for the full account
  and the fix (`ClipMember`/`TeamDiver`/`TripTeamInput` all gained
  `experienceType`, sourced from the diver's open visit). Verified
  end-to-end: built a real trip with a `dive_course`-tagged diver,
  confirmed the persisted column and `/crew`'s rendered badge both
  correct. `tsc --noEmit`/`npm run lint` re-run clean after the fix.
- Database confirmed empty of test data after this pass's own
  verification (a third seeded dive center, used specifically to
  reproduce and verify the `experience_type` fix) — back to just the
  two real accounts and one real `dive_centers` row.

**One real regression found this pass that the earlier same-day audit
missed** (`schedule_divers.experience_type` never written by the new
save path) — the mid-session audit's usage-count method is good at
catching *unused* exports but does not catch a *write path that's
missing a column entirely*, since the column itself doesn't appear as a
dead symbol anywhere in the TypeScript it was reviewing. See
retrospective #37 for why this specific class of gap (a column read only
by a SQL RPC) needs its own explicit cross-page/cross-language grep, not
just a symbol-usage pass.

## Dead-code audit (2026-07-30 session — Signed Documents identity, Group Management visibility, Scheduling per-dive tanks)

Requested explicitly by the user before closing out the session, as its
own separate step (not folded into the feature work), specifically
checking whether anything built today left old functions/code unused
instead of being replaced in place.

- `npx tsc --noEmit` and `npm run lint` — both clean, run after every
  feature and again fresh at the very end.
- Grepped the whole `src/` tree (not just the touched files) for every
  symbol removed or renamed today: `toggleSite`, `toggleDiverFlag`,
  `isGroupActive`, and the old tally field names `tank12L`/`tank15L`
  (replaced by `TankTally`'s `air12l`/`air15l`/`nitrox` shape) — zero
  remaining references to any of them.
- Usage-count pass (`grep -rl "\bsymbol\b" src/app | wc -l`) on every
  new exported symbol added today: `computeTankTally`, `formatTankLine`,
  `DiveTank`, `StaffDiveTanks`, `loadStaffDiveTanks`, `getStaffDiveTanks`,
  `includeDiverInClip`, and the new `courseName` field on
  `ScheduleDiverRow` — all resolve to 2+ files (definition plus at least
  one real consumer), none at 1. `courseName` showed 8 files at first
  glance, which per retrospective #25's warning is exactly the kind of
  count worth checking closely rather than trusting outright — confirmed
  a false alarm: it's a common field name independently reused across
  unrelated features (Diver Detail's course-rate display, the
  push-to-schedule experience-tag modal, Settings > Courses), not a
  naming collision or a sign of dead code.
- **One real item, already caught and fixed during implementation itself
  (confirmed still clean by this end-of-session pass, not newly found
  here)**: removing `PhaseThreePanel.tsx`'s manual crew-token "Generate"/
  "Regenerate" button left its `readOnly` prop completely unused (it
  existed only to gate that button). Lint flagged it immediately when
  the button was removed; the prop was removed from both
  `PhaseThreePanel`'s own type and its `SchedulingClient.tsx` call site
  in the same edit rather than leaving an unused prop threaded through
  for no reason — confirmed `isPastDate` (the value that had been
  passed in) is still genuinely used elsewhere in `SchedulingClient.tsx`,
  so this was a clean, complete removal, not a partial one.
- Confirmed the small-helper duplication pattern already established in
  this codebase (`peso`, `fmtDate`, `todayManila`) wasn't violated by
  today's new `scheduling/tanks.ts` — it's a single shared pure function
  used by both `TripCard.tsx` and `PhaseThreePanel.tsx` specifically
  *because* the two previously had their own independently-wrong tally
  computations that disagreed with each other; consolidating this one
  was the fix, not a deviation from the duplication precedent (which
  still applies to trivial one-line formatters like `peso`).
- **One known, deliberately-accepted gap found and left undone, not
  silently dropped**: the live app's schedule preview shows a "Crew:"
  line (comma-joined crew member names) alongside "Captain" for own-boat
  trips. This rebuild's `boats` table has no crew-list column at all
  (only `captain`), and building one wasn't asked for — the preview
  rewrite correctly omits the Crew line rather than fabricating data for
  a field that doesn't exist. Recorded in Known Gaps below so a future
  session doesn't assume this was an oversight.
- Test dive center (`Feedback Test DC` — owner, 3 divers, staff, boat,
  2 dive sites, a signed registration, 2 future-dated groups) and its
  `auth.users` row deleted after verification, confirmed via direct
  query that the user's own real `Demo Dive Center` was never touched.
  Database confirmed back to just the two real accounts and one real
  `dive_centers` row at session end.

**Nothing found that needed a code fix beyond the already-caught
`readOnly` prop** (see above) — the rest of the audit came back clean.

## Dead-code audit (2026-07-30 session, continued — Diver Form Apply Charges + Scheduling captain/crew/UI feedback pass)

- `npx tsc --noEmit` and `npm run lint` — both clean, run after every
  part of the change and again fresh at the end.
- Grepped the whole `src/` tree for the removed `wantsNitrox`/
  `wants15L` checkbox state and the `isCourseVisit` prop it was gated
  by (`VisitPanel.tsx`) — zero remaining references; `isCourseVisit`
  was removed completely (type, destructure, and call site), not left
  as a dead prop, matching the same-day precedent set by the
  `readOnly`-prop removal in the earlier session's audit above.
  Confirmed live via `document.querySelectorAll('table input[type=
  "checkbox"]')` on a real activities table — zero checkboxes.
- Grepped for `fuelLiters` (the removed Phase 3 local input state) and
  `boat?.captain` (the old, always-empty preview/header source) —
  `PhaseThreePanel.tsx` has neither; both call sites now read
  `detail.captain`/`detail.fuelConsumedLiters`/`detail.crew` instead.
  `boats.captain` itself is untouched and still legitimately read by
  Settings > Fleet (`BoatsSection.tsx`) and Boat Manifest
  (`boat-manifest/data.ts`) — confirmed these are a separate,
  pre-existing feature (a boat's own Fleet-configured captain) not
  superseded by the new per-trip `schedules.captain`, so left alone;
  not a stale reference.
- Usage-count pass on every new exported symbol this session
  (`replaceScheduleCrew`, `validateOwnBoatFields`, `tankFlagsFromRow`,
  `applyChargesToVisit`, `to12h`/`to24h`, `padCrewSlots`,
  `MIN_CREW_SLOTS`) — all resolve to 2+ files (definition plus a real
  call site) or are correctly used only within their own defining file
  (`to12h`/`to24h`/`padCrewSlots` are `TripCard.tsx`-local, matching
  the existing `padSiteSlots`/`MIN_SITE_SLOTS` pattern they mirror).
- The `markBoatReturned` signature change (dropping its
  `fuelLitersConsumed` parameter) was traced to its one caller
  (`TripSummaryCard.returnBoat` in `PhaseThreePanel.tsx`) — confirmed
  no other file calls it, so this wasn't a partial signature change
  left half-migrated.
- **One pre-existing (not newly introduced) rough edge noticed, not
  fixed — out of scope for what was asked**: a freelancer team's name
  (e.g. "DM Alex") reverts to "Unassigned" after a trip is saved and
  reloaded, because `TripCard.tsx`'s load path resolves a team's
  display name via `staffOptions.find(s => s.id === t.staffId)?.
  fullName ?? "Unassigned"` — always "Unassigned" for a freelancer
  since `staffId` is null by design. This is unchanged pre-existing
  code from the original three-phase Scheduling rebuild, not touched
  or caused by this session's edits (confirmed by reading the exact
  same logic, unmodified, in the file's git history) — noted here for
  a future session rather than silently worked around.
- Database confirmed empty of test data at session end — only the two
  real accounts and the one real `dive_centers` row remain (see the
  main write-up above for the exact cleanup sequence).

**Nothing found that needed fixing beyond what's already noted above.**
The one real pre-existing rough edge found (freelancer name reverting
to "Unassigned" on reload) is flagged, not fixed — it wasn't part of
what the user asked for this session and predates these changes.

## Dead-code audit (2026-07-30 session, continued yet again — on-brand dialogs, package-pricing correctness, Scheduling visual mirror)

- `npx tsc --noEmit` and `npm run lint` — both clean, run after every
  part and again fresh at the end.
- Grepped the whole `src/` tree for `window.confirm`/`window.alert`/
  `window.prompt` — zero remaining real call sites (one harmless hit is
  this session's own code comment referencing `window.alert()` by name
  to explain what it replaced, not a live call).
- Grepped for `linkedPackageId`/`linked_package_id` across `diver-form/`
  — the only remaining references are in `pricing.ts`'s own explanatory
  comments; the dead `SiteMeta.linkedPackageId` field and its now-unused
  `dive_sites.linked_package_id` select column were removed together,
  not left half-stripped. `dive_sites.linked_package_id` itself (the
  column, and Settings > Dive Sites' own read/write of it) is untouched
  and confirmed still genuinely used there — a deliberate, correct
  Settings-UI-only survivor, not a stale reference.
- Usage-count pass on every new exported symbol this session
  (`useConfirm`, `ConfirmProvider`, `useToast`, `ToastProvider`,
  `UIProviders`, `Button`, `SectionBox`, `normalizeSiteKey`,
  `resolvePackageBySiteCombo`) — all resolve to 2+ files (definition
  plus real call sites across the 7+ components each was wired into).
- Confirmed `replaceScheduleSites`'s new `{ error?: string }` return
  value is actually read at both call sites (`createTrip`/`updateTrip`)
  — not a return value that's computed but silently discarded, the
  exact class of bug this fix was closing.
- Test dive center (`Package Test DC` — owner, boat, 2 dive sites, 1
  package, 1 diver) and its `auth.users` row deleted after verification,
  confirmed via direct query that the user's own real `Demo Dive
  Center` was never touched. Database confirmed back to just the two
  real accounts and one real `dive_centers` row at session end.

**Nothing found that needed fixing beyond what's already documented in
the session write-up above** (the `schedule_sites` unique-constraint
bug, found and fixed via migration 019 during this session's own live
verification, not left for a future pass).

## Dead-code audit (2026-07-30 session, continued a fifth and sixth time — Scheduling UX fixes, `/crew` login bug, Diver Form table cleanup)

Requested explicitly by the user at session close, as its own separate
step, specifically checking whether anything built across *both* of
today's remaining passes left old functions/code unused instead of
being replaced in place.

- `npx tsc --noEmit` and `npm run lint` — both clean, run after every
  part of both passes and again fresh at the very end.
- Grepped the whole `src/` tree for every symbol removed today
  (`cycleDiverTank`, `autoPriceActivityRow`, `AutoPriceRequest`) — zero
  remaining references to any of them. `autoPriceActivityRow`'s removal
  also left one stale explanatory comment referencing it by name in
  `applyChargesToVisit`'s doc comment (`actions.ts`) — caught and
  reworded in the same pass, not left dangling.
- Usage-count pass (`grep -rl "\bsymbol\b" src/ | wc -l`) on every new
  symbol added across both passes: `mbca`, `replaceScheduleSpareTanks`,
  `setSpareTankSlot`/`addSpareTank`/`removeSpareTank`,
  `toggleDiverNitrox`/`toggleDiverTank15l`, `formatTime12h`,
  `nowManilaMinute` (the new client-side copy in `PhaseThreePanel.tsx`),
  `CERT_LEVEL_LABELS` (the new `diver-form/constants.ts` copy). Several
  showed "1 file" under the blunt heuristic — per retrospective #25's
  standing warning, checked each one's actual occurrence lines rather
  than trusting the count alone: every one resolved to a real
  definition-plus-call-site pair within its own file (all are
  intentionally module-private helpers, never exported, so "1 file" is
  the *correct* outcome here, not a red flag) — none were dead.
- The two additional certification-label bugs found while verifying
  (Diver Form's list page, `DiversListClient.tsx`) were genuine gaps
  beyond the one the user reported (`DocumentsViewer.tsx`) — found by
  grepping the whole codebase for every remaining raw
  `certificationLevel`/`certification_level` display expression rather
  than stopping at the one reported site, per this project's standing
  "grep the whole codebase, not just the reported spot" practice. Both
  fixed, not just the reported one.
- Confirmed `ActivityFields.discount` (the type field backing the now
  UI-removed per-row Discount column) is still correctly threaded
  through unchanged — `toFields`/`commit` still read/pass the row's own
  already-persisted value, just never expose an editor for it anymore;
  the `activities.discount` **database column** itself is untouched and
  still real, matching this project's established "TypeScript-layer-only
  removal, don't touch a column something else might still read"
  precedent from retrospective #25's own `Visit.isPaid` case.
- Test dive centers (`Scheduling Feedback Test DC`, `Feedback Pass 2 Test
  DC`) and their `auth.users` rows deleted after verification, confirmed
  via direct query that the user's own real `Demo Dive Center` was never
  touched. Database confirmed back to just the two real accounts and one
  real `dive_centers` row at session end.

**Nothing found that needed fixing beyond what's already described in
the session write-up above** — the `autoPriceActivityRow` removal and
its one stale comment reference, and the second certification-label
bug, were all caught and fixed during this session itself, not left for
a future pass.

## Dead-code audit (2026-07-31 session — Equipment/Group Management/Inventory rename, Scheduling clip-merge + turnaround-time, Move-diver + app-wide font/color)

Requested explicitly by the user at session close, as its own separate
step, covering all four passes from today.

- `npx tsc --noEmit` and `npm run lint` — both clean, run after every
  pass and again fresh at the end.
- Usage-count pass (`grep -rl "\bsymbol\b" src | wc -l`) on every
  exported symbol added across all four passes: `computeTripWindow`/
  `windowsOverlap` (2 files each — definition + `WarningsBanner.tsx`'s
  one consumer, correct), `TripTypeOption`/`loadTripTypeOptions`/
  `saveTripType`/`deleteTripType`/`TripTypesSection` (2-4 files each,
  all resolve to real definition-plus-consumer chains), `findMatchingClip`/
  `moveDiverToNewClip` (2 files each, confirmed single real call site),
  `ratioBadgeClass` (3 files — `constants.ts`, `WarningsBanner.tsx`,
  `PhaseOnePanel.tsx`, matching the three call sites the shared helper
  was built for), `loadGearInventoryCounts`/`getGearInventoryCounts` (2
  files each). `FALLBACK_DURATION` and `findRequestedItem` both showed
  "1 file" — checked closely per retrospective #25's standing warning
  rather than trusting the count alone: both are correctly
  module-private helpers genuinely used within their own defining file
  (`tripWindow.ts`'s own fallback default; `EquipmentManagementTab.tsx`'s
  own shortage tally), not orphaned exports — false positives of the
  blunt heuristic, same pattern as several earlier sessions'
  `StaffPageData`-style finds.
- **One real duplication found and fixed**: `EquipmentManagementTab.tsx`
  (written in pass one) had `findRequestedItem` and `cellValue`
  independently implementing the identical "does this item match this
  column" predicate in the same file — `findRequestedItem` was added
  later for the new inventory-shortage tally, but `cellValue`'s own
  original match logic was never refactored to reuse it, leaving two
  copies of the same one-line rule that could silently drift if only
  one were ever changed. Fixed by having `cellValue` call
  `findRequestedItem` (committed as `aquadesk-app@34c713f`, pass four
  above).
- Grepped for `TODO`/`FIXME`/`XXX` across every file touched today
  (`scheduling/`, `divers/components/{EquipmentManagementTab,
  GroupManagementTab,DiverCard}.tsx`, `settings/dive-sites/`,
  `settings/inventory/GearSection.tsx`, `settings/staff/components/
  CertificationsSection.tsx`, `reports/StaffTab.tsx`, `staff/
  StaffScheduleClient.tsx`, `globals.css`) — none found.
- Database confirmed empty of test data at session end (three separate
  test dive centers seeded and torn down across the day's passes,
  `schedules.created_by` nulled in its own committed statement first
  each time, per the established cleanup-ordering lesson) — only the
  real accounts and the one real `dive_centers` row remain. Both repos'
  `git status` clean as of this write-up.

**One real dead-code item found and fixed** (the `findRequestedItem`/
`cellValue` duplication above). Nothing else found — everything else
built today was either a genuinely new symbol with a real, confirmed
consumer, or module-private and correctly scoped to its own file.

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
