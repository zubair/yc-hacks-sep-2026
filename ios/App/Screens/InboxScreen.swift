import SwiftUI
import PostcardCore
import PostcardUI

struct InboxScreen: View {
  @Environment(AppEnvironment.self) private var env
  @Binding var path: [Route]

  var body: some View {
    PostcardInboxView(
      conversations: env.inbox.conversations,
      isLoading: env.inbox.isLoading,
      error: env.inbox.errorMessage,
      isDemo: env.mode == .fixture,
      onSelect: { path.append(.conversation($0)) },
      onCompose: { env.compose.startNewDraft(); path.append(.compose) },
      onRefresh: { Task { await env.inbox.load() } }
    )
    .navigationTitle("Postcards")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Write", systemImage: "square.and.pencil") { path.append(.compose) }
      }
      .axisBehavior(.automatic)
      .visibilityPriority(.high)
      ToolbarItem(placement: .secondaryAction) {
        Button("Refresh", systemImage: "arrow.clockwise") { Task { await env.inbox.load() } }
      }
      ToolbarOverflowMenu {
        if let profile = env.session.profile {
          Text("@\(profile.username)")
        }
        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
          Task { await env.session.signOut() }
        }
      }
    }
    .task {
      await env.inbox.load()
      await env.inbox.observeUpdates()
    }
  }
}
