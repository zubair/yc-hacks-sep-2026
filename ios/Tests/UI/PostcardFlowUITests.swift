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
        app.buttons["Find recipient"].tap()
        let sam = app.buttons["Sam Lee · @sam"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5))
        sam.tap()
        XCTAssertTrue(app.staticTexts["Selected: Sam Lee"].waitForExistence(timeout: 5))

        let note = app.textViews["Postcard note"]
        app.swipeUp()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("A note from the demo postcard.")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        app.swipeUp()
        let open = app.buttons["Open postcard"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        app.buttons["Seal postcard"].tap()
        XCTAssertTrue(app.buttons["Send postcard"].isEnabled)
        app.buttons["Send postcard"].tap()
        XCTAssertTrue(app.staticTexts["Postcard stored in the conversation"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sam Lee")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["View as Sam"].tap()
        let alex = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alex Rivera")).firstMatch
        XCTAssertTrue(alex.waitForExistence(timeout: 5))
        alex.tap()
        XCTAssertTrue(app.staticTexts["A note from the demo postcard."].waitForExistence(timeout: 5))
    }
}
