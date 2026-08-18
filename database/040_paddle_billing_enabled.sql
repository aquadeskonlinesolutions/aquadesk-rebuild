begin;

-- Most current/expected customers are Philippine dive centers paying by
-- manual bank transfer, which avoids Paddle's ~16-18% combined fee/tax/FX
-- cost entirely. This is a second, per-dive-center gate on top of the
-- existing global NEXT_PUBLIC_SUBSCRIPTION_TAB_ENABLED build-time kill
-- switch — both must be true for a dive center to see/use the Subscription
-- tab. Defaults false (opt-in), unlike boat_manifest_enabled's opt-out
-- default true: no existing dive center currently uses Paddle in
-- production, so this stays off until deliberately turned on per customer
-- (e.g. an international customer where bank transfer isn't practical).
alter table public.dive_centers
  add column paddle_billing_enabled boolean not null default false;

-- Extend the platform-admin update-scope allowlist so /office can toggle
-- this new field too, same as boat_manifest_enabled just added in 039.
-- Based on 039's current body of this function (the chronologically latest
-- create or replace of this name), not reconstructed from memory.
create or replace function public.enforce_dive_center_update_scope()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_platform_admin() and not public.is_owner() then
    if (to_jsonb(NEW) - array['subscription_status','billing_due_date','billing_amount','last_payment_date','boat_manifest_enabled','paddle_billing_enabled'])
       is distinct from
       (to_jsonb(OLD) - array['subscription_status','billing_due_date','billing_amount','last_payment_date','boat_manifest_enabled','paddle_billing_enabled'])
    then
      raise exception 'platform admin may only modify subscription/billing fields on dive_centers';
    end if;
  end if;
  return NEW;
end;
$$;

commit;
