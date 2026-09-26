# Postcard — fresh team workspace

A personal photo and message become a postcard: open to read, close to seal, explicitly send to another person. This repository has been reset to a shared brief and implementation contracts. No app or backend is implemented in this baseline.

## Give your AI agent this instruction

> Clone https://github.com/zubair/yc-hacks-sep-2026, check out MY_BRANCH, read AGENTS.md, and complete the assigned role prompt. Build, verify, commit, and push the work to that branch. Use local fixtures when credentials or another teammate's implementation are unavailable. Report what works and what remains blocked.

Replace MY_BRANCH with your branch below. AGENTS.md routes the agent to its full assignment.

| Person | Branch | Assignment |
|---|---|---|
| Zafar | `team/zafar` | [Supabase backend and direct messaging architecture](docs/agents/zafar.md) |
| Zubair | `team/zubair` | [iOS Duo interactions and app integration](docs/agents/zubair.md) |
| Pranav | `team/pranav` | [Client integrations and reusable animation implementation](docs/agents/pranav.md) |
| Barrat | `team/barrat` | [Frontend, visual design, and screen animation choreography](docs/agents/barrat.md) |
| Final integration agent | `integration/final` | [Combine and verify the four workstreams](docs/agents/integration.md) |

Start with [the product brief](docs/PRODUCT.md), [shared contracts](docs/CONTRACTS.md), and [file ownership](docs/OWNERSHIP.md). The default branch is `integration/final`. Work on the five assigned branches above. Each personal branch starts from the same clean baseline.

## Working together

Shared protocols, file ownership, and the wire format keep the work compatible. Each agent can implement and test its component against fixtures without waiting for another person. Only the final integration agent merges workstreams; contributors push to their assigned branches.

The old prototype, renders, and unrelated projects were deliberately removed from this fresh baseline. A local Git bundle was saved before the reset. A branch reset does not purge GitHub's retained commit objects or caches.
