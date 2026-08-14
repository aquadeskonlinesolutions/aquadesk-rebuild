begin;

-- Course pricing: equipment/gear inclusion toggle. Confirmed business
-- rule -- equipment is bundled into course pricing by default (matches
-- the already-shipped blanket course-mode equipment exclusion from
-- earlier today), but some dive centers charge equipment on top of the
-- course price for specific courses. This makes that a real per-course
-- setting instead of an unconditional rule. Every existing row (and any
-- new row, via the column default) starts with equipment included --
-- per explicit instruction, this must not silently change any existing
-- dive center's course billing.
alter table public.course_rates
  add column equipment_included boolean not null default true;

-- New: multi-dive "bundle" pricing (e.g. 3/6/9/10-dive packages), a
-- dive-center-configured flat price for a fixed number of dives --
-- distinct from course_rates' flat-course-price and from the tier/
-- package pricing_mode machinery. A bundle is applied explicitly, per
-- visit, from Diver Form -- never automatically the way tier/package
-- pricing is.
create table public.bundles (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  name text not null,
  dive_count integer not null check (dive_count between 1 and 100),
  price numeric(10,2) not null check (price >= 0),
  equipment_included boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.bundles enable row level security;

-- Same "Settings tier" shape as course_rates/equipment_rental_rates/etc.
-- (see 001_schema_and_rls.sql's settings_tables loop): every tenant user
-- can read, only the owner can write.
create policy bundles_select on public.bundles
  for select using (dive_center_id = public.current_dive_center_id());
create policy bundles_owner_write on public.bundles
  for all
  using (dive_center_id = public.current_dive_center_id() and public.is_owner())
  with check (dive_center_id = public.current_dive_center_id() and public.is_owner());

-- Display-only tag on the one activity row that carries a bundle's
-- lump-sum charge -- same pattern as activities.package_id (migration
-- 032): never read back for pricing, only marks which row's dive_site
-- text is actually a bundle name (rendered in italics by the UI) rather
-- than a real dive site.
alter table public.activities
  add column bundle_id uuid references public.bundles(id) on delete set null;

commit;
