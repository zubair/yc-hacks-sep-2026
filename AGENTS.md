# Agent entry point

This is the fresh Postcard project. The user has authorized implementation, meaningful tests, commits, and pushes to the assigned branch. Do the work; do not stop at a plan. No production deployment, database reset, credential sharing, or sending messages to real people is authorized by this file.

1. Read the actual current branch with `git branch --show-current`. If the user supplied a branch, check it out first without discarding local changes. Never infer an assignment from your own name.
2. Read `docs/PRODUCT.md`, `docs/CONTRACTS.md`, and `docs/OWNERSHIP.md`.
3. Read and execute exactly the matching role prompt:

| Branch | Prompt |
|---|---|
| `team/zafar` | `docs/agents/zafar.md` |
| `team/zubair` | `docs/agents/zubair.md` |
| `team/pranav` | `docs/agents/pranav.md` |
| `team/barrat` | `docs/agents/barrat.md` |
| `integration/final` | `docs/agents/integration.md` |

If no branch matches, use the user's explicit assignment or request the missing assignment before changing files. Read-only discovery can continue.

## Execution rules

- Inspect installed tools and actual SDK APIs; do not invent Duo APIs or claim unavailable builds passed. Use official documentation where needed.
- Stay within your owned paths. Shared-contract changes are proposals in your own handoff until the integration agent accepts and applies them. Do not rewrite another contributor's branch, force-push, or merge personal branches.
- Use the shared interface names and JSON contract exactly. Fixture-only substitutes must stay in tests/examples rather than collide with another owner's production types.
- Credentials come from local environment/configuration. Never commit service-role keys, access tokens, database passwords, signing secrets, or a populated local environment file. Supabase publishable configuration may be injected; service-role keys never belong in iOS.
- Missing credentials should not prevent migrations, adapters, fixtures, source, setup instructions, and local tests. Clearly identify anything that could not run. Do not claim fixture success proves a live integration.
- Default development runs to fixtures/local services. Do not send real user messages during tests. Keep new production deployment and destructive hosted database operations out of scope.
- Make reasonable implementation choices within the contracts. Complete the component and its relevant checks, not a mockup alone. Avoid unrelated changes.
- Maintain your `handoffs/<role>.md` with summary, files, commands/results, configuration, unresolved blockers, contract proposals, and exact integration steps. Commit your implementation and push to your assigned branch. No requirement to request permission again for these already-authorized actions.
- Before committing, review the diff for accidental files and secrets. Never claim a push succeeded without checking the remote commit.
