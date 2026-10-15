-- AquaDesk Rebuild — Add-ons in the Bill Summary (visit-level add-ons)
--
-- ADDITIVE ONLY. No existing row is read, changed or deleted by this file.
-- The old per-activity activities.addons column and addon_breakdown are NOT
-- touched: they keep their values and keep counting exactly as before.
--
--   1. addon_categories — per dive center, reusable, case-insensitive duplicate
--      prevention (unique on dive_center_id + normalized_label), same shape as
--      payment_channels (046) / expense_categories (045). Starts empty.
--   2. visit_addons — one row per add-on on a visit: description (required),
--      category (link + the category NAME copied onto the add-on, so renaming a
--      category later never rewrites a past bill), amount > 0 with 2 decimals.
--      Starts empty. Tenant-scoped RLS.
--   3. Bill lock (the database refuses, not just the screen): same rule as 057 —
--      no insert/update/delete of an add-on unless the bill is open. Unlock Bill
--      reopens it. It has its own small function (057's reads activities-only
--      columns); service_role/postgres and nested deletes are let through, as
--      in 057.
--   4. Audit after an unlock: 057's log_bill_change_after_unlock() is
--      re-created with exactly its 057 body plus a visit_addons branch, and
--      attached to visit_addons. Every add-on added/edited/deleted on an
--      unlocked bill writes audit_logs 'bill_changed_after_unlock' with who,
--      what and before -> after (Billing Audit already lists that action).
--   5. visit_addons_totals(uuid[]) — the ONE shared function every screen and
--      server action uses to get "add-ons per visit". Runs as the caller (RLS).
--
-- Deploy order: this migration first, then the app code.

begin;

-- ---- 1. categories -----------------------------------------------------------
create table public.addon_categories (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  label text not null,
  normalized_label text not null,
  created_at timestamptz not null default now(),
  unique (dive_center_id, normalized_label)
);

alter table public.addon_categories enable row level security;
create policy addon_categories_select on public.addon_categories
  for select using (dive_center_id = public.current_dive_center_id());
create policy addon_categories_write on public.addon_categories
  for all using (dive_center_id = public.current_dive_center_id())
  with check (dive_center_id = public.current_dive_center_id());

-- ---- 2. add-ons --------------------------------------------------------------
create table public.visit_addons (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  visit_id uuid not null references public.visits(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  description text not null check (btrim(description) <> ''),
  category_id uuid references public.addon_categories(id) on delete set null,
  category_name text not null,
  amount numeric(12,2) not null check (amount > 0),
  created_by uuid,
  created_at timestamptz not null default now()
);

create index visit_addons_visit_idx on public.visit_addons (visit_id);
create index visit_addons_dc_idx on public.visit_addons (dive_center_id);

alter table public.visit_addons enable row level security;
create policy visit_addons_select on public.visit_addons
  for select using (dive_center_id = public.current_dive_center_id());
create policy visit_addons_write on public.visit_addons
  for all using (dive_center_id = public.current_dive_center_id())
  with check (dive_center_id = public.current_dive_center_id());

-- ---- 3. bill lock ------------------------------------------------------------
create or replace function public.guard_closed_visit_addons()
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
    -- a deleted category only sets category_id to NULL
    if TG_OP = 'UPDATE'
       and NEW.category_id is null
       and (to_jsonb(NEW) - 'category_id') = (to_jsonb(OLD) - 'category_id') then
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

revoke all on function public.guard_closed_visit_addons() from public, anon, authenticated;

create trigger visit_addons_closed_bill_lock
  before insert or update or delete on public.visit_addons
  for each row execute function public.guard_closed_visit_addons();

-- ---- 4. audit after an unlock (057 body + a visit_addons branch) --------------
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
  elsif TG_TABLE_NAME = 'visit_addons' then
    v_fields := array['description','category_name','amount'];
    v_labels := array['Description','Category','Amount'];
    v_money  := array[false,false,true];
    v_what := format('Add-on "%s"', v_row->>'description');
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
    elsif TG_TABLE_NAME = 'visit_addons' then
      v_changes := array[format('Category %s; Amount %s', coalesce(nullif(v_old->>'category_name', ''), '—'),
                                public.bill_audit_money((v_old->>'amount')::numeric))];
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

create trigger visit_addons_log_change_after_unlock
  after insert or update or delete on public.visit_addons
  for each row execute function public.log_bill_change_after_unlock();

-- ---- 5. the one shared totals function --------------------------------------
create or replace function public.visit_addons_totals(p_visit_ids uuid[])
returns table (visit_id uuid, total numeric)
language sql stable security invoker set search_path = public as $$
  select a.visit_id, sum(a.amount)::numeric
    from public.visit_addons a
   where a.visit_id = any(p_visit_ids)
   group by a.visit_id;
$$;

revoke all on function public.visit_addons_totals(uuid[]) from public, anon;
grant execute on function public.visit_addons_totals(uuid[]) to authenticated;

commit;

-- ---- Rollback ----------------------------------------------------------------
-- Safe only while no add-on exists (select count(*) from visit_addons) —
-- otherwise those amounts would silently drop off bills.
-- begin;
-- drop function if exists public.visit_addons_totals(uuid[]);
-- drop trigger if exists visit_addons_log_change_after_unlock on public.visit_addons;
-- drop trigger if exists visit_addons_closed_bill_lock on public.visit_addons;
-- drop function if exists public.guard_closed_visit_addons();
-- drop table if exists public.visit_addons;
-- drop table if exists public.addon_categories;
-- -- then re-run 057's log_bill_change_after_unlock() body (without the visit_addons branch)
-- commit;
