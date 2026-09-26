# Ownership and dependencies

| Owner | Exclusive implementation paths | Responsibility |
|---|---|---|
| Zafar | `supabase/`, `backend/`, `tests/backend/`, `handoffs/zafar.md` | Database, migrations, RLS/storage policies, RPCs, auth/messaging architecture, backend tests |
| Zubair | `ios/App/`, `ios/Platform/`, `ios/Features/`, `ios/project.yml`, `ios/Config/`, `ios/Tests/App/`, `ios/README.md`, `handoffs/zubair.md` | App entry, coordinator/view models, dependency injection, draft persistence, PhotosPicker integration, authentication/inbox wiring, Duo controller, build configuration |
| Pranav | `packages/PostcardCore/`, `packages/PostcardServices/`, `packages/PostcardMotion/`, `tests/contracts/`, `handoffs/pranav.md` | Shared Swift types, Supabase client adapter, fixtures, network/realtime behavior, reusable motion components |
| Barrat | `packages/PostcardUI/`, `design/`, `handoffs/barrat.md` | Screen views, controls, typography, assets, responsive layouts, accessibility, screen animation choreography |
| Final integration agent | Cross-cutting integration after the four handoffs | Merge and reconcile, root docs/contracts, final build/test/demo, resolve wiring and compatibility issues |

## How the work fits

Zafar implements the wire contract. Pranav implements the Swift protocol and maps it onto that wire contract. Zubair injects the service into observable view models, handles platform events, and wires Barrat's screens. Barrat's screens expose callbacks and render value inputs; they do not perform network or hinge operations. Pranav supplies reusable motion; Barrat specifies how it should feel and uses it in the screen composition. Zubair owns state transitions so animation completion cannot accidentally trigger send.

Dependency direction: `PostcardCore` has no UI or service dependency; `PostcardServices` depends on Core; `PostcardMotion` is independent SwiftUI; `PostcardUI` depends on Core and Motion; App depends on all four packages. Use local Swift package paths under `packages/`. Package deployment target is iOS 17 or later; new Duo APIs must be availability-gated against the inspected SDK. The App may raise its target if a verified SDK requires it and must document the decision.

Each contributor can inspect the other branches but edits only owned paths. For dependent code that has not landed, use local test fixtures or a temporary worktree combining dependency commits; do not copy duplicate production types into your branch. Record the dependency and tested commit in the handoff. The integration agent merges Pranav first, then Zafar, Barrat, and Zubair to establish dependencies before the app build.
