import Foundation
import SwiftUI
import UIKit
import PostcardCore
import PostcardServices

@MainActor
final class PostcardAppModel: ObservableObject {
    @Published var isReady = false
    @Published var isBusy = false
    @Published var isDemo: Bool
    @Published var profile: PostcardProfile?
    @Published var authMessage: String?
    @Published var draft: PostcardDraft { didSet { saveDraft() } }
    @Published var presentationState: PostcardPresentationState = .front
    @Published var composerError: String?
    @Published var lookupResult: PostcardProfile?
    @Published var isLookingUpRecipient = false
    @Published var conversations: [PostcardConversation] = []
    @Published var isLoadingInbox = false
    @Published var inboxError: String?
    @Published var selectedConversation: PostcardConversation?
    @Published var messages: [PostcardMessage] = []
    @Published var photoURLs: [UUID: URL] = [:]
    @Published var isLoadingConversation = false
    @Published var conversationError: String?
    @Published var selectedTab = 0

    private let service: any PostcardService
    private let posture = PostcardPostureController()
    private var updateTask: Task<Void, Never>?
    private var started = false
    private let draftURL: URL

    init() {
        let configURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        let configKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String ?? ""
        let demo: Bool
        if let url = URL(string: configURL), url.scheme?.hasPrefix("http") == true,
           !configKey.isEmpty, !configKey.contains("$(") {
            service = SupabasePostcardService(url: url, publishableKey: configKey)
            demo = false
        } else {
            service = FixturePostcardService()
            demo = true
        }
        isDemo = demo
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        draftURL = base.appendingPathComponent("postcard-draft.json")
        if ProcessInfo.processInfo.arguments.contains("-resetDemo") {
            try? FileManager.default.removeItem(at: draftURL)
        }
        var restored = (try? Data(contentsOf: draftURL)).flatMap { try? JSONDecoder().decode(PostcardDraft.self, from: $0) } ?? PostcardDraft()
        if demo && restored.photoData == nil {
            restored.photoData = UIImage(named: "DemoPhoto")?.jpegData(compressionQuality: 0.82)
        }
        draft = restored
    }

    func start() async {
        guard !started else { return }
        started = true
        await loadProfile()
        isReady = true
        if profile != nil { await refresh(); startUpdates() }
    }

    func refresh() async {
        guard profile != nil else { return }
        isLoadingInbox = true
        defer { isLoadingInbox = false }
        do {
            conversations = try await service.conversations()
            inboxError = nil
            if let selected = selectedConversation,
               let updated = conversations.first(where: { $0.id == selected.id }) {
                selectedConversation = updated
                await loadConversation(selected.id)
            }
        } catch { inboxError = error.localizedDescription }
    }

    func lookup(_ username: String) async {
        guard !username.isEmpty else { return }
        isLookingUpRecipient = true
        lookupResult = nil
        composerError = nil
        defer { isLookingUpRecipient = false }
        do {
            lookupResult = try await service.lookupRecipient(username: username)
            if lookupResult == nil { composerError = "No account with that exact username." }
        } catch { composerError = error.localizedDescription }
    }

    func selectRecipient(_ recipient: PostcardProfile) {
        draft.recipientId = recipient.id
        draft.recipientName = recipient.displayName
        lookupResult = nil
        composerError = nil
    }

    func open() {
        if presentationState == .sent { posture.beginNewDraft() }
        posture.open()
        presentationState = posture.state
    }

    func seal() {
        posture.seal()
        presentationState = posture.state
    }

    func send() async {
        guard presentationState == .sealed, !isBusy else { return }
        isBusy = true
        posture.beginSend()
        presentationState = posture.state
        composerError = nil
        do {
            _ = try await service.send(draft: draft)
            posture.sendSucceeded()
            presentationState = posture.state
            draft = freshDraft()
            await refresh()
        } catch {
            composerError = error.localizedDescription
            posture.sendFailed()
            presentationState = posture.state
        }
        isBusy = false
    }

    func setPhoto(_ raw: Data) async {
        guard let image = UIImage(data: raw) else {
            composerError = "This photo could not be opened."
            return
        }
        guard let bitmap = image.cgImage,
              bitmap.width * bitmap.height <= 20_000_000 else {
            composerError = "Choose a photo smaller than 20 megapixels."
            return
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.82), jpeg.count <= 10_000_000 else {
            composerError = "Choose a photo smaller than 10 MB."
            return
        }
        draft.photoData = jpeg
        composerError = nil
    }

    func openConversation(_ item: PostcardConversation) {
        selectedConversation = item
        Task { await loadConversation(item.id) }
    }

    func loadConversation(_ id: UUID) async {
        isLoadingConversation = true
        defer { isLoadingConversation = false }
        do {
            let fetched = try await service.messages(conversationId: id, before: nil, limit: 100)
            messages = Array(Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values)
                .sorted { $0.createdAt < $1.createdAt }
            conversationError = nil
            for item in messages {
                if let path = item.photoPath {
                    photoURLs[item.id] = try? await service.photoURL(path: path)
                }
            }
        } catch { conversationError = error.localizedDescription }
    }

    func reply(to peer: PostcardProfile) {
        draft = freshDraft()
        draft.recipientId = peer.id
        draft.recipientName = peer.displayName
        posture.beginNewDraft()
        presentationState = posture.state
        selectedTab = 0
    }

    func switchDemoUser() async {
        guard let fixture = service as? FixturePostcardService else { return }
        await fixture.switchDemoUser()
        selectedConversation = nil
        messages = []
        photoURLs = [:]
        posture.beginNewDraft()
        presentationState = posture.state
        draft = freshDraft()
        await loadProfile()
        await refresh()
        selectedTab = 1
    }

    func signIn(email: String, password: String) async {
        await authAction { try await service.signIn(email: email, password: password) }
    }
    func signUp(email: String, password: String, username: String, displayName: String) async {
        await authAction { try await service.signUp(email: email, password: password, username: username, displayName: displayName) }
        if profile == nil && authMessage == nil {
            authMessage = "Check your email to confirm your account, then sign in."
        }
    }
    func signOut() async {
        updateTask?.cancel()
        do {
            try await service.signOut()
            profile = nil
            conversations = []
            messages = []
            selectedConversation = nil
        } catch { authMessage = error.localizedDescription }
    }

    private func authAction(_ action: () async throws -> Void) async {
        isBusy = true
        authMessage = nil
        defer { isBusy = false }
        do {
            try await action()
            await loadProfile()
            if profile != nil { await refresh(); startUpdates() }
        } catch { authMessage = error.localizedDescription }
    }

    private func loadProfile() async {
        do {
            profile = try await service.currentProfile()
            if draft.senderName.isEmpty { draft.senderName = profile?.displayName ?? "" }
        } catch { authMessage = error.localizedDescription }
    }

    private func startUpdates() {
        updateTask?.cancel()
        updateTask = Task {
            do {
                let stream = try await service.conversationUpdates()
                for try await _ in stream {
                    if Task.isCancelled { break }
                    await refresh()
                }
            } catch {
                if !Task.isCancelled { inboxError = error.localizedDescription }
            }
        }
    }

    private func saveDraft() {
        do {
            try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(draft)
            try data.write(to: draftURL, options: .atomic)
        } catch { composerError = "Draft could not be saved on this device." }
    }

    private func freshDraft() -> PostcardDraft {
        var result = PostcardDraft(senderName: profile?.displayName ?? "")
        if isDemo { result.photoData = UIImage(named: "DemoPhoto")?.jpegData(compressionQuality: 0.82) }
        return result
    }
}
