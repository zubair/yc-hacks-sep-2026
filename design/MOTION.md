# Motion direction

Motion is a response to a deliberate action. It has no authority to send, persist, authenticate, or mark a message delivered.

| Moment | Choreography | Owner |
|---|---|---|
| Open / reopen | Photo rotates into the message back in 800 ms; smooth ease-in-out, no overshoot. Back stays readable, not mirrored. | Pranav's `PostcardFlipContainer`; Barrat composes it |
| Close & seal | Reverse the flip. Show the existing vermilion seal on the photo. Seal effect settles gently at the end; no repeated bounce. | Pranav's `PostcardSealEffect`; Barrat supplies seal artwork |
| Read received card | Same flip, initiated by a labeled button. Preserve the full message and card scroll position. | UI-local face selection, shared Motion implementation |
| Send | Host enters sending only after explicit tap. Disable editing and send controls; show progress. Confirmation appears only when the host reports success. | Zubair controls state; Barrat renders it |
| Error / offline | Keep the photo, note, and recipient. Show a calm inline explanation and retry. No shaking or destructive reset. | App supplies error; UI renders it |
| Press feedback | Instant 0.75 opacity on the pressed control; no spring or geometry movement. | Barrat |

## Reduce Motion

Pranav must read `accessibilityReduceMotion` in the shared components: replace 3D rotation with a 150–200 ms crossfade and remove scale/translation effects. Screen code introduces no repeating or automatic decorative animation. Busy progress is the standard system indicator. Do not connect completion handlers to business state.

## Layout and accessibility

Keep both faces within the available width. A 5,000-character message must remain fully reachable in a vertical scroll view; do not constrain the entire flip container to a fixed postcard height. The inactive face must be hidden from hit testing and VoiceOver (the UI applies both gates in addition to the shared component). Switching faces must not move focus into an invisible control. Keyboard focus is dismissed before sealing.

The composer switches from a vertical card/control stack to a horizontal arrangement at 760 points; accessibility text sizes always use the vertical stack. Photo composition crops to fill, but note text never crops. Avoid animating layout changes caused by the keyboard or Dynamic Type.

## Validation boundary

The included fixture motion module only selects a visible face and applies no seal animation. It verifies layout and callbacks, not 3D motion or runtime Reduce Motion. Final animation timing, interruption behavior, inactive-face accessibility, and Reduce Motion require Pranav's real package in the integrated app.
