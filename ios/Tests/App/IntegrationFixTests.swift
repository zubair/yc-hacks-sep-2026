import XCTest
import PostcardCore
@testable import Postcard

/// Regression tests for defects found while integrating the four workstreams.
@MainActor
final class IntegrationFixTests: XCTestCase {
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

  func testSentDraftIsNeverWrittenBackOnBackgrounding() async {
    model.draft = .ready(recipient: await service.recipient)
    presentation.open(); presentation.seal()
    await model.send()
    XCTAssertEqual(presentation.state, .sent)
    model.persistNow() // scene goes to background after the send
    XCTAssertNil(store.load(), "a relaunch must not resurrect the sent draft with its old id")
  }

  func testTryAgainOnlyResendsAfterAFailedSend() async {
    model.draft = .ready(recipient: await service.recipient)
    presentation.open()
    model.draft.senderName = " "
    await model.send() // validation failure, not a send failure
    XCTAssertNotNil(model.errorMessage)
    XCTAssertFalse(model.canRetrySend)
    model.draft.senderName = "Tester"
    await model.retry()
    var calls = await service.sendCalls
    XCTAssertTrue(calls.isEmpty, "Try again after a non-send error only dismisses it")
    XCTAssertNil(model.errorMessage)

    await service.setFailNextSend(.offline)
    await model.send()
    XCTAssertTrue(model.canRetrySend)
    await model.retry()
    calls = await service.sendCalls
    XCTAssertEqual(calls.count, 2)
    XCTAssertEqual(presentation.state, .sent)
  }

  func testNewPhotoGetsANewIdempotencyKey() async {
    model.draft = .ready(recipient: await service.recipient)
    presentation.open(); presentation.seal()
    await service.setFailNextSend(.server("upload stored, RPC failed"))
    await model.send()
    let attemptedId = model.draft.id
    model.setPhoto(Data([0xFF, 0xD8, 0xFF, 0x01]))
    XCTAssertNotEqual(model.draft.id, attemptedId, "a retry must not reuse the photo uploaded under the old id")
    model.setPhoto(Data([0xFF, 0xD8, 0xFF, 0x01]))
    let sameId = model.draft.id
    model.setPhoto(Data([0xFF, 0xD8, 0xFF, 0x01]))
    XCTAssertEqual(model.draft.id, sameId, "re-picking the same bytes keeps the key")
  }

  func testSignOutAndAccountSwitchClearPreviousAccountData() async {
    let environment = AppEnvironment(mode: .fixture, service: service, draftStore: store, haptics: SpyHaptics())
    let alex = PostcardProfile(id: UUID(), username: "alex", displayName: "Alex")
    environment.sessionChanged(to: .signedIn(alex))
    environment.compose.draft = PostcardDraft(destination: "Lisbon", message: "Private words")
    environment.compose.persistNow()

    environment.sessionChanged(to: .unavailable("offline"))
    XCTAssertEqual(environment.compose.draft.message, "Private words", "an offline relaunch is not an account change")
    environment.sessionChanged(to: .signedIn(alex))
    XCTAssertEqual(environment.compose.draft.message, "Private words")

    environment.sessionChanged(to: .signedIn(PostcardProfile(id: UUID(), username: "sam", displayName: "Sam")))
    XCTAssertEqual(environment.compose.draft.message, "", "another account never sees or sends the draft")
    XCTAssertNil(store.load())
    XCTAssertTrue(environment.inbox.conversations.isEmpty)
  }
}
