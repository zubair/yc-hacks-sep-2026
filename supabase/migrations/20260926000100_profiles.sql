-- Profiles: one per Supabase Auth user. Created from signup metadata; never exposes email.

create schema if not exists private;
revoke all on schema private from public;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique
    constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,30}$'),
  display_name text not null default ''
    constraint profiles_display_name_length check (char_length(display_name) <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Public identity for a Postcard user. Email stays in auth.users.';

-- Lowercase and trim usernames before the format check runs.
create function private.normalize_profile()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.username := lower(btrim(new.username));
  new.display_name := btrim(coalesce(new.display_name, ''));
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.created_at := old.created_at;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

create trigger profiles_normalize
before insert or update on public.profiles
for each row execute function private.normalize_profile();

-- Runs as the table owner because auth.users inserts come from the Auth service.
-- search_path is empty, so every reference is schema-qualified.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text := lower(btrim(coalesce(new.raw_user_meta_data ->> 'username', '')));
  v_display_name text := btrim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));
begin
  if v_username !~ '^[a-z0-9_]{3,30}$' then
    raise exception 'username must be 3-30 characters of a-z, 0-9 or _'
      using errcode = 'PT422', hint = 'validation';
  end if;
  if char_length(v_display_name) > 100 then
    raise exception 'display_name must be at most 100 characters'
      using errcode = 'PT422', hint = 'validation';
  end if;
  insert into public.profiles (id, username, display_name)
  values (new.id, v_username, v_display_name);
  return new;
exception
  when unique_violation then
    raise exception 'username is already taken'
      using errcode = 'PT409', hint = 'username_taken';
end;
$$;

revoke all on function private.handle_new_user() from public;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

alter table public.profiles enable row level security;

-- Direct table access: only your own row. Other people are found via lookup_recipient.
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (username, display_name) on public.profiles to authenticated;
