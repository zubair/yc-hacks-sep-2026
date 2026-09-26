import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import Supabase
import PostcardCore
@testable import PostcardServices

/// Opt-in contract test of `SupabasePostcardService` against a LOCAL Supabase stack (`supabase start`).
/// It signs up throwaway users and sends postcards, so it refuses any non-local URL.
///
///     POSTCARD_LIVE_SUPABASE_URL=http://127.0.0.1:54321 \
///     POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY=<supabase status: PUBLISHABLE_KEY> swift test --filter LiveSupabaseTests
final class LiveSupabaseTests: XCTestCase {
    private static let jpeg = Data(base64Encoded:
        "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AN//Z")!
    private let run = String(UUID().uuidString.prefix(6)).lowercased()

    private func configuration() throws -> (URL, String) {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["POSTCARD_LIVE_SUPABASE_URL"], let key = env["POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY"],
              let url = URL(string: raw) else {
            throw XCTSkip("Set POSTCARD_LIVE_SUPABASE_URL and POSTCARD_LIVE_SUPABASE_PUBLISHABLE_KEY to run live tests.")
        }
        guard ["127.0.0.1", "localhost"].contains(url.host ?? "") else {
            throw XCTSkip("Refusing to create test users on non-local \(raw).")
        }
        return (url, key)
    }

    /// Each identity gets its own client and in-memory session so they never share a stored session.
    private func service() throws -> SupabasePostcardService {
        let (url, key) = try configuration()
        let options = SupabaseClientOptions(auth: .init(storage: InMemoryAuthStorage()))
        return SupabasePostcardService(client: SupabaseClient(supabaseURL: url, supabaseKey: key, options: options))
    }

    private func signedUp(_ label: String) async throws -> (SupabasePostcardService, PostcardProfile) {
        let service = try service()
        let username = "\(label)_\(run)"
        try await service.signUp(email: "\(username)@postcard.test", password: "local-test-password-1",
                                 username: username, displayName: label.capitalized)
        let profile = try await XCTUnwrapAsync(await service.currentProfile(), "local stack issues a session on signup")
        XCTAssertEqual(profile.username, username)
        return (service, profile)
    }

    private func draft(to recipient: PostcardProfile, message: String, id: UUID = UUID()) -> PostcardDraft {
        PostcardDraft(id: id, recipientId: recipient.id, recipientName: recipient.displayName, senderName: "Live Sender",
                      destination: "Porto", message: message, photoData: Self.jpeg)
    }

