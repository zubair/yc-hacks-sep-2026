import XCTest

@MainActor final class InteractionTests: XCTestCase {
    private var app: XCUIApplication!
    private func launch(_ screen: String, extras: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--screen", screen] + extras
        app.launch()
        XCTAssertTrue(app.staticTexts["demo-label"].waitForExistence(timeout: 10))
    }
    private func tap(_ id: String) {
        let element = app.buttons[id]
        for _ in 0..<10 {
            if element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("Button not reachable: \(id)")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testOpenSealAndExplicitSend() {
        launch("front")
        capture("01-front-compact")
        tap("open-postcard")
        XCTAssertTrue(app.textFields["message-editor"].exists || app.textViews["message-editor"].exists)
        XCTAssertTrue(app.staticTexts["send-count"].label.contains("sends: 0"))
        capture("02-writing-compact")
        tap("seal-postcard")
        XCTAssertTrue(app.staticTexts["send-count"].label.contains("sends: 0"))
        app.swipeDown(); app.swipeDown()
        capture("03-sealed-compact")
        tap("send-postcard")
        XCTAssertTrue(app.staticTexts["sent-state"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["send-count"].label.contains("sends: 1"))
        XCTAssertFalse(app.buttons["send-postcard"].exists)
    }
    func testKeyboardEditingAndDraftSurvivesSeal() {
        launch("writing")
        let field = app.descendants(matching: .any)["message-editor"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        if !field.isHittable { app.swipeUp() }
        field.tap()
        field.typeText(" A new memory.")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("04-keyboard-visible")
        app.buttons["Done"].tap()
        tap("seal-postcard")
        tap("open-postcard")
        let value = app.descendants(matching: .any)["message-editor"].firstMatch.value as? String
        XCTAssertTrue(value?.contains("A new memory.") == true)
        XCTAssertTrue(app.staticTexts["send-count"].label.contains("sends: 0"))
    }
    func testInboxAndReceivedMessage() {
        launch("inbox")
        capture("05-inbox")
        tap("conversation-00000000-0000-0000-0000-000000000001")
        capture("06-conversation-front")
        tap("flip-received-00000000-0000-0000-0000-000000000003")
        XCTAssertTrue(app.staticTexts["received-message"].exists)
        capture("07-conversation-back")
    }
    func testAuthValidationAndConfirmationNotice() {
        launch("auth")
        capture("08-sign-in")
        app.buttons["auth-submit"].tap()
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].exists)
        app.segmentedControls.buttons["Create account"].tap()
        app.textFields["auth-email"].tap(); app.textFields["auth-email"].typeText("alex@example.com")
        app.textFields["auth-username"].tap(); app.textFields["auth-username"].typeText("alex_1")
        app.textFields["auth-name"].tap(); app.textFields["auth-name"].typeText("Alex")
        app.secureTextFields["auth-password"].tap(); app.secureTextFields["auth-password"].typeText("long-enough")
        app.buttons["Done"].tap()
        tap("auth-submit")
        XCTAssertTrue(app.staticTexts["auth-notice"].exists)
    }
    func testLargeTextRemainsUsable() {
        launch("writing", extras: ["--large-text", "--long-message"])
        capture("09-large-type-writing")
        tap("seal-postcard")
        tap("open-postcard")
        XCTAssertTrue(app.staticTexts["send-count"].label.contains("sends: 0"))
    }
    func testOfflineDraftAndEmptyInbox() {
        launch("sealed", extras: ["--error"])
        XCTAssertTrue(app.otherElements["composer-error"].exists || app.staticTexts["composer-error"].exists)
        capture("10-offline")
        tap("retry-postcard")
        XCTAssertTrue(app.staticTexts["send-count"].label.contains("sends: 0"))
        launch("empty")
        capture("11-empty-inbox")
        XCTAssertTrue(app.buttons["compose-postcard"].exists)
    }
    func testWideLayout() {
        launch("front")
        XCUIDevice.shared.orientation = .landscapeLeft
        capture("12-wide-front")
        tap("open-postcard")
        capture("13-wide-writing")
        tap("seal-postcard")
        XCTAssertTrue(app.staticTexts["send-count"].label.contains("sends: 0"))
        XCUIDevice.shared.orientation = .portrait
    }
}
