begin;

-- Paddle billing integration: the new Settings > Subscription tab opens a
-- Paddle checkout carrying dive_center_id/user_id as customData, and a new
-- webhook route (aquadesk-app/src/app/api/webhooks/paddle/route.ts) writes
-- subscription_status back here. paddle_subscription_id is what every event
-- AFTER the initial activation (canceled, past_due, future renewals) gets
-- matched by -- those events never carry the checkout-time customData, only
-- the subscription's own Paddle id.
alter table public.dive_centers
  add column paddle_subscription_id text,
  add column paddle_customer_id text;

-- A given Paddle subscription can only ever belong to one dive center.
-- Partial (not null) so multiple rows with no subscription yet (trial,
-- pre-Paddle dive centers) don't collide against each other.
create unique index dive_centers_paddle_subscription_id_key
  on public.dive_centers (paddle_subscription_id)
  where paddle_subscription_id is not null;

commit;
