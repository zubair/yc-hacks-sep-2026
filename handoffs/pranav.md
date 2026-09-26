# Integrated Postcard implementation on `team/pranav`

## Status

Implemented the shared Swift packages, native iOS app, SwiftUI screens, and Supabase migration in this branch after the user requested the whole app. No hosted service was changed. The fixture app builds and runs without credentials. A device-specific Duo hinge feed remains pending a public API.

## Public API

`PostcardCore` exports `PostcardProfile`, `PostcardDraft`, `PostcardMessage`, `PostcardConversation`, `PostcardPresentationState`, and `PostcardServiceError`. `PostcardServices` exports the exact `PostcardService` protocol from `docs/CONTRACTS.md`, `FixturePostcardService(signedIn:)`, and `SupabasePostcardService(url:publishableKey:)`. `PostcardMotion` exports `PostcardFlipContainer(isOpen:duration:front:back:)` and `PostcardSealEffect(isSealed:)`. `PostcardUI` exports the four named screens in the contract. Their public initializer labels are in their source files. The UI owns local form state only; `PostcardAppModel` owns service calls and draft persistence.

## Configuration and dependencies

Supabase Swift SDK 2.55.2 is pinned in `packages/PostcardServices/Package.swift`. XcodeGen 2.46.0 generates `ios/Postcard.xcodeproj` from `ios/project.yml`. The app reads `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from build settings embedded in Info.plist. If absent, it uses fixture mode. The app must only receive a publishable/anon key. See the root README for commands.

## Tests and results

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` in `packages/PostcardCore`: passed, 1 test.
- Same command in `packages/PostcardServices`: passed, 2 tests (retry idempotency, auth/offline state).
- `xcodebuild ... build` for iPhone 17 Pro iOS 26.5: passed.
- `tests/backend/check.sh` on PostgreSQL 17 with mock Auth/Storage schemas: passed (profile trigger, exact lookup, duplicate send, conflict denial, RLS visibility, photo policy, direct-write denial).
- `npx supabase start`: blocked by Docker DNS timeout resolving `public.ecr.aws`; no live Auth, Storage API, or Realtime check was claimed.
- Simulator UI flow test is being verified; result is recorded before the final commit.

## Limits and integration notes

- `send_postcard` uses PostgreSQL `22023` for validation, `28000` for unauthenticated, `P0002` for not-found, and privilege errors for forbidden. The Swift adapter maps these to user-facing service errors.
- Timestamp-only `p_before` pagination can skip rows sharing the exact same timestamp at a page boundary; the RPC uses UUID as a stable tie order within a page. A cursor containing timestamp and UUID is the next contract improvement for large conversations.
- The Storage bucket enforces declared MIME and size, while content-byte JPEG signature validation is pending. The app decodes and converts selected photos to JPEG and caps pixels and bytes. Storage does not delete sent photos. An operational cleanup job for old unsent uploads is pending.
- The local SQL harness does not exercise Supabase API gateway grants, Auth session behavior, Storage signed URL authorization, or actual Realtime filtering. Run those with three local Supabase test accounts once Docker registry access works.
- Duo simulator was available, but the installed SDK headers expose no verified public hinge API. Manual Open/Seal controls are the supported path.
