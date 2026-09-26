import XCTest
import PostcardCore
@testable import Postcard

@MainActor
final class ComposeViewModelTests: XCTestCase {
  private var service: SpyPostcardService!
  private var store: MemoryDraftStore!
  private var presentation: PostcardPresentationController!
  private var model: ComposeViewModel!

  override func setUp() async throws {
    service = SpyPostcardService()
    store = MemoryDraftStore()
    presentation = PostcardPresentationController(haptics: SpyHaptics())
    let session = SessionCoordinator(service: service)
    await session.restore()
    model = ComposeViewModel(service: service, presentation: presentation, draftStore: store, session: session)
  }

  func testFoldingNeverSends() async {
    model.draft = .ready(recipient: await service.recipient)
    presentation.receive(posture: .closed)
    presentation.receive(posture: .fullyOpen)
    presentation.receive(posture: .closed)
    presentation.open(); presentation.seal()
    let calls = await service.sendCalls
    XCTAssertTrue(calls.isEmpty)
    XCTAssertEqual(presentation.state, .sealed)
  }

  func testExplicitSendSendsExactlyOncePerSubmission() async {
    model.draft = .ready(recipient: await service.recipient)
    let draftId = model.draft.id
    presentation.open(); presentation.seal()
    await model.send()
    await model.send() // second tap on the same draft
    let calls = await service.sendCalls
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls.first?.id, draftId)
    XCTAssertEqual(presentation.state, .sent)
    XCTAssertNil(store.load(), "draft cleared after confirmed send")
    model.startNewDraft()
    XCTAssertNotEqual(model.draft.id, draftId, "new draft gets a new idempotency key")
    XCTAssertEqual(presentation.state, .front)
  }

  func testFailedSendPreservesDraftAndRetryReusesId() async {
    model.draft = .ready(recipient: await service.recipient)
    let draftId = model.draft.id
    await service.setFailNextSend(.offline)
    presentation.open(); presentation.seal()
    await model.send()
    XCTAssertEqual(presentation.state, .sealed)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertEqual(store.load()?.id, draftId, "draft persisted for retry")
    await model.send()
    let calls = await service.sendCalls
    XCTAssertEqual(calls.map(\.id), [draftId, draftId])
    XCTAssertEqual(presentation.state, .sent)
  }

  func testValidationBlocksSendWithoutTouchingService() async {
    model.draft = PostcardDraft(message: "no recipient")
    await model.send()
    let calls = await service.sendCalls
    XCTAssertTrue(calls.isEmpty)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertEqual(presentation.state, .front)
  }

  func testSendRequiresOpeningThePostcard() async {
    model.draft = .ready(recipient: await service.recipient)
    XCTAssertFalse(model.canSend)
    await model.send()
    let calls = await service.sendCalls
    XCTAssertTrue(calls.isEmpty)
    XCTAssertNotNil(model.errorMessage)
    presentation.open()
    XCTAssertTrue(model.canSend)
  }

  func testRecipientLookupBindsIntoDraft() async {
    await model.lookup(username: "friend")
    XCTAssertNotNil(model.lookupResult)
    model.select(recipient: model.lookupResult!)
    XCTAssertEqual(model.draft.recipientName, "Friend")
    XCTAssertEqual(model.draft.senderName, "Tester")
    await model.lookup(username: "nobody")
    XCTAssertNil(model.lookupResult)
    XCTAssertNotNil(model.lookupMessage)
    XCTAssertNil(model.errorMessage, "lookup feedback must not surface as a send error with a re-send retry")
  }

  func testDraftRestoresFromStore() {
    let saved = PostcardDraft(destination: "Oslo", message: "Cold and bright.")
    store.save(saved)
    let restored = ComposeViewModel(service: service, presentation: presentation, draftStore: store, session: SessionCoordinator(service: service))
    XCTAssertEqual(restored.draft, saved)
  }
}
