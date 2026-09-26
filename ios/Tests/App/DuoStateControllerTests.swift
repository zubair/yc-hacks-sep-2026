import Foundation
import PostcardCore
import Testing
@testable import Postcard

@Suite("Duo posture state")
@MainActor
struct DuoStateControllerTests {
    @Test func initialAndRepeatedEvents() {
        let haptics = RecordingHaptics()
        let controller = DuoStateController(haptics: haptics)

        controller.observeNativePosture(.closed)
        #expect(controller.state == .front)
        controller.observeNativePosture(.open)
        controller.observeNativePosture(.open)
        #expect(controller.state == .writing)
        #expect(haptics.openCount == 1)

        controller.observeNativePosture(.closed)
        controller.observeNativePosture(.closed)
        #expect(controller.state == .sealed)
        #expect(haptics.sealCount == 1)
    }

    @Test func quickReopenAndManualFallback() {
        let controller = DuoStateController(haptics: RecordingHaptics())
        #expect(!controller.hasNativeHinge)
        controller.open()
        controller.seal()
        controller.open()
        #expect(controller.state == .writing)

        controller.observeNativePosture(.open)
        controller.observeNativePosture(.closed)
        controller.observeNativePosture(.open)
        #expect(controller.state == .writing)
    }

    @Test func modalAndSendingSuppressAutomaticChanges() {
        let controller = DuoStateController(haptics: RecordingHaptics())
        controller.observeNativePosture(.open)
        controller.setBlocked(true)
        controller.observeNativePosture(.closed)
        #expect(controller.state == .writing)
        controller.setBlocked(false)
        controller.observeNativePosture(.open)
        #expect(controller.state == .writing)
        controller.observeNativePosture(.closed)
        #expect(controller.state == .sealed)

        #expect(controller.beginSending())
        controller.observeNativePosture(.open)
        #expect(controller.state == .sending)
        controller.sendFailed()
        #expect(controller.state == .sealed)
        controller.open()
        #expect(controller.state == .writing)
    }

    @Test func initialOpenAndNoHinge() {
        let controller = DuoStateController(haptics: RecordingHaptics())
        controller.observeNativePosture(nil)
        #expect(!controller.hasNativeHinge)
        #expect(controller.state == .front)
        controller.observeNativePosture(.open)
        #expect(controller.hasNativeHinge)
        #expect(controller.state == .writing)
    }
}

@MainActor
private final class RecordingHaptics: PostcardHapticOutput {
    var openCount = 0
    var sealCount = 0
    var sentCount = 0

    func opened() { openCount += 1 }
    func sealed() { sealCount += 1 }
    func sent() { sentCount += 1 }
}
