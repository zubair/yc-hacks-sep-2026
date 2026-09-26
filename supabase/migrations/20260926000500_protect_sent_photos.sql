-- Sent photos are immutable in Storage, like the postcards that reference them.
--
-- RLS alone cannot guarantee this. createSignedUploadUrl(path, {upsert: true}) is authorized once,
-- against the INSERT policy, while the object does not exist yet. The token stays valid for its
-- whole lifetime (2 h), and every upload through it runs on Storage's privileged connection,
-- which bypasses RLS. Without this trigger a sender could upload, send, then upload again with the
-- same token and change the bytes the recipient downloads.

-- Refuses any change to a sent photo's row except timestamps, and refuses deleting it, for every
-- role. Unsent drafts are untouched: owners may still replace or delete them, and the orphan
-- cleanup job may still remove them. To remove a sent photo, delete its postcard first.
create function private.protect_sent_photo()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  -- Columns allowed to change. path_tokens is generated from name (which is compared), and a
  -- BEFORE trigger sees generated columns as null in NEW, so it is left out of the comparison.
  v_free constant text[] := array['created_at', 'updated_at', 'last_accessed_at', 'path_tokens'];
begin
  -- This function is volatile, so the check runs on a fresh snapshot: a postcard committed while
  -- the statement waited for send_postcard's row lock is visible here.
  if private.photo_is_sent(old.name) then
    if tg_op = 'DELETE' then
      raise exception 'a sent photo cannot be deleted' using errcode = 'PT403', hint = 'forbidden';
    end if;
    if (to_jsonb(new) - v_free) is distinct from (to_jsonb(old) - v_free) then
      raise exception 'a sent photo cannot be replaced, moved or edited'
        using errcode = 'PT403', hint = 'forbidden';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.protect_sent_photo() from public, anon, authenticated;

-- Fires for upserts too (INSERT ... ON CONFLICT DO UPDATE runs BEFORE UPDATE row triggers).
create trigger protect_sent_postcard_photos
before update or delete on storage.objects
for each row
when (old.bucket_id = 'postcard-photos')
execute function private.protect_sent_photo();

-- send_postcard, unchanged except that it now locks the photo's object row (FOR SHARE) instead of
-- only checking that it exists. Same signature, so owner and execute grants are kept.
create or replace function public.send_postcard(
  p_recipient_id uuid,
  p_sender_name text,
  p_recipient_name text,
  p_destination text,
  p_message text,
  p_photo_path text,
  p_client_request_id uuid
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
  if char_length(btrim(v_message)) = 0 or char_length(v_message) > 5000 then
    raise exception 'message must be 1-5000 characters' using errcode = 'PT422', hint = 'validation';
  end if;
  if char_length(v_sender_name) > 100 or char_length(v_recipient_name) > 100 then
    raise exception 'names must be at most 100 characters' using errcode = 'PT422', hint = 'validation';
  end if;
  if char_length(v_destination) > 200 then
    raise exception 'destination must be at most 200 characters' using errcode = 'PT422', hint = 'validation';
  end if;
  -- The photo must be the caller's own upload for this draft: <uid>/<draft id>/photo.jpg.
  if p_photo_path is distinct from (v_uid::text || '/' || p_client_request_id::text || '/photo.jpg') then
    raise exception 'photo_path must be <your user id>/<draft id>/photo.jpg'
      using errcode = 'PT403', hint = 'forbidden';
  end if;
  -- FOR SHARE holds the object row until this transaction ends. A concurrent overwrite or delete
  -- either commits first (and this send carries what it left) or waits, then sees the postcard
  -- and is refused by protect_sent_postcard_photos. The bytes never change after a send.
  perform 1 from storage.objects o
  where o.bucket_id = 'postcard-photos' and o.name = p_photo_path
  for share;
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


revoke all on function public.send_postcard(uuid, text, text, text, text, text, uuid) from public, anon;
grant execute on function public.send_postcard(uuid, text, text, text, text, text, uuid) to authenticated;
