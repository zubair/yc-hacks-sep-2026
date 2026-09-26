import XCTest
import PostcardCore
@testable import PostcardUI

final class FormRulesTests: XCTestCase {
    private func validDraft() throws -> PostcardDraft {
        let json: [String: Any] = ["id": UUID().uuidString, "recipientId": UUID().uuidString,
            "recipientName": "Olivia", "senderName": "Alex", "destination": "Cinque Terre",
            "message": "Wish you were here.", "photoData": Data([1]).base64EncodedString()]
        return try JSONDecoder().decode(PostcardDraft.self, from: JSONSerialization.data(withJSONObject: json))
    }
    func testIncompleteDraftCannotSendAndIsNotMutated() throws {
        var draft = try validDraft()
        XCTAssertNil(PostcardFormRules.sendIssue(draft))
        draft.recipientId = nil
        let before = draft
        XCTAssertNotNil(PostcardFormRules.sendIssue(draft))
        XCTAssertEqual(before, draft)
    }
    func testWhitespaceAndOverlongMessagesAreRejectedWithoutTruncation() throws {
        var draft = try validDraft()
        draft.message = " \n "
        XCTAssertNotNil(PostcardFormRules.sendIssue(draft))
        draft.message = String(repeating: "é", count: 5000)
        XCTAssertNil(PostcardFormRules.sendIssue(draft))
        draft.message += "!"
        XCTAssertNotNil(PostcardFormRules.sendIssue(draft))
        XCTAssertEqual(draft.message.count, 5001)
    }
    func testMissingPhotoAndOverlongNamesAreRejected() throws {
        var draft = try validDraft()
        draft.photoData = Data()
        XCTAssertNotNil(PostcardFormRules.sendIssue(draft))
        draft = try validDraft(); draft.senderName = String(repeating: "a", count: 101)
        XCTAssertNotNil(PostcardFormRules.sendIssue(draft))
        draft = try validDraft(); draft.destination = String(repeating: "a", count: 201)
        XCTAssertNotNil(PostcardFormRules.sendIssue(draft))
    }
    func testRecipientNormalizationAndExactUsernameRules() {
        XCTAssertEqual(PostcardFormRules.normalizedUsername(" OLIVIA_1 \n"), "olivia_1")
        XCTAssertTrue(PostcardFormRules.validUsername("olivia_1"))
        XCTAssertFalse(PostcardFormRules.validUsername("ab"))
        XCTAssertFalse(PostcardFormRules.validUsername("olivia@example.com"))
        XCTAssertFalse(PostcardFormRules.validUsername("olivia space"))
    }
    func testSignupValidation() {
        XCTAssertNil(PostcardFormRules.signupIssue(email: "alex@example.com", password: "long-enough", username: "alex_1", displayName: "Alex"))
        XCTAssertNotNil(PostcardFormRules.signupIssue(email: "alex", password: "long-enough", username: "alex_1", displayName: "Alex"))
        XCTAssertNotNil(PostcardFormRules.signupIssue(email: "alex@example.com", password: "short", username: "alex_1", displayName: "Alex"))
    }
}
