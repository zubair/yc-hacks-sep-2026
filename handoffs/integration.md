# Handoff: Integration

## Summary

All four workstreams are merged, and the app compiles against the real `PostcardCore`, `PostcardServices`, `PostcardMotion`, and `PostcardUI` packages; the local contract stubs are gone. The integration work also:

- Gated the Duo APIs on iOS 27.1 and lowered the app target to iOS 17.0.
- Fixed several app-state issues found while wiring.
- Added fixture demo controls and a UI test target.
- Added an opt-in live contract test of the Swift Supabase adapter against a local stack.

Results:

- **Backend:** the end-to-end suite passes 18/18 against local Supabase in the Linux container.
- **Security review:** one medium finding; the fix is in progress.
- **Xcode builds and tests:** need a Mac with Xcode 27.1. Their results are `TBD` below.
- **Not done:** no hosted deployment and no real-user messaging.

Working branch: `claude/great-cray-2rrx7l`, based on `origin/integration/final` @ `8d7e9fc`. Final pushed SHA: `TBD`.

## Integrated contributor SHAs

Merge order: pranav → zafar → barrat → zubair, using merge commits.

| Branch | SHA | How it entered | Notes |
|---|---|---|---|
| `team/pranav` | `4d04749` | Merge commit `ab434d2` | Already contained `team/zafar` `1bfc9fa`, `team/barrat` `a051f8a` (via `4d04749`), and an early `team/zubair` `815435e` (via `0430936`) |
| `team/zafar` | `1bfc9fa` | Already an ancestor after the Pranav merge | No separate merge commit needed |
| `team/barrat` | `a051f8a` | Already an ancestor after the Pranav merge | No separate merge commit needed |
| `team/zubair` | `6216a60` | Merge commit `091dac4` | Includes Zubair's reconcile `ee292d3` and the PostcardUI wiring `fe73bfd` |
| `team/zubair-claude` | `4af4e3b` | Ancestor of `team/zubair` | Not merged separately |

Integration commits: `7e658d6` wires Zubair's app to the real Core, Services, and Motion packages. Later integration commits, including the security fix and these docs: `TBD`.

## Conflict resolutions

- **`ios/` follows Zubair's final architecture.** His reconcile `ee292d3` superseded Pranav's early app layer. These files were removed:
  - `PostcardCoordinator`, `DuoStateController`, `LocalDraftStore`, `NativeHingeObserver`, `PostcardPhotoProcessor`, and `PostcardHaptics`
  - `PostcardRootView` and `AppRuntime`
  - `Config/Info.plist` and `LocalConfig.plist.example`, together with their tests

  Their equivalents are `PostcardPresentationController`, `SessionCoordinator` and the view models, `FileDraftStore`, `HingePosture`, `PhotoImporter`, `Haptics`, and `Local.xcconfig`.
- **`packages/PostcardUI` keeps Barrat's `Package.swift`, `PostcardAuthView`, and `PostcardStyle`.** Zubair's edits to them referenced an uncommitted `PostcardHero` view and a `Resources` directory, and would not compile from a clean checkout.
- **Pranav's PostcardUI edits are kept:** memberwise-init tests and the demo sent copy.
- **`README.md` and `docs/CONTRACTS.md` were rewritten at integration.** The accepted contract changes are listed below.

## Integration fixes

1. **Real package APIs.** The app had been built against local stubs. Stub-only APIs were replaced with the real package API:

   | Stub API | Real API |
   |---|---|
   | `PostcardCoding` (draft persistence) | Foundation `JSONEncoder` and `JSONDecoder` with the Core models' `Codable` conformance |
   | `.postcardSeal(isSealed:)` | `.modifier(PostcardSealEffect(isSealed:))` |
   | `FixturePostcardService(scenario:signedInAs:)` | `FixturePostcardService(signedIn:)` |
   | `PostcardService` protocol in Core | the protocol in `PostcardServices` |

