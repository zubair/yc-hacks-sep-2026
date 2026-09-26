# Postcard iOS app (Zubair — `team/zubair`)

Native SwiftUI shell, Duo hinge controller, view models, persistence, and wiring for the four shared packages. Owned paths per `docs/OWNERSHIP.md`: `ios/App`, `ios/Platform`, `ios/Features`, `ios/project.yml`, `ios/Config`, `ios/Tests/App`.

## Toolchain (verified 2026-09-26)

| Item | Value |
|---|---|
| Xcode | 27.1 (27A9269), iOS 27.1 SDK. On this Mac it lives at `~/Downloads/Xcode.app`; `/Applications/Xcode.app` is 27.0 and lacks the Duo APIs |
| Simulator | iOS 27.1 runtime `24A94401`, device type **iPhone Duo** |
| Generator | XcodeGen 2.44 from `ios/project.yml` |
| Bitrig | 0.26.1, opens `ios/` in place and builds `Postcard.xcodeproj`; its Duo simulator has the Fold controls |

Duo APIs compiled in this target: `onHingeChange` / `DeviceHinge` (status + angle), `ToolbarItem.axisBehavior`, `visibilityPriority`, `ToolbarOverflowMenu`. The controller's posture behavior is covered by simulator unit tests; a physical hinge was not exercised. Layout is standard `NavigationStack` + toolbars, so bars go vertical on the outer display. Only `Platform/HingePosture.swift` touches the native hinge API.

**Deployment target decision.** Packages stay at iOS 17 per the contract. The app target is **iOS 27.1** because the product is a Duo launch app and the hinge, vertical-bar, and overflow APIs are 27.1-only; this removes every availability gate from app code. Lowering it later means gating `HingePosture.swift` and the toolbar modifiers with `#available(iOS 27.1, *)`; nothing else depends on 27.1.

## Build and run

```sh
cd ios
xcodegen generate                                   # writes Postcard.xcodeproj + App/Info.plist (both gitignored)
export DEVELOPER_DIR=$HOME/Downloads/Xcode.app/Contents/Developer   # only if 27.1 isn't xcode-select'ed
xcodebuild -project Postcard.xcodeproj -scheme Postcard -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Postcard.xcodeproj -scheme Postcard \
  -destination 'platform=iOS Simulator,name=iPhone Duo' CODE_SIGNING_ALLOWED=NO test
```

Bitrig: **File → Open** the `ios/` folder. Pick **iPhone Duo** in the device list, Run, then use the Fold controls (Closed / Partially Open / Fully Open) beside the simulator.

The app needs the four packages at `../packages/PostcardCore|PostcardServices|PostcardMotion|PostcardUI`. Barrat's `PostcardUI` is included on this branch. The other three still come from local, excluded contract stubs while Pranav's branch is pending; see `handoffs/zubair.md`. The current build does not verify live Supabase behavior.

## Demo mode (no credentials)

Leave `Config/Local.xcconfig` absent. The app boots `FixturePostcardService`, and each screen labels the demo and simulated send. Sign in as `alice@demo`, `bob@demo`, or `eve@demo` with any password. Flow: Write → look up `bob` → select → Photo → open the device (or tap Open) → write → close (or tap Seal) → **Send**. Sends are simulated in memory; ~4 s later the recipient "replies", which exercises the realtime refetch path in the inbox. Nothing leaves the device.

## Real mode

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # gitignored
# SUPABASE_URL = http:/$()/127.0.0.1:54321   ("//" is a comment in xcconfig, hence $())
# SUPABASE_PUBLISHABLE_KEY = <from `supabase status`>
xcodegen generate
xcodebuild -project Postcard.xcodeproj -scheme Postcard -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Values flow xcconfig → Info.plist → `AppConfiguration`. Publishable key only; never a service-role key. When configured, `AppEnvironment.bootstrap()` constructs `SupabasePostcardService(url:publishableKey:)` from PostcardServices.

## Architecture

```
App/            PostcardApp → AppEnvironment (composition root) → RootView → Auth | Main(NavigationStack: Inbox → Compose | Conversation)
Platform/       DevicePosture, HingePosture (onHingeChange bridge), Haptics, AppConfiguration, DraftStore, PhotoImporter
Features/       PostcardPresentationController (Duo controller), SessionCoordinator, ComposeViewModel, InboxViewModel, ConversationViewModel
Tests/App/      XCTest: controller, compose/send semantics, persistence, photo import, photo loading, configuration
```

### Presentation controller rules (`Features/Presentation`)

- Input: `DevicePosture` (from hinge or simulated) plus manual `open()` / `seal()`.
- First posture event only sets the baseline (initial posture never flips a card). Angle jitter with unchanged open/closed meaning is ignored.
- `front → writing` on open; `writing → sealed` on close; `sealed` stays sealed on repeated closes (seal once); `sealed → writing` on reopen.
- Debounce 250 ms between hinge transitions; a deferred event re-syncs to the physical posture when the window or suppression ends (quick reopen is not lost).
- Suppressed while: `.sending`, `.authenticating`, `.modal` (PhotosPicker), `.composerHidden` (not on the compose screen).
- Haptics: light on open, medium on seal, success on sent.
- The controller has no reference to `PostcardService`. `ComposeViewModel.send()` is the only caller of `send(draft:)`, guarded by `beginSending()` plus a per-draft sent set, so one submission = one send. Failure returns to `.sealed` with the draft intact and the same `draft.id` for the retry.

### Persistence

`FileDraftStore` writes `draft.json` (Application Support, complete file protection) 300 ms after each edit and immediately when the scene leaves the foreground. It is cleared only after a confirmed send. `startNewDraft()` rotates the id.

### Photos

`PhotosPicker` → `Data` → `PhotoImporter.makeJPEG`: downscales to ≤ 20 MP and recompresses to ≤ 10 MB (rejects if impossible). The fixture service and Zafar's backend both require a photo; Send is disabled without one.
