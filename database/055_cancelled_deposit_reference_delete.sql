-- AquaDesk Rebuild — let a payment channel or user be deleted when a
-- cancelled deposit references it
--
-- Three deposits columns point at rows that may be deleted, with
-- "on delete set null":
--   custom_channel_id        -> payment_channels (046)
--   refund_custom_channel_id -> payment_channels (047)
--   cancelled_by             -> users            (047)
-- 047's guard trigger treats ANY change to a cancelled deposit as an edit
-- ("A cancelled deposit cannot be edited."), including the automatic
-- set-null, so deleting such a channel or user failed.
--
-- This replaces guard_deposit_cancellation() (047's body, unchanged) with
-- one extra allowance: when the update comes from a foreign-key
-- "set null" action (it runs nested inside the delete, pg_trigger_depth()
-- > 1), and the only change is one or more of those three columns
-- becoming NULL, it is allowed. Every other column — amount, dates,
-- reason, refund/forfeit, status — must stay identical. Any other edit of
-- a cancelled deposit is still refused, as is any direct change to the
-- cancellation fields, and the restrictive RLS policies from 047/049
-- (no client update/delete) are untouched.
--
-- Only the trigger function changes: no table, column, constraint, policy
-- or grant. The currently deployed code keeps working unchanged (it never
-- edits cancelled deposits or deletes channels/users).
--
-- (deposits.recorded_by_user_id references users with no ON DELETE
-- action, so a user who recorded any deposit still can't be deleted —
-- unchanged, not part of this migration.)

begin;

create or replace function public.guard_deposit_cancellation()
returns trigger
language plpgsql as $$
declare
  v_via_rpc boolean := coalesce(current_setting('aquadesk.cancel_deposit', true), '') = 'on';
  v_refs text[] := array['custom_channel_id', 'refund_custom_channel_id', 'cancelled_by'];
begin
  if TG_OP = 'INSERT' then
    if NEW.status <> 'active' and not v_via_rpc then
      raise exception 'A deposit can only be created as active.';
    end if;
    return NEW;
  end if;

  -- A foreign-key "set null" from deleting a payment channel or user:
  -- only the reference columns may change, and only to NULL.
  if OLD.status = 'cancelled' and not v_via_rpc
    and pg_trigger_depth() > 1
    and (to_jsonb(NEW) - v_refs) = (to_jsonb(OLD) - v_refs)
    and (NEW.custom_channel_id is null or NEW.custom_channel_id = OLD.custom_channel_id)
    and (NEW.refund_custom_channel_id is null or NEW.refund_custom_channel_id = OLD.refund_custom_channel_id)
    and (NEW.cancelled_by is null or NEW.cancelled_by = OLD.cancelled_by)
  then
    return NEW;
  end if;

  if OLD.status = 'cancelled' and not v_via_rpc then
    raise exception 'A cancelled deposit cannot be edited.';
  end if;

  if not v_via_rpc and (
    NEW.status, NEW.cancelled_at, NEW.cancelled_date, NEW.cancelled_by, NEW.cancel_reason,
    NEW.refund_amount, NEW.forfeited_amount, NEW.refund_method, NEW.refund_channel,
    NEW.refund_custom_channel_id
  ) is distinct from (
    OLD.status, OLD.cancelled_at, OLD.cancelled_date, OLD.cancelled_by, OLD.cancel_reason,
    OLD.refund_amount, OLD.forfeited_amount, OLD.refund_method, OLD.refund_channel,
    OLD.refund_custom_channel_id
  ) then
    raise exception 'Deposits can only be cancelled through cancel_deposit().';
  end if;

  return NEW;
end;
$$;

commit;

-- ---- Rollback (safe any time): restores 047's function exactly -------------
-- begin;
-- create or replace function public.guard_deposit_cancellation()
-- returns trigger
-- language plpgsql as $$
-- declare
--   v_via_rpc boolean := coalesce(current_setting('aquadesk.cancel_deposit', true), '') = 'on';
-- begin
--   if TG_OP = 'INSERT' then
--     if NEW.status <> 'active' and not v_via_rpc then
--       raise exception 'A deposit can only be created as active.';
--     end if;
--     return NEW;
--   end if;
--
--   if OLD.status = 'cancelled' and not v_via_rpc then
--     raise exception 'A cancelled deposit cannot be edited.';
--   end if;
--
--   if not v_via_rpc and (
--     NEW.status, NEW.cancelled_at, NEW.cancelled_date, NEW.cancelled_by, NEW.cancel_reason,
--     NEW.refund_amount, NEW.forfeited_amount, NEW.refund_method, NEW.refund_channel,
--     NEW.refund_custom_channel_id
--   ) is distinct from (
--     OLD.status, OLD.cancelled_at, OLD.cancelled_date, OLD.cancelled_by, OLD.cancel_reason,
--     OLD.refund_amount, OLD.forfeited_amount, OLD.refund_method, OLD.refund_channel,
--     OLD.refund_custom_channel_id
--   ) then
--     raise exception 'Deposits can only be cancelled through cancel_deposit().';
--   end if;
--
--   return NEW;
-- end;
-- $$;
-- commit;
