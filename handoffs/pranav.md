# Integrated Postcard implementation on `team/pranav`

## Status

This branch integrates Zafar's Supabase migrations and service contract, Zubair's native iOS app and Duo state controller, Barrat's SwiftUI screens and visual system, and the shared Core and Motion packages. The app runs without credentials in fixture mode and supports live Supabase configuration. No hosted Supabase project or App Store release was changed.

## App flow

In demo mode, Alex starts with a sample photo, looks up `sam`, writes and seals a postcard, and explicitly previews sending. The fixture stores the message only after that tap. **View as Sam** switches the demo profile so the recipient can open the conversation, load the photo, and read the note. The app labels simulated sends. In live mode, the app uses Supabase Auth, exact-username lookup, private photo Storage, transactional `send_postcard` RPC, signed photo URLs, and Realtime invalidation.

`PostcardCoordinator` owns session and conversation state, draft persistence, explicit send/retry/cancel behavior, photo download and retry, and foreground refresh. `DuoStateController` maps manual and native iOS 27.1 hinge changes to the same front → writing → sealed → sending → sent flow; folding does not send. `LocalDraftStore` saves drafts atomically. Selected photos are converted to JPEG with 20-megapixel and 10 MB limits. The UI screens use Barrat's `PostcardStyle` and component package.

## Configuration

XcodeGen 2.46 generates `ios/Postcard.xcodeproj`; Xcode 27.1 supplies the Duo SDK and simulator. `packages/PostcardServices/Package.swift` pins Supabase Swift 2.55.2. Copy `ios/Config/LocalConfig.plist.example` to ignored `LocalConfig.plist` and set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` for live mode. Use a publishable or anon key, never a service-role key. Missing or placeholder values keep the app in demo mode.

## Verification

- Core: 1 Swift package test passed. Services: 5 Swift package tests passed against the shared models and Zafar's recorded RPC wire fixtures.
- UI: 5 iOS package tests passed on the iPhone Duo simulator.
- App: 11 integration and unit tests plus the compose → send → recipient inbox UI test passed on iPhone 17 Pro iOS 26.5.
- The integrated app built against the iOS 27.1 SDK for iPhone Duo. It was launched and captured on iPhone 17 Pro, iPad mini, and iPhone Duo simulators; captures are in `design/screenshots`.
- Zafar's handoff reports 18 local Supabase end-to-end checks. A fresh run on this machine could not start the local stack because Docker's internal DNS could not resolve Docker Hub. The live service was therefore not validated against a running Supabase instance here.
- The native Duo hinge API is wired and the state machine has tests. A physical fold event in Bitrig's 3D simulator was not validated with this integrated app.

## Follow-up for a live release

Configure a Supabase project, apply the migrations, run the backend end-to-end suite against it, and test a real two-account send and photo receipt. Confirm a physical Duo fold transition in Bitrig with this project. Signed URLs expire after five minutes; the app requests fresh URLs on refresh and while a conversation is open. The current conversation request is capped at 100 messages and has no pagination UI.
