# Pranav — client integrations and reusable animations

Your branch is `team/pranav`. Read AGENTS.md and the shared documents, then implement PostcardCore, PostcardServices, and PostcardMotion as separate local Swift packages. Own only your paths in OWNERSHIP.md. This is client integration: Zafar owns backend SQL/RPCs, Zubair owns app wiring/platform actions, Barrat owns screen composition and visual direction.

## Build

1. Implement all shared Codable/Sendable models, errors, and the exact PostcardService protocol in CONTRACTS.md. Supply well-documented initializers and fixture data. Keep Core independent of SwiftUI and Supabase.
2. Implement an injectable real Supabase adapter and a deterministic fixture adapter. Select and pin a compatible official Swift Supabase SDK after checking its current documentation. Map JSON fields, timestamps, RPC errors, and authentication accurately. Email-confirmation-required signup is an explicit UI state, not assumed sign-in.
3. Implement private image upload, signed URL resolution, send idempotency using draft.id, recipient lookup, inbox/messages, and authenticated realtime invalidation. Upload retries must reuse an owned existing image without overwriting a sent photo. Keep secrets out of code and logs.
4. Implement session lifecycle, cancellation/unsubscribe, offline/retry handling, reconnect/refetch, and deduplication by message UUID. Do not imply realtime receipt is a read or delivery acknowledgment.
5. Implement PostcardFlipContainer and PostcardSealEffect exactly as the shared boundary describes. Honor Reduce Motion and accessibility. Keep effects reusable, deterministic, and independent of networking, hinge APIs, haptics, and send completion. Apply Barrat's design/MOTION.md when available; document temporary visual defaults when it is not.
6. Supply adapter contract tests against Zafar's response fixtures and clear package usage examples for Zubair/Barrat. If backend code is not ready, use committed HTTP/RPC fixtures matching the agreed wire contract and mark live tests pending.

## Verify and finish

Test JSON round-tripping, auth/validation error mapping, upload/send retries, stable idempotency key, duplicate events, stream cancellation, reconnect, signed URL expiry refresh, and fixture success/failure states. Use meaningful tests rather than tests that repeat constants. Build packages on the available toolchain and verify SwiftUI motion in previews/simulator if possible. Write handoffs/pranav.md with public API examples and exact dependency versions, commit, and push to team/pranav.
