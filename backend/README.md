# Postcard backend (Supabase)

Account-to-account postcards on Supabase Auth, Postgres (RLS), private Storage and Realtime. The wire contract is `docs/CONTRACTS.md`. This document covers setup, architecture, and error mapping.

## Local setup

Requires Docker and the Supabase CLI (`npm i -g supabase`, tested with 2.118.0).

```sh
supabase start                      # from the repo root; applies supabase/migrations
supabase db reset                   # re-apply migrations + seed alice/bob/eve (local only)
supabase status -o env              # SUPABASE_URL / publishable key for the app and tests

cd tests/backend && npm install
SUPABASE_PUBLISHABLE_KEY=<publishable key> npm test          # 18 end-to-end checks
SUPABASE_PUBLISHABLE_KEY=<publishable key> node capture-fixtures.mjs   # refresh backend/fixtures (after db reset)
```

If `public.ecr.aws` is blocked on your network, set `SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io` before `supabase start`. To start only what Postcard needs: `supabase start -x imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor`.

Seeded local users (password `postcard-local-1`): `alice@postcard.test`, `bob@postcard.test`, `eve@postcard.test`. Local email confirmation is off. On hosted projects, confirmation is typically on, so `signUp` returns no session until the user confirms.

Configuration names: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` (app-safe). `SUPABASE_SECRET_KEY` is only for server jobs. See `backend/.env.example`.

## Architecture

```
 iOS app (publishable key + user JWT)
   │ 1 Auth: signUp(email, password, {username, display_name}) / signIn → access token
   │ 2 Storage: PUT postcard-photos/<uid>/<draft_id>/photo.jpg   (RLS: own folder, jpeg ≤10 MB, no overwrite)
   │ 3 RPC send_postcard(... p_photo_path, p_client_request_id = draft_id)
   │       └─ one transaction: validate → find/create pair → members → insert postcard
   │ 4 Realtime postgres_changes INSERT on postcards (RLS: sender/recipient only) → refetch
   ▼
 Postgres: profiles · conversations(user_low<user_high, unique) · conversation_members · postcards(immutable)
