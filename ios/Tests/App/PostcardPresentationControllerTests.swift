import XCTest
import PostcardCore
@testable import Postcard

@MainActor
final class PostcardPresentationControllerTests: XCTestCase {
  private var haptics: SpyHaptics!
  private var controller: PostcardPresentationController!
  private let t0 = Date(timeIntervalSince1970: 1_000)

  override func setUp() {
    haptics = SpyHaptics()
    controller = PostcardPresentationController(haptics: haptics, debounce: 0.25)
  }

  func testInitialPostureOnlySetsBaseline() {
    controller.receive(posture: .fullyOpen, at: t0)
    XCTAssertEqual(controller.state, .front)
    XCTAssertTrue(controller.transitions.isEmpty)
  }

  func testOpeningRevealsWritingAndClosingSealsOnce() {
    controller.receive(posture: .closed, at: t0)
    controller.receive(posture: .partiallyOpen(angleDegrees: 60), at: t0.addingTimeInterval(1))
    XCTAssertEqual(controller.state, .writing)
    controller.receive(posture: .closed, at: t0.addingTimeInterval(2))
    XCTAssertEqual(controller.state, .sealed)
    // Repeated closes never re-seal or flip back.
    controller.receive(posture: .closed, at: t0.addingTimeInterval(3))
    controller.receive(posture: .partiallyOpen(angleDegrees: 5), at: t0.addingTimeInterval(4))
    controller.receive(posture: .closed, at: t0.addingTimeInterval(5))
    XCTAssertEqual(controller.transitions.map(\.to), [.writing, .sealed, .writing, .sealed])
    XCTAssertEqual(haptics.events, [.opened, .sealed, .opened, .sealed])
  }

  func testAngleJitterWhileOpenDoesNothing() {
    controller.receive(posture: .closed, at: t0)
    controller.receive(posture: .partiallyOpen(angleDegrees: 40), at: t0.addingTimeInterval(1))
    controller.receive(posture: .partiallyOpen(angleDegrees: 90), at: t0.addingTimeInterval(2))
    controller.receive(posture: .fullyOpen, at: t0.addingTimeInterval(3))
    XCTAssertEqual(controller.transitions.count, 1)
  }

  func testRapidFlapIsDebouncedThenResyncs() {
    controller.receive(posture: .closed, at: t0)
    controller.receive(posture: .fullyOpen, at: t0.addingTimeInterval(1.0))
    controller.receive(posture: .closed, at: t0.addingTimeInterval(1.05))   // inside debounce window: deferred
    XCTAssertEqual(controller.state, .writing)
    controller.receive(posture: .fullyOpen, at: t0.addingTimeInterval(1.10)) // still open in the end
    XCTAssertEqual(controller.state, .writing)
    controller.receive(posture: .closed, at: t0.addingTimeInterval(2.0))
    XCTAssertEqual(controller.state, .sealed)
  }

  func testSuppressionWhileSendingAndModal() {
    controller.receive(posture: .closed, at: t0)
    controller.receive(posture: .fullyOpen, at: t0.addingTimeInterval(1))
    XCTAssertTrue(controller.beginSending())
    controller.receive(posture: .closed, at: t0.addingTimeInterval(2))
    XCTAssertEqual(controller.state, .sending)
    controller.sendFailed()
    XCTAssertEqual(controller.state, .sealed)

    controller.setSuppressed(true, reason: .modal)
    controller.receive(posture: .fullyOpen, at: t0.addingTimeInterval(3))
    XCTAssertEqual(controller.state, .sealed, "no transition while a modal is up")
    controller.setSuppressed(false, reason: .modal)
    XCTAssertEqual(controller.state, .writing, "quick reopen applied once the modal closes")
  }

  func testManualFallbackMirrorsHinge() {
    controller.open()
    XCTAssertEqual(controller.state, .writing)
    controller.seal()
    XCTAssertEqual(controller.state, .sealed)
    controller.open()
    XCTAssertEqual(controller.state, .writing)
    controller.setSuppressed(true, reason: .authenticating)
    controller.seal()
    XCTAssertEqual(controller.state, .writing, "manual actions respect suppression")
  }

  func testSendLifecycleAndReset() {
    controller.open()
    XCTAssertTrue(controller.beginSending())
    XCTAssertFalse(controller.beginSending(), "no double send")
    controller.sendSucceeded()
    XCTAssertEqual(controller.state, .sent)
    XCTAssertEqual(haptics.events.last, .sent)
    controller.open()
    XCTAssertEqual(controller.state, .sent, "a sent card cannot be reopened")
    controller.resetForNewDraft()
    XCTAssertEqual(controller.state, .front)
  }
}
