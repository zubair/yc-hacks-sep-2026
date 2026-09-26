import SwiftUI

/// The native API is isolated here so the rest of the app runs on iOS 17 and
/// ordinary iPhones. A nil hinge leaves the manual controls available.
struct NativeHingeObserver<Content: View>: View {
    var controller: DuoStateController
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                let posture: FoldPosture?
                if let hinge = context.hinge {
                    switch hinge.status {
                    case .closed: posture = .closed
                    case .partiallyOpen, .fullyOpen: posture = .open
                    default: posture = .unknown
                    }
                } else {
                    posture = nil
                }
                controller.observeNativePosture(posture)
            }
        } else {
            content
        }
    }
}
