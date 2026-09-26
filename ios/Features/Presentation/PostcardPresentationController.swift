import Foundation
import Observation
import PostcardCore

/// Owns the postcard's presentation state and decides when hinge or manual events change it.
/// Never talks to `PostcardService`: folding cannot send. Only `ComposeViewModel.send()` does.
@MainActor
@Observable
final class PostcardPresentationController {
  enum Source: Equatable, Sendable { case hinge, manual, system }

  enum SuppressionReason: Hashable, Sendable {
    case modal, sending, authenticating, composerHidden
  }

  struct Transition: Equatable, Sendable {
    var from: PostcardPresentationState
    var to: PostcardPresentationState
    var source: Source
  }

  private(set) var state: PostcardPresentationState = .front
  private(set) var posture: DevicePosture = .unknown
  private(set) var transitions: [Transition] = []
  private(set) var suppressionReasons: Set<SuppressionReason> = []
  /// Set when a hinge event arrived while suppressed; applied when suppression lifts so a quick reopen isn't lost.
  private var pendingHingeOpen: Bool?
  private var resyncTask: Task<Void, Never>?

  private let haptics: any HapticsPlaying
  private let debounce: TimeInterval
  private var hasInitialPosture = false
  private var lastHingeTransition: Date?
  private var latestHingeEventTime: Date?

  var isSuppressed: Bool { !suppressionReasons.isEmpty }

  init(haptics: any HapticsPlaying, debounce: TimeInterval = 0.25) {
    self.haptics = haptics
    self.debounce = debounce
  }

  // MARK: Hinge input

  /// Feed native (or simulated) posture. The first event only establishes the baseline.
  func receive(posture newPosture: DevicePosture, at now: Date = Date()) {
    let previous = posture
    posture = newPosture
    latestHingeEventTime = now
    guard let isOpen = newPosture.isOpen else { return }
    guard hasInitialPosture else {
      hasInitialPosture = true
      return
    }
    // Ignore angle-only jitter while the open/closed meaning is unchanged.
    if previous.isOpen == isOpen {
      if pendingHingeOpen != nil, !isSuppressed {
        pendingHingeOpen = isOpen
        scheduleResync()
      }
      return
    }
    if isSuppressed {
      pendingHingeOpen = isOpen
      resyncTask?.cancel()
      return
    }
    if let last = lastHingeTransition, now.timeIntervalSince(last) < debounce {
      pendingHingeOpen = isOpen
      scheduleResync()
      return
    }
    pendingHingeOpen = nil
    resyncTask?.cancel()
    if apply(open: isOpen, source: .hinge) {
      lastHingeTransition = now
    }
  }

  // MARK: Manual input

  func open(source: Source = .manual) {
    guard !isSuppressed || source == .system else { return }
    cancelPendingResync()
    _ = apply(open: true, source: source)
  }

  func seal(source: Source = .manual) {
    guard !isSuppressed || source == .system else { return }
    cancelPendingResync()
    _ = apply(open: false, source: source)
  }

  // MARK: Send lifecycle (driven by ComposeViewModel, never by animation or hinge)

  func beginSending() -> Bool {
    guard state == .sealed || state == .writing else { return false }
    move(to: .sending, source: .system)
    suppressionReasons.insert(.sending)
    return true
  }

  func sendSucceeded() {
    suppressionReasons.remove(.sending)
    cancelPendingResync()
    move(to: .sent, source: .system)
    haptics.play(.sent)
  }

  func sendFailed() {
    suppressionReasons.remove(.sending)
    move(to: .sealed, source: .system)
    if !isSuppressed { applyPendingResync() }
  }

  func resetForNewDraft() {
    cancelPendingResync()
    move(to: .front, source: .system)
  }

  // MARK: Suppression

  func setSuppressed(_ suppressed: Bool, reason: SuppressionReason) {
    if suppressed {
      suppressionReasons.insert(reason)
    } else {
      suppressionReasons.remove(reason)
      if !isSuppressed { applyPendingResync() }
    }
  }

  // MARK: Internals

  private func scheduleResync() {
    resyncTask?.cancel()
    resyncTask = Task { [weak self, debounce] in
      try? await Task.sleep(for: .seconds(debounce))
      guard !Task.isCancelled else { return }
      self?.applyPendingResync()
    }
  }

  private func applyPendingResync() {
    guard !isSuppressed, let pending = pendingHingeOpen else { return }
    pendingHingeOpen = nil
    resyncTask?.cancel()
    resyncTask = nil
    // Re-sync to the latest physical posture rather than replaying a stale event.
    if posture.isOpen == pending, apply(open: pending, source: .hinge) {
      lastHingeTransition = latestHingeEventTime
    }
  }

  private func cancelPendingResync() {
    pendingHingeOpen = nil
    resyncTask?.cancel()
    resyncTask = nil
  }

  /// Returns true when the state changed.
  @discardableResult
  private func apply(open: Bool, source: Source) -> Bool {
    switch (state, open) {
    case (.front, true), (.sealed, true):
      move(to: .writing, source: source)
      haptics.play(.opened)
      return true
    case (.writing, false):
      move(to: .sealed, source: source)
      haptics.play(.sealed)
      return true
    default:
      // front+close, sealed+close (seal once), sending/sent+anything: no-op.
      return false
    }
  }

  private func move(to next: PostcardPresentationState, source: Source) {
    guard next != state else { return }
    transitions.append(Transition(from: state, to: next, source: source))
    state = next
  }
}
