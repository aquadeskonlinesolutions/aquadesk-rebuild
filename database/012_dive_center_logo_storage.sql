-- AquaDesk Rebuild — Storage bucket for the Settings > Profile logo upload.
-- Public bucket: logos are meant to display on public-facing pages (e.g.
-- /register), matching the live app's settings.html getPublicUrl usage.
-- Only an authenticated user can write, and only under their own dive
-- center's path — reuses current_dive_center_id(), already defined in
-- 001_schema_and_rls.sql and already used by the cert-cards bucket policies.
--
-- Same two storage gotchas as 003_cert_card_storage.sql apply here:
-- storage.buckets needs its own explicit SELECT policy (silently blocks the
-- bucket for non-service-role callers otherwise), and upsert:true needs all
-- three of INSERT/UPDATE/SELECT on storage.objects, not just INSERT.
--
-- Path convention: logos/{dive_center_id}.{ext}

begin;

insert into storage.buckets (id, name, public)
values ('dive-center-assets', 'dive-center-assets', true)
on conflict (id) do nothing;

-- storage.buckets already has a permissive buckets_select_all policy from
-- 003_cert_card_storage.sql ("using (true)"), which covers every bucket —
-- no new buckets policy needed here.

create policy dive_center_assets_insert on storage.objects for insert
to authenticated
with check (
  bucket_id = 'dive-center-assets'
  and split_part(name, '/', 1) = 'logos'
  and split_part(split_part(name, '/', 2), '.', 1) = public.current_dive_center_id()::text
);

create policy dive_center_assets_update on storage.objects for update
to authenticated
using (
  bucket_id = 'dive-center-assets'
  and split_part(name, '/', 1) = 'logos'
  and split_part(split_part(name, '/', 2), '.', 1) = public.current_dive_center_id()::text
)
with check (
  bucket_id = 'dive-center-assets'
  and split_part(name, '/', 1) = 'logos'
  and split_part(split_part(name, '/', 2), '.', 1) = public.current_dive_center_id()::text
);

create policy dive_center_assets_select on storage.objects for select
to authenticated
using (bucket_id = 'dive-center-assets');

-- Bucket is public, so anon read access goes through Storage's public-bucket
-- serving path automatically — no anon SELECT policy on storage.objects
-- needed for /register (or any other public page) to display a logo.

commit;
