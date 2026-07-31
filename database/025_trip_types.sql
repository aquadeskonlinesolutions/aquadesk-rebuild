-- AquaDesk Rebuild — Trip Types: real per-dive-center turnaround/duration config
--
-- The live app (scheduling.html) computes each trip's real time window from
-- a hardcoded JS constant, tripTypeDurations — keyed by free-text trip-type
-- names ("Local Dive", "Shark Dive", "Gato", "Outside Malapascua") specific
-- to one dive center's own geography, mapping each to travel-out/travel-
-- back/dive/surface-interval minutes. tripWindow()/overlaps() then use that
-- to flag genuine same-day schedule conflicts (a diver/staff member on two
-- trips whose time windows actually overlap), not just "on any trip that
-- day" — confirmed via full research of scheduling.html before this
-- migration was written.
--
-- That hardcoded list can't be reused as-is in a multi-tenant rebuild — a
-- different dive center's real sites/trip shapes won't match "Gato" or
-- "Outside Malapascua". Per the user's explicit choice (asked directly,
-- since this is a genuine architecture decision with several valid designs),
-- this recreates the Trip Type concept as a real per-dive-center Settings
-- list instead of a hardcoded constant — same fields the live app's JS
-- object holds, just editable per tenant.
--
-- schedules.trip_type_id is nullable: existing trips (and any dive center
-- that hasn't configured trip types yet) still work — the app-side duration
-- calculation falls back to a generic default when it's unset, rather than
-- erroring or silently disabling the overlap-warning feature.

begin;

create table public.trip_types (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  name text not null,
  travel_out_minutes integer not null default 0,
  travel_back_minutes integer not null default 0,
  dive_minutes integer not null default 60,
  surface_interval_minutes integer not null default 60,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Owner-write / tenant-read — the real access model course_rates already
-- has (via the one-time settings_tables loop in 001, which can't be
-- re-run for a new table), written explicitly here instead.
alter table public.trip_types enable row level security;
create policy trip_types_select on public.trip_types for select
  using (dive_center_id = public.current_dive_center_id());
create policy trip_types_owner_write on public.trip_types for all
  using (dive_center_id = public.current_dive_center_id() and public.is_owner())
  with check (dive_center_id = public.current_dive_center_id() and public.is_owner());

alter table public.schedules
  add column trip_type_id uuid references public.trip_types(id) on delete set null;

commit;
