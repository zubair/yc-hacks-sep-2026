import SwiftUI

/// Bridges the iOS 27.1 hinge API (`onHingeChange`, `DeviceHinge`) to `DevicePosture`.
/// Only this file touches the native API, so a device without a hinge (or an older SDK) degrades to manual controls.
struct HingePostureModifier: ViewModifier {
  let controller: PostcardPresentationController

  func body(content: Content) -> some View {
    content.onHingeChange { _, context in
      controller.receive(posture: DevicePosture(hinge: context.hinge))
    }
  }
}

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
