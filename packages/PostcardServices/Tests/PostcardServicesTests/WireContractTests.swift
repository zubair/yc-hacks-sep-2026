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
        XCTAssertEqual(sent.photoPath, "00000000-0000-4000-a000-00000000a11c/6acee6b3-adc1-42a9-a029-e834bc178932/photo.jpg")
        XCTAssertEqual(PostcardWireCoding.timestamp(sent.createdAt), "2026-09-26T20:59:44.965178Z")
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
}
