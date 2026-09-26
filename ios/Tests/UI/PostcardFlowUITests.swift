import XCTest

/// End-to-end fixture flow through the real app, screens, and packages. `-forceDemo` guarantees the
/// in-memory fixture service even when Local.xcconfig configures Supabase, so no real message is sent.
/// `-resetDemo` clears the stored draft, so each run starts on the seeded front (Cinque Terre, for Sam Lee).
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

    writeAndSeal(note: note)
    XCTAssertFalse(sentLabel.exists, "opening and sealing never send")
    sendButton.tap()
    XCTAssertTrue(sentLabel.waitForExistence(timeout: 10), "sent only after the explicit tap")
    attachScreenshot("sent")

    goBack()
    let samRow = button(containing: "Sam Lee")
    XCTAssertTrue(samRow.waitForExistence(timeout: 10), "sender's inbox shows the stored conversation")
    attachScreenshot("sender-inbox")

    switchDemoAccount(to: "Sam Lee")
    let alexRow = button(containing: "Alex Rivera")
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

    writeAndSeal(note: "Retry keeps this note.")
    sendButton.tap()
    let failure = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Demo failure")).firstMatch
    XCTAssertTrue(failure.waitForExistence(timeout: 10), "failure is shown, not hidden")
    XCTAssertFalse(sentLabel.exists)
    attachScreenshot("send-failed")

    sendButton.tap() // "Try again": same draft, same idempotency key
    XCTAssertTrue(sentLabel.waitForExistence(timeout: 10))

    goBack()
    let samRow = button(containing: "Sam Lee")
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

  private var sendButton: XCUIElement { app.buttons["Send postcard to Sam Lee"] }
  private var sentLabel: XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sent to Sam Lee")).firstMatch }

  /// Front (seeded) → Open to write → note → Done → Prepare to send → sealed with Continue enabled.
  private func writeAndSeal(note: String) {
    app.buttons["compose-postcard"].tap()
    let open = button(beginningWith: "Open to write")
    XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
    attachScreenshot("front")
    open.tap()

    let editor = app.textViews["Your note"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText(note)
    let done = app.buttons["Done"]
    if done.waitForExistence(timeout: 3) { done.tap() }
    attachScreenshot("writing")

    let seal = app.buttons["Prepare to send"]
    XCTAssertTrue(seal.waitForExistence(timeout: 5))
    seal.tap()
    XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
    XCTAssertTrue(sendButton.isEnabled, "a complete sealed draft can be sent")
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

  /// iOS 27.1 places the back button in the vertical toolbar; earlier versions keep it in the navigation bar.
  private func goBack() {
    let barBack = app.buttons["BackButton"]
    if barBack.waitForExistence(timeout: 2) {
      barBack.tap()
    } else {
      let back = app.navigationBars.buttons.element(boundBy: 0)
      XCTAssertTrue(back.waitForExistence(timeout: 5))
      back.tap()
    }
  }

  private func button(containing text: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  private func button(beginningWith text: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
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
