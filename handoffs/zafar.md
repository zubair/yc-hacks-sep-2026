# Handoff: Zafar (Supabase backend and direct messaging)

## Status

Implemented and verified against a **real local Supabase stack** (`supabase start`, CLI 2.118.0, Postgres 17.6.1.171, storage-api v1.77.0, plus Auth, PostgREST, Realtime and Kong). All 27 end-to-end tests pass through the real Auth, REST, Storage and Realtime APIs, including 9 regression tests from an adversarial review (below). Nothing is deployed to a hosted project.

Branch `team/zafar`. The latest commit on this branch is the tested revision.

## Files

| Path | Purpose |
|---|---|
| `supabase/config.toml` | Local project; private `postcard-photos` bucket (10 MiB, image/jpeg) |
| `supabase/migrations/20260926000100_profiles.sql` | `profiles`, signup trigger, owner-only RLS |
| `supabase/migrations/20260926000200_messaging.sql` | `conversations`, `conversation_members`, `postcards` (immutable), RLS, 4 RPCs |
| `supabase/migrations/20260926000300_storage.sql` | Bucket, storage policies, orphan listing |
| `supabase/migrations/20260926000400_realtime.sql` | `postcards` added to `supabase_realtime` |
| `supabase/migrations/20260926000500_hardening.sql` | Review fixes: photo overwrite/delete triggers, locked send, inserts-only realtime, stricter validation, index |
| `supabase/seed.sql` | Local-only users alice/bob/eve (password `postcard-local-1`) |
| `backend/TEAM_SETUP.md` | Team access guide: who needs what, local + hosted setup |
| `backend/README.md` | Setup, architecture, SECURITY DEFINER notes, error mapping, deploy checklist |
| `backend/fixtures/*.json` | Real request/response pairs recorded from the local stack (tokens redacted) |
| `backend/scripts/cleanup-orphans.mjs` | Server-side orphan photo cleanup (dry run by default) |
| `backend/.env.example` | Placeholder configuration |
| `tests/backend/` | `messaging.test.mjs` (18 tests), `hardening.test.mjs` (9 regression tests), `helpers.mjs`, `capture-fixtures.mjs` |

## Public API

RPCs `lookup_recipient`, `list_conversations`, `list_messages`, `send_postcard` exactly as in `docs/CONTRACTS.md`. Single-result RPCs return objects, not arrays. Details and the error table are in `backend/README.md`; examples are in `backend/fixtures/`.

## Commands and results

```
SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io supabase start -x imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
  → all 5 migrations applied, bucket created
supabase db reset → migrations + seed OK; seeded alice can sign in
cd tests/backend && SUPABASE_PUBLISHABLE_KEY=… SUPABASE_SECRET_KEY=… npm test → tests 27, pass 27, fail 0 (twice in a row)
hardening tests with 20260926000500 removed → 8 of 9 fail (they catch the bugs); restored → 9 of 9 pass
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

## Adversarial review

A five-lens review (privilege/RLS, storage, contract, concurrency, realtime/auth/ops) used 69 agents against the live stack. It raised 32 findings. 19 were confirmed by an independent reproduction plus a skeptic; the other 13 were disputed. All confirmed code defects are fixed in `20260926000500_hardening.sql` and covered by `hardening.test.mjs`:

| Finding | Fix |
|---|---|
| A signed upload URL minted with `upsert` before sending could swap a sent photo (signed-upload PUTs skip RLS) | `storage.objects` BEFORE UPDATE trigger freezes content (`version`) and path for the bucket |
| Delete racing `send_postcard` could orphan a sent postcard's photo, and a re-upload could then swap it | `send_postcard` takes `FOR KEY SHARE` on the photo row; a BEFORE DELETE trigger skips referenced photos after acquiring the row lock |
| Orphan cleanup (service key) could delete a photo sent between listing and removal | Same delete trigger; it applies to every role |
| Realtime: DELETE ids reached all subscribers; anon received a frame per insert | Publication is inserts-only; `grant select (id)` to anon routes anon through RLS, so anon gets nothing |
| Whitespace-only messages (newlines, NBSP) passed | Blank check uses `[^[:space:]]` |
| An omitted `p_recipient_id` returned PGRST202 instead of PT422 | All `send_postcard` params default to NULL |
| No index on `conversations.user_high` | Index added |
| Docs: lowercase UUID paths, Storage error bodies, pagination precision | README, TEAM_SETUP and this handoff updated |

Disputed (the skeptic judged them intended or out of scope) and documented as limitations, not fixed:
- Deleting an account cascades and removes that conversation for both people.
- Signed URL lifetime is client-chosen.
- Unconfirmed sign-ups can claim usernames when email confirmation is off.
- A renamed username can be claimed at once by someone else.
- Text limits count Unicode code points, not Swift `Character`s.

## Limitations

- **Hosted Supabase:** not deployed and not tested. The owner has created an org; deploying needs explicit authorization and the database password supplied outside chat.
- **Image content:** byte signatures and pixel dimensions are **not** validated server-side. MIME comes from the upload's Content-Type. The client must enforce the 20 MP limit.
- **Signed URL lifetime:** the ≤5-minute expiry is a client obligation. Supabase Storage lets the caller choose `expiresIn`.
- **Pagination:** pass the `created_at` string from the response back as `p_before`. Re-encoding a Swift `Date` (millisecond precision) can skip same-millisecond messages. Clients merge by id and refetch the first page on reconnect.
- **Account deletion:** cascades and removes that conversation for both people. There is no account-deletion flow in v1.
- **Invalid signup:** an invalid username fails the whole signup. GoTrue surfaces this as a generic "Database error saving new user", so clients should pre-validate `^[a-z0-9_]{3,30}$`.
- **Environment:** in this container, `public.ecr.aws` image layers were blocked by the proxy (403), so images come from Docker Hub. Docker Hub also rate-limited once (429) before a retry succeeded.

## Proposed contract changes (for the integration agent)

1. **Photo path is required.** `PostcardMessage.photoPath` is non-optional, so `send_postcard` requires an uploaded photo. `PostcardDraft.photoData` is optional; the app must block Send without a photo, or the contract should allow photo-less postcards.
2. **Photo path is tied to the draft.** `p_photo_path` must equal `<auth uid>/<p_client_request_id>/photo.jpg` with **lowercase** UUIDs (Swift: `uuidString.lowercased()`), which ties the upload to the draft id. This matches the documented path.
3. **Errors use PostgREST custom codes** (`PT401/403/404/409/422`) with stable `hint` values. The mapping table is in `backend/README.md`.
4. **Timestamps include microseconds.** Swift decoding needs `.withFractionalSeconds`.

## Integration steps

- **Pranav:** use `backend/fixtures/` for `FixturePostcardService` and the contract tests. Map errors per the README table.
  - Upload with `x-upsert: false`, and treat `KeyAlreadyExists` as success on retry.
  - Subscribe to `postgres_changes` INSERT on `public.postcards` and yield `conversation_id`.
- **Zubair:** app configuration needs only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (from `supabase status`). The local demo accounts are alice, bob and eve, password `postcard-local-1`.
- **Integration agent:** run `supabase start`, `supabase db reset`, then the tests in `tests/backend`. Follow the deploy checklist in `backend/README.md` only with authorization.
