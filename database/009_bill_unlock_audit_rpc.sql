-- AquaDesk Rebuild — RPC for writing bill-unlock audit log entries
--
-- audit_logs deliberately has no client insert policy (see
-- 001_schema_and_rls.sql: "rows are written only by the SECURITY DEFINER
-- log_audit_event() trigger function") — that generic trigger logs raw
-- insert/update/delete on whatever table it's attached to, with the action
-- always being lower(TG_OP) ('insert'/'update'/'delete') and no notes field.
-- It can't produce a custom action = 'bill_unlocked' row with a real
-- explanatory note, which is exactly what Diver Detail's bill-unlock flow
-- needs (and what the already-shipped Billing Audit Reports tab already
-- expects to read, filtering on action = 'bill_unlocked').
--
-- Caught while building Diver Detail's checkout/unlock flow: a direct
-- client insert into audit_logs silently failed (RLS has no insert policy,
-- and the Supabase client doesn't throw on a rejected insert unless the
-- caller checks the returned error — a real bug in the calling code too,
-- fixed alongside this migration).

begin;

create or replace function public.log_bill_unlock(
  p_dive_center_id uuid,
  p_visit_id uuid,
  p_notes text
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.current_dive_center_id() <> p_dive_center_id then
    raise exception 'Cannot log an audit event for another dive center.';
  end if;

  insert into public.audit_logs (dive_center_id, action, target_type, target_id, performed_by, notes)
  values (p_dive_center_id, 'bill_unlocked', 'visits', p_visit_id, auth.uid(), p_notes);
end;
$$;

grant execute on function public.log_bill_unlock(uuid, uuid, text) to authenticated;

commit;
