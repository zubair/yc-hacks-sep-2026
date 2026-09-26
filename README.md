# Postcard

Postcard is an iOS app for sending a photo and a short note to someone you know, presented as a postcard. You look up a recipient by exact username, choose a photo for the front, and write on the back. Opening the card starts writing and closing it seals the card. Sending is always an explicit tap. The recipient reads the postcard in their inbox.

On the iPhone Duo (iOS 27.1), unfolding the device opens the card and folding it seals the card. On any other iPhone running iOS 17 or later, **Open** and **Seal** buttons do the same. Folding never sends.

The backend is Supabase: Auth, a private Storage bucket, transactional RPCs, and a Realtime refetch signal, all under row-level security. A credential-free fixture mode runs the complete flow on the device with simulated sends.

Scope: direct account-to-account postcards. "Sent" means stored by the backend, not delivered or read. Printed cards, payments, public links, push notifications, and read receipts are out of scope for v1 (see [docs/PRODUCT.md](docs/PRODUCT.md)).

## 60-second demo (fixture mode, no credentials)

1. Generate the project and open it: `cd ios && xcodegen generate && open Postcard.xcodeproj`. Choose the **iPhone Duo** simulator or any iPhone simulator, then Run. Without `ios/Config/Local.xcconfig`, the app runs in fixture mode and labels every screen as a demo.
2. The app opens signed in as **Alex Rivera** with an empty inbox.
3. Tap **Write**, type `sam`, find the user, and select **Sam Lee**. A bundled sample photo is already on the front.
4. Tap **Open**, or unfold the Duo in Bitrig, and write a note on the back.
5. Tap **Seal**, or fold the Duo. Nothing has been sent yet.
6. Tap **Send**. The composer shows the sent state, and the postcard is stored in the in-memory fixture.
7. Go back. The inbox lists Sam Lee.
8. Choose **Demo → View as Sam Lee**, open the Alex Rivera conversation, and tap **Read their note**. The photo and note appear.
9. Optional: **Demo → Fail the next send** shows the error and Retry path, which stores the postcard exactly once. **Demo → Simulate offline** shows the retryable offline inbox.

The `PostcardUITests` target runs the same flow automatically; see [ios/README.md](ios/README.md).

## Setup

Requirements:

- **iOS:** Xcode 27.1 with the iOS 27.1 SDK. Xcode 27.0 cannot compile the Duo APIs.
- **Project generator:** XcodeGen 2.44 or later.
- **Backend:** Docker, the Supabase CLI (tested with 2.118.0), and Node 20 or later.
- **Package tests on macOS or Linux:** a Swift 6 toolchain.

### iOS app

```sh
cd ios
xcodegen generate
export DEVELOPER_DIR=$HOME/Downloads/Xcode.app/Contents/Developer   # only if Xcode 27.1 is not xcode-select'ed

xcodebuild -project Postcard.xcodeproj -scheme Postcard -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# PostcardAppTests and PostcardUITests
xcodebuild -project Postcard.xcodeproj -scheme Postcard \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

To test the button fallback, use an ordinary iPhone destination, for example `'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'`.

### Swift packages

```sh
(cd packages/PostcardCore && swift test)
(cd packages/PostcardServices && swift test)       # fixture + recorded wire-contract tests; live tests skip without env
(cd packages/PostcardUI && xcodebuild -scheme PostcardUI \
   -destination 'platform=iOS Simulator,name=iPhone Duo' test)   # iOS-only package
python3 packages/PostcardUI/Examples/test_rules.py              # form rules, no simulator
```

### Local Supabase backend

```sh
# From the repo root. Use docker.io if public.ecr.aws is blocked.
SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io supabase start \
  -x imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
supabase db reset          # applies supabase/migrations and seeds local users alice/bob/eve
supabase status -o env     # API URL and publishable key

