-- AquaDesk Rebuild — database-level bill lock + audit of changes after an unlock
--
-- Until now a closed bill was only locked on screen: the server actions and
-- the direct API would still add, edit or delete a closed visit's
-- activities. This adds:
--
--   guard_closed_visit_activities(): BEFORE trigger on activities. Any
--     insert/update/delete of an activity whose visit is not 'open'
--     (closed or voided) is refused with a plain message. Runs as the
--     caller (SECURITY INVOKER), so a visit the caller can't see counts as
--     not open. Not blocked:
--       * database maintenance — the SQL Editor (postgres) and server
--         scripts using the secret key (service_role);
--       * nested foreign-key actions (pg_trigger_depth() > 1) that only
--         delete rows (deleting a visit/diver/dive center cascades) or only
--         set schedule_id to NULL (deleting a trip). Same idea as 055.
--     Unlock Bill (migration 048) sets the visit back to 'open', so edits
--     work again after an unlock; Checkout closes it and the lock returns.
--
--   log_bill_change_after_unlock(): AFTER trigger on activities, payments
--     and deposits. When the visit is open AND has been unlocked at least
--     once (an audit_logs 'bill_unlocked' row exists for it), every real
--     change writes one audit_logs row: action 'bill_changed_after_unlock',
--     target = the visit, performed_by = the signed-in user, notes =
--     "<diver> — <what>: <field> <before> → <after>; ...". Saves that
--     change nothing are not logged. Billing Audit shows these rows.
--
-- Additive only: no data is changed. One index is added for the
-- "has this visit been unlocked" lookup.

begin;

-- ---- 1. Lock -----------------------------------------------------------------

create or replace function public.guard_closed_visit_activities()
returns trigger
language plpgsql security invoker set search_path = public as $$
declare
  v_status public.visit_status;
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return coalesce(NEW, OLD);
  end if;

  if pg_trigger_depth() > 1 then
    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    if TG_OP = 'UPDATE'
       and NEW.schedule_id is null
       and (to_jsonb(NEW) - 'schedule_id') = (to_jsonb(OLD) - 'schedule_id') then
      return NEW;
    end if;
  end if;

  if TG_OP in ('UPDATE', 'DELETE') then
    select visit_status into v_status from public.visits where id = OLD.visit_id;
    if v_status is distinct from 'open' then
      raise exception 'This bill is closed. Unlock it with the billing password before changing it.'
        using errcode = 'P0001';
    end if;
  end if;
  if TG_OP in ('INSERT', 'UPDATE') then
    select visit_status into v_status from public.visits where id = NEW.visit_id;
    if v_status is distinct from 'open' then
      raise exception 'This bill is closed. Unlock it with the billing password before changing it.'
        using errcode = 'P0001';
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$$;

revoke all on function public.guard_closed_visit_activities() from public, anon, authenticated;

create trigger activities_closed_bill_lock
  before insert or update or delete on public.activities
  for each row execute function public.guard_closed_visit_activities();

-- ---- 2. Audit of changes made after an unlock --------------------------------

create index if not exists audit_logs_bill_unlocked_target_idx
  on public.audit_logs (target_id) where action = 'bill_unlocked';

create or replace function public.bill_audit_money(v numeric)
returns text
language sql immutable set search_path = public as $$
  select case when v is null then '—' else '₱' || to_char(v, 'FM999,999,999,990.00') end;
$$;

revoke all on function public.bill_audit_money(numeric) from public, anon, authenticated;

create or replace function public.log_bill_change_after_unlock()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_row jsonb := to_jsonb(coalesce(NEW, OLD));
  v_old jsonb := case when TG_OP = 'INSERT' then null else to_jsonb(OLD) end;
  v_new jsonb := case when TG_OP = 'DELETE' then null else to_jsonb(NEW) end;
  v_visit_id uuid := (v_row->>'visit_id')::uuid;
  v_dc uuid := (v_row->>'dive_center_id')::uuid;
  v_diver text;
  v_what text;
  v_changes text[] := '{}';
  v_fields text[];
  v_labels text[];
  v_money boolean[];
  i int;
  v_before text;
  v_after text;
