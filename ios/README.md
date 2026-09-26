# Postcard iOS app

Native SwiftUI app shell, Duo presentation controller, view models, draft persistence, and wiring for the four local packages. Zubair owns `ios/App`, `ios/Platform`, `ios/Features`, `ios/project.yml`, `ios/Config`, and `ios/Tests/App` (see `docs/OWNERSHIP.md`). The integration branch added `ios/Tests/UI`.

## Toolchain

| Item | Value |
|---|---|
| Xcode | 27.1 (27A9269) with the iOS 27.1 SDK. It is needed to compile the Duo APIs. On the dev Mac it is `~/Downloads/Xcode.app`; `/Applications/Xcode.app` there is 27.0 and cannot build the app. |
| Generator | XcodeGen 2.44 or later, reading `ios/project.yml`. The generated `Postcard.xcodeproj` and `App/Info.plist` are gitignored. |
| App deployment target | iOS 17.0, the same as the packages |
| Simulators | **iPhone Duo** on the iOS 27.1 runtime for hinge and vertical-bar behavior. Any other iPhone (for example iPhone 17 Pro) for the button path. |
| Bitrig | 0.26.1. It opens `ios/` in place, and its iPhone Duo simulator has Fold controls (Closed / Partially Open / Fully Open). |

### Duo APIs and availability gating

Every Duo API the app uses ships in the iOS 27.1 SDK (declared `anyAppleOS 27.1`; `visibilityPriority` is iOS 27.0):

- `onHingeChange` and `DeviceHinge`
- `ArrangementView` with `.split`
- `GeometryProxy.reservedRegions`
- `ToolbarItem.axisBehavior` and `visibilityPriority`
- `ToolbarOverflowMenu`

Each use is inside `if #available(iOS 27.1, *)` or an `@available(iOS 27.1, *)` declaration. Only `Platform/HingePosture.swift` touches the hinge API.

- **iOS 27.1 on a Duo:** unfolding the device opens the card and folding it seals the card. The compose screen is the postcard (`PostcardExperienceView`): open, its back is an `ArrangementView` split with the note on one side of the fold and the address on the other; toolbars use vertical bars.
- **Earlier iOS versions and ordinary iPhones:** the same controller is driven only by the **Open** and **Seal** buttons, with a standard navigation toolbar.
- **Every device:** folding never sends.

## Build and test

```sh
cd ios
xcodegen generate
export DEVELOPER_DIR=$HOME/Downloads/Xcode.app/Contents/Developer   # only if Xcode 27.1 is not xcode-select'ed

# Build
xcodebuild -project Postcard.xcodeproj -scheme Postcard -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# All tests (unit + UI) on the Duo simulator
xcodebuild -project Postcard.xcodeproj -scheme Postcard \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test

# One target only
xcodebuild ... test -only-testing:PostcardAppTests
xcodebuild ... test -only-testing:PostcardUITests
```

To check the button path, swap the destination for an ordinary iPhone, for example `'platform=iOS Simulator,name=iPhone 17 Pro'`.

Latest results (Xcode 27.1): iPhone Duo on iOS 27.1 and iPhone 16 Pro on iOS 18.5 each pass 25/25 unit and 3/3 UI tests.

| Target | Sources | Covers |
|---|---|---|
| `PostcardAppTests` | `Tests/App` | The presentation controller: baseline posture, open/seal-once, jitter, debounce and deferred close, suppression, and manual fallback. Compose semantics: folding never sends, one send per submission, failed send keeps the draft id, and validation guards. Draft persistence, photo import limits, configuration, posture mapping, and photo loading with retry. `IntegrationFixTests`: a sent draft is never persisted again, Try again re-sends only after a failed send, a new photo gets a new draft id, and account changes clear the previous account's data. |
| `PostcardUITests` | `Tests/UI` | The fixture flow through the real app: compose, open, seal, explicit send, then the recipient reads the note and photo. A failed send followed by Retry stores exactly one postcard. The offline inbox shows Retry and recovers. It launches with `-resetDemo -forceDemo` and attaches screenshots to the result bundle. |

Bitrig: **File → Open** the `ios/` folder, choose **iPhone Duo**, Run, then use the Fold controls beside the simulator.

## Demo mode (no credentials)

The app starts in fixture mode when `Config/Local.xcconfig` is absent or the `-forceDemo` launch argument is passed. It uses the in-memory `FixturePostcardService`, and every screen shows the demo label. Nothing leaves the device.

