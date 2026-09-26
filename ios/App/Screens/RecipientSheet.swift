import SwiftUI
import PostcardCore
import PostcardUI

/// Exact-username lookup, bound into the draft by the app. No directory browsing.
struct RecipientSheet: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(\.dismiss) private var dismiss
  @State private var username = ""
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            TextField("Exact username", text: $username)
              .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
              .onSubmit { Task { await env.compose.lookup(username: username) } }
            if env.compose.isLookingUp { ProgressView() }
          }
          Button("Look up", systemImage: "magnifyingglass") { Task { await env.compose.lookup(username: username) } }
            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || env.compose.isLookingUp)
        } header: {
          Text("Who is this for?")
        } footer: {
          Text(env.mode == .fixture ? "Demo usernames: bob, eve." : "Ask them for their Postcard username.")
        }
        if let profile = env.compose.lookupResult {
          Section {
            Button {
              env.compose.select(recipient: profile)
              dismiss()
            } label: {
              Label("\(profile.displayName) · @\(profile.username)", systemImage: "person.crop.circle.badge.checkmark")
            }
          }
        } else if let error = env.compose.errorMessage {
          Section { Text(error).foregroundStyle(PostcardStyle.vermilion) }
        }
        Section("Where are you?") {
          @Bindable var compose = env.compose
          TextField("Destination", text: $compose.draft.destination).textInputAutocapitalization(.words)
        }
      }
      .navigationTitle("Address")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
      .onAppear { focused = env.compose.draft.recipientId == nil }
    }
    .presentationDetents([.medium, .large])
  }
}
