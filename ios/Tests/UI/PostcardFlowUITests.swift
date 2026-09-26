import XCTest

@MainActor
final class PostcardFlowUITests: XCTestCase {
    func testFixtureComposeSendAndRecipientInbox() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetDemo"]
        app.launch()

        XCTAssertTrue(app.staticTexts["DEMO · simulated sends"].waitForExistence(timeout: 15))
        let recipient = app.textFields["Recipient username"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 5))
        recipient.tap()
        recipient.typeText("sam")
        XCTAssertEqual(recipient.value as? String, "sam")
        app.buttons["find-recipient"].tap()
        let sam = app.buttons["select-recipient"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5), app.debugDescription)
        sam.tap()
        XCTAssertTrue(app.staticTexts["selected-recipient"].waitForExistence(timeout: 5))

        app.buttons["open-postcard"].tap()
        app.swipeDown()
        app.swipeDown()
        let note = app.descendants(matching: .any).matching(identifier: "message-editor").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("A note from the demo postcard.")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        app.buttons["seal-postcard"].tap()
        XCTAssertTrue(app.buttons["send-postcard"].isEnabled)
        app.buttons["send-postcard"].tap()
        XCTAssertTrue(app.staticTexts["sent-state"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sam Lee")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["View as Sam"].tap()
        let alex = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alex Rivera")).firstMatch
        XCTAssertTrue(alex.waitForExistence(timeout: 5))
        alex.tap()
        XCTAssertTrue(app.images["Your postcard photograph"].waitForExistence(timeout: 10))
        let read = app.buttons["Read their note"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        XCTAssertTrue(app.staticTexts["A note from the demo postcard."].waitForExistence(timeout: 5))
    }
}
