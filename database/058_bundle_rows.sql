-- AquaDesk Rebuild — Apply Bundle rework (row_type, price snapshots, apply/remove)
--
-- ADDITIVE ONLY. No existing row is read, changed or deleted by this file:
--
--   1. activities.row_type — new nullable text column. It is NULL for every
--      existing row (no default, no backfill) and stays NULL for ordinary
--      dives. New-style bundle rows get 'bundle'. Existing (legacy) bundle
--      rows keep their bundle_id tag and a NULL row_type, so they display,
--      price and count exactly as before.
--   2. A unique partial index: at most ONE new-style bundle row per visit.
--   3. activity_bundle_snapshots — new empty table holding each dive row's
--      exact previous prices while a bundle is applied, so Remove Bundle can
--      restore them. Tenant-scoped read access; no direct writes from the
--      app's users (only the two functions below write it). The same
--      closed-bill lock trigger as migration 057 is attached.
--   4. activity_dive_count() — how many dives one activity row stands for,
--      read from its dive-site text (one comma-separated entry per dive:
--      "Gato, Gato, Gato" = 3, "Local, Local" = 2, "Lighthouse" = 1). No
--      dive count is stored anywhere else. Returns NULL when the text cannot
--      be counted reliably (empty, or an entry containing a digit or "+",
--      e.g. "3sharks+3gato"); Apply Bundle then refuses instead of guessing.
--   5. apply_bundle() / remove_bundle() — each does its whole job in one
--      database transaction (all-or-nothing), checks the visit is open and
--      belongs to the caller's dive center, and — because they run with the
--      owner's rights and so bypass the 057 trigger — check "open" themselves.
--      The existing 057 audit triggers on activities still record every
--      change after an unlock (who, what, before -> after).
--
-- Deploy order: this migration first, then the app code.

begin;

-- ---- 1. row_type -------------------------------------------------------------
alter table public.activities
  add column row_type text check (row_type in ('bundle'));

-- ---- 2. one new-style bundle row per visit -----------------------------------
create unique index activities_one_bundle_row_per_visit
  on public.activities (visit_id) where row_type = 'bundle';

-- ---- 3. snapshots ------------------------------------------------------------
create table public.activity_bundle_snapshots (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  visit_id uuid not null references public.visits(id) on delete cascade,
  bundle_activity_id uuid not null references public.activities(id) on delete cascade,
  activity_id uuid not null references public.activities(id) on delete cascade,
  dive_rate numeric(12,2) not null,
  fuel_surcharge numeric(12,2) not null,
  marine_tax numeric(12,2) not null,
  shark_fee numeric(12,2) not null,
  equipment_rental numeric(12,2) not null,
  created_at timestamptz not null default now(),
  unique (bundle_activity_id, activity_id)
);

create index activity_bundle_snapshots_visit_idx on public.activity_bundle_snapshots (visit_id);

alter table public.activity_bundle_snapshots enable row level security;

create policy activity_bundle_snapshots_select on public.activity_bundle_snapshots
  for select using (dive_center_id = public.current_dive_center_id());

revoke insert, update, delete on public.activity_bundle_snapshots from anon, authenticated;

create trigger activity_bundle_snapshots_closed_bill_lock
  before insert or update or delete on public.activity_bundle_snapshots
  for each row execute function public.guard_closed_visit_activities();

-- ---- 4. dive count of a row -----------------------------------------------------
create or replace function public.activity_dive_count(p_site text)
returns integer
language sql immutable set search_path = public as $$
  select case when t.n = 0 or t.bad > 0 then null else t.n::integer end
    from (select count(*) filter (where btrim(e) <> '') as n,
                 count(*) filter (where btrim(e) ~ '[0-9+]') as bad
            from regexp_split_to_table(coalesce(p_site, ''), ',') as e) t;
$$;

