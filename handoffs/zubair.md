# Handoff — Zubair (`team/zubair`): iOS Duo interactions and app integration

## Status

**Implemented and building.** Native app shell, Duo presentation controller, session/compose/inbox/conversation view models, draft persistence, PhotosPicker + JPEG validation, configuration, and unit tests are on this branch under `ios/`. The app builds with Xcode 27.1 / iOS 27.1 SDK and runs on the iPhone Duo simulator in Bitrig in credential-free demo mode.

**Follow-up verification (2026-09-26).** Barrat's `team/barrat` branch is merged and the app now compiles against its real `PostcardUI` package. The Bitrig project build passed. `xcodebuild test -project Postcard.xcodeproj -scheme Postcard -destination 'platform=iOS Simulator,name=iPhone Duo' CODE_SIGNING_ALLOWED=NO` passed **21 app tests, 0 failures**, verified from `/private/tmp/postcard-zubair-barrat.xcresult`. Barrat's isolated form-rule suite passed **5 tests, 0 failures**. The hinge controller applies a debounced final close even when no later event arrives; manual actions cancel stale deferred events. Compose enables Send only after opening, keeps the submitted draft snapshot stable during the service call, and disables draft controls while sending. Conversation photos are downloaded by the app and passed as bytes to Barrat's view, with per-photo retry. SDK declaration inspection confirmed `onHingeChange` and `DeviceHinge` in the installed iOS 27.1 SwiftUICore interface. The Bitrig simulator inspection plugin could not read the running UI, but `simctl` captured the integrated auth screen at `/private/tmp/postcard-barrat-auth.png`.

**Remaining dependency.** `ios/project.yml` references `../packages/PostcardCore|PostcardServices|PostcardMotion|PostcardUI`. `PostcardUI` is now tracked from Barrat. Core, Services, and Motion are still local excluded contract stubs because Pranav's branch has not landed here. They are not competing production implementations. The integration agent must merge Pranav, remove the local stubs, and rebuild. The old local PostcardUI stub was preserved at `/private/tmp/postcardui-contract-stub-ff6f7ca` before the merge.

## Source

Branch `team/zubair`. Files (all new):

