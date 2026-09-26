-- LOCAL DEMO ONLY. Three test identities for `supabase db reset`; never run against a hosted project.
-- Password for all: postcard-local-1  (emails use the reserved .test TLD)
--   alice  (sender)     bob  (recipient)     eve  (outsider)

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('00000000-0000-4000-a000-00000000a11c'::uuid, 'alice@postcard.test', 'alice', 'Alice'),
      ('00000000-0000-4000-a000-000000000b0b'::uuid, 'bob@postcard.test', 'bob', 'Bob'),
      ('00000000-0000-4000-a000-000000000e0e'::uuid, 'eve@postcard.test', 'eve', 'Eve')
    ) as t(id, email, username, display_name)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
      extensions.crypt('postcard-local-1', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object('username', u.username, 'display_name', u.display_name),
      now(), now(), '', '', '', ''
    )
    on conflict (id) do nothing;

    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      gen_random_uuid(), u.id, u.id::text,
      jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
      'email', now(), now(), now()
    )
    on conflict do nothing;
  end loop;
end;
$$;
