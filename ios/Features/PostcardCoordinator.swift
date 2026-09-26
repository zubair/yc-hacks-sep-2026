import Foundation
import Observation
import PostcardCore
import PostcardServices
import UIKit

enum PostcardRuntimeMode: Sendable {
    case demo
    case live

    var label: String? {
        self == .demo ? "DEMO · simulated sends" : nil
    }
}

@MainActor
@Observable
final class PostcardCoordinator {
    var draft: PostcardDraft {
        didSet { scheduleDraftSave() }
    }

    private(set) var presentation: DuoStateController
    private(set) var profile: PostcardProfile?
    private(set) var recipientLookupResult: PostcardProfile?
    private(set) var recipientLookupMessage: String?
    private(set) var conversations: [PostcardConversation] = []
    private(set) var messages: [PostcardMessage] = []
    private(set) var resolvedPhotoURLs: [UUID: URL] = [:]
    private(set) var resolvedPhotoData: [UUID: Data] = [:]
    private(set) var photoErrors: [UUID: String] = [:]
    private(set) var selectedConversationID: UUID?
    private(set) var isStarting = true
    private(set) var isLookingUpRecipient = false
    private(set) var isLoadingInbox = false
    private(set) var isLoadingConversation = false
    private(set) var isAuthenticating = false
    private(set) var authError: String?
    private(set) var authNotice: String?
    private(set) var composerError: String?
    private(set) var inboxError: String?
    private(set) var conversationError: String?
    private(set) var lastSentMessage: PostcardMessage?

    let mode: PostcardRuntimeMode

    @ObservationIgnored private let service: any PostcardService
    @ObservationIgnored private let draftStore: LocalDraftStore
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>?
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var draftRevision: UInt64 = 0
    @ObservationIgnored private var lookupRevision: UInt64 = 0
    @ObservationIgnored private var submissionToken: UUID?
    @ObservationIgnored private var isModalPresented = false

    init(
        service: any PostcardService,
        mode: PostcardRuntimeMode,
        draftStore: LocalDraftStore = LocalDraftStore(),
        haptics: any PostcardHapticOutput = SystemPostcardHaptics()
    ) {
        self.service = service
        self.mode = mode
        self.draftStore = draftStore
        draft = PostcardDraft()
        presentation = DuoStateController(haptics: haptics)
        presentation.setBlocked(mode == .live)
    }

    var requiresAuthentication: Bool {
        mode == .live && profile == nil
    }

    func start() async {
        defer { isStarting = false }
        do {
            if mode == .demo && ProcessInfo.processInfo.arguments.contains("-resetDemo") {
                draft = freshDraft()
            } else if let saved = try await draftStore.load() {
                draft = saved
            }
        } catch {
            composerError = "Your saved draft could not be opened. A new draft is ready."
        }
        if mode == .demo && draft.photoData == nil {
            draft.photoData = demoPhotoData()
        }
        await refreshSession()
    }

    func refreshSession() async {
        do {
            profile = try await service.currentProfile()
            if draft.senderName.isEmpty, let profile {
                draft.senderName = profile.displayName
            }
            authError = nil
            authNotice = nil
            updateInteractionGuard()
            if profile != nil || mode == .demo {
                await refreshInbox()
                startRealtime()
            } else {
                stopRealtime()
            }
        } catch {
            profile = nil
            authError = message(for: error)
            updateInteractionGuard()
            stopRealtime()
        }
    }

