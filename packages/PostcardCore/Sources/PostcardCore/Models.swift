import Foundation

public struct PostcardProfile: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let username: String
    public let displayName: String

    public init(id: UUID, username: String, displayName: String) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
    }
}

public struct PostcardDraft: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var recipientId: UUID?
    public var recipientName: String
    public var senderName: String
    public var destination: String
    public var message: String
    public var photoData: Data?

    public init(
        id: UUID = UUID(), recipientId: UUID? = nil, recipientName: String = "",
        senderName: String = "", destination: String = "", message: String = "",
        photoData: Data? = nil
    ) {
        self.id = id
        self.recipientId = recipientId
        self.recipientName = recipientName
        self.senderName = senderName
        self.destination = destination
        self.message = message
        self.photoData = photoData
    }

    enum CodingKeys: String, CodingKey {
        case id, destination, message
        case recipientId = "recipient_id"
        case recipientName = "recipient_name"
        case senderName = "sender_name"
        case photoData = "photo_data"
    }
}

public struct PostcardMessage: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let conversationId: UUID
    public let senderId: UUID
    public let recipientId: UUID
    public let senderName: String
    public let recipientName: String
    public let destination: String
    public let message: String
    public let photoPath: String?
    public let createdAt: Date

    public init(
        id: UUID, conversationId: UUID, senderId: UUID, recipientId: UUID,
        senderName: String, recipientName: String, destination: String,
        message: String, photoPath: String?, createdAt: Date
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.recipientId = recipientId
        self.senderName = senderName
        self.recipientName = recipientName
        self.destination = destination
        self.message = message
        self.photoPath = photoPath
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, destination, message
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case senderName = "sender_name"
        case recipientName = "recipient_name"
        case photoPath = "photo_path"
        case createdAt = "created_at"
    }
}

public struct PostcardConversation: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let peer: PostcardProfile
    public let latestMessage: PostcardMessage?
    public let updatedAt: Date

    public init(id: UUID, peer: PostcardProfile, latestMessage: PostcardMessage?, updatedAt: Date) {
        self.id = id
        self.peer = peer
        self.latestMessage = latestMessage
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, peer
        case latestMessage = "latest_message"
        case updatedAt = "updated_at"
    }
}

public enum PostcardPresentationState: String, Codable, Equatable, Sendable {
    case front, writing, sealed, sending, sent
}

public enum PostcardServiceError: Error, Equatable, Sendable {
    case unauthenticated, forbidden, validation(String), offline, notFound, server(String)
}

extension PostcardServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthenticated: "Sign in to send and receive postcards."
        case .forbidden: "You do not have access to this postcard."
        case .validation(let detail): detail
        case .offline: "You appear to be offline. Your draft is saved; try again when connected."
        case .notFound: "That postcard or recipient was not found."
        case .server(let detail): "Something went wrong: \(detail)"
        }
    }
}
