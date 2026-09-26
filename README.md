# Postcard — YC Hackathon

Vintage travel postcards for iPhone Duo. Open `Postcard/` for the native app.

- [App setup and demo](Postcard/README.md)
- [Team assignments and copy/paste prompts](Postcard/TEAM_PROMPTS.md)
- [Visual references](design/)
- [Browser interaction demo](demos/postcard/index.html) — download/open locally; sending is a preview.

## Team branches

| Owner | Branch | Work |
|---|---|---|
| Barrat | `design/postcard-polish` | Visual direction and demo |
| Z | `feature/native-postcard-editor` | Photo/message editor and native integration |
| Zubair | `feature/duo-interaction` | Hinge interactions and simulator |
| Pranav | `feature/postcard-delivery` | Backend and recipient web experience |

All four branches start from the same Postcard baseline. The existing FoldGonio project below is retained. No branches have been merged.

## Current verification

Native Postcard builds with the Xcode 27.1 beta simulator SDK. Live simulator installation/interaction has not yet been verified because Device Hub requests stalled. Hosted recipient links and printed delivery are not implemented. Image/HTML sharing and supported-device Messages composition are implemented.

---

# FoldGonio

People in physical therapy can't measure their joint range at home, so the phone becomes the goniometer. A goniometer is two arms joined at a pivot, and iPhone Duo has the same parts: two halves and a hinge. FoldGonio reads the hinge as the knee angle.

