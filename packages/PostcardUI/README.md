# PostcardUI

SwiftUI screens for iOS 17+, with local Swift package dependencies on `../PostcardCore` and `../PostcardMotion`. The app owns state, authentication, photo loading, persistence, networking, and device events. This package renders values and invokes callbacks.

## Integration

Add the local PostcardUI package to the iOS app and `import PostcardUI`. Embed screens in your NavigationStack. Wire the public initializers in the four `Sources/PostcardUI/*View.swift` files. Callback argument order for auth is sign-in `(email, password)` and sign-up `(email, password, username, displayName)`.

```swift
PostcardComposerView(
    draft: $model.draft,
    state: model.presentation,
    error: model.errorMessage,
    recipientLookupResult: model.lookupResult,
    isLookingUpRecipient: model.isLookingUpRecipient,
    recipientLookupMessage: model.lookupMessage,
    isDemo: model.isDemo,
    onLookupRecipient: model.lookupRecipient,
    onSelectRecipient: model.selectRecipient,
    onChoosePhoto: model.choosePhoto,
    onOpen: model.open,
    onSeal: model.seal,
    onSend: model.send,
    onRetry: model.retry
)
```

Those `model` names are an illustrative app-side adapter, not types supplied by this package. Closures are synchronous UI events; the app starts and cancels its own async tasks. Set `.sending` immediately when handling Send to prevent duplicate taps. The UI checks incomplete fields, but the app/backend must enforce authoritative validation and idempotency. Recipient result selection appears only when its exact username matches the current normalized search query.

Additional UI inputs beyond the original outline:

- All screens: `isDemo: Bool = false` shows a clear local-demo label and prevents misleading sent copy in the composer.
- Composer: `recipientLookupMessage: String?` renders no-match/error status from the app.
- Conversation: `photoData: [UUID: Data]`, `photoErrors: [UUID: String]`, and `onRetryPhoto(UUID)` let the app load/refresh signed resources without introducing a network client into views. Continue passing `photoURLs`; those describe availability. URL values alone do not download images. Supply image bytes after loading and update the dictionaries together. `title` is optional.
- Auth: `notice: String?` supports email confirmation and other non-error states. The view never assumes sign-up created a session.

The package uses both `PostcardFlipContainer(isOpen:duration:front:back:)` and `PostcardSealEffect(isSealed:)`. Actual motion is supplied by Pranav. See `design/MOTION.md` at repo root.

## Isolated validation while dependencies are pending

The examples contain explicitly labeled contract fixtures. They are excluded from the package target. Do not copy these fixture modules into the production `packages/PostcardCore` or `packages/PostcardMotion` directories.

Requirements: Xcode with an iOS simulator, Python 3, and XcodeGen.

```sh
python3 packages/PostcardUI/Examples/validate.py --output /tmp/postcard-ui-validation
cd /tmp/postcard-ui-validation
xcodebuild -project PostcardUIValidation.xcodeproj -scheme PostcardUIValidation \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -derivedDataPath build test
```

The generator copies source/tests into an isolated directory and creates framework targets plus a fixture app. It uses no credentials and links no backend. Screens menu selects each state; all sends are simulated. Launch arguments: `--screen front|writing|sealed|inbox|empty|conversation|auth`, `--large-text`, `--long-message`, and `--error`.

The harness's static motion substitute does not validate Pranav's animation. Once real packages land, build this Swift package and the actual app against their exact commits and repeat the accessibility/motion checks. The frontend intentionally has no PhotosPicker, auth session storage, URLSession, Supabase, or hinge API dependency.

Pure form rules can be checked without a simulator:

```sh
python3 packages/PostcardUI/Examples/test_rules.py
```

Open the generated `PostcardUIValidation.xcodeproj`, select the `PostcardUIValidation` scheme and your iPhone Duo device, then Run. Use your Duo-capable Xcode installation (set `DEVELOPER_DIR` for command-line builds). If the simulator runtime cannot boot, the same generated project supports the `My Mac (Mac Catalyst)` destination for reviewing the views; that does not validate iOS keyboard or hinge behavior. See `handoffs/barrat.md` for the actual validation results and remaining checks.