-- ---- 5. apply_bundle ---------------------------------------------------------
-- p_equipment: the gear amount the app priced with its usual equipment rule;
-- ignored (treated as 0) when the bundle already includes equipment.
create or replace function public.apply_bundle(p_visit_id uuid, p_bundle_id uuid, p_equipment numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dc uuid := public.current_dive_center_id();
  v_visit record;
  v_bundle record;
  v_rows int;
  v_count int;
  v_unknown record;
  v_last_date date;
  v_equipment numeric(12,2);
  v_bundle_row uuid;
begin
  if v_dc is null then
    raise exception 'Not signed in.';
  end if;

  select id, diver_id, visit_status, experience_type into v_visit
    from public.visits where id = p_visit_id and dive_center_id = v_dc for update;
  if not found then
    raise exception 'Visit not found.';
  end if;
  if v_visit.visit_status <> 'open' then
    raise exception 'This bill is closed. Unlock it with the billing password before changing it.';
  end if;
  if v_visit.experience_type <> 'fun_diving' then
    raise exception 'Bundles can only be applied to fun-diving visits.';
  end if;

  select id, name, dive_count, price, equipment_included into v_bundle
    from public.bundles where id = p_bundle_id and dive_center_id = v_dc and is_active;
  if not found then
    raise exception 'Bundle not found.';
  end if;

  if exists (select 1 from public.activities
              where visit_id = p_visit_id and row_type = 'bundle') then
    raise exception 'A bundle is already applied to this visit. Remove it first.';
  end if;
  if exists (select 1 from public.activities
              where visit_id = p_visit_id and bundle_id is not null and row_type is null
                and status <> 'cancelled') then
    raise exception 'This visit already has a bundle from before this update, which can''t be changed here. Nothing was applied.';
  end if;

  select count(*), max(date), coalesce(sum(public.activity_dive_count(dive_site)), 0)
    into v_rows, v_last_date, v_count
    from public.activities
   where visit_id = p_visit_id and status <> 'cancelled' and row_type is null;
  if v_rows = 0 then
    raise exception 'Add at least one dive before applying a bundle.';
  end if;
  -- A row whose dives can't be counted from its site text stops the apply.
  select date, dive_site into v_unknown
    from public.activities
   where visit_id = p_visit_id and status <> 'cancelled' and row_type is null
     and public.activity_dive_count(dive_site) is null
   order by date, created_at limit 1;
  if found then
    raise exception 'The dives on the % row (%) can''t be counted, so no bundle was applied. Set that row''s dive site to one entry per dive (for example "Gato, Gato, Gato") and try again.',
      v_unknown.date, coalesce(nullif(btrim(v_unknown.dive_site), ''), 'no dive site');
  end if;
  if v_count <> v_bundle.dive_count then
    raise exception 'This bundle is for % dives but the visit has %. Nothing was applied.', v_bundle.dive_count, v_count;
  end if;

  v_equipment := case when v_bundle.equipment_included then 0
                      else greatest(coalesce(p_equipment, 0), 0) end;

  -- The new bundle row first (so the snapshots can point at it)...
  insert into public.activities
    (dive_center_id, diver_id, visit_id, date, dive_site, dive_rate, equipment_rental,
     status, bundle_id, row_type)
  values
    (v_dc, v_visit.diver_id, p_visit_id, v_last_date, v_bundle.name, v_bundle.price, v_equipment,
     'completed', v_bundle.id, 'bundle')
  returning id into v_bundle_row;

  -- ...then save each dive's exact prices and set those dives to 0.
  insert into public.activity_bundle_snapshots
    (dive_center_id, visit_id, bundle_activity_id, activity_id,
     dive_rate, fuel_surcharge, marine_tax, shark_fee, equipment_rental)
  select v_dc, p_visit_id, v_bundle_row, a.id,
         a.dive_rate, a.fuel_surcharge, a.marine_tax, a.shark_fee, a.equipment_rental
    from public.activities a
   where a.visit_id = p_visit_id and a.status <> 'cancelled' and a.row_type is null;

  update public.activities
     set dive_rate = 0, fuel_surcharge = 0, marine_tax = 0, shark_fee = 0, equipment_rental = 0
   where visit_id = p_visit_id and status <> 'cancelled' and row_type is null;

  return jsonb_build_object('bundle_activity_id', v_bundle_row, 'dives', v_count);
end;
$$;

-- ---- 6. remove_bundle --------------------------------------------------------
create or replace function public.remove_bundle(p_visit_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dc uuid := public.current_dive_center_id();
  v_status public.visit_status;
  v_bundle_row uuid;
  v_restored int;
begin
  if v_dc is null then
    raise exception 'Not signed in.';
  end if;

  select visit_status into v_status
    from public.visits where id = p_visit_id and dive_center_id = v_dc for update;
  if not found then
    raise exception 'Visit not found.';
  end if;
  if v_status <> 'open' then
    raise exception 'This bill is closed. Unlock it with the billing password before changing it.';
  end if;

  select id into v_bundle_row from public.activities
   where visit_id = p_visit_id and row_type = 'bundle';
  if v_bundle_row is null then
    raise exception 'This visit has no removable bundle.';
  end if;

  update public.activities a
     set dive_rate = s.dive_rate, fuel_surcharge = s.fuel_surcharge, marine_tax = s.marine_tax,
         shark_fee = s.shark_fee, equipment_rental = s.equipment_rental
    from public.activity_bundle_snapshots s
   where s.bundle_activity_id = v_bundle_row and s.activity_id = a.id;
  get diagnostics v_restored = row_count;

  delete from public.activities where id = v_bundle_row; -- snapshots go with it

  return jsonb_build_object('restored', v_restored);
end;
$$;

revoke all on function public.apply_bundle(uuid, uuid, numeric) from public, anon;
revoke all on function public.remove_bundle(uuid) from public, anon;
grant execute on function public.apply_bundle(uuid, uuid, numeric) to authenticated;
grant execute on function public.remove_bundle(uuid) to authenticated;

commit;

-- ---- Rollback ----------------------------------------------------------------
-- Safe only while NO new-style bundle exists (select count(*) from activities
-- where row_type = 'bundle'); otherwise Remove Bundle on each first, or the
-- dives stay at 0.
-- begin;
-- drop function if exists public.apply_bundle(uuid, uuid, numeric);
-- drop function if exists public.remove_bundle(uuid);
-- drop function if exists public.activity_dive_count(text);
-- drop table if exists public.activity_bundle_snapshots;
-- drop index if exists public.activities_one_bundle_row_per_visit;
-- alter table public.activities drop column if exists row_type;
-- commit;
