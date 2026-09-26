import SwiftUI
import PhotosUI
import PostcardCore
import PostcardServices
import PostcardUI

@main
struct PostcardApp: App {
    @StateObject private var model = PostcardAppModel()
    @State private var isChoosingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if !model.isReady {
                    ProgressView("Opening your mailbox")
                } else if model.profile == nil {
                    PostcardAuthView(
                        isLoading: model.isBusy, error: model.authMessage,
                        onSignIn: { email, password in Task { await model.signIn(email: email, password: password) } },
                        onSignUp: { email, password, username, name in
                            Task { await model.signUp(email: email, password: password, username: username, displayName: name) }
                        }
                    )
                } else {
                    appContent
                }
            }
            .tint(PostcardTheme.accent)
            .modifier(PostcardHingeObserver(model: model))
            .task { await model.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
            .photosPicker(isPresented: $isChoosingPhoto, selection: $selectedPhoto, matching: .images)
            .onChange(of: isChoosingPhoto) { _, visible in model.setModalVisible(visible) }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return }
                        await model.setPhoto(data)
                    } catch { model.composerError = "Could not load that photo. Choose another image." }
                }
            }
        }
    }

    private var appContent: some View {
        VStack(spacing: 0) {
            if model.isDemo { demoBanner } else { accountBar }
            TabView(selection: $model.selectedTab) {
            PostcardComposerView(
                draft: $model.draft, presentationState: model.presentationState,
                error: model.composerError, recipientLookupResult: model.lookupResult,
                isLookingUpRecipient: model.isLookingUpRecipient,
                onLookupRecipient: { value in Task { await model.lookup(value) } },
                onSelectRecipient: model.selectRecipient,
                onChoosePhoto: { isChoosingPhoto = true },
                onOpen: model.open, onSeal: model.seal,
                onSend: { Task { await model.send() } },
                onRetry: { Task { await model.send() } }
            )
            .tabItem { Label("Write", systemImage: "square.and.pencil") }
            .tag(0)

            NavigationStack {
                PostcardInboxView(
                    conversations: model.conversations, isLoading: model.isLoadingInbox,
                    error: model.inboxError,
                    onSelect: { item in model.openConversation(item) },
                    onCompose: { model.selectedTab = 0 },
                    onRefresh: { Task { await model.refresh() } }
                )
                .navigationDestination(item: $model.selectedConversation) { item in
                    PostcardConversationView(
                        peer: item.peer, messages: model.messages, photoURLs: model.photoURLs,
                        isLoading: model.isLoadingConversation, error: model.conversationError,
                        onReply: { model.reply(to: item.peer) },
                        onRefresh: { Task { await model.loadConversation(item.id) } }
                    )
                }
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .tag(1)
            }
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Text("DEMO · simulated sends")
                .font(.caption.weight(.bold))
            Spacer()
            Button("View as \(model.profile?.id == FixturePostcardService.sender.id ? "Sam" : "Alex")") {
                Task { await model.switchDemoUser() }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(PostcardTheme.accent.ignoresSafeArea(edges: .top))
        .foregroundStyle(.white)
    }

    private var accountBar: some View {
        HStack {
            Text("Postcard")
                .font(.system(.title3, design: .serif).bold())
            Spacer()
            Button("Sign out") { Task { await model.signOut() } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .foregroundStyle(PostcardTheme.ink)
        .background(PostcardTheme.paper.ignoresSafeArea(edges: .top))
    }
}

private struct PostcardHingeObserver: ViewModifier {
    @ObservedObject var model: PostcardAppModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                guard let hinge = context.hinge else { return }
                switch hinge.status {
                case .closed:
                    model.receiveHinge(isOpen: false)
                case .partiallyOpen, .fullyOpen:
                    model.receiveHinge(isOpen: true)
                default:
                    break
                }
            }
        } else {
            content
        }
    }
}