Built for [Bitrig Hacks: iPhone Duo Edition](https://events.ycombinator.com/bitrig-hacks-september2026) (YC, San Francisco, 26 Sep 2026). It's SwiftUI on the iOS 27.1 iPhone Duo APIs.

## Brief → build

| Brief item | What's built | API |
|---|---|---|
| Hinge = joint angle, recorded only while `.partiallyOpen` and steady for 1 s | `StabilityGate` fires once per hold and re-arms when you bend further. A 10 Hz clock drives it, because a phone held still sends no hinge updates. | `onHingeChange` → `DeviceHinge.angle` / `.status` |
| One-time 90° calibration | Seat the phone in a square and tap Set 90°. It stores an offset and refuses anything more than 15° from 90°. | — |
| Thigh on the top half, shin on the bottom, knee pinned to the fold | `FoldLegView`. The knee sits on the fold's reserved region. It also handles book pose, with the thigh on the leading half. | `GeometryProxy.reservedRegions(kind: .division)` |
| ArrangementView: live dial primary, recovery curve secondary, stacked when closed | `ReviewArrangement` | `ArrangementView`, `.split.axes([.horizontal, .vertical])`, `splitArrangementLayoutRatio` |
| Side toolbar: Measure, History, Send to PT | Two tabs plus a pinned share action, each with a title and an SF Symbol, so the system can move them into the vertical bar | `Tab`, `.topBarPinnedTrailing`, `ToolbarOverflowMenu` |
| Outer screen when closed: "Today: 104° → goal 110°" | With the phone closed the dial pane becomes `TodayGlance`, which shows today's value, goal, degrees to go, and days to the goal at the current pace | hinge `.closed` |
| Clinician opens two patient windows side by side | Clinician View (in the overflow menu) opens one window per patient. The seeded second patient has stalled, so the comparison shows something. | `WindowGroup(for:)`, `openWindow`, `UIApplicationSupportsMultipleScenes` |
| HW roadmap: gait on the outer screen during a video visit | Not built. See below. | `CameraCaptureAccessory` |
| Signature moment: fold, the drawn leg bends, the angle ticks up | The leg is drawn straight across the crease, so the physical fold bends it. A side-view inset shows the same bend on a flat screen. | — |

## Where the build departs from the brief, and why

1. **The number is flexion (180° − hinge angle), not the raw hinge angle.** A straight knee holds the phone flat, which is 180° of hinge and 0° of flexion. A PT's 104° of flexion is a hinge angle of 76°. Showing the raw hinge would report a straight leg as 180°.
2. **During a real knee measurement the inner display faces the back of the knee.** The Duo only folds screen-in, so the screens always face into the fold. When the knee bends, that fold is behind the knee, where the patient can't see it. The build therefore confirms each reading with a haptic and a spoken "104 degrees", and the 1-second hold becomes eyes-free capture. The drawn leg is still the demo moment in the hand, but it isn't the at-home interface.
3. **Layout follows the fold region, not the hinge angle.** Apple's guidance is to use reserved regions and arrangements for layout, and the hinge only for effects and interactions. The hinge here drives the number, the hold ring, and the side view, and nothing else.
4. **Recording only happens on the Measure tab.** Otherwise a phone standing in tabletop pose on a desk would log readings.
5. **Camera accessory: left out.** `CameraCaptureAccessory` is a shipping iOS 27.1 API, not hardware. It's also the one way to put content on the outer display while the phone is open, and that display faces the patient during a measurement. But it's only available while a camera session is running, so using it to show an angle is a hack: App Review risk, the camera indicator is on, and it takes time to build. It's a roadmap slide, not demo code.

## Demo script (about 90 s)

Tap **History → Reset Demo Data** before you go on stage. The demo patient is Alex, day 24 after a total knee replacement, with 18 days of seeded readings ending yesterday at 101°.

1. **Closed.** The outer display shows *Today — → goal 110° · Last: 101° on day 23 · 9° to go · about 7 days at this pace*.
2. **Unfold flat.** The live dial and the recovery curve sit side by side, with a dashed projection to the goal.
3. **Fold partway.** The screen switches to the leg: thigh above the crease, shin below, knee on the fold. Fold to a 76° hinge angle and the reading shows **104°**. Hold still and the ring fills around the knee, then the phone buzzes and says "104 degrees. Best today."
4. **Close.** *Today 104° → goal 110° · 6° to go · about 5 days at this pace*.
5. Optional: in landscape, Send to PT is in the vertical bar. It opens the share sheet with a plain-text report of today, the trend, 14 days of daily bests, the calibration, and the method.
6. Optional, and the first thing to cut: open Clinician View, then Alex and Sam in two windows. Sam is flagged with a plateau at +0.2°/day.

**Fallbacks**
- On a device without a hinge (any non-Duo iOS 27.1 simulator), a "simulated hinge" slider appears and everything except the fold layout still runs.
- Before going on stage, check that your simulator reports a continuous angle while you fold, not just fixed poses. The "ticking up" beat depends on it.
- If your simulator draws the screen flat, the physical bend won't show, and the side-view inset carries it.

## Honest read

| Risk | Status |
|---|---|
| **No hardware exists yet.** iPhone Duo ships 23 Oct 2026. | Everything today runs in a simulator. The demo shows the interaction, not measurement accuracy. |
| **Hinge accuracy is unknown.** Apple says the rate and precision of angle updates are system policy. | Hinge data is meant for effects, and using it as an instrument goes beyond that. Validating against a real goniometer is the first thing to do once hardware ships. |
| Full extension can't be measured | At about 0° of flexion the phone is flat, which reads as `.fullyOpen`, and the gate ignores it. An extension deficit, a key post-knee-replacement number, isn't captured. |
| One-point calibration | It fixes a constant offset, not error that scales with the angle. |
| Short arms | Along the leg, each half is about as long as a closed phone is wide, roughly 8 cm, against 15–30 cm on a clinical goniometer. Placement error weighs more. |
| Prior art | Phone goniometer apps that use the accelerometer already exist. What's new is the mechanism, two real arms and a pivot, not measuring range of motion on a phone. |
| Market | The phone costs $1,999, and very few owners are in knee rehab. This is a demo of an interaction, not a company. |
| Regulatory | Goniometers are medical devices. Frame it as home tracking to share with your PT, not a clinical reading. |

## Build and run

Requirements: Xcode 27.1 with the iOS 27.1 SDK and the iPhone Duo simulator.

```sh
brew install xcodegen   # once
xcodegen generate
open FoldGonio.xcodeproj   # pick the iPhone Duo simulator and run
```

The app is plain SwiftUI in one target with no dependencies, so the files can also be copied into a Bitrig project.

The measuring logic in `FoldGonio/Core` is Foundation-only and tested without Xcode:

```sh
swift test   # 27 tests: hinge→flexion, calibration, the 1 s gate, fold geometry, trend, report, persistence
```

**Verification status:** the core builds and all 27 tests pass on Swift 6.2 (Linux). The SwiftUI layer passes a syntax check (`swiftc -parse`), but it has **not been compiled against the iOS 27.1 SDK**, since that needs Xcode 27.1 on a Mac. Its API calls follow Apple's docs and two public iPhone Duo sample projects. Expect a few small fixes on the first build.

## Code map

```
FoldGonio/
  App/FoldGonioApp.swift      scenes: main window, one window per patient
  App/GonioModel.swift        hinge in, hold gate, capture → haptic + speech, persistence
  Core/Goniometry.swift       HingeSample, Calibration (hinge → flexion), StabilityGate
  Core/LegGeometry.swift      thigh/knee/shin placement from the fold region
  Core/Recovery.swift         readings, daily bests, trend, days to goal, plateau, PT report
  Core/Persistence.swift      JSON state, seeded demo patients
  Views/MeasureScreen.swift   fold region → leg layout, or ArrangementView (dial | curve)
  Views/FoldLegView.swift     the leg across the crease, side-view inset
  Views/Components.swift      readout, hold ring, today summary, simulated hinge
  Views/RecoveryChart.swift   Swift Charts curve, goal line, projection
  Views/HistoryScreen.swift, CalibrationSheet.swift, Clinic.swift, RootView.swift
Tests/GonioCoreTests/         Swift Testing suites for Core
```
