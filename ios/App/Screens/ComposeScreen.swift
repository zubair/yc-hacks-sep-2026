import PhotosUI
import SwiftUI
import PostcardCore
import PostcardUI

struct ComposeScreen: View {
  @Environment(AppEnvironment.self) private var env
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingPicker = false

  var body: some View {
    composeToolbar(PostcardExperienceView(onChoosePhoto: { showingPicker = true }))
      .photosPicker(isPresented: $showingPicker, selection: $pickerItem, matching: .images)
      .onChange(of: showingPicker) { _, showing in env.presentation.setSuppressed(showing, reason: .modal) }
      .onChange(of: pickerItem) { _, item in
        guard let item else { return }
        Task {
          await env.compose.importPhoto(from: item)
          pickerItem = nil
        }
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .sensoryFeedback(.success, trigger: env.presentation.state == .sent)
      .onAppear {
        // `--open` launch argument starts on the back spread (screenshot automation on simulators without a hinge).
        if ProcessInfo.processInfo.arguments.contains("--open") { env.presentation.open(source: .system) }
      }
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
    ToolbarItem(placement: .secondaryAction) { photoButton }
    ToolbarOverflowMenu {
      openSealButton
      draftItems
    }
  }

  @ToolbarContentBuilder
  private var classicToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) { sendButton }
    ToolbarItem(placement: .secondaryAction) { photoButton }
    ToolbarItem(placement: .secondaryAction) {
      Menu("More", systemImage: "ellipsis.circle") {
        openSealButton
        draftItems
      }
    }
  }

  private var sendButton: some View {
    Button("Send", systemImage: "paperplane") { Task { await env.compose.send() } }
      .disabled(!env.compose.canSend)
  }

  private var photoButton: some View {
    Button("Photo", systemImage: "photo") { showingPicker = true }
      .disabled(env.compose.isSending)
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
