import Foundation
import PostcardCore
import Supabase

/// Live service backed by Supabase Auth, RPC, Storage, and Realtime.
/// Construct with a project URL and publishable key; never pass a service-role key to an app.
public actor SupabasePostcardService: PostcardService {
    private let client: SupabaseClient
    private let decoder: JSONDecoder

    public init(url: URL, publishableKey: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
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
        guard !displayName.isEmpty, displayName.count <= 100 else {
            throw PostcardServiceError.validation("Enter a display name of 100 characters or less.")
        }
        do {
            _ = try await client.auth.signUp(email: email, password: password, data: [
                "username": .string(normalized), "display_name": .string(displayName)
            ])
        } catch { throw Self.map(error) }
    }

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
            if response.data == Data("null".utf8) { return nil }
            return try decoder.decode(PostcardProfile.self, from: response.data)
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
        let photoPath: String?
        if let photo = draft.photoData {
            do {
                let user = try await client.auth.session.user
                let path = "\(user.id.uuidString.lowercased())/\(draft.id.uuidString.lowercased())/photo.jpg"
                do {
                    try await client.storage.from("postcard-photos").upload(
                        path, data: photo, options: FileOptions(contentType: "image/jpeg", upsert: false)
                    )
                } catch {
                    // An earlier attempt can have uploaded the same draft photo before its RPC failed.
                    // Only an already-existing object at this exact owned path is retryable.
                    let storageError = error as? StorageError
                    guard storageError?.statusCode == "409" else {
                        throw error
                    }
                }
                photoPath = path
            } catch { throw Self.map(error) }
        } else {
            photoPath = nil
        }
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
                do {
                    try await channel.subscribeWithError()
                    // Initial and periodic refetch also cover reconnects and dropped realtime events.
                    for item in try await self.conversations() { continuation.yield(item.id) }
                    let poll = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(20))
                            if Task.isCancelled { break }
                            for item in (try? await self.conversations()) ?? [] { continuation.yield(item.id) }
                        }
                    }
                    for await _ in changes {
                        if Task.isCancelled { break }
                        for item in try await self.conversations() { continuation.yield(item.id) }
                    }
                    poll.cancel()
                } catch { continuation.finish(throwing: Self.map(error)) }
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
                try container.encode(ISO8601DateFormatter().string(from: p_before), forKey: .p_before)
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
        let p_photo_path: String?
        let p_client_request_id: UUID
    }

    private static func map(_ error: Error) -> PostcardServiceError {
        if let known = error as? PostcardServiceError { return known }
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(urlError.code) {
            return .offline
        }
        if let postgrest = error as? PostgrestError {
            switch postgrest.code {
            case "22023", "23514", "23505": return .validation(postgrest.message)
            case "28000": return .unauthenticated
            case "42501": return .forbidden
            case "P0002", "PGRST116": return .notFound
            default: return .server("Please try again.")
            }
        }
        if let storage = error as? StorageError {
            switch storage.statusCode {
            case "401": return .unauthenticated
            case "403": return .forbidden
            case "404": return .notFound
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