cd tests/backend && npm install
SUPABASE_PUBLISHABLE_KEY=<publishable key> npm test
```

### Live Swift contract test (local stack only)

`LiveSupabaseTests` runs `SupabasePostcardService` against the running local stack. It creates throwaway users, uploads, sends, reads, and checks realtime. It refuses any host other than `127.0.0.1` and `localhost`, and it also runs on Linux.

```sh
cd packages/PostcardServices
POSTCARD_LIVE_SUPABASE_URL=http://127.0.0.1:54321 \
POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY=<publishable key> \
swift test --filter LiveSupabaseTests
```

### App in live mode (local Supabase)

```sh
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # gitignored
# Edit: SUPABASE_URL = http:/$()/127.0.0.1:54321   and   SUPABASE_PUBLISHABLE_KEY = <publishable key>
cd ios && xcodegen generate
```

Sign in as a seeded local user (`alice@postcard.test`, `bob@postcard.test`, or `eve@postcard.test`, password `postcard-local-1`), or sign up. Use two simulators or accounts to see both sides. `-forceDemo` keeps fixture mode even with this file present.

## Configuration

| Name | Where | Used by | Notes |
|---|---|---|---|
| `SUPABASE_URL` | `ios/Config/Local.xcconfig` (ignored), `backend/.env` (ignored) | App, backend tests | Empty or absent in the app means fixture mode |
| `SUPABASE_PUBLISHABLE_KEY` | same | App, backend tests | Publishable key only. It is the only key the app ever gets. |
| `SUPABASE_SECRET_KEY` | `backend/.env` (ignored) | `backend/scripts/cleanup-orphans.mjs` | Server jobs only. Never in the app, never committed. |
| `SUPABASE_DB_URL` | environment | `tests/backend` | Defaults to the local stack |
| `POSTCARD_LIVE_SUPABASE_URL`, `POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY` | environment | `LiveSupabaseTests` | Opt-in; local hosts only |
| `-forceDemo`, `-resetDemo` | launch arguments | App | Force fixture mode; clear the stored draft |

The committed `ios/Config/Postcard.xcconfig` has empty values and includes `Local.xcconfig`. Examples are in `ios/Config/Local.xcconfig.example` and `backend/.env.example`.

## Architecture

```
Swift packages (packages/, iOS 17+; arrows point at dependencies)
  PostcardCore       models, PostcardPresentationState, PostcardServiceError      (no dependencies)
  PostcardMotion     PostcardFlipContainer, PostcardSealEffect                    (no dependencies)
  PostcardServices ─▶ Core, supabase-swift 2.55.2
                     PostcardService protocol, SupabasePostcardService, FixturePostcardService
  PostcardUI ──────▶ Core, Motion
                     PostcardComposerView, PostcardInboxView, PostcardConversationView, PostcardAuthView
  ios/ app ────────▶ all four