    func testSendReceiveAndReadThroughTheRealBackend() async throws {
        let (alice, _) = try await signedUp("alice")
        let (bob, bobProfile) = try await signedUp("bob")
        let (eve, _) = try await signedUp("eve")

        // Exact, case-insensitive lookup that exposes only the public profile.
        let found = try await alice.lookupRecipient(username: bobProfile.username.uppercased())
        XCTAssertEqual(found, bobProfile)
        let missing = try await alice.lookupRecipient(username: "nobody_\(run)")
        XCTAssertNil(missing)

        // Upload + transactional RPC; a retry of the same draft id returns the original message.
        let first = draft(to: bobProfile, message: "Hello from the live contract test.")
        let sent = try await alice.send(draft: first)
        let retried = try await alice.send(draft: first)
        XCTAssertEqual(sent, retried, "same draft id is idempotent across upload and RPC")
        XCTAssertEqual(sent.recipientId, bobProfile.id)
        XCTAssertTrue(sent.photoPath.hasSuffix("/\(first.id.uuidString.lowercased())/photo.jpg"))

        // Reusing a sent draft id with different content is rejected rather than silently re-sent.
        var conflicting = first
        conflicting.message = "Different content, same idempotency key."
        await XCTAssertThrowsErrorAsync(try await alice.send(draft: conflicting)) { error in
            guard case .validation = error as? PostcardServiceError else { return XCTFail("expected validation, got \(error)") }
        }

        // The recipient lists the conversation and messages; microsecond timestamps survive p_before paging.
        let conversations = try await bob.conversations()
        let conversation = try XCTUnwrap(conversations.first { $0.id == sent.conversationId })
        XCTAssertEqual(conversation.latestMessage, sent)
        let messages = try await bob.messages(conversationId: sent.conversationId, before: nil, limit: 20)
        XCTAssertEqual(messages, [sent])
        let older = try await bob.messages(conversationId: sent.conversationId, before: sent.createdAt, limit: 20)
        XCTAssertTrue(older.isEmpty)

        // Signed photo URL (≤ 5 minutes) downloads the exact uploaded bytes for the recipient.
        let url = try await bob.photoURL(path: sent.photoPath)
        let (bytes, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(bytes, Self.jpeg)

        // An outsider can see neither the conversation nor the photo.
        await XCTAssertThrowsErrorAsync(try await eve.messages(conversationId: sent.conversationId, before: nil, limit: 20)) { error in
            XCTAssertEqual(error as? PostcardServiceError, .notFound)
        }
        let eveConversations = try await eve.conversations()
        XCTAssertTrue(eveConversations.isEmpty)
        await XCTAssertThrowsErrorAsync(try await eve.photoURL(path: sent.photoPath))
    }

    func testValidationAndAuthenticationErrorsMapToServiceErrors() async throws {
        let (alice, aliceProfile) = try await signedUp("carol")
        var noPhoto = draft(to: aliceProfile, message: "No photo")
        noPhoto.photoData = nil
        await XCTAssertThrowsErrorAsync(try await alice.send(draft: noPhoto)) { error in
            XCTAssertEqual(error as? PostcardServiceError, .validation("Choose a photo for your postcard."))
        }
        await XCTAssertThrowsErrorAsync(try await alice.send(draft: self.draft(to: aliceProfile, message: "To myself"))) { error in
            guard case .validation = error as? PostcardServiceError else { return XCTFail("self-send must be rejected, got \(error)") }
        }
        let anonymous = try service()
        let nobody = try await anonymous.currentProfile()
        XCTAssertNil(nobody)
        await XCTAssertThrowsErrorAsync(try await anonymous.conversations()) { error in
            XCTAssertEqual(error as? PostcardServiceError, .unauthenticated)
        }
        try await alice.signOut()
        await XCTAssertThrowsErrorAsync(try await alice.conversations()) { error in
            XCTAssertEqual(error as? PostcardServiceError, .unauthenticated)
        }
    }

    /// swift-corelibs-foundation opens WebSockets through the system libcurl, which some distributions
    /// (e.g. Ubuntu 24.04's libcurl 8.5) build without `ws`/`wss`. Skip clearly instead of failing after the
    /// realtime client's retries. Run with `LD_LIBRARY_PATH` pointing at a libcurl built with WebSockets to cover it.
    private func requireWebSocketSupport() async throws {
        #if canImport(FoundationNetworking)
        let (url, key) = try configuration()
        var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.scheme = url.scheme == "https" ? "wss" : "ws"
        components.path = "/realtime/v1/websocket"
        components.queryItems = [URLQueryItem(name: "apikey", value: key), URLQueryItem(name: "vsn", value: "2.0.0")]
        let task = URLSession.shared.webSocketTask(with: try XCTUnwrap(components.url))
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }
        do {
            try await task.send(.string(#"{"topic":"phoenix","event":"heartbeat","payload":{},"ref":"probe"}"#))
        } catch let error as URLError where error.code == .unsupportedURL {
            throw XCTSkip("This Foundation's libcurl lacks WebSocket support: \(error.localizedDescription)")
        } catch {
            // Any other probe failure is left for the realtime assertions below to report.
        }
        #endif
    }

    func testRealtimeInsertTriggersConversationRefetch() async throws {
        try await requireWebSocketSupport()
        let (sender, _) = try await signedUp("dave")
        let (recipient, recipientProfile) = try await signedUp("erin")
        let opening = try await sender.send(draft: draft(to: recipientProfile, message: "First, so the conversation exists."))

        let updates = try await recipient.conversationUpdates()
        var iterator = updates.makeAsyncIterator()
        // Subscribing refetches once; that covers reconnects and anything missed while disconnected.
        let initial = try await iterator.next()
        XCTAssertEqual(initial, opening.conversationId)

        let started = Date()
        _ = try await sender.send(draft: draft(to: recipientProfile, message: "Second, delivered by realtime."))
        let pushed = try await iterator.next()
        XCTAssertEqual(pushed, opening.conversationId)
        // The adapter's fallback poll runs every 20 s, so an earlier event came from the postgres_changes subscription.
        XCTAssertLessThan(Date().timeIntervalSince(started), 15, "insert should arrive via realtime, not the poll")
    }
}

// MARK: Async assertion helpers

private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let resolved = try await value()
    return try XCTUnwrap(resolved, message, file: file, line: line)
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath,
                                          line: UInt = #line, _ handler: (Error) -> Void = { _ in }) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}
