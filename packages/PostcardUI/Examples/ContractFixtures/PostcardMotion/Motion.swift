// VALIDATION FIXTURE ONLY. This is a static face switch, not Pranav's production animation.
import SwiftUI
public struct PostcardFlipContainer<Front: View, Back: View>: View {
    let isOpen: Bool
    let front: Front
    let back: Back
    public init(isOpen: Bool, duration: Double = 0.8, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.isOpen = isOpen; self.front = front(); self.back = back()
    }
    public var body: some View { if isOpen { back } else { front } }
}
public struct PostcardSealEffect: ViewModifier {
    let isSealed: Bool
    public init(isSealed: Bool) { self.isSealed = isSealed }
    public func body(content: Content) -> some View { content }
}
