# Zubair — iOS Duo interactions and app integration

Your branch is `team/zubair`. Read AGENTS.md and the shared documents, then build the native application shell and platform integration from scratch. Own App, Platform, Features, project/configuration files, and app tests per OWNERSHIP.md. Pranav owns shared models/services/motion; Barrat owns view packages; Zafar owns backend.

## Build

1. Inspect installed Xcode and simulator SDKs and official platform docs before using Duo APIs. Generate the app with ios/project.yml (XcodeGen). Reference the four sibling local packages. No invented hinge API. If a Duo SDK is unavailable, create a protocol-backed manual/simulated posture provider and clearly document what remains hardware-specific.
2. Build main-actor observable coordinators/view models and dependency injection. Fixture mode must run without credentials and be visibly labeled. Real mode requires SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY through ignored local configuration.
3. Implement the Duo state controller per CONTRACTS.md, supported haptics, manual open/seal fallback, modal/sending guards, repeated-event handling, and stable draft preservation. Folding must never invoke send.
4. Integrate PhotosPicker with JPEG conversion, image size/dimension validation, and local draft persistence. Wire authenticated recipient lookup, composer, inbox/conversation, signed photo URL resolution, explicit sending/retry, sign-in/sign-up/sign-out, and realtime subscription lifecycle through PostcardService.
5. Wire Barrat's view callbacks and Pranav's packages. If dependencies have not landed, build/test your isolated controller and view models using test fixtures; do not add competing production service/UI implementations. A temporary validation worktree may combine their commits without merging your personal branch.
6. Document simulator setup, credential-free demo commands, real-mode configuration, and which device APIs were actually compiled and exercised.

## Verify and finish

Test initial/repeated/rapid hinge events, open→seal, modal/sending suppression, manual fallback, cancel/retry, preserved draft across relaunch, authentication transitions, realtime reconnect, and one explicit send per submission. Run the available build/simulator checks and capture actual app screenshots once dependencies are ready. Do not claim a full app build if dependency packages are still missing. Write handoffs/zubair.md, commit, and push to team/zubair, describing exact remaining integration dependencies.
