import SwiftUI

/// Bridges the iOS 27.1 hinge API (`onHingeChange`, `DeviceHinge`) to `DevicePosture`.
/// Only this file touches the native hinge API. Earlier iOS versions and devices without a hinge
/// never emit events, so the composer's Open and Seal buttons remain the way to change state.
struct HingePostureModifier: ViewModifier {
  let controller: PostcardPresentationController

  func body(content: Content) -> some View {
    if #available(iOS 27.1, *) {
      content.onHingeChange { _, context in
        controller.receive(posture: DevicePosture(hinge: context.hinge))
      }
    } else {
      content
    }
  }
}

@available(iOS 27.1, *)
extension DevicePosture {
  init(hinge: DeviceHinge?) {
    guard let hinge else {
      self = .unknown
      return
    }
    switch hinge.status {
    case .closed: self = .closed
    case .partiallyOpen: self = .partiallyOpen(angleDegrees: hinge.angle.degrees)
    case .fullyOpen: self = .fullyOpen
    default: self = .unknown
    }
  }
}

extension View {
  func hingePosture(feeding controller: PostcardPresentationController) -> some View {
    modifier(HingePostureModifier(controller: controller))
  }
}
