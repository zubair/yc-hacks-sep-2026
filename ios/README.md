# Postcard iOS app

This is the integrated iOS app using the shared Core, Services, Motion, and UI packages. `project.yml` generates the Xcode project with XcodeGen. The minimum deployment target is iOS 17.

## Demo

With no `Config/LocalConfig.plist`, the app runs with `FixturePostcardService`. It starts as Alex, includes a sample photo, and can look up Sam by the exact username `sam`. Write a note, open the postcard, close and seal it, then explicitly tap **Preview sending**. In the Inbox, tap **View as Sam** to see the received postcard and its photo. The app labels this as a simulated send; no network message is sent.

## Live service

Copy `Config/LocalConfig.plist.example` to `Config/LocalConfig.plist` and fill in `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Run `xcodegen generate` again so the file is included as a resource. The file is ignored by Git. Use a publishable or anon key, never a service-role key. An incomplete configuration selects demo mode.

`PostcardCoordinator` owns session state, exact username lookup, explicit sending and retry, inbox refresh, conversation state, and signed photo downloads. It requests fresh photo URLs on conversation refresh, foregrounding, and every four minutes while a conversation is open. Failed photo downloads have a retry action. `LocalDraftStore` saves the draft atomically, including the photo, in Application Support. `PostcardPhotoProcessor` converts selected photos to JPEG and enforces a 20-megapixel and 10 MB limit.

`DuoStateController` maps Apple's iOS 27.1 hinge events and manual controls to the same front → writing → sealed → sending → sent flow. Folding never sends. On ordinary iPhones and older iOS versions, the Open and Seal buttons provide the same experience.

## Build and test

Use Xcode 27.1 and XcodeGen 2.46 or later:

```sh
cd ios
xcodegen generate
xcodebuild -project Postcard.xcodeproj -scheme Postcard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO test
```

See the [root README](../README.md) for backend setup and verification status.
