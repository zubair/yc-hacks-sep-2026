import PhotosUI
import SwiftUI
import PostcardCore
import PostcardUI

struct ComposeScreen: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(\.horizontalSizeClass) private var widthClass
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingPicker = false

  var body: some View {
    composeToolbar(stage)
      .background(PostcardStyle.paper)
      .photosPicker(isPresented: $showingPicker, selection: $pickerItem, matching: .images)
      .onChange(of: showingPicker) { _, showing in env.presentation.setSuppressed(showing, reason: .modal) }
      .onChange(of: pickerItem) { _, item in
        guard let item else { return }
        Task {
          await env.compose.importPhoto(from: item)
          pickerItem = nil
        }
      }
      .navigationTitle(env.presentation.state == .sent ? "Sent" : "New postcard")
      .navigationBarTitleDisplayMode(.inline)
      .sensoryFeedback(.success, trigger: env.presentation.state == .sent)
  }

  /// Inner Duo display: composer and the standing postcard share one arrangement. Split adapts around an
  /// active fold: book pose puts them side by side, table pose puts the card above and controls below.
  /// Everywhere else (older iOS, ordinary iPhones, compact width) the composer stands alone.
  @ViewBuilder
  private var stage: some View {
    if #available(iOS 27.1, *) {
      if widthClass == .regular {
        ArrangementView {
          composer
        } secondary: {
          DuoComposeStage()
        }
        .arrangementViewStyle(.split)
      } else {
        composer
      }
    } else {
      composer
    }
  }

  private var composer: some View {
    @Bindable var compose = env.compose
    return PostcardComposerView(
      draft: $compose.draft,
      state: env.presentation.state,
      error: compose.errorMessage,
      recipientLookupResult: compose.lookupResult,
      isLookingUpRecipient: compose.isLookingUp,
      recipientLookupMessage: compose.lookupMessage,
      isDemo: env.mode == .fixture,
      onLookupRecipient: { username in Task { await compose.lookup(username: username) } },
      onSelectRecipient: { compose.select(recipient: $0) },
      onChoosePhoto: { showingPicker = true },
      onOpen: { env.presentation.open(source: .manual) },
      onSeal: { env.presentation.seal(source: .manual) },
      onSend: { Task { await compose.send() } },
      onRetry: { Task { await compose.send() } }
    )
    .disabled(compose.isSending)
  }

  // MARK: Toolbar — Duo vertical bars on iOS 27.1, a standard navigation bar elsewhere.

  @ViewBuilder
  private func composeToolbar(_ content: some View) -> some View {
    if #available(iOS 27.1, *) {
      content.toolbar { duoToolbar }
    } else {
      content.toolbar { classicToolbar }
    }
  }

  @available(iOS 27.1, *)
  @ToolbarContentBuilder
  private var duoToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) { sendButton }
      .axisBehavior(.automatic)
      .visibilityPriority(.high)
    ToolbarItem(placement: .secondaryAction) { openSealButton }
    ToolbarOverflowMenu { draftItems }
  }

  @ToolbarContentBuilder
  private var classicToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) { sendButton }
    ToolbarItem(placement: .secondaryAction) { openSealButton }
    ToolbarItem(placement: .secondaryAction) {
      Menu("Draft", systemImage: "ellipsis.circle") { draftItems }
    }
  }

  private var sendButton: some View {
    Button("Send", systemImage: "paperplane") { Task { await env.compose.send() } }
      .disabled(!env.compose.canSend)
  }

  @ViewBuilder
  private var openSealButton: some View {
    if env.presentation.state == .writing {
      Button("Seal", systemImage: "seal") { env.presentation.seal(source: .manual) }
    } else {
      Button("Open", systemImage: "rectangle.portrait.and.arrow.right") { env.presentation.open(source: .manual) }
        .disabled(env.presentation.state == .sent || env.presentation.state == .sending)
    }
  }

  @ViewBuilder
  private var draftItems: some View {
    Button("Start another postcard", systemImage: "plus.rectangle.portrait") { env.compose.startNewDraft() }
      .disabled(env.compose.isSending)
    Button("Discard draft", systemImage: "trash", role: .destructive) { env.compose.discardDraft() }
      .disabled(env.compose.isSending)
  }
}
