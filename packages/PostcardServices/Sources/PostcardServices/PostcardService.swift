import Foundation
import PostcardCore

public protocol PostcardService: Sendable {
    func currentProfile() async throws -> PostcardProfile?
    func signUp(email: String, password: String, username: String, displayName: String) async throws
    func signIn(email: String, password: String) async throws
    func signOut() async throws
    func lookupRecipient(username: String) async throws -> PostcardProfile?
    func conversations() async throws -> [PostcardConversation]
    func messages(conversationId: UUID, before: Date?, limit: Int) async throws -> [PostcardMessage]
    func send(draft: PostcardDraft) async throws -> PostcardMessage
    func photoURL(path: String) async throws -> URL
    func conversationUpdates() async throws -> AsyncThrowingStream<UUID, Error>
}

public enum PostcardValidation {
    /// Postgres `char_length` counts Unicode scalars, while Swift's `count` counts grapheme clusters
    /// (one flag emoji is 1 character but 2 scalars), so limits are checked on scalars to match the server.
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    public static func validate(_ draft: PostcardDraft) throws {
        guard draft.recipientId != nil else {
            throw PostcardServiceError.validation("Choose a recipient by username.")
        }
        guard !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              length(draft.message) <= 5000 else {
            throw PostcardServiceError.validation("Write a note between 1 and 5,000 characters.")
        }
        guard length(draft.senderName) <= 100, length(draft.recipientName) <= 100 else {
            throw PostcardServiceError.validation("Names must be 100 characters or less.")
        }
        guard length(draft.destination) <= 200 else {
            throw PostcardServiceError.validation("Destination must be 200 characters or less.")
        }
        guard let photo = draft.photoData, !photo.isEmpty else {
            throw PostcardServiceError.validation("Choose a photo for your postcard.")
        }
        guard photo.count <= 10_000_000 else {
            throw PostcardServiceError.validation("Photo must be 10 MB or less.")
        }
    }
}
