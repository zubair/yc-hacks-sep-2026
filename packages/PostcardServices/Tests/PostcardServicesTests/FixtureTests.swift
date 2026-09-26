import XCTest
import PostcardCore
@testable import PostcardServices

final class FixtureTests: XCTestCase {
    func testSendRetryIsIdempotentAndFailurePreservesRequest() async throws {
        let service = FixturePostcardService()
        let draft = PostcardDraft(recipientId: FixturePostcardService.recipient.id,
                                  recipientName: "Sam", senderName: "Alex", destination: "Paris", message: "Wish you were here",
                                  photoData: Data([0xFF, 0xD8, 0xFF]))
        await service.failOneSend()
        do {
            _ = try await service.send(draft: draft)
            XCTFail("Expected failure")
        } catch PostcardServiceError.server { }
        let first = try await service.send(draft: draft)
        let second = try await service.send(draft: draft)
        XCTAssertEqual(first.id, second.id)
        let messages = try await service.messages(conversationId: first.conversationId, before: nil, limit: 20)
        XCTAssertEqual(messages.count, 1)
    }

    func testOfflineAndAuthStates() async throws {
        let service = FixturePostcardService(signedIn: false)
        do {
            _ = try await service.conversations()
            XCTFail("Expected auth error")
        } catch PostcardServiceError.unauthenticated { }
        try await service.signIn(email: "sam@demo.com", password: "any-demo-password")
        let sam = try await service.currentProfile()
        XCTAssertEqual(sam, FixturePostcardService.recipient)
        await service.signOut()
        await service.setOffline(true)
        do {
            _ = try await service.currentProfile()
            XCTFail("Expected offline error")
        } catch PostcardServiceError.offline { }
    }
}
