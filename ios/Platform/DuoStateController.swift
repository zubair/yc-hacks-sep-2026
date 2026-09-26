import Foundation
import Observation
import PostcardCore

enum FoldPosture: Equatable, Sendable {
    case closed
    case open
    case unknown
}

@MainActor
@Observable
final class DuoStateController {
    private(set) var state: PostcardPresentationState = .front
    private(set) var hasNativeHinge = false
    private(set) var isBlocked = false

    @ObservationIgnored private var lastPosture: FoldPosture?
    @ObservationIgnored private let haptics: any PostcardHapticOutput

    init(haptics: any PostcardHapticOutput) {
        self.haptics = haptics
    }

    func setBlocked(_ blocked: Bool) {
        isBlocked = blocked
    }

    func observeNativePosture(_ posture: FoldPosture?) {
        hasNativeHinge = posture != nil
        guard let posture else {
            lastPosture = nil
            return
        }
        guard posture != .unknown else { return }
        guard posture != lastPosture else { return }

        let previous = lastPosture
        lastPosture = posture
        guard !isBlocked else { return }

        // A first open observation reveals the card. A first closed observation
        // does not seal an untouched draft.
        if previous == nil {
            if posture == .open { open() }
            return
        }

        switch (previous, posture) {
        case (.open, .closed): seal()
        case (.closed, .open): open()
        default: break
        }
    }

    func open() {
        guard !isBlocked, state == .front || state == .sealed else { return }
        state = .writing
        haptics.opened()
    }

    func seal() {
        guard !isBlocked, state == .writing else { return }
        state = .sealed
        haptics.sealed()
    }

    @discardableResult
    func beginSending() -> Bool {
        guard !isBlocked, state == .sealed else { return false }
        state = .sending
        return true
    }

    func sendSucceeded() {
        guard state == .sending else { return }
        state = .sent
        haptics.sent()
    }

    func sendFailed() {
        guard state == .sending else { return }
        state = .sealed
    }

    func startNewDraft() {
        guard state == .sent else { return }
        state = .front
    }

    func resetForAccountSwitch() {
        state = .front
        lastPosture = nil
    }
}
