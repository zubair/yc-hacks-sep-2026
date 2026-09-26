# Handoff: Integration

## Summary

All four workstreams are merged. The app builds with Xcode 27.1 against the real `PostcardCore`, `PostcardServices`, `PostcardMotion`, and `PostcardUI` packages; the app's local contract stubs are gone. Integration also gated the Duo APIs on iOS 27.1 (app target iOS 17.0), added fixture demo controls and a UI test target, fixed the defects found by two code reviews and a security review, and added an opt-in live contract test that runs the Swift Supabase adapter against a real local stack.

Verified on the final tree: backend 27/27 from scratch; PostcardServices 11/11 including live tests against the hardened backend (Linux); PostcardCore 1/1; PostcardUI 6/6; the app builds with Xcode 27.1; iPhone Duo (iOS 27.1) and iPhone 16 Pro (iOS 18.5) each pass 25/25 unit and 3/3 UI tests. Not done: hosted deployment, app UI in live mode, a physical fold, real-user messaging.

Working branch: `claude/great-cray-2rrx7l`, based on `origin/integration/final` @ `8d7e9fc`, merged into `integration/final` through zubair/yc-hacks-sep-2026#3.

## Integrated contributor SHAs

Merge order: pranav → zafar → barrat → zubair, using merge commits.

| Branch | SHA | How it entered | Notes |
|---|---|---|---|
| `team/pranav` | `4d04749` | Merge commit `ab434d2` | Already contained `team/zafar` `1bfc9fa`, `team/barrat` `a051f8a` (via `4d04749`), and an early `team/zubair` `815435e` (via `0430936`) |
| `team/zafar` | `1bfc9fa` | Already an ancestor after the Pranav merge | No separate merge commit needed |
| `team/barrat` | `a051f8a` | Already an ancestor after the Pranav merge | No separate merge commit needed |
| `team/zubair` | `6216a60` | Merge commit `091dac4` | Includes Zubair's reconcile `ee292d3` and the PostcardUI wiring `fe73bfd` |
| `team/zubair-claude` | `4af4e3b` | Ancestor of `team/zubair` | Not merged separately |

Integration commits (after the merges):

| Commit | Change |
|---|---|
| `7e658d6` | Wire the app to the real packages; Duo gating; lookup feedback; draft resume; offline launch state; demo controls; UI tests |
| `29045b1` | Import `PostcardService` from Services (first Xcode build failure); live adapter test; rule harness uses the real Core |
| `ad20349` | Text lengths counted in Unicode scalars, matching Postgres `char_length` |
| `2f10709` | Adapter: update-stream poll leak and full-reload churn; username-taken mapping; fixture parity |
| `daa0cbb` | Backend: sent photos cannot be replaced or deleted; realtime inserts only |
| `2146398` | App review fixes: sent-draft resurrection, retry semantics, per-account data, photo caching |

### Second integration round (after #3 and #4 were merged)

`integration/final` gained PR #4 (`claude/vigilant-hypatia-r7k61c`, a template-driven render pipeline under `renders/`), and two contributor branches moved on. Both were merged on top, with merge commits:

