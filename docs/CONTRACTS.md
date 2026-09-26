# Shared v1 contracts

This is the implemented v1 wire and package contract. Recorded backend request and response examples are in `backend/fixtures/`.

## Swift packages and types (Pranav owns)

Use Swift Package Manager, Swift 6 tools, iOS 17 minimum, and strict concurrency-safe boundaries. All models are public, Codable, Equatable, and Sendable where applicable. Swift member names are camelCase; decode JSON snake_case using explicit CodingKeys or a consistent strategy. IDs are UUID; timestamps are Date with ISO-8601 wire encoding. Storage paths are String, not permanently public URLs.

- `PostcardProfile`: id, username, displayName.
- `PostcardDraft`: id, recipientId (optional UUID), recipientName, senderName, destination, message, photoData (optional Data). Required nonoptional text fields default to empty. Draft id stays stable across retries; it is the idempotency key. On confirmed send, the app starts a new draft with a new id. `photoData` is optional while editing, but a photo is required to send: the app disables Send without one and `send(draft:)` throws `.validation` if it is missing.
- `PostcardMessage`: id, conversationId, senderId, recipientId, senderName, recipientName, destination, message, photoPath (required String), createdAt. Backend timestamps have six fractional digits; clients preserve microseconds when decoding and sending `p_before`.
- `PostcardConversation`: id, peer (PostcardProfile), latestMessage (optional PostcardMessage), updatedAt.
- `PostcardPresentationState`: front, writing, sealed, sending, sent.
- `PostcardServiceError`: unauthenticated, forbidden, validation(String), offline, notFound, server(String).

Models, `PostcardPresentationState`, and `PostcardServiceError` live in `PostcardCore`. The `PostcardService` protocol and its two implementations live in `PostcardServices`.

`PostcardService: Sendable` async throwing methods:

```swift
func currentProfile() async throws -> PostcardProfile?
func signUp(email: String, password: String, username: String, displayName: String) async throws
func signIn(email: String, password: String) async throws
func signOut() async throws
func lookupRecipient(username: String) async throws -> PostcardProfile?
func conversations() async throws -> [PostcardConversation]
func messages(conversationId: UUID, before: Date?, limit: Int) async throws -> [PostcardMessage]
func send(draft: PostcardDraft) async throws -> PostcardMessage
func photoURL(path: String) async throws -> URL
func conversationUpdates() async throws -> AsyncThrowingStream<UUID, Error>
```

Sign-up may require email confirmation; the app must explain that state instead of pretending a session exists. Stream yields conversation IDs requiring refetch, not proof of delivery. Cancellation unsubscribes. Expose public concrete `SupabasePostcardService` and `FixturePostcardService` implementations from PostcardServices with documented construction. Fixtures implement the same protocol and deliberately model failure and retry.

Construction: `SupabasePostcardService(url:publishableKey:)` (sessions use the Keychain on Apple platforms and in-memory storage elsewhere; an internal `init(client:)` exists for tests) and `FixturePostcardService(signedIn: Bool = true)`. Fixture-only controls: `switchDemoUser()`, `failOneSend()`, `setOffline(_:)`. Fixture accounts are `alex` (Alex Rivera, sender) and `sam` (Sam Lee, recipient); fixture sign-in chooses `sam` when the email's local part is `sam`, otherwise `alex`, and requires a password of at least 8 characters.

## Backend (Zafar owns)

Supabase Auth authenticates each user. A profile uses the auth user's UUID; normalize usernames to lowercase, unique 3–30 characters `[a-z0-9_]`. Create profiles safely from signup metadata keys `username` and `display_name` with validation. Only the owner can edit their profile. An authenticated exact-username lookup RPC returns only id, username, and display_name. Never expose email in directory results.

Tables: `profiles`, `conversations` (one canonical pair of distinct users), `conversation_members`, `postcards`. Postcards contain all PostcardMessage fields plus a sender-scoped unique `client_request_id` for retries. Messages are immutable in v1. Enforce membership and sender identity in the database, including concurrent requests; an arbitrary client cannot add itself to a conversation or impersonate a sender. Store source-of-truth messages durably before realtime events.

Authenticated RPC endpoints, under `/rest/v1/rpc/`:

