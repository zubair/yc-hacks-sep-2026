import XCTest
import PostcardCore
@testable import Postcard

@MainActor
final class PostcardPostureTests: XCTestCase {
    func testHingeOpenCloseAndManualFallbackShareState() {
        let posture = PostcardPostureController()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        posture.receivePosture(isOpen: false, at: start)
        XCTAssertEqual(posture.state, .front)

        posture.receivePosture(isOpen: true, at: start.addingTimeInterval(0.1))
        XCTAssertEqual(posture.state, .writing)
        posture.receivePosture(isOpen: false, at: start.addingTimeInterval(0.2))
        XCTAssertEqual(posture.state, .sealed)
        posture.receivePosture(isOpen: false, at: start.addingTimeInterval(0.3))
        XCTAssertEqual(posture.state, .sealed)

        posture.open()
        XCTAssertEqual(posture.state, .writing)
        posture.seal()
        XCTAssertEqual(posture.state, .sealed)
    }

    func testModalAndSendingIgnoreHingeEvents() {
        let posture = PostcardPostureController()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        posture.isModalVisible = true
        posture.receivePosture(isOpen: true, at: start)
        XCTAssertEqual(posture.state, .front)
        posture.isModalVisible = false
        posture.receivePosture(isOpen: true, at: start.addingTimeInterval(1))
        XCTAssertEqual(posture.state, .writing)
        posture.seal()
        posture.beginSend()
        posture.receivePosture(isOpen: true, at: start.addingTimeInterval(2))
        XCTAssertEqual(posture.state, .sending)
        posture.sendSucceeded()
        posture.receivePosture(isOpen: false, at: start.addingTimeInterval(3))
        XCTAssertEqual(posture.state, .sent)
    }
}
