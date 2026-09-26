# Zubair handoff — Postcard iOS app

## Delivered

- `ios/project.yml`: iOS 17 Swift 6 app and test targets with references to all four sibling packages.
- `ios/App/`: entry point, fixture/real service selection, native tab and navigation shell, PhotosPicker presentation, view callback wiring, visible fixture label.
- `ios/Platform/`: availability-gated iOS 27.1 hinge listener, open/seal/send state controller, haptics, atomic local draft storage, JPEG conversion and validation.
- `ios/Features/PostcardCoordinator.swift`: main-actor observable session and screen state, exact-username lookup, draft preservation, explicit idempotent send/retry/cancel, inbox and conversation loads, signed photo URL resolution, realtime invalidation and reconnect refetch.
- `ios/Tests/App/`: state machine, persistence, auth, retry/cancel, and reconnect tests.

## Verified locally

- Xcode 27.1 / iOS 27.1 SDK and iPhone Duo simulator are installed. The installed SwiftUICore interface declares `DeviceHingeContext`, `DeviceHinge.Status`, and `onHingeChange` at iOS 27.1.
- App sources and tests, including two iOS photo conversion tests, typecheck for an iOS 17 deployment target against the 27.1 SDK with temporary modules shaped exactly like the shared contracts. This found and removed an iOS 18-only tab API call.
- Nine isolated Swift Testing tests pass on macOS using the app-owned controller, store, and coordinator plus temporary contract-shaped fixture modules. These fixtures live under `/private/tmp`, not in the repository.
- `plutil -lint` passes for both checked-in plist files; `git diff --check` passes.

This does **not** establish a full app build or live backend behavior. As of this work, `team/pranav` and `team/barrat` contain no package source, and XcodeGen is not installed here. A simulator screenshot is pending those dependencies.

## Configuration

Fixture mode is the default without `ios/Config/LocalConfig.plist`. The app labels simulated sends visibly. For real mode, copy the checked-in example to that ignored file and provide `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Regenerate the project after the local file is present. Never place a service-role key in the iOS app.

## Integration steps

1. Merge `packages/PostcardCore`, `packages/PostcardServices`, and `packages/PostcardMotion` from Pranav, then `packages/PostcardUI` from Barrat. Keep the package and type names in `docs/CONTRACTS.md`.
2. Confirm the concrete `FixturePostcardService()` and `SupabasePostcardService(url:publishableKey:)` initializers. If Pranav publishes different documented constructors, adapt only `ios/App/AppRuntime.swift`.
3. Confirm Barrat's public initializer labels for `PostcardComposerView`, `PostcardInboxView`, `PostcardConversationView`, and `PostcardAuthView`. The app's expected labels and callback shapes are in `ios/App/PostcardRootView.swift`; adapt that one file if needed.
4. Run XcodeGen on `ios/project.yml`, build and test the Postcard scheme in the iPhone Duo simulator, and capture screenshots of compose, sealed, sent, and recipient inbox. Exercise the Fold controls manually, plus narrow layout, Dynamic Type, VoiceOver, and Reduce Motion.
5. With local publishable configuration, check email-confirmation signup, exact-username lookup, photo upload, durable send/retry, signed URL refresh, and realtime reconnect against Zafar's backend. Do not send a real user message as a test.

## Contract notes

No shared contract edits were made. `PostcardDraft()` is expected to create a fresh UUID and empty text fields, and `PostcardMessage`/`PostcardProfile` are expected to have public member initializers used by the app tests. The fixture service should provide a signed-in local profile and deterministic send/inbox behavior to complete the credential-free demo. A send success creates a new draft ID and leaves `.sent` visible for the confirmation view. Cancellation and failure keep the old draft ID for idempotent retry.
