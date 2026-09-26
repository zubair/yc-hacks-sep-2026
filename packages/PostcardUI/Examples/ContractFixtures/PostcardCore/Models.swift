// VALIDATION FIXTURE ONLY. Never link this module into the production app.
// Minimal agreed wire models used until Pranav's packages are available.
import Foundation
public struct PostcardProfile: Codable, Equatable, Sendable {
    public var id: UUID
    public var username: String
    public var displayName: String
}
public struct PostcardDraft: Codable, Equatable, Sendable {
    public var id: UUID
    public var recipientId: UUID?
    public var recipientName: String
    public var senderName: String
    public var destination: String
    public var message: String
    public var photoData: Data?
}
public struct PostcardMessage: Codable, Equatable, Sendable {
    public var id: UUID
    public var conversationId: UUID
    public var senderId: UUID
    public var recipientId: UUID
    public var senderName: String
    public var recipientName: String
    public var destination: String
    public var message: String
    public var photoPath: String
    public var createdAt: Date
}
public struct PostcardConversation: Codable, Equatable, Sendable {
    public var id: UUID
    public var peer: PostcardProfile
    public var latestMessage: PostcardMessage?
    public var updatedAt: Date
}
public enum PostcardPresentationState: String, Codable, Sendable { case front, writing, sealed, sending, sent }
