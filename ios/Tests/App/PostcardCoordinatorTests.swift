import Foundation
import PostcardCore
import PostcardServices
import Testing
@testable import Postcard

@Suite("Postcard app integration")
@MainActor
struct PostcardCoordinatorTests {
    @Test func foldingNeverSendsAndRetryKeepsTheIdempotencyKey() async {
        let service = FixtureRecordingService()
        let store = LocalDraftStore(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "postcard-test-\(UUID().uuidString).json")
        )
        let coordinator = PostcardCoordinator(
            service: service,
            mode: .demo,
            draftStore: store,
            haptics: QuietHaptics()
        )
        await coordinator.start()
        let originalID = coordinator.draft.id
        coordinator.draft.recipientId = UUID()
        coordinator.draft.recipientName = "Ari"
        coordinator.draft.message = "Hello from the coast"

        coordinator.presentation.observeNativePosture(.open)
        coordinator.presentation.observeNativePosture(.closed)
        #expect(coordinator.presentation.state == .sealed)
        #expect(await service.sentDraftIDs().isEmpty)

        coordinator.send()
        coordinator.send()
        await coordinator.waitForSend()
        #expect(coordinator.presentation.state == .sealed)
        #expect(coordinator.draft.id == originalID)

        coordinator.send()
        await coordinator.waitForSend()
        #expect(coordinator.presentation.state == .sent)
        #expect(coordinator.draft.id != originalID)
        #expect(await service.sentDraftIDs() == [originalID, originalID])
        await coordinator.signOut()
    }

    @Test func authenticationRequiredUntilSessionExists() async {
        let service = FixtureRecordingService()
        let coordinator = PostcardCoordinator(
            service: service,
            mode: .live,
            haptics: QuietHaptics()
        )
        await coordinator.start()
        #expect(coordinator.requiresAuthentication)
        coordinator.presentation.observeNativePosture(.open)
        #expect(coordinator.presentation.state == .front)

        await coordinator.signUp(
            email: "test@example.invalid",
            password: "password",
            username: "test_user",
            displayName: "Test"
        )
        #expect(coordinator.authError?.contains("confirm") == true)

        await coordinator.signIn(email: "test@example.invalid", password: "password")
        #expect(!coordinator.requiresAuthentication)
        await coordinator.signOut()
        #expect(coordinator.requiresAuthentication)
    }

    @Test func cancelPreservesTheDraftForAnExplicitRetry() async throws {
        let service = FixtureRecordingService()
        await service.delayNextSend()
        let coordinator = PostcardCoordinator(
            service: service,
            mode: .demo,
            haptics: QuietHaptics()
        )
        await coordinator.start()
        coordinator.draft.recipientId = UUID()
        coordinator.draft.message = "A note"
        let draftID = coordinator.draft.id
        coordinator.presentation.open()
        coordinator.presentation.seal()
        coordinator.send()

        for _ in 0..<50 {
            if await service.sentDraftIDs().count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        coordinator.cancelSend()
        #expect(coordinator.presentation.state == .sealed)
        #expect(coordinator.draft.id == draftID)

        coordinator.send()
        await coordinator.waitForSend()
        #expect(coordinator.presentation.state == .sent)
        #expect(await service.sentDraftIDs() == [draftID, draftID])
        await coordinator.signOut()
    }

    @Test func resumeRefetchesDurableInbox() async {
        let service = FixtureRecordingService()
        let coordinator = PostcardCoordinator(
            service: service,
            mode: .demo,
            haptics: QuietHaptics()
        )
        await coordinator.start()
        let before = await service.inboxFetchCount()
        await coordinator.suspend()
        await coordinator.resume()
        #expect(await service.inboxFetchCount() > before)
        await coordinator.signOut()
    }
}

@MainActor
private struct QuietHaptics: PostcardHapticOutput {
    func opened() {}
    func sealed() {}
    func sent() {}
}

private actor FixtureRecordingService: PostcardService {
    private var profile: PostcardProfile?
    private var sentIDs: [UUID] = []
    private var shouldFailFirstSend = true
    private var shouldDelayNextSend = false
    private var fetchCount = 0

    func sentDraftIDs() -> [UUID] { sentIDs }
    func inboxFetchCount() -> Int { fetchCount }
    func delayNextSend() {
        shouldFailFirstSend = false
        shouldDelayNextSend = true
    }

    func currentProfile() async throws -> PostcardProfile? { profile }

    func signUp(email: String, password: String, username: String, displayName: String) async throws {}

    func signIn(email: String, password: String) async throws {
        profile = PostcardProfile(id: UUID(), username: "test_user", displayName: "Test")
    }

    func signOut() async throws { profile = nil }

    func lookupRecipient(username: String) async throws -> PostcardProfile? { nil }

    func conversations() async throws -> [PostcardConversation] {
        fetchCount += 1
        return []
    }

    func messages(conversationId: UUID, before: Date?, limit: Int) async throws -> [PostcardMessage] { [] }

    func send(draft: PostcardDraft) async throws -> PostcardMessage {
        sentIDs.append(draft.id)
        if shouldDelayNextSend {
            shouldDelayNextSend = false
            try await Task.sleep(for: .seconds(1))
        }
        if shouldFailFirstSend {
            shouldFailFirstSend = false
            throw PostcardServiceError.offline
        }
        return PostcardMessage(
            id: UUID(),
            conversationId: UUID(),
            senderId: profile?.id ?? UUID(),
            recipientId: draft.recipientId ?? UUID(),
            senderName: draft.senderName,
            recipientName: draft.recipientName,
            destination: draft.destination,
            message: draft.message,
            photoPath: nil,
            createdAt: .now
        )
    }

    func photoURL(path: String) async throws -> URL { URL(string: "https://example.invalid/photo")! }

    func conversationUpdates() async throws -> AsyncThrowingStream<UUID, Error> {
        AsyncThrowingStream { _ in }
    }
}