| Branch | SHA | Merge commit | Resolution |
|---|---|---|---|
| `team/zafar` | `0a3cdc9` | `72d9488` | Zafar's `20260926000500_hardening.sql` supersedes the integration branch's `000500_protect_sent_photos` and `000600_realtime_insert_only` (the same fixes and more: delete-race protection, anonymous realtime, whitespace, an index; the duplicate `000500` version would also collide). Tests, the cleanup script, and the backend README follow the owner. Backend: 27/27 from scratch. The wire-contract test now reads expected values from the re-recorded fixtures (`d471b27`). |
| `team/zubair` | `9f34463` | `e1563fa` | Zubair's redesign makes the compose screen the postcard (`PostcardExperienceView`, `PostcardOrnaments`, `RecipientSheet`) and replaces `DuoComposeStage`. It was written against the old stubs, so the merge adapts it: the demo seed uses the real fixture recipient (Sam Lee) and `SamplePhoto`, `ArrangementView` and the Duo toolbar modifiers are gated on iOS 27.1 with stacked/standard fallbacks, the recipient sheet shows `lookupMessage`, `canSend` fills an empty signature from the profile as `send()` does, the note editor gains a keyboard Done button, and the UI tests follow the new flow. |

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
   - a bundled sample photo (now `SamplePhoto`, shared with Zubair's seeded first draft)
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

## Review fixes

Two read-only code reviews (app, packages) and a security review ran against the integrated tree. Everything below is fixed and covered by tests unless marked open.

| Severity | Finding | Fix |
|---|---|---|
| High | A confirmed-sent draft was written back to disk on backgrounding and returned after relaunch with its old id | Never persist a sent draft (`IntegrationFixTests`) |
| High | The composer's Try again called send for any error, so after a photo error it could send a half-written card | Re-send only after a failed send; otherwise dismiss |
| High | The realtime update stream leaked its 20 s poll when a refetch threw | Poll cancelled on every exit; failed refetch no longer ends the stream |
| High | The update stream yielded every conversation on every event and tick; the app reloaded and re-downloaded all photos every 20 s | Yield only new or updated conversations; photos download once per screen |
| Medium | A new photo reused the old draft id, so a retry could send the previously uploaded photo | New photo, new idempotency key |
| Medium | Previous account's inbox and unsent draft stayed visible and sendable after sign-out or account switch | Cleared on sign-out/switch; offline relaunch keeps them |
| Medium | Client counted characters, server counts Unicode scalars; emoji-heavy notes failed after upload | Scalar counting in `PostcardValidation`, form rules, and the counter |
| Medium | A taken username at sign-up surfaced as "Please try again." | Specific validation message (GoTrue 409; 500 on older GoTrue) |
| Medium (security) | A signed upload URL issued before sending could replace a sent photo | Storage trigger refuses changes to sent photos for every role; `send_postcard` locks the photo row; attack reproduced by a new e2e test |
| Low | Demo: Simulate offline then View as recipient stranded the app | Switch disabled while offline |
| Low | Sign-out while offline left the session state signed in | Always ends signed out |
| Low | Fixture self-send and conflicting draft reuse differed from the live RPC | Fixture matches the RPC |
| Low (security) | Realtime publication included deletes, which Realtime does not filter by RLS | Inserts only |

## Commands and results

Final tree (after the second integration round):

| Command | Environment | Result |
|---|---|---|
| `supabase db reset` then `cd tests/backend && SUPABASE_PUBLISHABLE_KEY=… SUPABASE_SECRET_KEY=<local dev key> npm test` | Local Supabase (CLI 2.118.0, Linux container), all migrations from scratch | 27/27 pass (without the secret key, the service-role cleanup test skips: 26 pass, 1 skip) |
| `cd packages/PostcardServices && POSTCARD_LIVE_SUPABASE_URL=http://127.0.0.1:54321 POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY=… swift test` | Linux, Swift 6.4, hardened local stack | 11/11 pass with a WebSocket-capable libcurl; with Ubuntu 24.04's libcurl 8.5 the realtime test skips with the reason |
| `cd packages/PostcardCore && swift test` | Linux, Swift 6.4 | 1/1 pass |
| `python3 packages/PostcardUI/Examples/test_rules.py`; `xcodebuild -scheme PostcardUI test` | Linux Swift 6.4; Xcode 27.1 simulator | 6/6 pass; 6/6 pass |
| `cd ios && xcodegen generate && xcodebuild … -destination 'generic/platform=iOS Simulator' build` | Xcode 27.1 on macOS 27.0 | Build succeeded |
| `xcodebuild … test` (PostcardAppTests + PostcardUITests) | iPhone Duo simulator, iOS 27.1 | 25/25 unit, 3/3 UI pass |
| Same | iPhone 16 Pro simulator, iOS 18.5 | 25/25 unit, 3/3 UI pass |
| App in live mode, two accounts against local Supabase | — | Not run: the local stack ran in the Linux container, which the Mac simulator cannot reach |
| Physical fold in Bitrig's 3D Duo simulator | — | Not run |

Screenshots: `design/screenshots/integration/iphone-flow.jpg` and `iphone-states.jpg`, contact sheets of the UI-test captures from the iOS 18.5 run of the final tree.

Earlier rounds, for the record: before the redesign merge, an iPhone 17 Pro on iOS 27.0 passed 25/25 unit and 3/3 UI tests, and the old composer's UI tests could not focus its message field on the Duo (a test-tap issue on empty editor lines, moot after the redesign).

## Security review

Scope: RLS, storage policies, SECURITY DEFINER functions, idempotency, logging, and realtime exposure. Probed empirically on the local stack with throwaway users. Confirmed sound: all eight SECURITY DEFINER functions pin `search_path = ''` with no grants to `PUBLIC` or `anon`; identity always comes from `auth.uid()`; RLS policies compare columns with `auth.uid()` (no recursion); postcards are immutable; idempotency holds under concurrency via unique keys.

| Severity | Finding | Status |
|---|---|---|
| Medium | A signed upload URL issued with `upsert: true` before sending (valid 2 h, runs as the storage superuser) could replace a sent photo | **Fixed** in `20260926000500_protect_sent_photos.sql` with an e2e test that reproduces the attack |
| Low | `sender_name` is client-supplied free text, so the displayed sender name can be spoofed (`sender_id` is always correct) | Open: derive it from the sender's profile on the server, or show the peer profile name |
| Low | A U+0000 in message text fails JSON parsing, and Postgres logs part of the body | Open: clients should strip NUL; documented in `backend/README.md` |
| Low | Realtime publication included deletes, not filtered by RLS | **Fixed** in `20260926000600_realtime_insert_only.sql` |
| Info | Anonymous realtime subscribers see event timing, not content | Accepted for v1; private channels would close it |
| Info | Kong logs signed-URL tokens (query string) | Accepted; URLs expire in 5 minutes |
| Info | Local minimum password was 6 | Set to 8 in `supabase/config.toml` (applies on next `supabase start`) |

## Unresolved blockers

1. **App UI in live mode is unverified.** The adapter is verified live on Linux; the app has not been run against a backend.
2. **The hinge** has not been exercised on hardware or in Bitrig's 3D fold simulator with this build.
3. **Accessibility of the redesigned compose screen:** fixed-size fonts (no Dynamic Type) and no full VoiceOver pass yet. The UI tests log a non-fatal SwiftUI "Invalid frame dimension" warning while composing.
4. **Barrat's `PostcardComposerView`** is no longer used by the app (the compose screen is Zubair's `PostcardExperienceView`); decide whether to keep it in `PostcardUI`.
5. **Hosted Supabase** is not deployed; there is no authorization or credentials for it.

## Next steps for a live release

1. **Accessibility.** Give the compose screen Dynamic Type (relative font sizes) and a VoiceOver pass.
2. **Mac live run.** Start Supabase on the Mac (Docker Desktop) so the simulator can reach it.
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
