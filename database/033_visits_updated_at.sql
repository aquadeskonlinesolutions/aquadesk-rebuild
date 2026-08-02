begin;

-- Version token for optimistic-concurrency checks on Diver Form's checkout/
-- payment-save actions — matches the already-existing schedules.updated_at
-- + set_updated_at() trigger pattern (001_schema_and_rls.sql). Two people
-- racing the same visit (e.g. an owner and a secretary both working the
-- same bill without knowing it) should get an explicit conflict, not a
-- silently overwritten payment record or a duplicated invoice.
alter table visits
  add column updated_at timestamptz not null default now();

create trigger visits_set_updated_at before update on public.visits
  for each row execute function public.set_updated_at();

commit;
