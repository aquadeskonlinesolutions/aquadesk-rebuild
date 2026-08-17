begin;

-- Boat Manifest is specific to Malapascua's local Bureau of Customs
-- passenger-manifest requirement — as AquaDesk expands to other regions
-- (Koh Tao, Indonesia, etc.) it shouldn't be forced on dive centers that
-- have no such requirement. Defaults true so every existing (all
-- Malapascua-based) dive center keeps working exactly as it does today
-- with zero disruption; new dive centers in other regions get it turned
-- off during onboarding via /office.
alter table public.dive_centers
  add column boat_manifest_enabled boolean not null default true;

-- Extend the platform-admin update-scope allowlist so /office can toggle
-- this new field, same as it already can for subscription/billing fields.
-- This function has only ever been defined once (001_schema_and_rls.sql),
-- so this replace is based directly on that current, unmodified body.
create or replace function public.enforce_dive_center_update_scope()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_platform_admin() and not public.is_owner() then
    if (to_jsonb(NEW) - array['subscription_status','billing_due_date','billing_amount','last_payment_date','boat_manifest_enabled'])
       is distinct from
       (to_jsonb(OLD) - array['subscription_status','billing_due_date','billing_amount','last_payment_date','boat_manifest_enabled'])
    then
      raise exception 'platform admin may only modify subscription/billing fields on dive_centers';
    end if;
  end if;
  return NEW;
end;
$$;

commit;
