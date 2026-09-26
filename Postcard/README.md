# Postcard

A native SwiftUI postcard demo: a photographic front, a personal message on the back, and a sealed postcard ready to share. Cream paper, dark green ink, and a vermilion stamp frame the experience.

## Demo in under a minute

1. Start on the Cinque Terre photo postcard.
2. Tap **Open your postcard** to reveal the back. Edit the message and recipient.
3. Tap **Close & seal** to return to the front with a love postmark and a haptic on supported hardware.
4. Tap **Send your postcard**. The exported image contains both the photo and the written back.
5. Choose **Share or save postcard** to use the system share sheet. On a device that supports Messages and image attachments, choose **Send with Messages**, select the recipient, and confirm in the composer.

**Play demo** automatically previews the front → back → sealed sequence. It does not send anything. Native hinge changes open the back and seal an open postcard when the device closes; adaptive layouts respond to available screen width. The on-screen controls provide the same sequence without changing the simulator posture.

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
