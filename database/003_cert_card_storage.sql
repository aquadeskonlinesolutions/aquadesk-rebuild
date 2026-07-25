-- AquaDesk Rebuild — Cert card photo upload during registration
-- Storage bucket for diver certification card photos, uploaded during the
-- public registration flow. Private bucket: only dive-center staff of the
-- owning dive center can view the full bucket; anon can only touch the
-- single path that matches a diver record that already exists (proven
-- server-side moments earlier by submit_diver_registration), matching the
-- live app's original design intent.
--
-- Note: storage.buckets has RLS enabled by default with zero policies out
-- of the box, which silently blocks the Storage API from even resolving
-- the bucket for anon/authenticated callers (manifests as a generic "row-
-- level security" error with no obvious connection to buckets). A SELECT
-- policy on storage.buckets is required for any bucket to be usable by
-- non-service-role callers.

insert into storage.buckets (id, name, public)
values ('cert-cards', 'cert-cards', false)
on conflict (id) do nothing;

create policy buckets_select_all on storage.buckets for select
using (true);

-- Path convention: {dive_center_id}/{diver_id}.{ext}
create or replace function public.diver_exists_for_path(p_dive_center_id uuid, p_diver_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.divers d
    where d.dive_center_id = p_dive_center_id and d.id = p_diver_id
  );
$$;

create policy cert_cards_insert on storage.objects for insert
to anon, authenticated
with check (
  bucket_id = 'cert-cards'
  and public.diver_exists_for_path(
    split_part(name, '/', 1)::uuid,
    split_part(split_part(name, '/', 2), '.', 1)::uuid
  )
);

-- Needed because the client uploads with upsert:true (a returning diver may
-- re-upload their cert card) — Postgres/Storage requires an UPDATE policy
-- for the ON CONFLICT DO UPDATE path even when no conflict actually occurs.
create policy cert_cards_update on storage.objects for update
to anon, authenticated
using (
  bucket_id = 'cert-cards'
  and public.diver_exists_for_path(
    split_part(name, '/', 1)::uuid,
    split_part(split_part(name, '/', 2), '.', 1)::uuid
  )
)
with check (
  bucket_id = 'cert-cards'
  and public.diver_exists_for_path(
    split_part(name, '/', 1)::uuid,
    split_part(split_part(name, '/', 2), '.', 1)::uuid
  )
);

-- Also needed for upsert:true — Storage checks/returns the row under SELECT
-- visibility as part of the upsert path, even on a first-time insert. Scoped
-- to the same "this diver exists" predicate, so anon can only ever resolve
-- a specific diver's own cert card path, never browse the bucket.
create policy cert_cards_owner_select on storage.objects for select
to anon, authenticated
using (
  bucket_id = 'cert-cards'
  and public.diver_exists_for_path(
    split_part(name, '/', 1)::uuid,
    split_part(split_part(name, '/', 2), '.', 1)::uuid
  )
);

-- Dive-center staff can browse/view every cert card for their own dive
-- center (not just a specific diver's path) — this is the actual "staff
-- looks up a diver's uploaded cert card" access path.
create policy cert_cards_staff_select on storage.objects for select
to authenticated
using (
  bucket_id = 'cert-cards'
  and split_part(name, '/', 1) = public.current_dive_center_id()::text
);

-- Only linked to the diver's record after a confirmed successful upload —
-- anon has no direct UPDATE grant on divers, so a failed upload never
-- leaves the diver row pointing at a file that doesn't exist.
create or replace function public.set_diver_cert_card_url(
  p_diver_id uuid,
  p_dive_center_id uuid,
  p_path text
)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.divers where id = p_diver_id and dive_center_id = p_dive_center_id
  ) then
    raise exception 'Diver not found for this dive center.';
  end if;

  update public.divers set cert_card_url = p_path where id = p_diver_id;
end;
$$;

grant execute on function public.set_diver_cert_card_url(uuid, uuid, text) to anon, authenticated;
