import PhotosUI
import SwiftUI
import PostcardCore
import PostcardUI

struct ComposeScreen: View {
  @Environment(AppEnvironment.self) private var env
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingPicker = false
  @State private var showingRecipient = false

  var body: some View {
    PostcardExperienceView(onChooseRecipient: { showingRecipient = true }, onChoosePhoto: { showingPicker = true })
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
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Send", systemImage: "paperplane") { Task { await env.compose.send() } }
            .disabled(!env.compose.canSend)
        }
        .axisBehavior(.automatic)
        .visibilityPriority(.high)
        ToolbarItem(placement: .secondaryAction) {
          Button("Photo", systemImage: "photo") { showingPicker = true }
            .disabled(env.compose.isSending)
        }
        ToolbarItem(placement: .secondaryAction) {
          Button("Address", systemImage: "person.crop.rectangle") { showingRecipient = true }
            .disabled(env.compose.isSending)
        }
        ToolbarOverflowMenu {
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
      .sensoryFeedback(.success, trigger: env.presentation.state == .sent)
      .onAppear {
        // `--open` launch argument starts on the back spread (screenshot automation on simulators without a hinge).
        if ProcessInfo.processInfo.arguments.contains("--open") { env.presentation.open(source: .system) }
      }
  }
}
