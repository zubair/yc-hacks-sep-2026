# Zafar — Supabase backend and direct messaging

Your branch is `team/zafar`. Read AGENTS.md and the three shared documents, then implement the backend from scratch. Own only the paths assigned to Zafar. Your consumer is Pranav's service adapter; your integration partner is Zubair. Barrat's frontend must never need a service-role key.

## Build

1. Scaffold a reproducible Supabase local project, ordered migrations, configuration, and a backend setup guide. Inspect available CLI/container tools before choosing commands. Missing hosted credentials must not block local development.
2. Implement Auth-linked profiles, canonical two-person conversations, membership, immutable postcard messages, sender-scoped idempotency, and the exact RPC responses in CONTRACTS.md.
3. Implement restrictive table RLS and private image storage policies. Validate ownership on every operation, concurrent pair creation, duplicate sends, and signed photo access. Explain and test SECURITY DEFINER grants and search_path where used.
4. Enable the required realtime publication. Supply fixtures and a seed approach using local test users only; keep seeds free of production credentials or personal data.
5. Document the direct messaging architecture: auth/session flow, upload-before-send, transaction boundary, retry semantics, receiving/reconnect, storage cleanup, and error mapping. Include a small architecture diagram if useful.
6. Supply exact request/response fixtures and setup examples for Pranav, and a migration/deployment checklist for the integration agent. Do not deploy to a hosted Supabase project without explicit authorization.

## Verify and finish

Use meaningful integration/database tests with at least three test identities: sender, recipient, and outsider. Verify unauthorized reads/writes/storage access fail; legitimate sender/recipient access succeeds; mismatched sender is rejected; invalid recipient/length/path fails; duplicate and concurrent retries create one message; realtime cannot expose outsider messages; orphan cleanup preserves sent images. Run locally when tools are available and report exact blockers otherwise. Write handoffs/zafar.md, commit, and push to team/zafar. Your final answer links the branch and handoff with passed checks and real limitations.