- The app starts signed in as **Alex Rivera** (`@alex`). The first demo draft is seeded (recipient Sam Lee, destination Cinque Terre; skipped under `-resetDemo`), and demo drafts get a bundled sample photo (`DemoPhoto` asset).
- Flow: **Write** → type `sam` → find → select **Sam Lee** → **Open** (or unfold the Duo) → write a note → **Seal** (or fold) → **Send**. Go back; the inbox lists Sam Lee.
- The **Demo** menu, in the inbox toolbar, appears only in fixture mode:
  - **View as Sam Lee / View as Alex Rivera** switches accounts, so one device shows both sides. Open Alex's conversation as Sam, then **Read their note**.
  - **Fail the next send** makes the next send fail. The draft and its id are kept; **Retry** stores the postcard once.
  - **Simulate offline / Go back online** makes the inbox fail with a retryable offline error, then recover.
- After you sign out, fixture sign-in uses the part of the email before `@`. `sam@…` signs in as Sam Lee; any other valid email signs in as Alex. The password must have at least 8 characters.

### Launch arguments

| Argument | Effect |
|---|---|
| `-forceDemo` | Fixture mode even when `Local.xcconfig` configures Supabase. UI tests always pass it, so they never reach a backend. |
| `-resetDemo` | Clears the stored draft at launch |

## Live mode (local Supabase)

```sh
# From the repo root, with a local stack running (see backend/README.md):
supabase status                                          # API URL and publishable key
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # gitignored
# Edit Local.xcconfig:
#   SUPABASE_URL = http:/$()/127.0.0.1:54321     ("//" starts a comment in xcconfig, hence $())
#   SUPABASE_PUBLISHABLE_KEY = <publishable key>
cd ios && xcodegen generate
```

Values flow from `Config/Postcard.xcconfig`, which includes `Local.xcconfig`, to Info.plist and then `AppConfiguration`. When both values are present, `AppEnvironment.bootstrap()` constructs `SupabasePostcardService(url:publishableKey:)`. Without a saved session, the app shows `PostcardAuthView`. Use the **publishable key only**, never a service-role or secret key. The example file already points at the local stack, so replace its placeholder key before building. The seeded local users are `alice@postcard.test`, `bob@postcard.test`, and `eve@postcard.test`, all with password `postcard-local-1`. If launch cannot reach the backend, the app shows a retryable "can't connect" screen and keeps the saved session and draft.

## Architecture

```
App/            PostcardApp → AppEnvironment (composition root: fixture vs Supabase, demo controls)
                → RootView (loading | Auth | Main | can't-connect) → NavigationStack: Inbox → Compose | Conversation
                Screens/ PostcardExperienceView (compose: front with inline username lookup, fold-spread back,
                         sealed), PostcardOrnaments; Inbox/Conversation/Auth wire PostcardUI views to view models
Platform/       DevicePosture, HingePosture (the only hinge API use), Haptics, AppConfiguration, DraftStore, PhotoImporter
Features/       PostcardPresentationController (Duo controller), SessionCoordinator, ComposeViewModel,
                InboxViewModel (realtime refetch + reconnect), ConversationViewModel (merge by UUID, signed URLs, photo bytes)
Tests/App/      PostcardAppTests
Tests/UI/       PostcardUITests
```

### Presentation controller rules (`Features/Presentation`)

- Inputs: `DevicePosture` from the hinge bridge, plus manual `open()` and `seal()`.
- The first posture event only sets the baseline. Angle jitter that does not change the open/closed meaning is ignored.
- Transitions:
  - `front → writing` on open.
  - `writing → sealed` on close. Repeated closes keep it sealed, so the card seals once.
  - `sealed → writing` on reopen.
  - `sending` and `sent` ignore posture.
- Hinge transitions are debounced by 250 ms. A deferred event re-syncs to the physical posture when the window or a suppression ends.
- Suppression reasons: `.sending`, `.authenticating`, `.modal` (PhotosPicker), and `.composerHidden`.
- Haptics: light on open, medium on seal, success on sent.
- The controller holds no `PostcardService`. `ComposeViewModel.send()` is the only caller of `send(draft:)`. It is guarded by `beginSending()` and a per-draft sent set. On failure the state returns to `.sealed` and the draft keeps its id. Recipient lookup errors go to `recipientLookupMessage`, never to the send error.

### Drafts and photos

- `FileDraftStore` writes `draft.json` to Application Support with complete file protection, 300 ms after each edit and immediately when the scene leaves the foreground. The file is cleared only after a confirmed send.
- Write and Reply resume an unsent draft that has content. Reply readdresses it to the peer unless it is sealed.
- `PhotosPicker` data goes through `PhotoImporter.makeJPEG`, which downscales to at most 20 MP and recompresses to at most 10 MB, or rejects the image.
- A photo is required: Send stays disabled without one, and the backend rejects a send with no photo.
