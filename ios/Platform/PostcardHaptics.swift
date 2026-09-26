import UIKit

@MainActor
protocol PostcardHapticOutput {
    func opened()
    func sealed()
    func sent()
}

@MainActor
struct SystemPostcardHaptics: PostcardHapticOutput {
    func opened() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func sealed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func sent() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