2. **Duo gating.** All Duo APIs are declared `@available(anyAppleOS 27.1)` in the SDK: `onHingeChange`/`DeviceHinge`, `ArrangementView` with `.split`, `reservedRegions`, `ToolbarItem.axisBehavior`/`visibilityPriority`, and `ToolbarOverflowMenu`. They are now inside `if #available(iOS 27.1, *)`. The app target is iOS 17.0 (it was 27.1), so ordinary iPhones use the Open and Seal buttons with a classic toolbar.
3. **Lookup feedback.** Recipient lookup feedback now goes to `recipientLookupMessage`. Before, it appeared as a send error, and that error's Try again button re-sent the postcard.
4. **Draft resume.** Write and Reply resume an unsent draft that has content instead of discarding it.
5. **Offline launch.** Launching while offline shows a retryable "can't connect" state that keeps the session and draft. Before, it signed the user out.
6. **Demo:**
   - a bundled sample photo (`DemoPhoto`)
   - a Demo menu with View as Sam Lee / Alex Rivera, Fail the next send, and Simulate offline
   - fixture sign-in that picks `alex` or `sam` from the email
7. **Launch arguments.** `-resetDemo` clears the stored draft. `-forceDemo` forces fixture mode. UI tests always pass both.
8. **UI tests.** New `PostcardUITests` target (`ios/Tests/UI`) with three flows:
   - compose → open → seal → explicit send → the recipient reads it
   - failed send → Retry stores exactly one postcard
   - offline inbox → Retry → recovery
9. **Live contract test.** `SupabasePostcardService` gained an internal `init(client:)` and in-memory session storage off Apple platforms. With these, `packages/PostcardServices/Tests/PostcardServicesTests/LiveSupabaseTests.swift` runs on Linux. It is opt-in via `POSTCARD_LIVE_SUPABASE_URL` and `POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY` and refuses non-local hosts. It covers:
   - lookup
   - upload with an idempotent send and a conflicting-reuse rejection
   - microsecond paging
   - signed-URL download
   - outsider denial
   - error mapping
   - realtime refetch

## Accepted contract changes (applied to `docs/CONTRACTS.md`)

- A photo is required to send. `p_photo_path` equals `<uid>/<client_request_id>/photo.jpg`.
- Errors use `PT401`, `PT403`, `PT404`, `PT409`, and `PT422`.
- Timestamps carry microseconds.
- Barrat's additive UI inputs:
  - `isDemo`
  - `recipientLookupMessage`
  - conversation `photoData`, `photoErrors`, `onRetryPhoto`, and `title`
  - auth `notice`
- The app minimum is iOS 17 with the Duo APIs gated.
- Documented where types live: `PostcardService` in PostcardServices, and the service constructors.

## Configuration

- **App:** `ios/Config/Local.xcconfig` is gitignored and copied from `Local.xcconfig.example`. It holds `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` only. Absent values mean fixture mode.
- **Backend:** `backend/.env` is gitignored and copied from `backend/.env.example`. `SUPABASE_SECRET_KEY` is for server jobs only.
- **Live Swift test:** `POSTCARD_LIVE_SUPABASE_URL` and `POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY`, local hosts only.
- **Committed secrets:** none. `ios/Config/Postcard.xcconfig` is committed with empty values.

## Commands and results

| Command | Environment | Result |
|---|---|---|
| `SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io supabase start -x imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor` | Linux container, CLI 2.118.0 | Stack started, 4 migrations applied |
| `cd tests/backend && SUPABASE_PUBLISHABLE_KEY=… npm test` | Local Supabase | 18/18 pass |
| Same suite with migrations `…000500_protect_sent_photos` and `…000600_realtime_insert_only` and the new overwrite test | Local Supabase | TBD |
| `cd packages/PostcardCore && swift test` | TBD | TBD |
| `cd packages/PostcardServices && swift test` | TBD | TBD |
| `POSTCARD_LIVE_SUPABASE_URL=http://127.0.0.1:54321 POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY=… swift test --filter LiveSupabaseTests` | Local Supabase, Linux | TBD |
| `cd packages/PostcardUI && xcodebuild -scheme PostcardUI -destination 'platform=iOS Simulator,name=iPhone Duo' test` | Xcode 27.1 | TBD |
| `python3 packages/PostcardUI/Examples/test_rules.py` | Python 3 | TBD |
| `cd ios && xcodegen generate && xcodebuild … -destination 'generic/platform=iOS Simulator' build` | Xcode 27.1 | TBD |
| `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone Duo' test` (PostcardAppTests and PostcardUITests) | Xcode 27.1, iOS 27.1 | TBD |
| Same, on an ordinary iPhone below iOS 27.1 (button fallback) | Xcode 27.1 | TBD |
| Live app against local Supabase: two-account send, photo, realtime, reconnect | Mac with simulators | TBD |
| Physical fold in Bitrig's 3D Duo simulator | Bitrig | TBD |

