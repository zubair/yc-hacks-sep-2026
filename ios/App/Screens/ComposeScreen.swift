import PhotosUI
import SwiftUI
import PostcardCore
import PostcardUI

struct ComposeScreen: View {
  @Environment(AppEnvironment.self) private var env
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingPicker = false

  var body: some View {
    @Bindable var compose = env.compose
    PostcardComposerView(
      draft: $compose.draft,
      presentation: env.presentation.state,
      errorMessage: compose.errorMessage,
      recipientLookupResult: compose.lookupResult,
      isLookingUpRecipient: compose.isLookingUp,
      onLookupRecipient: { username in Task { await compose.lookup(username: username) } },
      onSelectRecipient: { compose.select(recipient: $0) },
      onChoosePhoto: { showingPicker = true },
      onOpen: { env.presentation.open(source: .manual) },
      onSeal: { env.presentation.seal(source: .manual) },
      onSend: { Task { await compose.send() } },
      onRetry: { Task { await compose.send() } }
    )
    .photosPicker(isPresented: $showingPicker, selection: $pickerItem, matching: .images)
    .onChange(of: showingPicker) { _, showing in env.presentation.setSuppressed(showing, reason: .modal) }
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      Task {
        await compose.importPhoto(from: item)
        pickerItem = nil
      }
    }
    .navigationTitle(env.presentation.state == .sent ? "Sent" : "New postcard")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Send", systemImage: "paperplane") { Task { await compose.send() } }
          .disabled(!compose.canSend)
      }
      .axisBehavior(.automatic)
      .visibilityPriority(.high)
      ToolbarOverflowMenu {
        Button("Start another postcard", systemImage: "plus.rectangle.portrait") { compose.startNewDraft() }
        Button("Discard draft", systemImage: "trash", role: .destructive) { compose.discardDraft() }
      }
    }
    .sensoryFeedback(.success, trigger: env.presentation.state == .sent)
  }
}
