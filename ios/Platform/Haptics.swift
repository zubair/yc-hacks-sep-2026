import UIKit

enum HapticEvent: Equatable, Sendable {
  case opened, sealed, sent
}

@MainActor
protocol HapticsPlaying: AnyObject {
  func play(_ event: HapticEvent)
}

@MainActor
final class SystemHaptics: HapticsPlaying {
  private let light = UIImpactFeedbackGenerator(style: .light)
  private let medium = UIImpactFeedbackGenerator(style: .medium)
  private let notification = UINotificationFeedbackGenerator()

  func play(_ event: HapticEvent) {
    switch event {
    case .opened: light.impactOccurred()
    case .sealed: medium.impactOccurred(intensity: 0.9)
    case .sent: notification.notificationOccurred(.success)
    }
  }
}