```
ios/project.yml                     XcodeGen spec: app target Postcard (iOS 27.1), test target PostcardAppTests, 4 local packages
ios/.gitignore                      generated xcodeproj/Info.plist, Local.xcconfig, DerivedData
ios/Config/Postcard.xcconfig        SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY (empty = fixture mode) + `#include? Local.xcconfig`
ios/Config/Local.xcconfig.example
ios/App/PostcardApp.swift           @main
ios/App/AppEnvironment.swift        composition root: fixture vs Supabase from configuration; owns controller + view models
ios/App/RootView.swift              auth / main routing, demo banner, hinge bridge attached here, suppression on auth busy, persist on background
ios/App/Screens/{Auth,Main,Inbox,Conversation,Compose}Screen.swift   mechanical wiring of Barrat's views to view models
ios/Platform/DevicePosture.swift    platform-neutral posture (unknown/closed/partiallyOpen(angle)/fullyOpen)
ios/Platform/HingePosture.swift     ONLY file touching the 27.1 hinge API: onHingeChange → DeviceHinge → DevicePosture
ios/Platform/Haptics.swift          HapticsPlaying protocol + SystemHaptics (UIKit generators)
ios/Platform/AppConfiguration.swift Info.plist → config
ios/Platform/DraftStore.swift       DraftStoring + FileDraftStore (Application Support, atomic, file protection)
ios/Platform/PhotoImporter.swift    JPEG conversion, ≤ 20 MP downscale, ≤ 10 MB recompress
ios/Features/Presentation/PostcardPresentationController.swift   the Duo controller (see below)
ios/Features/Session/SessionCoordinator.swift                     sign in / up / out / restore; email-confirmation state; UserFacingError mapping
ios/Features/Compose/ComposeViewModel.swift                       draft, lookup, photo import, the only send path
ios/Features/Inbox/InboxViewModel.swift                           conversations + realtime refetch loop with reconnect
ios/Features/Conversation/ConversationViewModel.swift             messages merged by UUID + signed photo URL resolution
ios/Tests/App/*.swift               XCTest (see results)
ios/README.md                       toolchain, build/run, demo/real mode, architecture, controller rules
```

## Public API / integration surface

- `AppEnvironment.bootstrap()` chooses `SupabasePostcardService(url:publishableKey:)` when config is present, else `FixturePostcardService(scenario: .standard)`. Both come from `PostcardServices`.
- Views are wired to Barrat's actual public initializers:
  - `PostcardComposerView(draft:, state:, error:, recipientLookupResult:, isLookingUpRecipient:, isDemo:, onLookupRecipient:, onSelectRecipient:, onChoosePhoto:, onOpen:, onSeal:, onSend:, onRetry:)`
  - `PostcardInboxView(conversations:, isLoading:, error:, isDemo:, onSelect:, onCompose:, onRefresh:)`
  - `PostcardConversationView(messages:, photoURLs:, photoData:, photoErrors:, isLoading:, error:, isDemo:, title:, onReply:, onRefresh:, onRetryPhoto:)`
  - `PostcardAuthView(isLoading:, error:, notice:, isDemo:, onSignIn:, onSignUp:)`
  - Barrat's refresh callbacks are synchronous, so the app launches a Task in each callback. The app resolves signed URLs and loads photo bytes; the view never performs networking.
- Motion: not called from app code; Barrat's views compose `PostcardFlipContainer`/`PostcardSealEffect`. The app passes `PostcardPresentationState` only.

## Duo controller (`PostcardPresentationController`)

Main-actor `@Observable`. Inputs: `receive(posture:at:)` from the hinge bridge, manual `open()`/`seal()`, and send lifecycle `beginSending()`/`sendSucceeded()`/`sendFailed()`/`resetForNewDraft()`.

- Initial posture only sets a baseline. Angle jitter with the same open/closed meaning is ignored.
- `front→writing` on open, `writing→sealed` on close, seal once (repeated closes are no-ops), `sealed→writing` on reopen, `sending`/`sent` ignore posture.
- 250 ms debounce between hinge transitions; deferred events re-sync to the physical posture when the window or suppression ends (quick reopen preserved).
- Suppression reasons: `.sending`, `.authenticating`, `.modal` (PhotosPicker), `.composerHidden`. Manual actions also respect suppression.
- Haptics: opened → light impact, sealed → medium impact, sent → success notification.
- Holds no `PostcardService`. `ComposeViewModel.send()` is the only caller of `send(draft:)`; guarded by `beginSending()` and a sent-draft set. Failure → `.sealed`, draft kept, same `draft.id` on retry. Success → clear stored draft; `startNewDraft()` rotates the id.

## Setup / configuration

See `ios/README.md`. Short form: `cd ios && xcodegen generate`, build with Xcode 27.1 (`~/Downloads/Xcode.app` on the dev Mac; `/Applications/Xcode.app` is 27.0). Demo mode needs no config. Real mode: `Config/Local.xcconfig` with `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` (Zafar: `supabase status`; demo users alice/bob/eve, password `postcard-local-1`).

## Commands and results (2026-09-26)

```
xcodegen generate                                                     → Postcard.xcodeproj
xcodebuild -scheme Postcard -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
                                                                      → ** BUILD SUCCEEDED ** (Swift 6, strict concurrency)
xcodebuild -scheme Postcard -destination 'id=<iPhone Duo 27.1>' test  → see "Tests" below
Bitrig 0.26.1 → open ios/ → iPhone Duo → Run                          → app boots in demo mode (screenshot: closed pose, auth screen)
```

Device APIs actually compiled and exercised: `onHingeChange`/`DeviceHinge` (status, angle), `ToolbarItem.axisBehavior`, `visibilityPriority`, `ToolbarOverflowMenu`. Vertical bars come from standard `NavigationStack` toolbars. The 27.1 simulator runtime on this machine is Duo-only (`iPhone 17 Pro` cannot be created on it), so tests run on an iPhone Duo simulator.

### Tests

`xcodebuild test` on iPhone Duo (iOS 27.1 simulator), latest integration run: **21 tests, 0 failures**.

- `PostcardPresentationControllerTests` (8): initial posture baseline; open→writing→sealed with seal-once on repeated closes; angle jitter ignored; rapid flap and deferred close; suppression while sending and while a modal is up; manual fallback; send lifecycle.
- `ComposeViewModelTests` (7): folding and manual open/seal never call `send`; explicit send once per submission; failed send keeps the same draft id for retry; validation and front-state send guard; recipient lookup; draft restoration.
- `PlatformTests` (6): draft round-trip with photo bytes; photo downscaling and garbage rejection; fixture configuration; posture mapping; conversation photo loading with retry error preserving the visible photo.

Not covered by automation: relaunch persistence on device (manual: draft survives kill/relaunch in the Duo simulator), realtime reconnect against a real adapter, UI screenshots.

## Dependencies and tested revisions

| Dependency | State at handoff | Tested against |
|---|---|---|
| `packages/PostcardCore` (Pranav) | not on `team/pranav` (assignment only, `origin/team/pranav`) | local contract stub |
| `packages/PostcardServices` (Pranav) | not landed | local stub: full `FixturePostcardService` (idempotent send, `.sendFailsOnce`/`.offline` scenarios, auto-reply for realtime), `SupabasePostcardService` that throws a clear "not integrated" error |
| `packages/PostcardMotion` (Pranav) | not landed | local stub flip/seal |
| `packages/PostcardUI` (Barrat) | merged from `origin/team/barrat` | real package; integrated app build and 21 app tests passed; Barrat's 5 form-rule tests passed |
| Backend (Zafar) | `origin/team/zafar` @ fixtures + migrations present | wire fixtures used to shape the fixture service; live mode untested (no adapter yet) |

## Unresolved blockers

1. A clean checkout still needs Pranav's three packages. The local build used excluded contract stubs for Core, Services, and Motion. I do not claim live service integration.
2. Live Supabase mode is unverified: the adapter is Pranav's. Configuration plumbing and mode switch are in place.
3. Realtime reconnect was exercised only against the fixture stream (auto-reply after send; stream cancellation on screen exit). Real reconnect behaviour depends on the adapter.
4. The integrated auth screen was captured on iPhone Duo at `/private/tmp/postcard-barrat-auth.png`. The Bitrig simulator inspection plugin returned “Failed to read the simulator state” three times, so compose/seal/send screenshots were not recaptured in this follow-up.

## Proposed contract changes

1. Barrat's additive `photoData`, `photoErrors`, `onRetryPhoto`, `notice`, and `isDemo` inputs are now wired. The shared contract should be updated during final integration; no shared contract file was edited here.
2. Agree with Zafar's proposal that a photo is required to send; the app already blocks Send without one.
3. App deployment target is iOS 27.1 (packages remain iOS 17). Rationale in `ios/README.md`; reversible by gating `HingePosture.swift` and the toolbar modifiers.

## Integration steps

1. Merge `team/pranav` so Core, Services, and Motion become tracked production packages; remove the excluded local stubs and rebuild. Barrat is already merged into this branch.
2. Verify Pranav's concrete service and motion initializers against the app and UI call sites.
3. `cd ios && xcodegen generate && xcodebuild … build && … test` with Xcode 27.1.
4. Demo: run on iPhone Duo in Bitrig, sign in as `alice@demo`, Write → look up `bob` → Photo → fold open/close (or Open/Seal) → Send → watch the inbox update ~4 s later.
5. Real mode: `Config/Local.xcconfig` from Zafar's `supabase status`; never a service-role key.
