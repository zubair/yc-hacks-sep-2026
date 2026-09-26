# Postcard

Postcard turns a photo and a personal note into a direct postcard between two accounts. The iOS app supports exact-username recipient lookup, a photographic front and message back, manual open/seal controls, explicit sending, an inbox and conversations. A credential-free demo runs the same flow with simulated messages. Real mode uses Supabase Auth, private Storage, Realtime invalidation, and transactional RPCs.

This `team/pranav` branch contains an integrated app implementation following the request to complete the whole app. The original ownership plan remains in [docs/OWNERSHIP.md](docs/OWNERSHIP.md).

## Run the fixture demo

Requirements: Xcode 27.1 with the iOS 27.1 SDK and XcodeGen 2.46. On this machine the 27.1 Xcode app is in `~/Downloads/Xcode.app`. The app supports iOS 17 and later; Duo hinge input is available on iOS 27.1.

```sh
cd ios
xcodegen generate
DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer" xcodebuild \
  -project Postcard.xcodeproj -scheme Postcard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO build
```

Open the generated project in Xcode and Run. With no local configuration file, the app enters fixture mode and labels it `DEMO · simulated sends`. A generated sample travel photo is preselected. Start as Alex, search for `sam`, select Sam Lee, open the postcard, write a note, seal it, then tap **Preview sending**. Open Inbox and use **View as Sam** to see the recipient side. A send is simulated only after the send button is tapped. A failed send retains the same draft and request ID for retry.

The UI test runs this send and recipient-inbox flow:

```sh
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
cd ios
xcodegen generate
xcodebuild -project Postcard.xcodeproj -scheme Postcard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

For Duo, change the destination to `platform=iOS Simulator,name=iPhone Duo,OS=27.1`. The iOS 27.1 build uses Apple's `onHingeChange` events when available. An opening hinge reveals the message side; closing an opened draft seals it. The Open and Seal buttons work on every supported device, and folding never sends the postcard. Bitrig provides a 3D Duo simulator for physical fold checks.

The [iPhone](design/screenshots/iphone-17-pro-compose.png), [iPad](design/screenshots/ipad-mini-compose.png), and [Duo outer display](design/screenshots/duo-outer-compose.png) screenshots show the fixture compose screen. Barrat's [visual system](design/SYSTEM.md) and [reference screens](design/references/README.md) document the UI.

## Run against local Supabase

The app uses the [official Supabase Swift SDK](https://github.com/supabase/supabase-swift) pinned to 2.55.2. Docker and the Supabase CLI must be available. From the repo root:

```sh
SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io npx supabase start
npx supabase status
```

Use the local API URL and **anon/publishable** key from the CLI. Copy [LocalConfig.plist.example](ios/Config/LocalConfig.plist.example) to `ios/Config/LocalConfig.plist` and fill `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, then regenerate the Xcode project. This populated file is ignored by Git. Never put a service-role key in the app. Sign up with an email, password, lowercase username, and display name. When email confirmation is enabled, confirm the email before signing in. Use separate test accounts for a real local send and inbox check. A local simulator can reach `http://127.0.0.1:54321` on the host.

The [Supabase migrations](supabase/migrations) create auth-linked profiles, private two-person conversations, immutable postcards, sender-scoped idempotency, constrained RPCs, photo policies, and a Realtime publication. `send_postcard` stores the message and pair atomically. A client upload uses `<sender UUID>/<draft UUID>/photo.jpg`; retries reuse that path without overwriting the stored object. Signed photo URLs last five minutes. The app refetches on Realtime events, on foregrounding, and periodically while subscribed; it deduplicates displayed messages by UUID. See [backend/README.md](backend/README.md) for setup, wire fixtures, error mapping, and local tests.

To run the backend end-to-end suite against the local stack, install dependencies in `tests/backend`, then run `SUPABASE_PUBLISHABLE_KEY=<key from supabase status> npm test` there. The suite covers Auth, Storage, RPCs, RLS, retries, and Realtime.

## Architecture

| Area | Path | Purpose |
| --- | --- | --- |
| Shared types | `packages/PostcardCore` | Codable, Sendable wire models and error states |
| Client services | `packages/PostcardServices` | Shared protocol, deterministic fixture, Supabase adapter |
| Motion | `packages/PostcardMotion` | Reusable flip and seal effects |
| Screens | `packages/PostcardUI` | Compose, inbox, conversation, auth views |
| Native app | `ios` | Draft persistence, photo conversion, account and navigation state |
| Backend | `supabase` | Migration, RLS, Storage, RPCs, Realtime publication |

The app has no print, payment, public-link, push delivery, or read-receipt feature. `Sent` means persisted by the RPC, not delivered or read. [DuoStateController.swift](ios/Platform/DuoStateController.swift) maps both Apple hinge events and manual Open/Seal controls into the same state machine. [PostcardCoordinator.swift](ios/Features/PostcardCoordinator.swift) owns drafts, cancellation, inbox refresh, and session state.

## Current verification

- `swift test` passed for Core (1) and Services (5), including Zafar's recorded RPC responses and errors.
- The combined Xcode app builds for iPhone Duo on iOS 27.1. Eleven app tests and the iPhone 17 Pro simulator UI flow passed; the flow covers compose → send → recipient conversation, including the received note. Five shared UI package tests passed on the Duo simulator. The integrated app was captured on iPhone, iPad, and Duo displays.
- Zafar's branch reports 18 backend end-to-end checks passing against local Supabase. A fresh run on this machine was blocked by Docker's internal DNS failing to resolve Docker Hub; the Swift adapter was checked against Zafar's recorded fixtures.
- The native hinge API compiles and the posture state machine is tested. Physical fold input in Bitrig has not yet been verified with this integrated app.

See [handoffs/pranav.md](handoffs/pranav.md) for the exact implementation status and remaining integration checks.
