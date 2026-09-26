# Rendered frontend references

Captured from the running PostcardUI fixture app on Mac Catalyst, September 26, 2026. Compact captures constrain the SwiftUI view to 390 points; they retain the desktop window height. Wide captures show the expanded layout. These are actual renders, not mockups, and are not screenshots from iPhone Duo. The Screens menu and send counter belong only to the example harness.

| Screen | Reference |
| --- | --- |
| Front | [Compact](front-compact.png) |
| Writing | [Compact](writing-compact.png), [Wide](writing-wide.png) |
| Sealed | [Compact](sealed-compact.png) |
| Inbox | [Compact](inbox-compact.png) |
| Received note | [Compact](conversation-back-compact.png) |
| Sign in | [Compact](auth-compact.png) |

Open, Seal, and Send occupy a fixed bottom safe-area inset. The content above scrolls independently. The example motion module switches faces statically; use the production motion package for animation acceptance.

iOS keyboard-visible, accessibility text, and actual Duo folded/unfolded captures remain pending because the simulator runtime failed boot. The fixture app exposes Accessibility text and screen-selection controls, and the UI test suite includes these scenarios. Repeat on a working Duo runtime before calling device verification complete.
