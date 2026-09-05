-- AquaDesk Rebuild — Expense "+ Add Category" (replaces "Uncategorized")
--
-- The 12 real fixed expense categories (everything except Uncategorized)
-- are untouched — same enum, same labels, zero risk to existing
-- analytics/filters keyed off those exact string values. This only adds
-- a lean mechanism for per-dive-center custom categories, mirroring the
-- existing 'other' + expenses.custom_category (free text) precedent
-- already in this table: one new enum sentinel ('custom') paired with a
-- new nullable FK column, instead of converting the whole enum into a
-- table.
--
-- "Uncategorized" itself is not removed from the enum (existing rows
-- keep it forever, untouched) — it just stops being written by any new
-- code path, replaced in the dropdown by "+ Add Category".
--
-- Note: ALTER TYPE ... ADD VALUE cannot be *used* within the same
-- transaction that adds it. Nothing else in this migration references
-- 'custom', so it's safe inside one begin/commit.

begin;

alter type public.expense_category add value 'custom';

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  label text not null,
  normalized_label text not null,
  created_at timestamptz not null default now(),
  unique (dive_center_id, normalized_label)
);

alter table public.expense_categories enable row level security;
create policy expense_categories_select on public.expense_categories for select
  using (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue());
create policy expense_categories_write on public.expense_categories for all
  using (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue())
  with check (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue());

alter table public.expenses
  add column custom_category_id uuid references public.expense_categories(id) on delete set null;

commit;
