-- Hardening from the adversarial review. A separate migration, so projects that already ran
-- `supabase db push` pick it up. Every guard lives in the database, below the Storage API,
-- because signed-upload PUTs and service-role calls do not go through RLS.

-- 1. Photos are written once. Signed upload URLs are checked against RLS only when minted; the
--    later PUT runs with elevated rights and honours the token's upsert flag. So "no overwrite"
--    must be a trigger, not merely the absence of an UPDATE policy. Content (version) and
--    identity (bucket/name, i.e. move) are frozen; bookkeeping columns may still change.
create function private.reject_photo_overwrite()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.bucket_id = 'postcard-photos'
     and (new.version is distinct from old.version
          or new.name is distinct from old.name
          or new.bucket_id is distinct from old.bucket_id) then
    raise exception 'postcard photos cannot be overwritten or moved' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger postcard_photos_no_overwrite
before update on storage.objects
for each row execute function private.reject_photo_overwrite();

-- 2. A photo referenced by a postcard is never deleted, by anyone (the service role and the
--    orphan cleanup included). BEFORE ROW DELETE triggers fire after the row lock is taken, and
--    this VOLATILE function reads with a fresh snapshot, so it sees a send that committed while
--    the delete waited. Returning NULL skips the row; Storage only removes blobs for rows the
--    DELETE actually returned, so a batch cleanup quietly keeps sent photos.
create function private.keep_sent_photos()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if old.bucket_id = 'postcard-photos'
     and exists (select 1 from public.postcards where photo_path = old.name) then
    return null;
  end if;
  return old;
end;
$$;

create trigger postcard_photos_keep_sent
before delete on storage.objects
for each row execute function private.keep_sent_photos();

revoke all on function private.reject_photo_overwrite(), private.keep_sent_photos() from public, anon, authenticated;

-- 3. send_postcard locks the photo row (FOR KEY SHARE) instead of just checking it exists.
--    A concurrent delete waits for the send and then skips the row (trigger above); a delete
--    that wins first makes the send fail with photo_missing. Also:
--      - whitespace-only messages are rejected (any Unicode space, not only ' ');
--      - every parameter defaults to NULL, so an omitted key (e.g. a nil recipientId that a
--        Swift encoder drops) returns the intended PT422 instead of PostgREST's PGRST202.
create or replace function public.send_postcard(
  p_recipient_id uuid default null,
  p_sender_name text default null,
  p_recipient_name text default null,
  p_destination text default null,
  p_message text default null,
  p_photo_path text default null,
  p_client_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_sender_name text := btrim(coalesce(p_sender_name, ''));
  v_recipient_name text := btrim(coalesce(p_recipient_name, ''));
  v_destination text := btrim(coalesce(p_destination, ''));
  v_message text := coalesce(p_message, '');
  v_low uuid;
  v_high uuid;
  v_conversation_id uuid;
  v_row public.postcards;
begin
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'finish creating your profile first' using errcode = 'PT403', hint = 'forbidden';
  end if;
  if p_client_request_id is null then
    raise exception 'client_request_id is required' using errcode = 'PT422', hint = 'validation';
  end if;

  -- Fast path for retries: no conversation writes, same response.
  select * into v_row from public.postcards
  where sender_id = v_uid and client_request_id = p_client_request_id;
  if found then
    return private.check_retry(v_row, p_recipient_id, v_sender_name, v_recipient_name, v_destination, v_message, p_photo_path);
  end if;

  if p_recipient_id is null then
    raise exception 'choose a recipient' using errcode = 'PT422', hint = 'validation';
  end if;
  if p_recipient_id = v_uid then
    raise exception 'you can''t send a postcard to yourself' using errcode = 'PT422', hint = 'validation';
  end if;
  if not exists (select 1 from public.profiles where id = p_recipient_id) then
    raise exception 'recipient not found' using errcode = 'PT404', hint = 'not_found';
  end if;
  if v_message !~ '[^[:space:]]' or char_length(v_message) > 5000 then
    raise exception 'message must be 1-5000 characters' using errcode = 'PT422', hint = 'validation';
  end if;
  if char_length(v_sender_name) > 100 or char_length(v_recipient_name) > 100 then
    raise exception 'names must be at most 100 characters' using errcode = 'PT422', hint = 'validation';
  end if;
  if char_length(v_destination) > 200 then
    raise exception 'destination must be at most 200 characters' using errcode = 'PT422', hint = 'validation';
  end if;
  -- The photo must be the caller's own upload for this draft: <uid>/<draft id>/photo.jpg,
  -- with lowercase UUIDs (Swift: uuidString.lowercased()).
  if p_photo_path is distinct from (v_uid::text || '/' || p_client_request_id::text || '/photo.jpg') then
    raise exception 'photo_path must be <your user id>/<draft id>/photo.jpg (lowercase UUIDs)'
      using errcode = 'PT403', hint = 'forbidden';
  end if;
  perform 1 from storage.objects o
  where o.bucket_id = 'postcard-photos' and o.name = p_photo_path
  for key share;
  if not found then
    raise exception 'upload the photo before sending' using errcode = 'PT422', hint = 'photo_missing';
  end if;

  v_low := least(v_uid, p_recipient_id);
  v_high := greatest(v_uid, p_recipient_id);

  -- Concurrent first messages between the same pair converge on one row.
  insert into public.conversations (user_low, user_high)
  values (v_low, v_high)
  on conflict (user_low, user_high) do nothing
  returning id into v_conversation_id;
  if v_conversation_id is null then
    select id into v_conversation_id from public.conversations
    where user_low = v_low and user_high = v_high;
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  values (v_conversation_id, v_low), (v_conversation_id, v_high)
  on conflict do nothing;

  insert into public.postcards (
    conversation_id, sender_id, recipient_id, sender_name, recipient_name,
    destination, message, photo_path, client_request_id
  ) values (
    v_conversation_id, v_uid, p_recipient_id, v_sender_name, v_recipient_name,
    v_destination, v_message, p_photo_path, p_client_request_id
  )
  on conflict (sender_id, client_request_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    -- A concurrent retry with the same key committed first; return its message.
    select * into v_row from public.postcards
    where sender_id = v_uid and client_request_id = p_client_request_id;
    return private.check_retry(v_row, p_recipient_id, v_sender_name, v_recipient_name, v_destination, v_message, p_photo_path);
  end if;

  update public.conversations
  set updated_at = greatest(updated_at, v_row.created_at)
  where id = v_conversation_id;

  return private.message_json(v_row);
end;
$$;

-- CREATE OR REPLACE keeps existing grants; restate them so this file is self-describing.
revoke all on function public.send_postcard(uuid, text, text, text, text, text, uuid) from public, anon;
grant execute on function public.send_postcard(uuid, text, text, text, text, text, uuid) to authenticated;

-- 4. Realtime. Postcards are immutable and clients only need INSERT hints, and Realtime cannot
--    RLS-filter DELETE events (it would broadcast cascaded-delete ids to every subscriber), so
--    publish inserts only. This covers the whole publication; revisit if another table needs
--    UPDATE/DELETE events.
alter publication supabase_realtime set (publish = 'insert');
-- Without SELECT on the key, Realtime sends anon a payload-less 401 frame per insert, which
-- leaks activity timing. Granting only the id column routes anon through RLS, and there is no
-- anon policy, so anon receives nothing and can still read no rows.
grant select (id) on public.postcards to anon;

-- 5. RLS and list_conversations filter on (user_low OR user_high); index the non-leading column.
create index conversations_user_high_idx on public.conversations (user_high);