- `lookup_recipient`: `{p_username}` → profile object or null.
- `list_conversations`: `{}` → conversation objects with `peer` and `latest_message` matching the models above, newest first.
- `list_messages`: `{p_conversation_id, p_before, p_limit}` → message objects, newest first; null p_before means first page, limit clamped to 1–100. Use a consistent deterministic tie order and document timestamp pagination limitations.
- `send_postcard`: `{p_recipient_id, p_sender_name, p_recipient_name, p_destination, p_message, p_photo_path, p_client_request_id}` → one PostcardMessage object. `p_photo_path` is required and equals `<auth uid>/<p_client_request_id>/photo.jpg`. Validate auth, known distinct recipient, owned uploaded image, lengths, and membership; create/find the pair and insert atomically. Concurrent retries by the same sender/key return the original message; reject conflicting payload reuse. Never mark a draft sent before this succeeds.

Return objects, not single-element arrays, for single-result RPCs. Use `auth.uid()` for identity, safe search_path for any SECURITY DEFINER function, and explicit execute grants. Avoid recursive RLS. Include the exact error-code mapping in backend documentation and fixtures for Pranav.

RPC errors use `PT401`, `PT403`, `PT404`, `PT409`, and `PT422` as documented in `backend/README.md`; an anonymous gateway denial can use `42501`. The client maps these to `PostcardServiceError` without exposing internal details.

Photo bucket: private `postcard-photos`; path `<auth_user_id>/<draft_id>/photo.jpg`. Client converts picked images to JPEG and validates upload size (maximum 10 MB) and decoded dimensions (maximum 20 megapixels). Backend enforces bucket size/type plus ownership and validates that the referenced object exists. Document whether content-byte validation is implemented or pending; do not claim MIME policy checks validate image signatures. Upload once; on retry reuse an existing owned object at the same path. Do not enable overwrite of an already-sent photo. Only sender and recipient of a sent postcard can read its object; sender can access their unsent draft object. Signed URLs expire after at most 5 minutes. Document cleanup for unsent orphan uploads; never delete a sent photo during retry cleanup.

Text limits: message 1–5,000 characters, display names at most 100, destination at most 200. `photo_path` and authenticated identities are validated on the server. Keep personal message text and full access tokens out of logs.

Realtime: authenticated postgres_changes subscriptions on `postcards`, constrained by recipient/sender RLS. A received event identifies a conversation to refetch. Reconnect always refetches so dropped events do not lose messages. Clients merge by message UUID.

## UI boundary (Barrat owns; Zubair binds)

Provide public SwiftUI `PostcardComposerView`, `PostcardInboxView`, `PostcardConversationView`, and `PostcardAuthView`. Composer takes a Binding<PostcardDraft>, presentation state, optional user-facing error, recipientLookupResult (optional PostcardProfile), isLookingUpRecipient (Bool), and callbacks onLookupRecipient(String), onSelectRecipient(PostcardProfile), onChoosePhoto, onOpen, onSeal, onSend, onRetry. Keep typed lookup text local; the app performs lookup and binds the selected recipient into the draft. Reopening a sealed draft uses onOpen. Inbox takes conversations, loading/error inputs, and onSelect/onCompose/onRefresh callbacks. Conversation takes messages, resolved photo URLs keyed by message UUID, loading/error inputs, and onReply/onRefresh callbacks. Auth uses local form state and callbacks to sign in/sign up, plus loading/error inputs.

Accepted additive inputs (all defaulted, so the outline above still compiles):

- Every screen: `isDemo: Bool = false`. It shows the demo label and keeps composer copy from implying a real send.
- Composer: `recipientLookupMessage: String? = nil` for no-match and lookup-failure feedback. The app shows lookup problems here, not in `error`, so the composer's Retry never re-sends because of a lookup failure.
- Conversation: `photoData: [UUID: Data] = [:]`, `photoErrors: [UUID: String] = [:]`, `title: String = "Your correspondence"`, and `onRetryPhoto: (UUID) -> Void = { _ in }`. The app downloads photo bytes from signed URLs and passes them in; `photoURLs` alone does not load images.
- Auth: `notice: String? = nil` for email confirmation and other non-error states.

Exact public initializers:

```swift
PostcardComposerView(draft:state:error:recipientLookupResult:isLookingUpRecipient:recipientLookupMessage:isDemo:
                     onLookupRecipient:onSelectRecipient:onChoosePhoto:onOpen:onSeal:onSend:onRetry:)
PostcardInboxView(conversations:isLoading:error:isDemo:onSelect:onCompose:onRefresh:)
PostcardConversationView(messages:photoURLs:photoData:photoErrors:isLoading:error:isDemo:title:
                         onReply:onRefresh:onRetryPhoto:)
PostcardAuthView(isLoading:error:notice:isDemo:onSignIn:onSignUp:)   // onSignIn(email, password); onSignUp(email, password, username, displayName)
```

