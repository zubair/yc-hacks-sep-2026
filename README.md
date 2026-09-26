# Postcard

Postcard turns a photo and a personal note into a direct postcard between two accounts. The iOS app supports exact-username recipient lookup, a photographic front and message back, manual open/seal controls, explicit sending, an inbox and conversations. A credential-free demo runs the same flow with simulated messages. Real mode uses Supabase Auth, private Storage, Realtime invalidation, and transactional RPCs.

This `team/pranav` branch contains an integrated app implementation following the request to complete the whole app. The original ownership plan remains in [docs/OWNERSHIP.md](docs/OWNERSHIP.md).

## Run the fixture demo

Requirements: Xcode 27, iOS 26.5 simulator, Swift 6.3, and XcodeGen 2.46. Earlier supported iOS versions can run the app, but the commands below were verified with iPhone 17 Pro on iOS 26.5.

```sh
cd ios
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Postcard.xcodeproj -scheme Postcard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO build
```

Open the generated project in Xcode and Run. With no Supabase build settings, the app enters fixture mode and labels it `DEMO · simulated sends`. A generated sample travel photo is preselected. Start as Alex, search for `sam`, select Sam Lee, write a note, Open, Seal, then tap Send. Open Inbox and use **View as Sam** to see the recipient side. A send is simulated only after the Send button is tapped. A failed send retains the same draft and request ID for retry.

The UI test runs this send and recipient-inbox flow:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ios
xcodegen generate
xcodebuild -project Postcard.xcodeproj -scheme Postcard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

## Run against local Supabase

The app uses the [official Supabase Swift SDK](https://github.com/supabase/supabase-swift) pinned to 2.55.2. Docker and the Supabase CLI must be available. From the repo root:

```sh
npx supabase start
npx supabase status
```

Use the local API URL and **anon/publishable** key from the CLI. Supply them as local Xcode build settings named `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`; never put a service-role key in the app. For command-line builds, pass those two settings to `xcodebuild`. Do not commit a populated configuration file. Sign up with an email, password, lowercase username, and display name. When email confirmation is enabled, confirm the email before signing in. Use separate test accounts for a real local send and inbox check. A local simulator can reach `http://127.0.0.1:54321` on the host.

The database migration is [202609260001_postcard.sql](supabase/migrations/202609260001_postcard.sql). It creates auth-linked profiles, private two-person conversations, immutable postcards, sender-scoped idempotency, constrained RPCs, photo policies, and a Realtime publication. `send_postcard` stores the message and pair atomically. A client upload uses `<sender UUID>/<draft UUID>/photo.jpg`; retries reuse that path without overwriting the stored object. Signed photo URLs last five minutes. The app refetches on Realtime events, on foregrounding, and periodically while subscribed; it deduplicates displayed messages by UUID.

For local SQL verification without Docker, [tests/backend/check.sh](tests/backend/check.sh) runs against a disposable PostgreSQL 17 database after [bootstrap.sql](tests/backend/bootstrap.sql) supplies test versions of the Supabase Auth and Storage schemas. It checks policy and RPC behavior but is not a substitute for the full Storage/Auth/Realtime service stack.

## Architecture

| Area | Path | Purpose |
| --- | --- | --- |
| Shared types | `packages/PostcardCore` | Codable, Sendable wire models and error states |
| Client services | `packages/PostcardServices` | Shared protocol, deterministic fixture, Supabase adapter |
| Motion | `packages/PostcardMotion` | Reusable flip and seal effects |
| Screens | `packages/PostcardUI` | Compose, inbox, conversation, auth views |
| Native app | `ios` | Draft persistence, photo conversion, account and navigation state |
| Backend | `supabase` | Migration, RLS, Storage, RPCs, Realtime publication |

The app has no print, payment, public-link, push delivery, or read-receipt feature. `Sent` means persisted by the RPC, not delivered or read. Duo hinge input is not wired because the installed iOS 27 SDK exposes no verified public hinge posture API; manual Open and Seal work on ordinary iPhones and the Duo simulator. [PostcardPostureController.swift](ios/Platform/PostcardPostureController.swift) is the narrow adapter point for a future documented device API.

## Current verification

- `swift test` passed for Core and Services on Swift 6.3.
- Xcode simulator build passed on iPhone 17 Pro, iOS 26.5.
- PostgreSQL 17 migration and role/RPC checks passed using the disposable local harness.
- Full Supabase service validation requires registry access for Docker images. On this machine, `public.ecr.aws` DNS lookups from Docker timed out while `supabase start` pulled images.

See [handoffs/pranav.md](handoffs/pranav.md) for the exact implementation status and remaining integration checks.
