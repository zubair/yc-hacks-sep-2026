# Postcard iOS app

This is the `team/zubair` app layer. It depends on four sibling Swift packages owned by other workstreams: `PostcardCore`, `PostcardServices`, `PostcardMotion`, and `PostcardUI`. The packages are referenced by `project.yml`; they are not copied into this branch.

## Build and demo

With those packages present, generate the Xcode project from `ios/project.yml` using XcodeGen, then build the Postcard scheme in Bitrig. The minimum deployment target is iOS 17. The installed Xcode 27.1 SDK contains `onHingeChange` and the iPhone Duo simulator. On iOS 27.1, Duo posture events open and seal a draft; on older iOS versions and ordinary iPhones, the Open and Seal buttons use the same controller. Only a tap on Send calls `PostcardService.send`.

With no local configuration file, `AppRuntime` selects `FixturePostcardService` and displays **Demo data · sends are simulated** above the app. The fixture service must provide a local profile, recipient, and inbox flow for the complete credential-free demo. No real message is sent in fixture mode.

## Real service configuration

Copy `Config/LocalConfig.plist.example` to `Config/LocalConfig.plist` and replace both placeholders with `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Generate the project again after adding the file so XcodeGen includes it as a bundle resource. The local file is ignored by Git. The publishable key belongs in the app; a service-role key does not. If the file is absent or still contains a placeholder, the app starts in demo mode.

## App behavior

- `PostcardCoordinator` owns the authenticated session, recipient lookup, draft, explicit send and retry, inbox, conversation, signed photo URLs, and realtime subscription lifecycle. A foreground reconnect refetches durable conversations and messages. An open conversation refreshes signed photo URLs every four minutes.
- `DuoStateController` owns front → writing → sealed → sending → sent transitions and haptics. It ignores repeated posture events and suppresses fold transitions while authentication or a modal is active. Folding never sends.
- `LocalDraftStore` saves the Codable draft atomically in Application Support. A revision prevents an older delayed save from replacing a newer one. Backgrounding flushes the current draft.
- `PostcardPhotoProcessor` checks decoded dimensions before conversion, converts PhotosPicker data to JPEG, and rejects output above 10 MB or 20 megapixels.

The app shell binds the four views specified in `docs/CONTRACTS.md`. The dependency owners must confirm their concrete service constructors and public view initializer labels against the call sites in `AppRuntime.swift` and `PostcardRootView.swift` during integration.

## Current verification boundary

The app and test Swift files typecheck against the iOS 27.1 SDK using temporary contract-shaped package modules. Nine isolated state, persistence, authentication, retry, cancellation, and reconnect tests pass on macOS with temporary fixture modules. Two iOS photo tests typecheck and await the simulator run. The actual sibling packages and XcodeGen binary are not present in this checkout, so a full app build, simulator screenshot, and live Supabase test remain for integration.
