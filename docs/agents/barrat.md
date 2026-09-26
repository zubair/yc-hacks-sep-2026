# Barrat — frontend, visual design, and animation choreography

Your branch is `team/barrat`. Read AGENTS.md and the shared documents, then build the production SwiftUI frontend in packages/PostcardUI and the visual specifications/assets in design/. Own only your paths in OWNERSHIP.md. Zubair owns platform and application behavior; Pranav owns reusable animation mechanics and service packages; Zafar owns the backend.

## Build

1. Create the visual system: warm paper, deep green ink, vermilion stamp, legible typography, spacing, photo treatment, shadows, and accessible color contrast. Use an intentional postcard composition that works on narrow and unfolded layouts. Keep the image and personal message dominant.
2. Build PostcardComposerView, PostcardInboxView, PostcardConversationView, and PostcardAuthView with the state/callback boundaries in CONTRACTS.md. Include photo choice affordance, recipient lookup presentation (via app-provided state/callback additions documented for Zubair), message editing, front/back preview, seal, explicit send, retry, and sender/recipient displays. Document any needed additive initializer inputs in your handoff.
3. Implement loading, empty, error, offline, sending, and sent presentations, keyboard-visible editing, long-message scrolling, large type, VoiceOver labels/order, and clear disabled controls. Preserve typed content and provide an obvious path back to editing a sealed card.
4. Write design/MOTION.md specifying the front→back flip, seal appearance, transitions, easing, timing, and Reduce Motion alternatives. Compose Pranav's PostcardFlipContainer and PostcardSealEffect; do not duplicate the reusable 3D engine or trigger business actions from animation completions. Local decorative UI animation belongs here.
5. Supply previews/fixtures and reference images for front, writing, sealed, inbox, conversation, and auth, covering compact/wide layouts, keyboard and large-text cases. Use bundled original or appropriately licensed assets and document provenance. If shared packages are missing, use isolated previews/temporary validation worktrees rather than defining duplicate production Core/Motion types.
6. Write exact public initializer/callback examples and visual acceptance criteria so Zubair can wire the screens mechanically. Keep network, auth operations, hinge events, haptics, and persistence out of PostcardUI.

## Verify and finish

Build the UI package and inspect actual rendered previews/simulator screenshots where available. Check no clipped messages/buttons, visible keyboard editing, tap targets, Reduce Motion, and nonvisible postcard faces hidden from accessibility. Report any rendering/toolchain limitations. Write handoffs/barrat.md, commit, and push to team/barrat. Deliver functioning view code and assets, not only designs or instructions.
