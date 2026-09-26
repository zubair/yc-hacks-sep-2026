# Barrat handoff — Postcard frontend

Branch: `team/barrat`. Scope: only `packages/PostcardUI/`, `design/`, and this handoff.

## Delivered

Four controlled SwiftUI screens: composer, inbox, conversation, and authentication. Includes a shared paper/ink/vermilion visual system, native text input, exact-username recipient selection, front/back composition, sealed state, explicit-send affordance, inline errors/retry, loading/empty states, email-confirmation notices, and a clearly labeled local demo. Composer input survives view-state changes because the draft binding belongs to the host.

The package uses the agreed PostcardCore properties and composes Pranav's `PostcardFlipContainer` and `PostcardSealEffect`. Barrat supplies the original stamp/seal artwork and choreography in `design/MOTION.md`; no alternative production flip engine is added.

## Integration for Zubair

1. Add the local PostcardUI package to the app; its sibling dependencies must be `packages/PostcardCore` and `packages/PostcardMotion`.
2. Embed screens in your NavigationStack. Public initializers are in the four `Sources/PostcardUI/*View.swift` files; the package README has a composer wiring example.
3. Bind the persisted draft and presentation state. The package requests open/seal/send/retry through callbacks. Set state to sending immediately on accepting Send; guard duplicate submission and maintain draft-id idempotency in the app/service. A seal callback never invokes send.
4. Supply exact-username lookup results and status. Selection sends the complete `PostcardProfile` back to the app; the app updates draft recipient id/display name. Results for a stale username are not selectable.
5. Supply photo data from PhotosPicker. The UI doesn't request photo permission, fetch network images, or persist files.
6. For conversations, supply `photoURLs` plus downloaded `photoData` keyed by message UUID. Report per-photo errors and wire `onRetryPhoto` to renew expired URLs/reload. Signing/downloading is owned by the app/service. No AsyncImage or URLSession is hidden in the UI.
7. Pass auth callbacks with positional arguments `(email, password)` and `(email, password, username, displayName)`. Supply `notice` for email confirmation and `error` for failures. The screen does not assume signup creates a session.
8. Set `isDemo` accurately. UI success means backend storage succeeded, never proof of recipient delivery/read.

## Additive contract proposals

No shared contract files were changed. Accept these public initializer additions during integration:

- `isDemo: Bool = false` on every screen.
- `recipientLookupMessage: String? = nil` on composer for no-match/failure feedback.
- Conversation `photoData: [UUID: Data] = [:]`, `photoErrors: [UUID: String] = [:]`, `onRetryPhoto: (UUID) -> Void`, and optional `title`. Required because the shared contract gives URLs while also forbidding view-owned networking.
- Auth `notice: String? = nil` for confirmation state.

## Validation approach

Pranav's remote branch contained only assignment documents when implementation began. The `Examples/ContractFixtures` modules are deliberately isolated and excluded from the production package target. They supply minimal interface models and a static face selector, not real services or animation. `Examples/validate.py` generates an isolated Xcode project in /tmp without modifying anyone else's owned paths.

Validation on September 26, 2026:

- `python3 packages/PostcardUI/Examples/test_rules.py`: 5 tests passed, 0 failures (draft guards, limits, username normalization, signup validation).
- The actual Swift package built for a generic iOS Simulator against isolated sibling contract fixtures.
- The generated harness built successfully for generic iOS Simulator with Xcode 27.1 and for Mac Catalyst with Xcode 27.0, including the final fixed bottom composer actions.
- Manual Mac Catalyst checks: editing survives seal/reopen; opening and sealing keep send count at zero; explicit send increments it once and removes Send; inbox opens the received card; Read their note exposes the complete message; empty sign-in displays validation. Compact and wide layouts were visually inspected.
- Actual runtime reference images: `design/references/README.md`. These are Mac Catalyst captures, not Duo screenshots.
- iPhone Duo / iOS 27.1 failed system startup with `Data Migration Failed` after `Waiting on BackBoard`. Installation and UI tests could not complete. Restarting the virtual device and the per-user CoreSimulator service did not resolve it. No device data was erased.

The committed UI test suite contains open/seal/send, keyboard/draft retention, receiving, signup confirmation, large type, offline retry, and wide-layout checks. Those UI tests have NOT passed yet: simulator boot blocked execution. Keyboard-visible iOS layout, full VoiceOver operation, and actual Duo folding remain unverified. Do not treat fixture builds as live integration success.

## Known integration limits

The real Core/Motion packages, app model, Supabase delivery, runtime Reduce Motion behavior, and hardware hinge transitions still need the team integration pass. The fixture test target uses a Codable model shape for setup; align its fixture decoder if Pranav chooses different CodingKeys. The UI source accesses model properties only and does not assume Core initializers.

The frontend intentionally uses a light paper palette in both system appearances. There is no separate dark palette. Backend length/authorization checks remain authoritative. The demo image is documented in design/ASSETS.md.
