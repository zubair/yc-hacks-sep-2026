import PhotosUI
import PostcardCore
import PostcardServices
import PostcardUI
import SwiftUI

struct PostcardRootView: View {
    @State var coordinator: PostcardCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .compose
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var conversationPath: [UUID] = []

    var body: some View {
        NativeHingeObserver(controller: coordinator.presentation) {
            Group {
                if coordinator.isStarting {
                    ProgressView("Opening Postcard…")
                } else if coordinator.requiresAuthentication {
                    authScreen
                } else {
                    mainTabs
                }
            }
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhoto, matching: .images)
        .onChange(of: isPhotoPickerPresented) { _, presented in
            coordinator.setModalPresented(presented)
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    coordinator.setPhotoData(data)
                } else {
                    coordinator.photoSelectionFailed()
                }
                selectedPhoto = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await coordinator.suspend() }
            } else if phase == .active && !coordinator.isStarting {
                Task { await coordinator.resume() }
            }
        }
        .task { await coordinator.start() }
    }

    private var authScreen: some View {
        NavigationStack {
            PostcardAuthView(
                isLoading: coordinator.isAuthenticating,
                error: coordinator.authError,
                notice: coordinator.authNotice,
                onSignIn: { email, password in
                    Task { await coordinator.signIn(email: email, password: password) }
                },
                onSignUp: { email, password, username, displayName in
                    Task {
                        await coordinator.signUp(
                            email: email,
                            password: password,
                            username: username,
                            displayName: displayName
                        )
                    }
                }
            )
            .navigationTitle("Postcard")
        }
    }

    private var mainTabs: some View {
        VStack(spacing: 0) {
            if coordinator.mode == .demo { demoBanner }
            TabView(selection: $selectedTab) {
            NavigationStack {
                composerScreen
                    .navigationTitle("Postcard")
                    .toolbar {
                        if coordinator.presentation.state == .sending {
                            Button("Cancel sending", systemImage: "xmark") {
                                coordinator.cancelSend()
                            }
                        }
                        if coordinator.presentation.state == .sent {
                            Button("New postcard", systemImage: "plus") {
                                coordinator.startNewDraft()
                            }
                        }
                    }
            }
            .tabItem { Label("Write", systemImage: "square.and.pencil") }
            .tag(AppTab.compose)

            NavigationStack(path: $conversationPath) {
                PostcardInboxView(
                    conversations: coordinator.conversations,
                    isLoading: coordinator.isLoadingInbox,
                    error: coordinator.inboxError,
                    isDemo: coordinator.mode == .demo,
                    onSelect: { conversation in
                        Task { await coordinator.selectConversation(conversation.id) }
                        conversationPath.append(conversation.id)
                    },
                    onCompose: { selectedTab = .compose },
                    onRefresh: { Task { await coordinator.refreshInbox() } }
                )
                .navigationTitle("Inbox")
                .navigationDestination(for: UUID.self) { _ in
                    conversationScreen
                }
                .toolbar {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await coordinator.refreshInbox() }
                    }
                    if coordinator.mode == .live {
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                            Task { await coordinator.signOut() }
                        }
                    }
                }
            }
            .tabItem { Label("Inbox", systemImage: "tray.full") }
            .tag(AppTab.inbox)
            }
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Text("DEMO · simulated sends")
                .font(.caption.weight(.bold))
            Spacer()
            Button("View as \(coordinator.profile?.id == FixturePostcardService.sender.id ? "Sam" : "Alex")") {
                conversationPath = []
                selectedTab = .inbox
                Task { await coordinator.switchDemoUser() }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(PostcardStyle.vermilion.ignoresSafeArea(edges: .top))
        .foregroundStyle(.white)
    }

    private var composerScreen: some View {
        @Bindable var coordinator = coordinator
        return PostcardComposerView(
            draft: $coordinator.draft,
            state: coordinator.presentation.state,
            error: coordinator.composerError,
            recipientLookupResult: coordinator.recipientLookupResult,
            isLookingUpRecipient: coordinator.isLookingUpRecipient,
            recipientLookupMessage: coordinator.recipientLookupMessage,
            isDemo: coordinator.mode == .demo,
            onLookupRecipient: { coordinator.lookupRecipient($0) },
            onSelectRecipient: { coordinator.selectRecipient($0) },
            onChoosePhoto: { isPhotoPickerPresented = true },
            onOpen: { coordinator.presentation.open() },
            onSeal: { coordinator.presentation.seal() },
            onSend: { coordinator.send() },
            onRetry: { coordinator.send() }
        )
    }

    private var conversationScreen: some View {
        Group {
            if let conversation = coordinator.conversations.first(where: { $0.id == coordinator.selectedConversationID }) {
                PostcardConversationView(
                    messages: coordinator.messages,
                    photoURLs: coordinator.resolvedPhotoURLs,
                    photoData: coordinator.resolvedPhotoData,
                    photoErrors: coordinator.photoErrors,
                    isLoading: coordinator.isLoadingConversation,
                    error: coordinator.conversationError,
                    isDemo: coordinator.mode == .demo,
                    title: "With \(conversation.peer.displayName)",
                    onReply: {
                        coordinator.reply(to: conversation.peer)
                        selectedTab = .compose
                    },
                    onRefresh: { Task { await coordinator.refreshConversation() } },
                    onRetryPhoto: { id in Task { await coordinator.retryPhoto(id) } }
                )
            } else {
                ProgressView("Opening conversation")
            }
        }
        .navigationTitle("Conversation")
        .task(id: coordinator.selectedConversationID) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(240))
                guard !Task.isCancelled else { return }
                await coordinator.refreshConversation()
            }
        }
    }
}

private enum AppTab: Hashable {
    case compose
    case inbox
}
