# Handoff: Zafar (Supabase backend and direct messaging)

## Status

Implemented and verified against a **real local Supabase stack** (`supabase start`, CLI 2.118.0, Postgres 17.6.1.171, storage-api v1.77.0, plus Auth, PostgREST, Realtime and Kong). All 18 end-to-end tests pass through the real Auth, REST, Storage and Realtime APIs. Nothing is deployed to a hosted project.

Branch `team/zafar`. The latest commit on this branch is the tested revision.

## Files

| Path | Purpose |
|---|---|
| `supabase/config.toml` | Local project; private `postcard-photos` bucket (10 MiB, image/jpeg) |
| `supabase/migrations/20260926000100_profiles.sql` | `profiles`, signup trigger, owner-only RLS |
| `supabase/migrations/20260926000200_messaging.sql` | `conversations`, `conversation_members`, `postcards` (immutable), RLS, 4 RPCs |
| `supabase/migrations/20260926000300_storage.sql` | Bucket, storage policies, orphan listing |
| `supabase/migrations/20260926000400_realtime.sql` | `postcards` added to `supabase_realtime` |
| `supabase/seed.sql` | Local-only users alice/bob/eve (password `postcard-local-1`) |
| `backend/TEAM_SETUP.md` | Team access guide: who needs what, local + hosted setup |
| `backend/README.md` | Setup, architecture, SECURITY DEFINER notes, error mapping, deploy checklist |
| `backend/fixtures/*.json` | Real request/response pairs recorded from the local stack (tokens redacted) |
| `backend/scripts/cleanup-orphans.mjs` | Server-side orphan photo cleanup (dry run by default) |
| `backend/.env.example` | Placeholder configuration |
| `tests/backend/` | `messaging.test.mjs` (18 tests), `helpers.mjs`, `capture-fixtures.mjs` |

## Public API

RPCs `lookup_recipient`, `list_conversations`, `list_messages`, `send_postcard` exactly as in `docs/CONTRACTS.md`. Single-result RPCs return objects, not arrays. Details and the error table are in `backend/README.md`; examples are in `backend/fixtures/`.

## Commands and results

```
SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io supabase start -x imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
  → all 4 migrations applied, bucket created
supabase db reset → migrations + seed OK; seeded alice can sign in
cd tests/backend && SUPABASE_PUBLISHABLE_KEY=… npm test → tests 18, pass 18, fail 0
node capture-fixtures.mjs → 14 fixtures (200/401/403/404/409/422 as designed)
node backend/scripts/cleanup-orphans.mjs --apply → sent photo preserved
```

Covered by the tests, using sender, recipient and outsider identities:
- Profiles:
  - The profile is created from signup metadata.
  - An invalid or duplicate username fails signup.
  - Profiles are owner-only: outsiders can neither see nor edit them.
- Directory: lookup is exact and case-insensitive, returns only id/username/display_name, and exposes no email.
- Anonymous callers are denied every RPC.
- Storage:
  - Uploads are allowed only into your own folder with the canonical file name.
  - Overwrite and upsert are refused.
  - The bucket rejects PNG and files over 10 MB.
  - An unsent draft photo is readable only by its owner.
- Sending:
  - Send returns one message object and creates the conversation.
  - The recipient can list and read the message and download the photo through a signed URL.
  - The outsider gets 404 on the conversation and no rows, conversations or photo access.
  - Direct table inserts, self-joining a conversation, and editing or deleting a postcard are all refused.
- Validation:
  - Spoofing another user's photo path returns 403.
  - A path that doesn't match the draft id returns 403.
  - Self-recipient returns PT422.
  - Unknown recipient returns PT404.
  - Blank or 5,001-character messages, over-long names and over-long destinations return PT422. 5,000 characters is accepted.
  - A missing upload returns PT422 `photo_missing`.
- Idempotency:
  - A same-key retry returns an identical response.
  - Reusing a key with different content returns PT409.
  - 20 concurrent duplicate sends create exactly 1 row (8 consecutive runs).
  - Concurrent first sends in both directions between a new pair create 1 conversation with 2 members.
- Pagination: newest first, `p_before` paging works, and the limit is clamped to 1–100.
- Photo lifecycle:
  - A sent photo survives the sender's delete attempt.
  - The orphan listing includes old unsent uploads and never sent ones.
  - The owner can delete an unsent upload.
- Realtime: the recipient receives the INSERT event and the outsider receives nothing.

## Limitations

- **Hosted Supabase:** not deployed and not tested. The owner has created an org; deploying needs explicit authorization and the database password supplied outside chat.
- **Image content:** byte signatures and pixel dimensions are **not** validated server-side. MIME comes from the upload's Content-Type. The client must enforce the 20 MP limit.
- **Signed URL lifetime:** the ≤5-minute expiry is a client obligation. Supabase Storage lets the caller choose `expiresIn`.
- **Pagination:** messages sharing the exact boundary microsecond can be skipped by `p_before`. Clients merge by id and refetch the first page on reconnect.
- **Invalid signup:** an invalid username fails the whole signup. GoTrue surfaces this as a generic "Database error saving new user", so clients should pre-validate `^[a-z0-9_]{3,30}$`.
- **Environment:** in this container, `public.ecr.aws` image layers were blocked by the proxy (403), so images come from Docker Hub. Docker Hub also rate-limited once (429) before a retry succeeded.

## Proposed contract changes (for the integration agent)

1. **Photo path is required.** `PostcardMessage.photoPath` is non-optional, so `send_postcard` requires an uploaded photo. `PostcardDraft.photoData` is optional; the app must block Send without a photo, or the contract should allow photo-less postcards.
2. **Photo path is tied to the draft.** `p_photo_path` must equal `<auth uid>/<p_client_request_id>/photo.jpg`, which ties the upload to the draft id. This matches the documented path.
3. **Errors use PostgREST custom codes** (`PT401/403/404/409/422`) with stable `hint` values. The mapping table is in `backend/README.md`.
4. **Timestamps include microseconds.** Swift decoding needs `.withFractionalSeconds`.

## Integration steps

- **Pranav:** use `backend/fixtures/` for `FixturePostcardService` and the contract tests. Map errors per the README table.
  - Upload with `x-upsert: false`, and treat `KeyAlreadyExists` as success on retry.
  - Subscribe to `postgres_changes` INSERT on `public.postcards` and yield `conversation_id`.
- **Zubair:** app configuration needs only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (from `supabase status`). The local demo accounts are alice, bob and eve, password `postcard-local-1`.
- **Integration agent:** run `supabase start`, `supabase db reset`, then the tests in `tests/backend`. Follow the deploy checklist in `backend/README.md` only with authorization.
