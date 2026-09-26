import XCTest

/// End-to-end fixture flow through the real app, screens, and packages. `-forceDemo` guarantees the
/// in-memory fixture service even when Local.xcconfig configures Supabase, so no real message is sent.
@MainActor
final class PostcardFlowUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-resetDemo", "-forceDemo"]
    app.launch()
  }

  func testComposeOpenSealExplicitSendThenRecipientReadsIt() throws {
    let note = "A note from the demo postcard."
    XCTAssertTrue(element("empty-inbox").waitForExistence(timeout: 15), "fresh demo starts with an empty inbox")

    writePostcard(to: "sam", note: note)
    XCTAssertFalse(element("sent-state").exists, "opening and sealing never send")
    app.buttons["send-postcard"].tap()
    XCTAssertTrue(element("sent-state").waitForExistence(timeout: 10))
    attachScreenshot("sent")

    goBack()
    let samRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sam Lee")).firstMatch
    XCTAssertTrue(samRow.waitForExistence(timeout: 10), "sender's inbox shows the stored conversation")
    attachScreenshot("sender-inbox")

    switchDemoAccount(to: "Sam Lee")
    let alexRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alex Rivera")).firstMatch
    XCTAssertTrue(alexRow.waitForExistence(timeout: 10), "recipient's inbox shows the postcard")
    alexRow.tap()
    XCTAssertTrue(app.images["Your postcard photograph"].waitForExistence(timeout: 10), "photo resolved through photoURL and loaded by the app")
    attachScreenshot("recipient-front")
    let read = app.buttons["Read their note"]
    XCTAssertTrue(read.waitForExistence(timeout: 5))
    read.tap()
    XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
    attachScreenshot("recipient-back")
  }

  func testFailedSendKeepsDraftAndRetryStoresExactlyOnePostcard() throws {
    XCTAssertTrue(element("empty-inbox").waitForExistence(timeout: 15))
    openDemoMenu()
    app.buttons["Fail the next send"].tap()

    writePostcard(to: "sam", note: "Retry keeps this note.")
    app.buttons["send-postcard"].tap()
    XCTAssertTrue(element("composer-error").waitForExistence(timeout: 10), "failure is shown, not hidden")
    XCTAssertFalse(element("sent-state").exists)
    attachScreenshot("send-failed")

    app.buttons["retry-postcard"].tap()
    XCTAssertTrue(element("sent-state").waitForExistence(timeout: 10))

    goBack()
    let samRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sam Lee")).firstMatch
    XCTAssertTrue(samRow.waitForExistence(timeout: 10))
    samRow.tap()
    XCTAssertTrue(app.buttons["Read their note"].waitForExistence(timeout: 10))
    let postcards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "flip-received-"))
    XCTAssertEqual(postcards.count, 1, "failed attempt plus retry stores one postcard")
  }

  func testOfflineInboxShowsRetryAndRecovers() throws {
    XCTAssertTrue(element("empty-inbox").waitForExistence(timeout: 15))
    openDemoMenu()
    app.buttons["Simulate offline"].tap()
    let refresh = app.buttons["Refresh inbox"]
    XCTAssertTrue(refresh.waitForExistence(timeout: 10), "offline inbox offers a retry")
    attachScreenshot("offline")
    openDemoMenu()
    app.buttons["Go back online"].tap()
    XCTAssertTrue(element("empty-inbox").waitForExistence(timeout: 10))
    XCTAssertFalse(refresh.exists)
  }

  // MARK: Steps

  private func writePostcard(to username: String, note: String) {
    app.buttons["compose-postcard"].tap()
    let recipient = app.textFields["recipient-username"]
    XCTAssertTrue(recipient.waitForExistence(timeout: 10))
    recipient.tap()
    recipient.typeText(username)
    app.buttons["find-recipient"].tap()
    let select = app.buttons["select-recipient"]
    XCTAssertTrue(select.waitForExistence(timeout: 10), app.debugDescription)
    select.tap()
    XCTAssertTrue(element("selected-recipient").waitForExistence(timeout: 5))
    attachScreenshot("front")

    app.buttons["open-postcard"].tap()
    let editor = element("message-editor")
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText(note)
    let done = app.buttons["Done"]
    if done.waitForExistence(timeout: 3) { done.tap() }
    attachScreenshot("writing")
    let seal = app.buttons["seal-postcard"]
    XCTAssertTrue(seal.waitForExistence(timeout: 5))
    seal.tap()
    let send = app.buttons["send-postcard"]
    XCTAssertTrue(send.waitForExistence(timeout: 5))
    XCTAssertTrue(send.isEnabled, "a complete sealed draft can be sent")
    attachScreenshot("sealed")
  }

  private func openDemoMenu() {
    let menu = app.buttons["demo-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.tap()
  }

  private func switchDemoAccount(to name: String) {
    openDemoMenu()
    let item = app.buttons["View as \(name)"]
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    item.tap()
  }

  private func goBack() {
    let back = app.navigationBars.buttons.element(boundBy: 0)
    XCTAssertTrue(back.waitForExistence(timeout: 5))
    back.tap()
  }

  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func attachScreenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