Callbacks are synchronous; the app starts and cancels its own tasks. Views have no Supabase import, network calls, local persistence, hinge listeners, or app-global coordinator. Do not infer 'sent' from the animation finishing. Loading and failure must preserve visible content. Zubair resolves signed photo URLs, downloads photo bytes, and provides state to the views.

## Motion boundary (Pranav owns; Barrat composes)

Provide public `PostcardFlipContainer<Front: View, Back: View>` with `isOpen: Bool`, `duration: Double = 0.8`, and front/back ViewBuilder closures, plus a `PostcardSealEffect` ViewModifier with `isSealed: Bool`. Read accessibilityReduceMotion; replace 3D movement with a crossfade. No timers, delays, or completion callbacks that send or mutate business state. Keep tap targets and VoiceOver traversal correct; hide the nonvisible face from accessibility. Barrat specifies easing/spacing/visual direction in `design/MOTION.md`; Pranav implements reusable mechanics; Zubair decides when state changes.

## Duo controller (Zubair owns)

An observable main-actor controller consumes verified native hinge events and manual open/seal events, exposing PostcardPresentationState. Opening reveals writing, closing an opened card seals once. Suppress automatic transitions while signing in/sending or a modal is active, debounce repeated hinge events, and handle initial posture and quick reopen. Haptics belong to this layer. Opening/sealing never invokes PostcardService.send. Only the explicit Send action calls the service. Persist drafts across app relaunches.

The app observes Apple's `onHingeChange` where iOS 27.1 is available. Build Duo support with Xcode 27.1; Bitrig's 3D simulator controls the Duo pose during manual testing. Earlier iOS versions retain the Open and Seal buttons.

Deployment and gating (accepted at integration): the app target is iOS 17.0, the same as the packages. The Duo APIs the app uses are declared `@available(anyAppleOS 27.1)` in the iOS 27.1 SDK: `onHingeChange`/`DeviceHinge`, `ArrangementView` with `.split`, `GeometryProxy.reservedRegions`, `ToolbarItem.axisBehavior`/`visibilityPriority`, and `ToolbarOverflowMenu`. Each use is inside `if #available(iOS 27.1, *)` or an `@available(iOS 27.1, *)` declaration. Only `ios/Platform/HingePosture.swift` touches the hinge API. On iOS 17 to 27.0 and on phones without a hinge, the same controller is driven only by the Open and Seal buttons, and the app uses a standard navigation toolbar.

Draft entry: Write and Reply resume an unsent draft that has content, and never discard it. Reply readdresses a resumed draft to the conversation peer unless the draft is sealed. A new draft, with a new id, starts only when the current one is blank or has just been sent.

## Configuration

Use `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` as shared configuration names. Zafar supplies local backend setup and an `.env.example` with placeholders. Zubair supplies ignored local app configuration and an example. Do not require real credentials for previews, fixtures, or unit tests.

- Backend: `backend/.env.example`. `SUPABASE_SECRET_KEY` is for server jobs only (orphan cleanup) and never goes into the app.
- App: `ios/Config/Postcard.xcconfig` (committed, empty values) includes the ignored `ios/Config/Local.xcconfig`, which is copied from `Local.xcconfig.example`. Values flow xcconfig → Info.plist → `AppConfiguration`. Both values present means live mode; otherwise the app runs in fixture mode.
- App launch arguments: `-forceDemo` forces fixture mode even when `Local.xcconfig` is configured. `-resetDemo` clears the stored draft at launch. UI tests always pass both, so they never reach a backend.
- Live Swift contract test: `POSTCARD_LIVE_SUPABASE_URL` and `POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY` opt in to `LiveSupabaseTests`. The test skips itself unless the host is `127.0.0.1` or `localhost`.

## Integration decisions (2026-09-26)

Proposals accepted from the contributor handoffs are folded into the sections above:

- A photo is required to send. `p_photo_path` equals `<auth uid>/<p_client_request_id>/photo.jpg` (Zafar, Zubair).
- RPC errors use `PT401`/`PT403`/`PT404`/`PT409`/`PT422` with stable hints (Zafar).
- Wire timestamps carry microseconds, and the clients preserve them (Zafar, Pranav).
- Barrat's additive UI inputs: `isDemo`, `recipientLookupMessage`, conversation `photoData`/`photoErrors`/`onRetryPhoto`/`title`, and auth `notice`.
- The app targets iOS 17.0 with gated Duo APIs. This replaces Zubair's proposed iOS 27.1 app target.
