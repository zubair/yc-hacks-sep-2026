import XCTest
@testable import PostcardCore

final class ModelTests: XCTestCase {
    func testWireNamesAndISODate() throws {
        let message = PostcardMessage(
            id: UUID(), conversationId: UUID(), senderId: UUID(), recipientId: UUID(),
            senderName: "A", recipientName: "B", destination: "Paris", message: "Hello",
            photoPath: "photo.jpg", createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(message)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("conversation_id"))
        XCTAssertTrue(json.contains("created_at"))
        XCTAssertEqual(try decoder.decode(PostcardMessage.self, from: data), message)
    }
}
