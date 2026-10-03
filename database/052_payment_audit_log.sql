-- AquaDesk Rebuild — audit log entries for payment saves
--
-- savePaymentOnly / checkoutVisit now validate everything the browser
-- sends (grand total, discount, amounts, exchange rate) on the server.
-- audit_logs has no client insert policy (rows are written only by
-- SECURITY DEFINER functions — same reason log_bill_unlock exists, 009),
-- so this adds one narrow function the server actions call to record:
--   'payment_rejected'      — a save/checkout refused because a value was
--                             invalid or the page's totals were stale
--   'payment_rate_override' — a foreign-cash exchange rate that differs
--                             from the dive center's stored rate (MK,
--                             2026-10-03: any typed rate is accepted, but
--                             a different one is recorded)
--
-- The caller must be an active dive-center user and the visit must belong
-- to their own dive center. Purely additive: nothing existing changes and
-- the currently deployed code (which never calls it) keeps working.

begin;

create or replace function public.log_payment_event(p_visit_id uuid, p_action text, p_notes text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_dc uuid;
begin
  if p_action not in ('payment_rejected', 'payment_rate_override') then
    raise exception 'Unknown payment audit action.';
  end if;

  select u.dive_center_id into v_dc
  from public.users u
  join public.visits v on v.dive_center_id = u.dive_center_id
  where u.id = auth.uid() and u.is_active and v.id = p_visit_id;

  if v_dc is null then
    raise exception 'Visit not found.';
  end if;

  insert into public.audit_logs (dive_center_id, action, target_type, target_id, performed_by, notes)
  values (v_dc, p_action, 'visits', p_visit_id, auth.uid(), left(coalesce(p_notes, ''), 2000));
end;
$$;

revoke all on function public.log_payment_event(uuid, text, text) from public, anon;
grant execute on function public.log_payment_event(uuid, text, text) to authenticated;

commit;

-- ---- Rollback (safe any time; roll back the code first if it calls this) ----
-- Existing audit_logs rows are kept.
-- begin;
-- drop function if exists public.log_payment_event(uuid, text, text);
-- commit;
