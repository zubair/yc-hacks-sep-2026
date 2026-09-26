import Foundation
import PostcardCore

/// An in-memory, deterministic demo. A send succeeds only after the explicit `send` call.
public actor FixturePostcardService: PostcardService {
    public static let sender = PostcardProfile(
        id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, username: "alex", displayName: "Alex Rivera"
    )
    public static let recipient = PostcardProfile(
        id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, username: "sam", displayName: "Sam Lee"
    )
    public static let conversationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    private var signedInProfile: PostcardProfile?
    private var stored: [PostcardMessage] = []
    private var byRequest: [UUID: PostcardMessage] = [:]
    private var photos: [String: URL] = [:]
    private var listeners: [UUID: AsyncThrowingStream<UUID, Error>.Continuation] = [:]
    private var failNextSend = false
    private var offline = false

    public init(signedIn: Bool = true) {
        signedInProfile = signedIn ? Self.sender : nil
    }

    public func setOffline(_ value: Bool) { offline = value }
    public func failOneSend() { failNextSend = true }
    public func switchDemoUser() {
        signedInProfile = signedInProfile?.id == Self.sender.id ? Self.recipient : Self.sender
    }

    public func currentProfile() throws -> PostcardProfile? {
        try requireOnline()
        return signedInProfile
    }

    public func signUp(email: String, password: String, username: String, displayName: String) throws {
        try requireOnline()
        try validateAuth(email: email, password: password)
        guard username.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil else {
            throw PostcardServiceError.validation("Username must be 3–30 lowercase letters, numbers, or underscores.")
        }
        signedInProfile = PostcardProfile(id: Self.sender.id, username: username, displayName: displayName)
    }

    public func signIn(email: String, password: String) throws {
        try requireOnline()
        try validateAuth(email: email, password: password)
        signedInProfile = Self.sender
    }

    public func signOut() {
        signedInProfile = nil
        for listener in listeners.values { listener.finish() }
        listeners.removeAll()
    }

    public func lookupRecipient(username: String) throws -> PostcardProfile? {
        try requireAccess()
        let profile = username.lowercased() == Self.recipient.username ? Self.recipient :
            (username.lowercased() == Self.sender.username ? Self.sender : nil)
        return profile?.id == signedInProfile?.id ? nil : profile
    }

    public func conversations() throws -> [PostcardConversation] {
        try requireAccess()
        guard let latest = stored.max(by: { $0.createdAt < $1.createdAt }) else { return [] }
        let peer = signedInProfile?.id == Self.sender.id ? Self.recipient : Self.sender
        return [PostcardConversation(id: Self.conversationID, peer: peer, latestMessage: latest, updatedAt: latest.createdAt)]
    }

    public func messages(conversationId: UUID, before: Date?, limit: Int) throws -> [PostcardMessage] {
        try requireAccess()
        guard conversationId == Self.conversationID else { throw PostcardServiceError.notFound }
        return Array(stored.filter { before == nil || $0.createdAt < before! }
            .sorted { $0.createdAt > $1.createdAt }.prefix(max(1, min(limit, 100))))
    }

    public func send(draft: PostcardDraft) throws -> PostcardMessage {
        try requireAccess()
        try PostcardValidation.validate(draft)
        guard draft.recipientId != signedInProfile?.id,
              [Self.sender.id, Self.recipient.id].contains(draft.recipientId!) else { throw PostcardServiceError.notFound }
        if let original = byRequest[draft.id] { return original }
        if failNextSend {
            failNextSend = false
            throw PostcardServiceError.server("Demo failure. Retry the same draft.")
        }
        let path = "demo/\(draft.id.uuidString)/photo.jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("postcard-\(draft.id.uuidString).jpg")
        guard let photo = draft.photoData else { throw PostcardServiceError.validation("Choose a photo for your postcard.") }
        try photo.write(to: url, options: .atomic)
        photos[path] = url
        let item = PostcardMessage(
            id: UUID(), conversationId: Self.conversationID, senderId: signedInProfile!.id,
            recipientId: draft.recipientId!, senderName: draft.senderName,
            recipientName: draft.recipientName, destination: draft.destination,
            message: draft.message, photoPath: path, createdAt: Date()
        )
        stored.append(item)
        byRequest[draft.id] = item
        for listener in listeners.values { listener.yield(Self.conversationID) }
        return item
    }

    public func photoURL(path: String) throws -> URL {
        try requireAccess()
        guard let url = photos[path] else { throw PostcardServiceError.notFound }
        return url
    }

    public func conversationUpdates() throws -> AsyncThrowingStream<UUID, Error> {
        try requireAccess()
        let id = UUID()
        return AsyncThrowingStream { continuation in
            listeners[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeListener(id) }
            }
        }
    }

    private func removeListener(_ id: UUID) { listeners.removeValue(forKey: id) }
    private func requireOnline() throws {
        if offline { throw PostcardServiceError.offline }
    }
    private func requireAccess() throws {
        try requireOnline()
        if signedInProfile == nil { throw PostcardServiceError.unauthenticated }
    }
    private func validateAuth(email: String, password: String) throws {
        guard email.contains("@"), password.count >= 8 else {
            throw PostcardServiceError.validation("Enter a valid email and a password of at least eight characters.")
        }
    }
}
