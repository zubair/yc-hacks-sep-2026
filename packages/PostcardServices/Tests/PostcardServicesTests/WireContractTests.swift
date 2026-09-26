import Foundation
import XCTest
import Supabase
import PostcardCore
@testable import PostcardServices

final class WireContractTests: XCTestCase {
    private func responseBody(_ filename: String) throws -> Data {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../backend/fixtures/\(filename)").standardizedFileURL
        let data = try Data(contentsOf: fixture)
        let wrapper = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let response = try XCTUnwrap(wrapper["response"] as? [String: Any])
        return try JSONSerialization.data(withJSONObject: response["body"]!, options: [.fragmentsAllowed])
    }

    func testRecordedRPCResponsesDecode() throws {
        let decoder = PostcardWireCoding.decoder()
        let sent = try decoder.decode(PostcardMessage.self, from: responseBody("send_postcard.json"))
        let conversations = try decoder.decode([PostcardConversation].self, from: responseBody("list_conversations.json"))
        let messages = try decoder.decode([PostcardMessage].self, from: responseBody("list_messages.json"))
        XCTAssertEqual(conversations.first?.latestMessage, sent)
        XCTAssertEqual(messages.first, sent)
        // Compare with the recording's own raw values so re-recorded fixtures stay valid.
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: responseBody("send_postcard.json")) as? [String: Any])
        XCTAssertEqual(sent.photoPath, raw["photo_path"] as? String)
        XCTAssertTrue(sent.photoPath.hasSuffix("/photo.jpg"))
        // Microseconds survive decoding and re-encoding for p_before.
        XCTAssertEqual(PostcardWireCoding.timestamp(sent.createdAt), raw["created_at"] as? String)
    }

    func testRecordedRPCErrorCodesMapToServiceErrors() throws {
        let cases: [(String, PostcardServiceError)] = [
            ("error_unauthenticated.json", .unauthenticated),
            ("error_forbidden_photo_path.json", .forbidden),
            ("error_recipient_not_found.json", .notFound),
            ("error_conversation_not_found.json", .notFound),
            ("error_photo_missing.json", .validation("upload the photo before sending")),
            ("error_validation.json", .validation("message must be 1-5000 characters")),
            ("error_idempotency_conflict.json", .validation("this draft was already sent with different content; start a new draft"))
        ]
        for (filename, expected) in cases {
            let error = try JSONDecoder().decode(PostgrestError.self, from: responseBody(filename))
            XCTAssertEqual(SupabasePostcardService.map(error), expected, filename)
        }
    }

    func testPhotoIsRequiredByBothServices() async throws {
        let draft = PostcardDraft(recipientId: FixturePostcardService.recipient.id,
                                  recipientName: "Sam", senderName: "Alex", message: "Hello")
        XCTAssertThrowsError(try PostcardValidation.validate(draft)) { error in
            XCTAssertEqual(error as? PostcardServiceError, .validation("Choose a photo for your postcard."))
        }
    }

    /// Postgres `char_length` counts Unicode scalars; a flag emoji is one Swift Character but two scalars.
    func testLengthLimitsCountUnicodeScalarsLikePostgres() throws {
        let flag = "\u{1F1F5}\u{1F1F9}"
        XCTAssertEqual(flag.count, 1)
        var draft = PostcardDraft(recipientId: FixturePostcardService.recipient.id, recipientName: "Sam", senderName: "Alex",
                                  message: String(repeating: flag, count: 2_500), photoData: Data([0xFF, 0xD8, 0xFF]))
        XCTAssertNoThrow(try PostcardValidation.validate(draft), "5,000 scalars is the server's limit")
        draft.message = String(repeating: flag, count: 2_600)
        XCTAssertEqual(draft.message.count, 2_600, "under 5,000 grapheme clusters")
        XCTAssertThrowsError(try PostcardValidation.validate(draft)) { error in
            XCTAssertEqual(error as? PostcardServiceError, .validation("Write a note between 1 and 5,000 characters."))
        }
        draft.message = "Hello"
        draft.senderName = String(repeating: flag, count: 51)
        XCTAssertThrowsError(try PostcardValidation.validate(draft)) { error in
            XCTAssertEqual(error as? PostcardServiceError, .validation("Names must be 100 characters or less."))
        }
        draft.senderName = "Alex"
        draft.destination = String(repeating: flag, count: 101)
        XCTAssertThrowsError(try PostcardValidation.validate(draft)) { error in
            XCTAssertEqual(error as? PostcardServiceError, .validation("Destination must be 200 characters or less."))
        }
    }

    func testUpdateTrackerReportsOnlyNewOrUpdatedConversationsAfterTheFirstFetch() async {
        func conversation(_ id: UUID, _ seconds: TimeInterval) -> PostcardConversation {
            PostcardConversation(id: id, peer: FixturePostcardService.recipient, latestMessage: nil,
                                 updatedAt: Date(timeIntervalSince1970: seconds))
        }
        let a = UUID(), b = UUID(), c = UUID()
        let tracker = ConversationChangeTracker()
        let initial = await tracker.changed(in: [conversation(a, 10), conversation(b, 5)], reportAll: true)
        XCTAssertEqual(initial, [a, b], "the first fetch after (re)subscribing reports everything")
        let unchanged = await tracker.changed(in: [conversation(a, 10), conversation(b, 5)])
        XCTAssertEqual(unchanged, [])
        let changed = await tracker.changed(in: [conversation(c, 12), conversation(a, 11), conversation(b, 5)])
        XCTAssertEqual(changed, [c, a], "a new conversation and one whose updatedAt moved")
        let stale = await tracker.changed(in: [conversation(a, 10)])
        XCTAssertEqual(stale, [], "an out-of-order older refetch neither reports nor rewinds")
        let after = await tracker.changed(in: [conversation(a, 11)])
        XCTAssertEqual(after, [])
    }
}
