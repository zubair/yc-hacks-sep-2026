import Foundation
import PostcardCore
import Supabase

/// Supabase Postgres emits microsecond timestamps; Foundation's plain `.iso8601` strategy rejects them.
enum PostcardWireCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let dot = value.firstIndex(of: "."), value.hasSuffix("Z") {
                let digits = value[value.index(after: dot)..<value.index(before: value.endIndex)]
                let whole = String(value[..<dot]) + "Z"
                if !digits.isEmpty, digits.allSatisfy(\.isNumber),
                   let date = plain.date(from: whole),
                   let fraction = TimeInterval("0." + digits) {
                    return date.addingTimeInterval(fraction)
                }
            }
            if let date = plain.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let totalMicroseconds = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
        let seconds = totalMicroseconds / 1_000_000
        let fraction = totalMicroseconds % 1_000_000
        let base = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        return String(base.dropLast()) + String(format: ".%06dZ", fraction)
    }
}

/// Live service backed by Supabase Auth, RPC, Storage, and Realtime.
/// Construct with a project URL and publishable key; never pass a service-role key to an app.
public actor SupabasePostcardService: PostcardService {
    private let client: SupabaseClient
    private let decoder: JSONDecoder

    public init(url: URL, publishableKey: String) {
        #if os(Linux) || os(Android)
        // No Keychain off Apple platforms: keep the session in memory (Linux CI and live contract tests).
        let options = SupabaseClientOptions(auth: .init(storage: InMemoryAuthStorage()))
        #else
        let options = SupabaseClientOptions()
        #endif
        self.init(client: SupabaseClient(supabaseURL: url, supabaseKey: publishableKey, options: options))
    }

    /// Injects a configured client, e.g. one with isolated session storage per test identity.
    init(client: SupabaseClient) {
        self.client = client
        decoder = PostcardWireCoding.decoder()
    }

    public func currentProfile() async throws -> PostcardProfile? {
        do {
            let session = try await client.auth.session
            let response = try await client.from("profiles").select("id,username,display_name")
                .eq("id", value: session.user.id.uuidString).single().execute()
            return try decoder.decode(PostcardProfile.self, from: response.data)
        } catch {
            if let authError = error as? AuthError, authError == .sessionMissing { return nil }
            throw Self.map(error)
        }
    }

    public func signUp(email: String, password: String, username: String, displayName: String) async throws {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil else {
            throw PostcardServiceError.validation("Username must be 3–30 lowercase letters, numbers, or underscores.")
        }
        guard !displayName.isEmpty, PostcardValidation.length(displayName) <= 100 else {
            throw PostcardServiceError.validation("Enter a display name of 100 characters or less.")
        }
        do {
            _ = try await client.auth.signUp(email: email, password: password, data: [
                "username": .string(normalized), "display_name": .string(displayName)
            ])
        } catch let AuthError.api(_, _, _, response) where [409, 500].contains(response.statusCode) {
            // The profile trigger rejects a taken username. GoTrue passes its PT409 through as HTTP 409;
            // older GoTrue versions report any trigger failure as HTTP 500 "Database error saving new user".
            throw PostcardServiceError.validation(Self.usernameUnavailable)
        } catch { throw Self.map(error) }
    }

    static let usernameUnavailable = "That username is taken or invalid. Choose another."

    public func signIn(email: String, password: String) async throws {
        do { _ = try await client.auth.signIn(email: email, password: password) }
        catch { throw Self.map(error) }
    }

    public func signOut() async throws {
        do { try await client.auth.signOut() }
        catch { throw Self.map(error) }
    }

    public func lookupRecipient(username: String) async throws -> PostcardProfile? {
        do {
            let response = try await client.rpc("lookup_recipient", params: ["p_username": username.lowercased()]).execute()
            return try decoder.decode(PostcardProfile?.self, from: response.data)
        } catch { throw Self.map(error) }
    }

    public func conversations() async throws -> [PostcardConversation] {
        do {
            let response = try await client.rpc("list_conversations").execute()
            return try decoder.decode([PostcardConversation].self, from: response.data)
        } catch { throw Self.map(error) }
    }

    public func messages(conversationId: UUID, before: Date?, limit: Int) async throws -> [PostcardMessage] {
        do {
            let params = MessageParams(p_conversation_id: conversationId, p_before: before, p_limit: max(1, min(limit, 100)))
            let response = try await client.rpc("list_messages", params: params).execute()
            return try decoder.decode([PostcardMessage].self, from: response.data)
        } catch { throw Self.map(error) }
    }

    public func send(draft: PostcardDraft) async throws -> PostcardMessage {
        try PostcardValidation.validate(draft)
        guard let recipientId = draft.recipientId else { throw PostcardServiceError.validation("Choose a recipient.") }
        guard let photo = draft.photoData else { throw PostcardServiceError.validation("Choose a photo for your postcard.") }
        let photoPath: String
        do {
            let user = try await client.auth.session.user
            let path = "\(user.id.uuidString.lowercased())/\(draft.id.uuidString.lowercased())/photo.jpg"
            do {
                try await client.storage.from("postcard-photos").upload(
                    path, data: photo, options: FileOptions(contentType: "image/jpeg", upsert: false)
                )
            } catch {
                // Storage returns HTTP 400 with an embedded 409 code for an existing object.
                let storageError = error as? StorageError
                guard storageError?.statusCode == "409" else {
                    throw error
                }
            }
            photoPath = path
        } catch { throw Self.map(error) }
        do {
            let params = SendParams(
                p_recipient_id: recipientId, p_sender_name: draft.senderName,
                p_recipient_name: draft.recipientName, p_destination: draft.destination,
                p_message: draft.message, p_photo_path: photoPath, p_client_request_id: draft.id
            )
            let response = try await client.rpc("send_postcard", params: params).execute()
            return try decoder.decode(PostcardMessage.self, from: response.data)
        } catch { throw Self.map(error) }
    }

    public func photoURL(path: String) async throws -> URL {
        do {
            return try await client.storage.from("postcard-photos").createSignedURL(path: path, expiresIn: 300)
        } catch { throw Self.map(error) }
    }

    public func conversationUpdates() async throws -> AsyncThrowingStream<UUID, Error> {
        _ = try await client.auth.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                let channel = client.channel("postcards-\(UUID().uuidString)")
                let changes = channel.postgresChange(InsertAction.self, schema: "public", table: "postcards")
                let tracker = ConversationChangeTracker()
                var poll: Task<Void, Never>?
                var failure: Error?
                do {
                    try await channel.subscribeWithError()
                    // The first fetch after subscribing reports every conversation, covering reconnects and
                    // anything missed while disconnected. Later refetches report only new or updated ones.
                    for id in await tracker.changed(in: try await self.conversations(), reportAll: true) {
                        continuation.yield(id)
                    }
                    // Periodic refetch covers dropped realtime events.
                    poll = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(20))
                            if Task.isCancelled { break }
                            guard let items = try? await self.conversations() else { continue }
                            for id in await tracker.changed(in: items) { continuation.yield(id) }
                        }
                    }
                    for await _ in changes {
                        if Task.isCancelled { break }
                        // One failed refetch must not end the stream; the next event or poll retries.
                        guard let items = try? await self.conversations() else { continue }
                        for id in await tracker.changed(in: items) { continuation.yield(id) }
                    }
                } catch { failure = error }
                poll?.cancel()
                if let failure { continuation.finish(throwing: Self.map(failure)) }
                await channel.unsubscribe()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct MessageParams: Encodable, Sendable {
        let p_conversation_id: UUID
        let p_before: Date?
        let p_limit: Int

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(p_conversation_id, forKey: .p_conversation_id)
            if let p_before {
                try container.encode(PostcardWireCoding.timestamp(p_before), forKey: .p_before)
            } else {
                try container.encodeNil(forKey: .p_before)
            }
            try container.encode(p_limit, forKey: .p_limit)
        }
        enum CodingKeys: String, CodingKey { case p_conversation_id, p_before, p_limit }
    }

    private struct SendParams: Encodable, Sendable {
        let p_recipient_id: UUID
        let p_sender_name: String
        let p_recipient_name: String
        let p_destination: String
        let p_message: String
        let p_photo_path: String
        let p_client_request_id: UUID
    }

    static func map(_ error: Error) -> PostcardServiceError {
        if let known = error as? PostcardServiceError { return known }
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(urlError.code) {
            return .offline
        }
        if let postgrest = error as? PostgrestError {
            switch postgrest.code {
            case "PT401", "42501", "PGRST301", "PGRST303": return .unauthenticated
            case "PT403": return .forbidden
            case "PT404", "PGRST116": return .notFound
            case "PT409", "PT422", "22023", "23514", "23505": return .validation(postgrest.message)
            default: return .server("Please try again.")
            }
        }
        if let storage = error as? StorageError {
            switch storage.statusCode {
            case "401": return .unauthenticated
            case "403": return .forbidden
            case "404": return .notFound
            case "400", "415": return .validation(storage.message)
            case "413": return .validation("Photo must be 10 MB or less.")
            default: return .server("Photo could not be saved. Please try again.")
            }
        }
        if let auth = error as? AuthError {
            switch auth {
            case .sessionMissing: return .unauthenticated
            case .weakPassword: return .validation("Choose a stronger password.")
            case .api(let message, _, _, let response):
                if response.statusCode == 401 { return .unauthenticated }
                if response.statusCode == 422 || response.statusCode == 400 { return .validation(message) }
                return .server("Please try again.")
            default: return .server("Please try again.")
            }
        }
        return .server("Please try again.")
    }
}

/// Remembers each conversation's `updatedAt` for one update stream so a refetch reports only what changed,
/// instead of making the app reload every conversation on each event or poll.
actor ConversationChangeTracker {
    private var known: [UUID: Date] = [:]

    /// IDs of conversations that are new or whose `updatedAt` moved forward; every ID when `reportAll`.
    /// `updated_at` only increases, so a stale, out-of-order refetch never reports or rewinds anything.
    func changed(in conversations: [PostcardConversation], reportAll: Bool = false) -> [UUID] {
        var ids: [UUID] = []
        for conversation in conversations {
            let isNewer = known[conversation.id].map { conversation.updatedAt > $0 } ?? true
            if isNewer { known[conversation.id] = conversation.updatedAt }
            if reportAll || isNewer { ids.append(conversation.id) }
        }
        return ids
    }
}

/// Process-local session storage for platforms without Keychain and for tests that need isolated identities.
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}
