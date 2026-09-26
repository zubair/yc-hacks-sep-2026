# Shared v1 contracts

This is the agreed implementation target, not an already-running service. Contributors implement it exactly or propose a change in their handoff. The integration agent resolves proposals before changing this document.

## Swift packages and types (Pranav owns)

Use Swift Package Manager, Swift 6 tools, iOS 17 minimum, and strict concurrency-safe boundaries. All models are public, Codable, Equatable, and Sendable where applicable. Swift member names are camelCase; decode JSON snake_case using explicit CodingKeys or a consistent strategy. IDs are UUID; timestamps are Date with ISO-8601 wire encoding. Storage paths are String, not permanently public URLs.

- `PostcardProfile`: id, username, displayName.
- `PostcardDraft`: id, recipientId (optional UUID), recipientName, senderName, destination, message, photoData (optional Data). Required nonoptional text fields default to empty. Draft id stays stable across retries; it is the idempotency key. On confirmed send, the app starts a new draft with a new id.
- `PostcardMessage`: id, conversationId, senderId, recipientId, senderName, recipientName, destination, message, photoPath, createdAt.
- `PostcardConversation`: id, peer (PostcardProfile), latestMessage (optional PostcardMessage), updatedAt.
- `PostcardPresentationState`: front, writing, sealed, sending, sent.
- `PostcardServiceError`: unauthenticated, forbidden, validation(String), offline, notFound, server(String).

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

## Backend (Zafar owns)

Supabase Auth authenticates each user. A profile uses the auth user's UUID; normalize usernames to lowercase, unique 3–30 characters `[a-z0-9_]`. Create profiles safely from signup metadata keys `username` and `display_name` with validation. Only the owner can edit their profile. An authenticated exact-username lookup RPC returns only id, username, and display_name. Never expose email in directory results.

Tables: `profiles`, `conversations` (one canonical pair of distinct users), `conversation_members`, `postcards`. Postcards contain all PostcardMessage fields plus a sender-scoped unique `client_request_id` for retries. Messages are immutable in v1. Enforce membership and sender identity in the database, including concurrent requests; an arbitrary client cannot add itself to a conversation or impersonate a sender. Store source-of-truth messages durably before realtime events.

Authenticated RPC endpoints, under `/rest/v1/rpc/`:

- `lookup_recipient`: `{p_username}` → profile object or null.
- `list_conversations`: `{}` → conversation objects with `peer` and `latest_message` matching the models above, newest first.
- `list_messages`: `{p_conversation_id, p_before, p_limit}` → message objects, newest first; null p_before means first page, limit clamped to 1–100. Use a consistent deterministic tie order and document timestamp pagination limitations.
- `send_postcard`: `{p_recipient_id, p_sender_name, p_recipient_name, p_destination, p_message, p_photo_path, p_client_request_id}` → one PostcardMessage object. Validate auth, known distinct recipient, owned uploaded image, lengths, and membership; create/find the pair and insert atomically. Concurrent retries by the same sender/key return the original message; reject conflicting payload reuse. Never mark a draft sent before this succeeds.

Return objects, not single-element arrays, for single-result RPCs. Use `auth.uid()` for identity, safe search_path for any SECURITY DEFINER function, and explicit execute grants. Avoid recursive RLS. Include the exact error-code mapping in backend documentation and fixtures for Pranav.

Photo bucket: private `postcard-photos`; path `<auth_user_id>/<draft_id>/photo.jpg`. Client converts picked images to JPEG and validates upload size (maximum 10 MB) and decoded dimensions (maximum 20 megapixels). Backend enforces bucket size/type plus ownership and validates that the referenced object exists. Document whether content-byte validation is implemented or pending; do not claim MIME policy checks validate image signatures. Upload once; on retry reuse an existing owned object at the same path. Do not enable overwrite of an already-sent photo. Only sender and recipient of a sent postcard can read its object; sender can access their unsent draft object. Signed URLs expire after at most 5 minutes. Document cleanup for unsent orphan uploads; never delete a sent photo during retry cleanup.

Text limits: message 1–5,000 characters, display names at most 100, destination at most 200. `photo_path` and authenticated identities are validated on the server. Keep personal message text and full access tokens out of logs.

Realtime: authenticated postgres_changes subscriptions on `postcards`, constrained by recipient/sender RLS. A received event identifies a conversation to refetch. Reconnect always refetches so dropped events do not lose messages. Clients merge by message UUID.

## UI boundary (Barrat owns; Zubair binds)

Provide public SwiftUI `PostcardComposerView`, `PostcardInboxView`, `PostcardConversationView`, and `PostcardAuthView`. Composer takes a Binding<PostcardDraft>, presentation state, optional user-facing error, recipientLookupResult (optional PostcardProfile), isLookingUpRecipient (Bool), and callbacks onLookupRecipient(String), onSelectRecipient(PostcardProfile), onChoosePhoto, onOpen, onSeal, onSend, onRetry. Keep typed lookup text local; the app performs lookup and binds the selected recipient into the draft. Reopening a sealed draft uses onOpen. Inbox takes conversations, loading/error inputs, and onSelect/onCompose/onRefresh callbacks. Conversation takes messages, resolved photo URLs keyed by message UUID, loading/error inputs, and onReply/onRefresh callbacks. Auth uses local form state and callbacks to sign in/sign up, plus loading/error inputs. Document exact public initializers in the handoff so app wiring is mechanical.

Views have no Supabase import, network calls, local persistence, hinge listeners, or app-global coordinator. Do not infer 'sent' from the animation finishing. Loading and failure must preserve visible content. Zubair resolves signed photo URLs and provides state to the views.

## Motion boundary (Pranav owns; Barrat composes)

Provide public `PostcardFlipContainer<Front: View, Back: View>` with `isOpen: Bool`, `duration: Double = 0.8`, and front/back ViewBuilder closures, plus a `PostcardSealEffect` ViewModifier with `isSealed: Bool`. Read accessibilityReduceMotion; replace 3D movement with a crossfade. No timers, delays, or completion callbacks that send or mutate business state. Keep tap targets and VoiceOver traversal correct; hide the nonvisible face from accessibility. Barrat specifies easing/spacing/visual direction in `design/MOTION.md`; Pranav implements reusable mechanics; Zubair decides when state changes.

## Duo controller (Zubair owns)

An observable main-actor controller consumes verified native hinge events and manual open/seal events, exposing PostcardPresentationState. Opening reveals writing, closing an opened card seals once. Suppress automatic transitions while signing in/sending or a modal is active, debounce repeated hinge events, and handle initial posture and quick reopen. Haptics belong to this layer. Opening/sealing never invokes PostcardService.send. Only the explicit Send action calls the service. Persist drafts across app relaunches.

## Configuration

Use `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` as shared configuration names. Zafar supplies local backend setup and an `.env.example` with placeholders. Zubair supplies ignored local app configuration and an example. Do not require real credentials for previews, fixtures, or unit tests.
