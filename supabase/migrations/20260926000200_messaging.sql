-- Direct messaging: canonical two-person conversations and immutable postcards.
-- Clients never write these tables directly; send_postcard is the only write path.

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_low uuid not null references public.profiles (id) on delete cascade,
  user_high uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversations_canonical_pair check (user_low < user_high),
  constraint conversations_pair_unique unique (user_low, user_high)
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index conversation_members_user_idx on public.conversation_members (user_id);

create table public.postcards (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  sender_name text not null default '' check (char_length(sender_name) <= 100),
  recipient_name text not null default '' check (char_length(recipient_name) <= 100),
  destination text not null default '' check (char_length(destination) <= 200),
  message text not null check (char_length(message) between 1 and 5000),
  photo_path text not null,
  client_request_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint postcards_distinct_people check (sender_id <> recipient_id),
  -- The only unique key besides id, so ON CONFLICT (sender_id, client_request_id) is the sole
  -- arbiter for concurrent retries. photo_path is unique by construction (<uid>/<draft id>/photo.jpg).
  constraint postcards_sender_request_unique unique (sender_id, client_request_id)
);
create index postcards_photo_path_idx on public.postcards (photo_path);
create index postcards_conversation_page_idx on public.postcards (conversation_id, created_at desc, id desc);
create index postcards_recipient_idx on public.postcards (recipient_id);

-- v1 messages are immutable, even for privileged roles.
create function private.reject_postcard_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'postcards are immutable' using errcode = 'PT403', hint = 'forbidden';
end;
$$;

create trigger postcards_immutable
before update on public.postcards
for each row execute function private.reject_postcard_change();

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.postcards enable row level security;

-- Policies only compare columns with auth.uid(); none query another RLS table, so nothing recurses.
create policy conversations_select_member on public.conversations
  for select to authenticated
  using ((select auth.uid()) in (user_low, user_high));

create policy conversation_members_select_own on public.conversation_members
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Also the filter Realtime applies to postgres_changes for each subscriber.
create policy postcards_select_participant on public.postcards
  for select to authenticated
  using ((select auth.uid()) in (sender_id, recipient_id));

revoke all on public.conversations, public.conversation_members, public.postcards from anon, authenticated;
grant select on public.conversations, public.conversation_members, public.postcards to authenticated;

-- JSON shapes shared by the RPCs (snake_case wire format from CONTRACTS.md).
create function private.message_json(p public.postcards)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'conversation_id', p.conversation_id,
    'sender_id', p.sender_id,
    'recipient_id', p.recipient_id,
    'sender_name', p.sender_name,
    'recipient_name', p.recipient_name,
    'destination', p.destination,
    'message', p.message,
    'photo_path', p.photo_path,
    'created_at', to_char(p.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
$$;

create function private.profile_json(p public.profiles)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'display_name', p.display_name);
$$;

create function private.require_uid()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = 'PT401', hint = 'unauthenticated';
  end if;
  return v_uid;
end;
$$;

-- lookup_recipient: exact, case-insensitive username match. Returns id/username/display_name or null.
create function public.lookup_recipient(p_username text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  perform private.require_uid();
  select * into v_profile from public.profiles where username = lower(btrim(coalesce(p_username, '')));
  if not found then
    return null;
  end if;
  return private.profile_json(v_profile);
end;
$$;

-- list_conversations: the caller's conversations with peer and latest message, newest first.
create function public.list_conversations()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  return coalesce((
    select jsonb_agg(item order by sort_at desc, conv_id desc)
    from (
      select
        c.id as conv_id,
        c.updated_at as sort_at,
        jsonb_build_object(
          'id', c.id,
          'peer', private.profile_json(peer),
          'latest_message', (
            select private.message_json(p)
            from public.postcards p
            where p.conversation_id = c.id
            order by p.created_at desc, p.id desc
            limit 1
          ),
          'updated_at', to_char(c.updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
        ) as item
      from public.conversations c
      join public.profiles peer
        on peer.id = case when c.user_low = v_uid then c.user_high else c.user_low end
      where v_uid in (c.user_low, c.user_high)
    ) rows
  ), '[]'::jsonb);
end;
$$;

-- list_messages: newest first. Page with p_before = created_at of the oldest message you hold.
-- Ties are ordered by id; messages sharing the exact boundary microsecond can be skipped by
-- p_before, so clients merge by id and refetch the first page on reconnect.
create function public.list_messages(p_conversation_id uuid, p_before timestamptz default null, p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  if not exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = v_uid
  ) then
    -- Same answer for "doesn't exist" and "not yours", so ids can't be probed.
    raise exception 'conversation not found' using errcode = 'PT404', hint = 'not_found';
  end if;
  return coalesce((
    select jsonb_agg(private.message_json(p) order by p.created_at desc, p.id desc)
    from (
      select * from public.postcards
      where conversation_id = p_conversation_id
        and (p_before is null or created_at < p_before)
      order by created_at desc, id desc
      limit v_limit
    ) p
  ), '[]'::jsonb);
end;
$$;

-- send_postcard: the only write path. Validates, finds or creates the pair, inserts atomically.
-- Retrying with the same p_client_request_id returns the original message.
create function public.send_postcard(
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
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'postcard-photos' and o.name = p_photo_path
  ) then
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

-- A retry must carry the same payload; reusing a key for different content is rejected.
create function private.check_retry(
  v_row public.postcards,
  p_recipient_id uuid,
  p_sender_name text,
  p_recipient_name text,
  p_destination text,
  p_message text,
  p_photo_path text
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  if v_row.recipient_id is distinct from p_recipient_id
     or v_row.sender_name is distinct from p_sender_name
     or v_row.recipient_name is distinct from p_recipient_name
     or v_row.destination is distinct from p_destination
     or v_row.message is distinct from p_message
     or v_row.photo_path is distinct from p_photo_path then
    raise exception 'this draft was already sent with different content; start a new draft'
      using errcode = 'PT409', hint = 'idempotency_conflict';
  end if;
  return private.message_json(v_row);
end;
$$;

-- Explicit execute grants. Functions default to PUBLIC execute, so revoke first.
revoke all on function
  public.lookup_recipient(text),
  public.list_conversations(),
  public.list_messages(uuid, timestamptz, integer),
  public.send_postcard(uuid, text, text, text, text, text, uuid)
from public, anon;
grant execute on function
  public.lookup_recipient(text),
  public.list_conversations(),
  public.list_messages(uuid, timestamptz, integer),
  public.send_postcard(uuid, text, text, text, text, text, uuid)
to authenticated;

revoke all on all functions in schema private from public, anon, authenticated;
