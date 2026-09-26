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

    /// Mirrors the live `send_postcard` rules: self-sends and reused draft ids with new content are rejected.
    func testSelfSendAndConflictingRetryMatchTheLiveBackend() async throws {
        let service = FixturePostcardService()
        let draft = PostcardDraft(recipientId: FixturePostcardService.recipient.id, recipientName: "Sam", senderName: "Alex",
                                  destination: "Paris", message: "Wish you were here", photoData: Data([0xFF, 0xD8, 0xFF]))
        var toSelf = draft
        toSelf.id = UUID()
        toSelf.recipientId = FixturePostcardService.sender.id
        do {
            _ = try await service.send(draft: toSelf)
            XCTFail("Expected self-send to be rejected")
        } catch let error as PostcardServiceError {
            XCTAssertEqual(error, .validation("You can't send a postcard to yourself."))
        }

        let sent = try await service.send(draft: draft)
        let edits: [(String, (inout PostcardDraft) -> Void)] = [
            ("message", { $0.message = "Different words" }), ("destination", { $0.destination = "Rome" }),
            ("sender name", { $0.senderName = "Al" }), ("recipient name", { $0.recipientName = "Samantha" }),
            ("photo", { $0.photoData = Data([0xFF, 0xD8, 0x00]) })
        ]
        for (field, edit) in edits {
            var conflicting = draft
            edit(&conflicting)
            do {
                _ = try await service.send(draft: conflicting)
                XCTFail("Expected a conflict when only the \(field) changes")
            } catch let error as PostcardServiceError {
                XCTAssertEqual(error, .validation("this draft was already sent with different content; start a new draft"), field)
            }
        }
        let retried = try await service.send(draft: draft)
        XCTAssertEqual(retried, sent, "an identical retry still returns the original")
        let messages = try await service.messages(conversationId: sent.conversationId, before: nil, limit: 20)
        XCTAssertEqual(messages, [sent])
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
