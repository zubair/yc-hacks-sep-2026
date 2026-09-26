import Foundation
import UIKit
import PostcardCore

/// Maps Apple's Duo hinge status and manual controls to one postcard state machine.
@MainActor
final class PostcardPostureController {
    private(set) var state: PostcardPresentationState = .front
    var isModalVisible = false
    private var lastEvent: (open: Bool, date: Date)?
    private var receivedInitialPosture = false

    func receivePosture(isOpen: Bool, at date: Date = Date()) {
        guard state != .sending, state != .sent, !isModalVisible else { return }
        if !receivedInitialPosture {
            receivedInitialPosture = true
            lastEvent = (isOpen, date)
            if isOpen { open() }
            return
        }
        if let lastEvent, lastEvent.open == isOpen,
           date.timeIntervalSince(lastEvent.date) < 0.35 { return }
        lastEvent = (isOpen, date)
        if isOpen { open() } else { seal() }
    }

    func open() {
        guard !isModalVisible, state == .front || state == .sealed else { return }
        state = .writing
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func seal() {
        guard !isModalVisible, state == .writing else { return }
        state = .sealed
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func beginSend() { state = .sending }
    func sendSucceeded() { state = .sent }
    func sendFailed() { state = .sealed }
    func beginNewDraft() { state = .front; lastEvent = nil; receivedInitialPosture = false }
}