Screenshots of the integrated app go in `design/screenshots/integration/`. They are TBD; the planned list is in the root README.

## Security review

Scope: RLS, storage policies, SECURITY DEFINER functions, idempotency, and realtime exposure in `supabase/migrations`.

| Severity | Finding | Status |
|---|---|---|
| Medium | A sent photo could be overwritten. A signed upload URL issued with `upsert: true` before send stays valid for 2 hours, and uploads through it run as the Storage superuser, which bypasses RLS. | Fix in progress: `supabase/migrations/20260926000500_protect_sent_photos.sql` adds a trigger that refuses any change to, or deletion of, a sent photo's object for every role. It comes with a new backend test, "a sent photo cannot be swapped through an upsert signed upload URL issued before sending". Verification is TBD. |
| Low / info | `sender_name` is free text supplied by the client, so a sender can show any display name. | Open. Consider deriving it from the sender's profile on the server. |
| Low / info | A NUL character in the message text reaches the Postgres log on a JSON parse error, which puts personal text in logs. | Open |
| Low / info | The realtime publication included deletes, and Realtime does not filter DELETE events by RLS. | Fix in progress: `supabase/migrations/20260926000600_realtime_insert_only.sql` publishes inserts only. Verification is TBD. |
| Low / info | Anonymous realtime subscribers receive no rows but can observe event timing. | Open, accepted for v1 |
| Low / info | The local stack allows 6-character passwords (`supabase/config.toml`). | Documented; hosted projects must set 8 or more (deploy checklist) |

## Unresolved blockers

1. The medium storage finding is not closed until migrations `20260926000500` and `20260926000600` are committed and the backend suite, including the new overwrite test, passes.
2. No Xcode 27.1 build or test has run from this integrated tree yet. The integration container is Linux. Every Xcode row above is TBD.
3. The Duo hinge has not been validated on hardware or in Bitrig's 3D fold simulator with this build.
4. Live app mode has been checked only through the Swift live contract test (TBD), not in the app UI against a backend.
5. Hosted Supabase is not deployed; there is no authorization or credentials for it.
6. There are no screenshots of the integrated app yet.

## Next steps for a live release

1. **Close the medium finding.** Run `supabase db reset`, then `cd tests/backend && SUPABASE_PUBLISHABLE_KEY=<key> npm test`. All tests, including the new overwrite test, must pass.
2. **Mac verification.** On a Mac with Xcode 27.1, run the iOS build and test commands in the root README:
   - iPhone Duo on iOS 27.1
   - one ordinary iPhone below 27.1
   - the PostcardUI package tests

   Capture the planned screenshots into `design/screenshots/integration/`, then fill in the TBD cells here and in the README.
3. **Local live run.** Create `ios/Config/Local.xcconfig` from `supabase status`. Sign in as `alice@postcard.test` and `bob@postcard.test` on two simulators, then check:
   - an explicit send
   - receipt of the photo and note
   - a realtime refresh
   - a relaunch while offline, followed by retry

   Run `LiveSupabaseTests` and record the result.
4. **Fold check.** In Bitrig, open `ios/`, run on iPhone Duo, and go Closed → Fully Open → Closed. The card should open, then seal once, and must never send.
5. **Hosted backend, only with explicit authorization.**
   1. `supabase link --project-ref <ref>`, with the database password supplied outside chat.
   2. `supabase db push`. Do not run `seed.sql`.
   3. Confirm that `postcard-photos` is private, 10 MiB, and `image/jpeg`.
   4. Confirm that `public.postcards` is in `supabase_realtime`.
   5. Set the Auth minimum password length to 8 or more, decide on email confirmation, and configure SMTP.
   6. Schedule `node backend/scripts/cleanup-orphans.mjs --apply` daily on a server that holds `SUPABASE_SECRET_KEY`.
   7. Validate against a disposable staging project first, never production users.
6. **App release.** Inject the hosted `SUPABASE_URL` and publishable key through an ignored or CI-provided xcconfig; never a secret key. Set signing for `com.bairisland.postcard`, then archive and distribute through TestFlight.
7. **Remaining low findings.** Derive `sender_name` on the server, and keep message text out of error logs.
8. **After v1.** A pagination UI (`p_before`), push notifications, and read receipts.
