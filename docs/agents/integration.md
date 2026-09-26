# Final integration — assemble the complete Postcard app

Your branch is `integration/final`, the intended repository default (the owner must select it in Settings if that change is still pending). Read AGENTS.md and all shared contracts, then inspect the four remote personal branches and their handoffs. Your job is to combine implemented work into a working app, resolve compatibility issues, verify the end-to-end experience, and push the integrated result. Never report the planning baseline as a completed product.

## Collect and integrate

1. Fetch origin and record each contributor's exact commit. Read handoffs/zafar.md, handoffs/zubair.md, handoffs/pranav.md, and handoffs/barrat.md from their branches. A missing handoff or branch that only has the starting assignment means implementation is not ready; identify it explicitly. Integrate whatever is ready while tracking missing work.
2. Work in a clean checkout/worktree on integration/final. Merge origin/team/pranav, origin/team/zafar, origin/team/barrat, then origin/team/zubair using merge commits so provenance remains visible. Do not force-push or alter personal branches. Resolve conflicts by preserving each owner's contribution and the agreed contracts; document deliberate contract adjustments.
3. Reconcile package paths/targets, exact model/protocol names, RPC JSON/errors, Supabase configuration, authentication states, UI callback signatures, signed photo loading, animation state binding, and verified Duo availability gates. Fix cross-cutting wiring and missing integration glue within this branch.
4. Review RLS/storage/privileged function behavior and idempotency before live mode. Real messages are not sent during validation. Use local Supabase test users and deterministic fixture mode. Never commit or request production credentials merely to make the fixture demo work.
5. Run component tests, contract tests, local backend tests if available, a simulator app build, and the complete fixture flow. Exercise sign-in/setup state, recipient selection, compose→open→seal→explicit send, recipient inbox, image loading, long messages, failure/retry, duplicate send prevention, reconnect, Reduce Motion, and ordinary-device fallback.
6. Verify the same flow against local Supabase when tooling permits. Mark production configuration, device-only behavior, and any unrun tests explicitly. Do not silently substitute fixture success for real backend verification.

## Deliver

Update the root README with exact setup/demo commands, configuration, architecture, team ownership, screenshots of the actual app, test results, and remaining limitations. Write handoffs/integration.md with integrated contributor SHAs, fixes, commands/results, and unresolved blockers. Commit and push integration/final; verify its remote SHA. Do not claim complete until all four workstreams are integrated and required checks pass, or clearly report the concrete missing components if they are not yet available. No hosted deployment or real-user messaging without separate authorization.
