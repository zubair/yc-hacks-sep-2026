# Postcard

A native SwiftUI postcard demo: a photographic front, a personal message on the back, and a sealed postcard ready to share. Cream paper, dark green ink, and a vermilion stamp frame the experience.

## Demo in under a minute

1. Start on the Cinque Terre photo postcard.
2. Tap **Open your postcard** to reveal the back. Edit the message and recipient.
3. Tap **Close & seal** to return to the front with a love postmark and a haptic on supported hardware.
4. Tap **Send your postcard**. The exported image contains both the photo and the written back.
5. Choose **Share or save postcard** to use the system share sheet. On a device that supports Messages and image attachments, choose **Send with Messages**, select the recipient, and confirm in the composer.

**Play demo** automatically previews the front → back → sealed sequence. It does not send anything. Native hinge changes open the back and seal an open postcard when the device closes; adaptive layouts respond to available screen width. The on-screen controls provide the same sequence without changing the simulator posture.

## Native editor and publishing (feature/native-postcard-editor)

- **Editor:** pick your own photo, **Adjust framing** (drag, pinch or slider zoom, reset), then edit recipient (defaults to Grandma), sender, destination and message on the back. Fields scale with Dynamic Type, the message grows instead of scrolling in a box, and the keyboard has Done/Next.
- **Persistence:** draft JSON + photo JPEG in Application Support (`PostcardDraft.swift`). Survives relaunch. Launch with `-PostcardResetDraft` to start clean.
- **Fold flow:** a single `PostcardFlow` owns front → writing → sealed (hinge, buttons, Play Demo). It is the seam for Zabir's `DuoInteractionController`; swap the type and delete `PostcardFlow`. Folding and the demo never publish.
- **Publishing:** after sealing, **Publish & get link** uploads via `PostcardPublishing` (`PostcardPublishing.swift`), implementing the proposed `POST /api/postcards` multipart contract with `Idempotency-Key`. The button is disabled while uploading; failures keep the draft and offer **Try again** with the same key; editing content rotates the key and invalidates the old link. Success shows **Ready to share**, never "Delivered", and opens the link handoff (Messages composer when available, share sheet, copy). **Save or send as an image instead** keeps the old export/HTML path.
- **Backend config:** set `PostcardAPIBaseURL` (Info.plist / project.yml, or `-PostcardAPIBaseURL https://…`). Empty = **fixture publisher**, whose `https://postcard.example/p/…` links are labeled "Test link (fixture)" in the UI. `-PostcardFixtureMode offline|fail|slow` exercises error paths. No service credentials in the app; an optional user bearer token hook exists if Pranav requires auth.

### Open questions for the backend contract

1. Publisher authentication for native is unspecified. The client sends no auth unless a user token provider is injected.
2. Error body shape is unspecified. The client accepts `{error:{message}}`, `{error:"…"}` or `{message:"…"}`.
3. The client requires `url` to be HTTPS and the response to be `{ id, url }`; anything else is shown as an unexpected reply.
4. The photo is uploaded pre-framed (1600 px JPEG at 0.92 aspect). The server does no cropping.

## What sending actually does

- The simulator usually cannot send Messages. It displays that limitation and offers the real system share/save flow instead.
- A supported physical iPhone opens Apple's Messages composer with a PNG attachment and message text. The user confirms the recipient and send action. iMessage versus SMS/MMS is determined by Messages and the recipient's availability.
- Closing the postcard seals the draft; it does not silently send a message. Sent status is shown only when the Messages composer reports success. Share completion means the selected share action completed, not confirmed recipient delivery.
- The recipient written on the postcard is decorative content; the delivery recipient is selected in Messages.
- Printed-card ordering and payment are not implemented.

## Build

Requires Xcode 27.1 beta and its iOS simulator SDK. From this directory, generate the Xcode project if needed, then build:

```sh
xcodegen generate
DEVELOPER_DIR=/Users/barratm/Downloads/Xcode.app/Contents/Developer xcodebuild \
  -project Postcard.xcodeproj \
  -scheme Postcard \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

The beta Xcode path is local to this workspace; replace it if your Xcode beta lives elsewhere. For a physical-device run, configure your own signing team and enable signing in Xcode.
