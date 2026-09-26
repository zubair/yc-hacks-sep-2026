# Handoff — Zubair (`team/zubair`): iOS Duo interactions and app integration

## Status

**Implemented and building.** Native app shell, Duo presentation controller, session/compose/inbox/conversation view models, draft persistence, PhotosPicker + JPEG validation, configuration, and unit tests are on this branch under `ios/`. The app builds with Xcode 27.1 / iOS 27.1 SDK and runs on the iPhone Duo simulator in Bitrig in credential-free demo mode.

**Blocked on dependencies (by design).** `ios/project.yml` references `../packages/PostcardCore|PostcardServices|PostcardMotion|PostcardUI`. Those packages are owned by Pranav and Barrat and had not landed on their branches at the time of this handoff (both branches still contain only the assignment). To build and test my layer I used **local, uncommitted stub packages** that implement `docs/CONTRACTS.md` literally (same type names, protocol, initializers). They are excluded from git and are not a competing implementation. The integration agent should merge Pranav then Barrat, delete any local stubs, and rebuild.

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
- Views are consumed exactly as the contract lists them. Initializers I coded against (Barrat: confirm or I adapt in one file each):
  - `PostcardComposerView(draft: Binding<PostcardDraft>, presentation:, errorMessage:, recipientLookupResult:, isLookingUpRecipient:, onLookupRecipient:(String)->Void, onSelectRecipient:(PostcardProfile)->Void, onChoosePhoto:, onOpen:, onSeal:, onSend:, onRetry:)`
  - `PostcardInboxView(conversations:, isLoading:, errorMessage:, onSelect:(PostcardConversation)->Void, onCompose:, onRefresh: () async -> Void)`
  - `PostcardConversationView(messages:, photoURLs: [UUID: URL], currentUserId: UUID?, isLoading:, errorMessage:, onReply:, onRefresh: () async -> Void)` — `currentUserId` is an additive input I need for sent/received alignment.
  - `PostcardAuthView(isLoading:, errorMessage:, infoMessage: String?, onSignIn:(email, password), onSignUp:(email, password, username, displayName))` — `infoMessage` carries the email-confirmation state.
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

`xcodebuild test` on iPhone Duo (iOS 27.1 simulator), 2026-09-26: **18 tests, 0 failures**.

- `PostcardPresentationControllerTests` (7): initial posture baseline; open→writing→sealed with seal-once on repeated closes; angle jitter ignored; rapid flap debounced then re-synced; suppression while sending and while a modal is up, with quick reopen applied after; manual fallback mirrors hinge and respects suppression; send lifecycle (no double `beginSending`, sent cannot reopen, reset to front).
- `ComposeViewModelTests` (6): folding and manual open/seal never call `send`; explicit send sends exactly once per submission and rotates the draft id afterwards; failed send keeps the draft and retries with the same id; validation blocks send without touching the service; recipient lookup binds into the draft; draft restores from the store.
- `PlatformTests` (5): file draft store round-trips photo bytes; photo importer downscales a 24 MP image under 20 MP and 10 MB (found and fixed a screen-scale bug here: the renderer now uses scale 1); rejects non-images; configuration falls back to fixture mode when empty; posture mapping.

Not covered by automation: relaunch persistence on device (manual: draft survives kill/relaunch in the Duo simulator), realtime reconnect against a real adapter, UI screenshots.

## Dependencies and tested revisions

| Dependency | State at handoff | Tested against |
|---|---|---|
| `packages/PostcardCore` (Pranav) | not on `team/pranav` (assignment only, `origin/team/pranav`) | local contract stub |
| `packages/PostcardServices` (Pranav) | not landed | local stub: full `FixturePostcardService` (idempotent send, `.sendFailsOnce`/`.offline` scenarios, auto-reply for realtime), `SupabasePostcardService` that throws a clear "not integrated" error |
| `packages/PostcardMotion` (Pranav) | not landed | local stub flip/seal |
| `packages/PostcardUI` (Barrat) | not on `team/barrat` (assignment only) | local stub views with the initializers listed above |
| Backend (Zafar) | `origin/team/zafar` @ fixtures + migrations present | wire fixtures used to shape the fixture service; live mode untested (no adapter yet) |

## Unresolved blockers

1. No full-app build is possible from this branch alone until the four packages exist at `packages/`. I do not claim otherwise.
2. Live Supabase mode is unverified: the adapter is Pranav's. Configuration plumbing and mode switch are in place.
3. Realtime reconnect was exercised only against the fixture stream (auto-reply after send; stream cancellation on screen exit). Real reconnect behaviour depends on the adapter.
4. Screenshots of compose → open → seal → send were taken manually in Bitrig; there is no UI-test automation yet.

## Proposed contract changes

1. `PostcardConversationView` needs `currentUserId: UUID?` (additive) to align sent vs received cards.
2. `PostcardAuthView` needs `infoMessage: String?` (additive) for the email-confirmation state.
3. Inbox/Conversation `onRefresh` should be `() async -> Void` so it can back `.refreshable`.
4. Agree with Zafar's proposal that a photo is required to send; the app already blocks Send without one.
5. App deployment target is iOS 27.1 (packages remain iOS 17). Rationale in `ios/README.md`; reversible by gating `HingePosture.swift` and the toolbar modifiers.

## Integration steps

1. Merge `team/pranav` and `team/barrat` first so `packages/` exists; then merge this branch.
2. If Barrat's initializers differ from the list above, adjust only `ios/App/Screens/*.swift` (one call site each).
3. `cd ios && xcodegen generate && xcodebuild … build && … test` with Xcode 27.1.
4. Demo: run on iPhone Duo in Bitrig, sign in as `alice@demo`, Write → look up `bob` → Photo → fold open/close (or Open/Seal) → Send → watch the inbox update ~4 s later.
5. Real mode: `Config/Local.xcconfig` from Zafar's `supabase status`; never a service-role key.
