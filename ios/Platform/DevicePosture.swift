import Foundation

/// Platform-neutral fold posture. Native hinge events and manual/simulated sources both map to this.
enum DevicePosture: Equatable, Sendable {
  case unknown
  case closed
  case partiallyOpen(angleDegrees: Double)
  case fullyOpen

  /// Whether the card should be considered open. Any partially open angle counts: the person has
  /// started to open the device, which is the gesture that reveals the back of the postcard.
  var isOpen: Bool? {
    switch self {
    case .unknown: nil
    case .closed: false
    case .partiallyOpen, .fullyOpen: true
    }
  }
}
