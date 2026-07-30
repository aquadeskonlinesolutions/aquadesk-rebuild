begin;

-- No live-app precedent (grepped every reference *.html for "spare" —
-- nothing but an unrelated placeholder string in a free-text notes
-- field) — this is new, rebuild-only scope: a per-trip list of spare
-- tanks, each independently typed, reusing the existing public.tank_type
-- enum rather than inventing a new one.
create table public.schedule_spare_tanks (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  schedule_id uuid not null references public.schedules(id) on delete cascade,
  tank_type public.tank_type not null,
  sort_order integer not null default 0
);

-- Same 4-policy shape as every other "operational" table (the one-time
-- do $$ loop that created those already ran in 001 and can't be re-run).
alter table public.schedule_spare_tanks enable row level security;
create policy schedule_spare_tanks_select on public.schedule_spare_tanks for select
  using (dive_center_id = public.current_dive_center_id());
create policy schedule_spare_tanks_insert on public.schedule_spare_tanks for insert
  with check (dive_center_id = public.current_dive_center_id());
create policy schedule_spare_tanks_update on public.schedule_spare_tanks for update
  using (dive_center_id = public.current_dive_center_id())
  with check (dive_center_id = public.current_dive_center_id());
create policy schedule_spare_tanks_delete on public.schedule_spare_tanks for delete
  using (dive_center_id = public.current_dive_center_id());

commit;