App layers (ios/, iOS 17.0 target; Duo APIs gated on iOS 27.1)
  App/        PostcardApp → AppEnvironment (composition root: fixture | Supabase, demo controls)
              → RootView (loading | auth | main | can't-connect) → Inbox → Compose | Conversation
  Features/   SessionCoordinator · ComposeViewModel (the only send path) · InboxViewModel (realtime refetch)
              ConversationViewModel (merge by UUID, signed URLs, photo bytes)
              PostcardPresentationController (front → writing → sealed → sending → sent; never sends)
  Platform/   HingePosture (onHingeChange, 27.1-gated) · DraftStore · PhotoImporter · Haptics · AppConfiguration

Backend (supabase/, live mode)
  app ──publishable key + user JWT──▶ Supabase
    Auth        email/password; profile created from signup metadata (username, display_name)
    Storage     private postcard-photos/<uid>/<draft id>/photo.jpg, JPEG ≤ 10 MB, no overwrite
    RPC         lookup_recipient · list_conversations · list_messages · send_postcard (atomic, idempotent per draft id)
    Realtime    postgres_changes INSERT on postcards → app refetches the conversation
    Postgres    profiles · conversations · conversation_members · postcards (immutable), all under RLS
```

The contracts are in [docs/CONTRACTS.md](docs/CONTRACTS.md). The backend design and error mapping are in [backend/README.md](backend/README.md). App internals are in [ios/README.md](ios/README.md). The visual system is in [design/SYSTEM.md](design/SYSTEM.md) and [design/MOTION.md](design/MOTION.md).

## Team ownership

| Owner | Paths | Delivered |
|---|---|---|
| Zafar | `supabase/`, `backend/`, `tests/backend/` | Schema, RLS and storage policies, RPCs, realtime publication, 18 end-to-end tests, recorded wire fixtures |
| Pranav | `packages/PostcardCore/`, `packages/PostcardServices/`, `packages/PostcardMotion/` | Shared models, Supabase adapter, fixture service, flip and seal motion |
| Barrat | `packages/PostcardUI/`, `design/` | Four screens, visual system, accessibility, motion choreography, assets |
| Zubair | `ios/` (App, Platform, Features, Config, Tests/App, project.yml) | App shell, Duo presentation controller, view models, draft persistence, photo import, Duo layouts |
| Integration | root docs, `docs/CONTRACTS.md`, `ios/Tests/UI`, cross-cutting fixes | Merges, contract reconciliation, stub removal, availability gating, demo controls, live contract test |

The details are in `handoffs/<owner>.md` and [handoffs/integration.md](handoffs/integration.md).

## Verification status

Results marked `TBD` are to be filled in by the integration lead from actual runs. Fixture success does not prove live integration.

| Suite | Environment | Result |
|---|---|---|
| Backend end-to-end (`tests/backend`, 18 tests) | Local Supabase, CLI 2.118.0, Linux container | 18/18 pass |
| Backend end-to-end with the security-fix migrations (`…000500`, `…000600`) and the new overwrite test | Local Supabase | TBD |
| `PostcardCore` `swift test` | TBD | TBD |
| `PostcardServices` `swift test` (fixture and wire contract) | TBD | TBD |
| `PostcardServices` `LiveSupabaseTests` | Local Supabase, Linux | TBD |
| `PostcardUI` package tests | iPhone Duo simulator | TBD |
| `PostcardUI` form rules (`test_rules.py`) | Python 3 | TBD |
| App build (Xcode 27.1, generic iOS Simulator) | TBD | TBD |
| `PostcardAppTests` | iPhone Duo, iOS 27.1 | TBD |
| `PostcardUITests` (fixture flow, retry, offline) | iPhone Duo, iOS 27.1 | TBD |
| `PostcardUITests`, button fallback | iPhone, iOS earlier than 27.1 | TBD |
| App live mode, two-account send and receive | Local Supabase | TBD |
| Physical fold in Bitrig 3D Duo simulator | Bitrig | TBD |
| Hosted Supabase | none | Not deployed |

## Screenshots

Captures of the integrated app go in `design/screenshots/integration/`. Planned captures (TBD):

- `inbox-empty.png`: fixture inbox with the demo label
- `compose-front.png`: recipient selected, sample photo on the front
- `compose-writing.png`: the open card with the note on the back
- `compose-sealed.png`: the sealed card with Send enabled
- `compose-sent.png`: the sent state
- `recipient-conversation.png`: Sam's view of the received postcard and note
- `send-failed.png`: a send error with Retry and the draft preserved
- `offline-inbox.png`: the offline inbox with Retry
- `duo-inner-split.png`: iPhone Duo inner display with the compose stage
- `iphone-buttons.png`: an ordinary iPhone with the Open and Seal buttons

Earlier captures in `design/screenshots/*.png` and `design/references/` predate the final app shell.

## Known limitations

- **Duo hardware:** the hinge path is unit-tested through the controller, and the APIs compile against the iOS 27.1 SDK. A physical fold has not been validated on hardware, or in Bitrig's 3D simulator with this integrated build.
- **Hosted Supabase:** not deployed. Live mode has been exercised only against a local stack. Deploying requires separate authorization; see "Next steps" in [handoffs/integration.md](handoffs/integration.md).
- **Security review:** one medium finding is in progress. A signed upload URL created before send could overwrite the sent photo; the fix is migration `20260926000500_protect_sent_photos.sql` plus a backend test. Realtime is also being limited to inserts (`20260926000600`). The remaining low and informational notes are listed in the integration handoff.
- **Not built:** push notifications, read receipts, printing, payments, and public links.
- **No pagination UI.** A conversation shows the newest 50 messages. The RPC supports `p_before`, but messages that share the boundary microsecond can be skipped.
- **Photos:** the server checks bucket size and declared MIME type, not image bytes or pixel dimensions; the client enforces 10 MB and 20 MP. Signed photo URLs expire after 5 minutes, and the app requests fresh ones on refresh.
- **Signup:** an invalid or taken username fails with a generic Auth error from GoTrue, so the client pre-validates `^[a-z0-9_]{3,30}$`. The local stack allows 6-character passwords; hosted projects should require 8 or more.
- **Layout:** the app target is iPhone only (device family 1). The palette is light paper in both appearances.
- **Fixture data:** two accounts (Alex and Sam) and one conversation, all in memory. Demo messages reset on relaunch; the draft persists unless the app is launched with `-resetDemo`.