begin
  if not exists (select 1 from public.visits where id = v_visit_id and visit_status = 'open') then
    return null;
  end if;
  if not exists (
    select 1 from public.audit_logs where action = 'bill_unlocked' and target_id = v_visit_id
  ) then
    return null;
  end if;

  if TG_TABLE_NAME = 'activities' then
    v_fields := array['date','dive_site','staff_name','dive_rate','fuel_surcharge','marine_tax','shark_fee',
                      'nitrox_fee','fifteen_l_fee','equipment_rental','addons','discount','status','total'];
    v_labels := array['Date','Activity','Staff','Dive rate','Fuel','Marine','Shark',
                      'Nitrox','15L','Equipment','Add-ons','Discount','Status','Total'];
    v_money  := array[false,false,false,true,true,true,true,true,true,true,true,true,false,true];
    v_what := format('Activity %s (%s)', v_row->>'date', coalesce(nullif(v_row->>'dive_site', ''), 'no site'));
  elsif TG_TABLE_NAME = 'payments' then
    v_fields := array['discount','cash_amount','cash_amount_foreign','cash_currency_code','cash_exchange_rate',
                      'card_amount','online_amount','online_channel','notes'];
    v_labels := array['Discount','Cash','Foreign cash','Foreign currency','Exchange rate',
                      'Card','Online','Online channel','Notes'];
    v_money  := array[true,true,false,false,false,true,true,false,false];
    v_what := 'Payment';
  else -- deposits
    v_fields := array['amount','method','channel','received_by','status'];
    v_labels := array['Amount','Method','Channel','Received by','Status'];
    v_money  := array[true,false,false,false,false];
    v_what := format('Deposit %s', v_row->>'deposit_date');
  end if;

  if TG_OP = 'INSERT' then
    for i in 1 .. array_length(v_fields, 1) loop
      if v_new->>v_fields[i] is not null and v_new->>v_fields[i] <> ''
         and not (v_money[i] and (v_new->>v_fields[i])::numeric = 0) then
        v_changes := v_changes || format('%s %s', v_labels[i],
          case when v_money[i] then public.bill_audit_money((v_new->>v_fields[i])::numeric) else v_new->>v_fields[i] end);
      end if;
    end loop;
    v_what := 'Added ' || lower(left(v_what, 1)) || substr(v_what, 2);
  elsif TG_OP = 'DELETE' then
    if TG_TABLE_NAME = 'activities' then
      v_changes := array[format('Total %s', public.bill_audit_money((v_old->>'total')::numeric))];
    elsif TG_TABLE_NAME = 'deposits' then
      v_changes := array[format('Amount %s', public.bill_audit_money((v_old->>'amount')::numeric))];
    end if;
    v_what := 'Deleted ' || lower(left(v_what, 1)) || substr(v_what, 2);
  else
    for i in 1 .. array_length(v_fields, 1) loop
      if (v_old->v_fields[i]) is distinct from (v_new->v_fields[i]) then
        if v_money[i] and coalesce((v_old->>v_fields[i])::numeric, 0) = coalesce((v_new->>v_fields[i])::numeric, 0) then
          continue;
        end if;
        v_before := case when v_money[i] then public.bill_audit_money((v_old->>v_fields[i])::numeric)
                         else coalesce(nullif(v_old->>v_fields[i], ''), '—') end;
        v_after  := case when v_money[i] then public.bill_audit_money((v_new->>v_fields[i])::numeric)
                         else coalesce(nullif(v_new->>v_fields[i], ''), '—') end;
        v_changes := v_changes || format('%s %s → %s', v_labels[i], v_before, v_after);
      end if;
    end loop;
    if coalesce(array_length(v_changes, 1), 0) = 0 then
      return null; -- a save that changed nothing the bill shows
    end if;
  end if;

  select trim(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))
    into v_diver from public.divers where id = (v_row->>'diver_id')::uuid;

  insert into public.audit_logs (dive_center_id, action, target_type, target_id, performed_by, notes)
  values (
    v_dc, 'bill_changed_after_unlock', 'visits', v_visit_id, auth.uid(),
    format('%s — %s%s', coalesce(nullif(v_diver, ''), 'Diver'), v_what,
      case when coalesce(array_length(v_changes, 1), 0) > 0 then ': ' || array_to_string(v_changes, '; ') else '' end)
  );
  return null;
end;
$$;

revoke all on function public.log_bill_change_after_unlock() from public, anon, authenticated;

create trigger activities_log_change_after_unlock
  after insert or update or delete on public.activities
  for each row execute function public.log_bill_change_after_unlock();
create trigger payments_log_change_after_unlock
  after insert or update or delete on public.payments
  for each row execute function public.log_bill_change_after_unlock();
create trigger deposits_log_change_after_unlock
  after insert or update or delete on public.deposits
  for each row execute function public.log_bill_change_after_unlock();

commit;

-- ---- Rollback (safe at any time; audit rows already written are kept) -------
-- begin;
-- drop trigger if exists deposits_log_change_after_unlock on public.deposits;
-- drop trigger if exists payments_log_change_after_unlock on public.payments;
-- drop trigger if exists activities_log_change_after_unlock on public.activities;
-- drop function if exists public.log_bill_change_after_unlock();
-- drop function if exists public.bill_audit_money(numeric);
-- drop index if exists public.audit_logs_bill_unlocked_target_idx;
-- drop trigger if exists activities_closed_bill_lock on public.activities;
-- drop function if exists public.guard_closed_visit_activities();
-- commit;