```

- **Auth/session:** Supabase Auth issues the JWT. The `on_auth_user_created` trigger creates `profiles` from signup metadata `username` and `display_name`: username lowercased and matched against `^[a-z0-9_]{3,30}$`, display name at most 100 characters. An invalid or taken username fails signup, so the client should validate first. Profiles are readable and editable only by their owner. Other users are found only through `lookup_recipient`, which returns id, username and display_name, never email.
- **Upload before send:** the client converts the image to JPEG, checks ≤10 MB and ≤20 MP, and uploads once to `<auth uid>/<draft id>/photo.jpg` with `x-upsert: false`. On retry, Storage answers HTTP 400 with body `{"statusCode":"409","code":"KeyAlreadyExists"}`. Treat that as "already uploaded" and reuse the path. There is no UPDATE policy, so no object can ever be overwritten, sent or not.
- **Transaction boundary:** `send_postcard` is a single SECURITY DEFINER function, so the conversation, the members and the postcard are committed together or not at all. The draft is "sent" only when it returns 200 with the message object.
- **Retry semantics:** `(sender_id, client_request_id)` is unique. The same draft id with the same payload returns the original message, even under concurrent retries (`INSERT … ON CONFLICT DO NOTHING`, then re-read). The same id with different content returns `PT409 idempotency_conflict`. Concurrent first messages between a pair converge on one conversation through `unique(user_low, user_high)`.
- **Receiving/reconnect:** subscribe to `postgres_changes` INSERT on `public.postcards`. Realtime applies the SELECT policy per subscriber. Treat an event as "refetch conversation `conversation_id`", not as delivery. On every (re)connect, call `list_conversations` and the first page of `list_messages`, then merge by message id.
- **Photo access:** `createSignedUrl(path, ≤300)`. The select policy allows the uploader, and the sender and recipient of a sent postcard. Supabase Storage does not let the server cap `expiresIn`, so clients must pass ≤300. That 5-minute limit is a client obligation.
- **Storage cleanup:** unsent uploads older than 24 h are orphans. `public.list_orphan_photos` is service-role only and never lists an object that a postcard references. `backend/scripts/cleanup-orphans.mjs` (dry run by default, `--apply` to delete) removes them through the Storage API. Clients can delete their own unsent uploads, and the delete policy refuses sent photos.
- **Content validation:** size and MIME are enforced by the bucket (`image/jpeg`, 10 MiB). MIME comes from the upload's Content-Type. **Image byte signatures and pixel dimensions are not validated server-side yet.**
- **Privacy:** the functions do not log message text. Tokens stay in headers. No email appears in any RPC response.

### SECURITY DEFINER functions

| Function | Why definer | Guard |
|---|---|---|
| `lookup_recipient`, `list_conversations`, `list_messages`, `send_postcard` | Read peer profiles and write tables clients cannot touch directly | `auth.uid()` required (`PT401`); membership and identity checks inside; `search_path = ''`; execute revoked from `public`/`anon`, granted to `authenticated` |
| `private.handle_new_user` | Auth trigger inserts the profile | Only fires from `auth.users`; no execute grant |
| `private.photo_is_sent`, `private.can_read_sent_photo` | Storage policies check postcards without depending on caller RLS | Return booleans only; `search_path = ''` |
| `list_orphan_photos` | Scans storage.objects | Execute granted to `service_role` only |

The RLS policies compare columns with `auth.uid()` and never query another RLS-protected table, so there is no policy recursion.

## RPCs (`POST /rest/v1/rpc/<name>`)

Exact request and response examples are in `backend/fixtures/`, recorded from the local stack.

| RPC | Body | 200 response |
|---|---|---|
| `lookup_recipient` | `{p_username}` | profile object or `null` |
| `list_conversations` | `{}` | `[ {id, peer, latest_message \| null, updated_at} ]`, newest first |
| `list_messages` | `{p_conversation_id, p_before, p_limit}` | `[message]`, newest first, `created_at desc, id desc`; limit clamped to 1–100 |
| `send_postcard` | `{p_recipient_id, p_sender_name, p_recipient_name, p_destination, p_message, p_photo_path, p_client_request_id}` | message object |

Timestamps are ISO-8601 UTC with microseconds (`2026-09-26T20:49:38.672277Z`). Swift's default `.iso8601` decoder rejects fractional seconds, so use `ISO8601DateFormatter` with `.withFractionalSeconds`. Pagination passes the oldest `created_at` held as `p_before`. Messages sharing that exact microsecond may be skipped, which is why clients merge by id and refetch the first page on reconnect.

## Error mapping

PostgREST returns `{code, message, details, hint}`. Map on HTTP status plus `code`:

| HTTP | `code` | `hint` | `PostcardServiceError` |
|---|---|---|---|
| 401 | `PT401`, `42501` (no JWT / anon), `PGRST301`/`PGRST303` (bad/expired JWT) | `unauthenticated` | `.unauthenticated` |
| 403 | `PT403` | `forbidden` | `.forbidden` |
| 404 | `PT404` | `not_found` | `.notFound` |
| 409 | `PT409` | `idempotency_conflict` or `username_taken` | `.validation(message)` |
| 422 | `PT422` | `validation` or `photo_missing` | `.validation(message)` |
| 400/413/415 from Storage | — | — | `.validation(message)` (size/type) |
| URLError offline family | — | — | `.offline` |
| other 5xx | any | — | `.server(message)` |

The `message` strings are written to be shown to users.

## Deploying (integration agent, with explicit authorization only)

1. `supabase link --project-ref <ref>`. The database password comes from the owner and is never committed.
2. `supabase db push` applies `supabase/migrations` in order. Do not run `seed.sql` on hosted projects.
3. Confirm that bucket `postcard-photos` is private, 10 MiB, `image/jpeg` (the migration upserts this).
4. Confirm that `public.postcards` is in the `supabase_realtime` publication.
5. Auth settings: decide on email confirmation. Keep the minimum password length at 8 or more.
6. Schedule `cleanup-orphans.mjs --apply` daily from a server with `SUPABASE_SECRET_KEY`.
7. Give the app only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
