import SwiftUI

/// A visual reveal only. The caller owns state and the explicit send action.
public struct PostcardFlipContainer<Front: View, Back: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let isOpen: Bool
    private let duration: Double
    private let front: Front
    private let back: Back

    public init(
        isOpen: Bool, duration: Double = 0.8,
        @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back
    ) {
        self.isOpen = isOpen
        self.duration = duration
        self.front = front()
        self.back = back()
    }

    public var body: some View {
        ZStack {
            front
                .opacity(reduceMotion ? (isOpen ? 0 : 1) : (isOpen ? 0 : 1))
                .rotation3DEffect(.degrees(reduceMotion ? 0 : (isOpen ? -180 : 0)), axis: (x: 0, y: 1, z: 0))
                .accessibilityHidden(isOpen)
                .allowsHitTesting(!isOpen)
            back
                .opacity(isOpen ? 1 : 0)
                .accessibilityHidden(!isOpen)
                .allowsHitTesting(isOpen)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: duration), value: isOpen)
    }
}

public struct PostcardSealEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let isSealed: Bool

    public init(isSealed: Bool) { self.isSealed = isSealed }

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isSealed {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(Color(red: 0.70, green: 0.22, blue: 0.15))
                        .padding(18)
                        .accessibilityLabel("Sealed")
                        .transition(reduceMotion ? .opacity : .scale(scale: 1.4).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45), value: isSealed)
    }
}