    func signIn(email: String, password: String) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        authNotice = nil
        defer { isAuthenticating = false }
        do {
            try await service.signIn(email: email, password: password)
            await refreshSession()
        } catch {
            authError = message(for: error)
        }
    }

    func signUp(email: String, password: String, username: String, displayName: String) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        authNotice = nil
        defer { isAuthenticating = false }
        do {
            try await service.signUp(email: email, password: password, username: username, displayName: displayName)
            await refreshSession()
            if profile == nil {
                authNotice = "Check your email to confirm your account, then sign in."
            }
        } catch {
            authError = message(for: error)
        }
    }

    func signOut() async {
        stopRealtime()
        do {
            try await service.signOut()
            profile = nil
            conversations = []
            messages = []
            selectedConversationID = nil
            resolvedPhotoURLs = [:]
            resolvedPhotoData = [:]
            photoErrors = [:]
            updateInteractionGuard()
        } catch {
            authError = message(for: error)
        }
    }

    func switchDemoUser() async {
        guard mode == .demo, let fixture = service as? FixturePostcardService else { return }
        stopRealtime()
        await fixture.switchDemoUser()
        selectedConversationID = nil
        messages = []
        resolvedPhotoURLs = [:]
        resolvedPhotoData = [:]
        photoErrors = [:]
        presentation.resetForAccountSwitch()
        await refreshSession()
        draft = freshDraft()
    }

    func setModalPresented(_ presented: Bool) {
        isModalPresented = presented
        updateInteractionGuard()
    }

    func lookupRecipient(_ username: String) {
        lookupTask?.cancel()
        lookupRevision &+= 1
        let revision = lookupRevision
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if recipientLookupResult?.username != normalized {
            draft.recipientId = nil
            draft.recipientName = ""
        }
        recipientLookupResult = nil
        recipientLookupMessage = nil
        composerError = nil
        guard !normalized.isEmpty else {
            isLookingUpRecipient = false
            return
        }
        isLookingUpRecipient = true
        recipientLookupMessage = "Finding @\(normalized)…"
        lookupTask = Task {
            do {
                let result = try await service.lookupRecipient(username: normalized)
                guard !Task.isCancelled, revision == lookupRevision else { return }
                recipientLookupResult = result
                recipientLookupMessage = result == nil ? "No recipient has that exact username." : nil
            } catch {
                guard !Task.isCancelled, revision == lookupRevision else { return }
                recipientLookupMessage = message(for: error)
            }
            if revision == lookupRevision { isLookingUpRecipient = false }
        }
    }

    func selectRecipient(_ recipient: PostcardProfile) {
        draft.recipientId = recipient.id
        draft.recipientName = recipient.displayName
        recipientLookupResult = recipient
        recipientLookupMessage = nil
        composerError = nil
    }

    func setPhotoData(_ data: Data) {
        do {
            draft.photoData = try PostcardPhotoProcessor.jpegData(from: data)
            composerError = nil
        } catch {
            composerError = message(for: error)
        }
    }

    func photoSelectionFailed() {
        composerError = "That photo could not be loaded. Choose another photo."
    }

    func reply(to profile: PostcardProfile) {
        selectRecipient(profile)
        if presentation.state == .sent { startNewDraft() }
    }

    func send() {
        guard sendTask == nil else { return }
        guard validateDraft() else { return }
        guard presentation.beginSending() else {
            composerError = "Seal the postcard before sending."
            return
        }
        composerError = nil
        let snapshot = draft
        let token = UUID()
        submissionToken = token
        sendTask = Task { await performSend(snapshot, token: token) }
    }

    func cancelSend() {
        guard sendTask != nil else { return }
        sendTask?.cancel()
        sendTask = nil
        submissionToken = nil
        presentation.sendFailed()
        composerError = "Sending was canceled. Your draft is saved; retry when ready."
    }

    func waitForSend() async {
        await sendTask?.value
    }

    func startNewDraft() {
        guard presentation.state == .sent else { return }
        lastSentMessage = nil
        presentation.startNewDraft()
    }

    func refreshInbox() async {
        guard !isLoadingInbox else { return }
        isLoadingInbox = true
        defer { isLoadingInbox = false }
        do {
            conversations = try await service.conversations()
            inboxError = nil
        } catch {
            inboxError = message(for: error)
        }
    }

    func selectConversation(_ id: UUID) async {
        selectedConversationID = id
        messages = []
        resolvedPhotoURLs = [:]
        resolvedPhotoData = [:]
        photoErrors = [:]
        await refreshConversation()
    }

    func refreshConversation() async {
        guard let id = selectedConversationID, !isLoadingConversation else { return }
        isLoadingConversation = true
        defer {
            isLoadingConversation = false
            if selectedConversationID != id {
                Task { await refreshConversation() }
            }
        }
        do {
            let fetched = try await service.messages(conversationId: id, before: nil, limit: 100)
            guard selectedConversationID == id else { return }
            var seen = Set<UUID>()
            messages = fetched.filter { seen.insert($0.id).inserted }
            conversationError = nil
            await resolvePhotos(for: messages)
        } catch {
            conversationError = message(for: error)
        }
    }

    func resume() async {
        stopRealtime()
        await refreshSession()
        await refreshConversation()
    }

    func suspend() async {
        stopRealtime()
        await flushDraft()
    }

    func flushDraft() async {
        draftSaveTask?.cancel()
        draftRevision &+= 1
        do {
            try await draftStore.save(draft, revision: draftRevision)
        } catch {
            composerError = "Your draft could not be saved on this device."
        }
    }

    private func performSend(_ snapshot: PostcardDraft, token: UUID) async {
        do {
            let message = try await service.send(draft: snapshot)
            guard submissionToken == token, !Task.isCancelled else { return }
            lastSentMessage = message
            presentation.sendSucceeded()
            draft = freshDraft()
            await flushDraft()
            await refreshInbox()
        } catch {
            guard submissionToken == token, !Task.isCancelled else { return }
            presentation.sendFailed()
            composerError = message(for: error)
        }
        if submissionToken == token {
            submissionToken = nil
            sendTask = nil
        }
    }

    private func validateDraft() -> Bool {
        guard draft.recipientId != nil else {
            composerError = "Find and select a recipient before sending."
            return false
        }
        guard !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.message.count <= 5_000 else {
            composerError = "Write a message of 1 to 5,000 characters."
            return false
        }
        guard draft.photoData != nil else {
            composerError = "Choose a photo for your postcard."
            return false
        }
        guard draft.senderName.count <= 100, draft.recipientName.count <= 100,
              draft.destination.count <= 200 else {
            composerError = "A name or destination is too long."
            return false
        }
        return true
    }

    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftRevision &+= 1
        let revision = draftRevision
        let snapshot = draft
        draftSaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
                try await draftStore.save(snapshot, revision: revision)
            } catch is CancellationError {
                return
            } catch {
                composerError = "Your draft could not be saved on this device."
            }
        }
    }

    private func updateInteractionGuard() {
        presentation.setBlocked(isModalPresented || requiresAuthentication)
    }

    private func resolvePhotos(for messages: [PostcardMessage]) async {
        let conversationID = selectedConversationID
        var urls: [UUID: URL] = [:]
        var data: [UUID: Data] = [:]
        var errors: [UUID: String] = [:]
        for message in messages {
            guard !Task.isCancelled, selectedConversationID == conversationID else { return }
            do {
                let url = try await service.photoURL(path: message.photoPath)
                urls[message.id] = url
                data[message.id] = try await loadPhoto(from: url)
            } catch {
                errors[message.id] = "The photograph could not be loaded. Tap to try again."
            }
        }
        guard selectedConversationID == conversationID else { return }
        resolvedPhotoURLs = urls
        resolvedPhotoData = data
        photoErrors = errors
    }

    func retryPhoto(_ id: UUID) async {
        guard let message = messages.first(where: { $0.id == id }) else { return }
        do {
            let url = try await service.photoURL(path: message.photoPath)
            let data = try await loadPhoto(from: url)
            guard messages.contains(where: { $0.id == id }) else { return }
            resolvedPhotoURLs[id] = url
            resolvedPhotoData[id] = data
            photoErrors[id] = nil
        } catch {
            photoErrors[id] = "The photograph could not be loaded. Tap to try again."
        }
    }

    private func loadPhoto(from url: URL) async throws -> Data {
        let bytes: Data
        if url.isFileURL {
            bytes = try Data(contentsOf: url)
        } else {
            let (received, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                throw PostcardServiceError.server("Photograph download failed.")
            }
            bytes = received
        }
        guard !bytes.isEmpty, bytes.count <= 10_000_000, UIImage(data: bytes) != nil else {
            throw PostcardServiceError.validation("The photograph is invalid.")
        }
        return bytes
    }

    private func startRealtime() {
        guard realtimeTask == nil else { return }
        realtimeTask = Task { await runRealtime() }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    private func runRealtime() async {
        while !Task.isCancelled {
            // Every reconnect refetches durable state; an event alone is not a receipt.
            await refreshInbox()
            await refreshConversation()
            do {
                let stream = try await service.conversationUpdates()
                for try await id in stream {
                    guard !Task.isCancelled else { break }
                    await refreshInbox()
                    if id == selectedConversationID { await refreshConversation() }
                }
            } catch {
                if !Task.isCancelled { inboxError = message(for: error) }
            }
            if !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func message(for error: Error) -> String {
        if let photoError = error as? PostcardPhotoError {
            return photoError.localizedDescription
        }
        if let serviceError = error as? PostcardServiceError {
            switch serviceError {
            case .unauthenticated: return "Sign in again to continue."
            case .forbidden: return "You do not have access to this postcard."
            case .validation(let detail): return detail
            case .offline: return "You are offline. Your draft is saved; retry when connected."
            case .notFound: return "That item is no longer available. Refresh and try again."
            case .server: return "The service is unavailable. Retry in a moment."
            }
        }
        return "Something went wrong. Retry in a moment."
    }

    private func freshDraft() -> PostcardDraft {
        PostcardDraft(senderName: profile?.displayName ?? "", photoData: mode == .demo ? demoPhotoData() : nil)
    }

    private func demoPhotoData() -> Data? {
        UIImage(named: "DemoPhoto")?.jpegData(compressionQuality: 0.82)
    }
}
