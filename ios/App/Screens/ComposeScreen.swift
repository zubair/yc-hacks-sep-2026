import PhotosUI
import SwiftUI
import PostcardCore
import PostcardUI

/// The compose screen is the postcard itself (`PostcardExperienceView`): the front when closed, the back spread
/// across the fold when open, sealed and ready when closed again. Sending is always the explicit Continue or Send.
struct ComposeScreen: View {
  @Environment(AppEnvironment.self) private var env
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingPicker = false
  @State private var showingRecipient = false

  var body: some View {
    composeToolbar(
      PostcardExperienceView(onChooseRecipient: { showingRecipient = true }, onChoosePhoto: { showingPicker = true })
    )
    .photosPicker(isPresented: $showingPicker, selection: $pickerItem, matching: .images)
    .sheet(isPresented: $showingRecipient) { RecipientSheet() }
    .onChange(of: showingPicker) { _, showing in env.presentation.setSuppressed(showing, reason: .modal) }
    .onChange(of: showingRecipient) { _, showing in env.presentation.setSuppressed(showing, reason: .modal) }
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
      // `--open` starts on the back spread (screenshot automation on simulators without a hinge).
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
    ToolbarItem(placement: .secondaryAction) { addressButton }
    ToolbarOverflowMenu { draftItems }
  }

  @ToolbarContentBuilder
  private var classicToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) { sendButton }
    ToolbarItem(placement: .secondaryAction) {
      Menu("Postcard", systemImage: "ellipsis.circle") {
        photoButton
        addressButton
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

  private var addressButton: some View {
    Button("Address", systemImage: "person.crop.rectangle") { showingRecipient = true }
      .disabled(env.compose.isSending)
  }

  @ViewBuilder
  private var draftItems: some View {
    if env.presentation.state == .writing {
      Button("Seal", systemImage: "seal") { env.presentation.seal(source: .manual) }
    } else if env.presentation.state == .front || env.presentation.state == .sealed {
      Button("Open", systemImage: "rectangle.portrait.and.arrow.right") { env.presentation.open(source: .manual) }
    }
    Button("Start another postcard", systemImage: "plus.rectangle.portrait") { env.compose.startNewDraft() }
      .disabled(env.compose.isSending)
    Button("Discard draft", systemImage: "trash", role: .destructive) { env.compose.discardDraft() }
      .disabled(env.compose.isSending)
  }
}
