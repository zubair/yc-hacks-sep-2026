-- Private photo bucket. Object path: <auth_user_id>/<draft_id>/photo.jpg
-- Size and MIME limits are enforced by the Storage API from these bucket settings.
-- MIME comes from the upload's Content-Type; image bytes are NOT signature-checked yet.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('postcard-photos', 'postcard-photos', false, 10485760, array['image/jpeg'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- True once any postcard references the object. Definer so storage policies need not
-- depend on the caller's postcards visibility; search_path is empty.
create function private.photo_is_sent(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.postcards where photo_path = p_name);
$$;

-- Sender or recipient of a sent postcard that uses this object.
create function private.can_read_sent_photo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.postcards
    where photo_path = p_name and auth.uid() in (sender_id, recipient_id)
  );
$$;

revoke all on function private.photo_is_sent(text), private.can_read_sent_photo(text) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.photo_is_sent(text), private.can_read_sent_photo(text) to authenticated;

-- Upload only into your own folder, only the canonical file name.
create policy postcard_photos_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'postcard-photos'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/photo\.jpg$'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Read your own uploads (unsent drafts included) or a sent postcard you're part of.
create policy postcard_photos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'postcard-photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or private.can_read_sent_photo(name)
    )
  );

-- Delete only your own unsent uploads. A sent photo is never deletable by clients.
create policy postcard_photos_delete_unsent on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'postcard-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and not private.photo_is_sent(name)
  );

-- No UPDATE policy, and 20260926000500_hardening.sql adds triggers: objects are never overwritten
-- or moved (signed upload URLs included), and photos of sent postcards are never deleted.

-- Orphans: uploads older than p_older_than that no postcard references. A server-side job
-- (backend/scripts/cleanup-orphans.mjs) removes them through the Storage API.
create function private.orphan_photos(p_older_than interval default interval '24 hours')
returns table (name text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select o.name, o.created_at
  from storage.objects o
  where o.bucket_id = 'postcard-photos'
    and o.created_at < now() - p_older_than
    and not exists (select 1 from public.postcards p where p.photo_path = o.name)
  order by o.created_at;
$$;

create function public.list_orphan_photos(p_older_than_hours integer default 24)
returns table (name text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select * from private.orphan_photos(make_interval(hours => greatest(coalesce(p_older_than_hours, 24), 1)));
$$;

revoke all on function private.orphan_photos(interval) from public, anon, authenticated;
revoke all on function public.list_orphan_photos(integer) from public, anon, authenticated;
grant execute on function public.list_orphan_photos(integer) to service_role;
