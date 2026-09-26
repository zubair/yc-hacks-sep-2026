import SwiftUI
import PostcardCore
import PostcardUI

struct InboxScreen: View {
  @Environment(AppEnvironment.self) private var env
  @Binding var path: [Route]

  var body: some View {
    inboxToolbar(
      PostcardInboxView(
        conversations: env.inbox.conversations,
        isLoading: env.inbox.isLoading,
        error: env.inbox.errorMessage,
        isDemo: env.mode == .fixture,
        onSelect: { path.append(.conversation($0)) },
        onCompose: compose,
        onRefresh: { Task { await env.inbox.load() } }
      )
    )
    .navigationTitle("Postcards")
    .task {
      await env.inbox.load()
      await env.inbox.observeUpdates()
    }
  }

  private func compose() {
    env.compose.prepareDraft()
    path.append(.compose)
  }

  // MARK: Toolbar — Duo vertical bars on iOS 27.1, a standard navigation bar elsewhere.

  @ViewBuilder
  private func inboxToolbar(_ content: some View) -> some View {
    if #available(iOS 27.1, *) {
      content.toolbar { duoToolbar }
    } else {
      content.toolbar { classicToolbar }
    }
  }

  @available(iOS 27.1, *)
  @ToolbarContentBuilder
  private var duoToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button("Write", systemImage: "square.and.pencil", action: compose)
    }
    .axisBehavior(.automatic)
    .visibilityPriority(.high)
    ToolbarItem(placement: .secondaryAction) {
      Button("Refresh", systemImage: "arrow.clockwise") { Task { await env.inbox.load() } }
    }
    ToolbarItem(placement: .topBarLeading) { demoMenu }
    ToolbarOverflowMenu { accountItems }
  }

  @ToolbarContentBuilder
  private var classicToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button("Write", systemImage: "square.and.pencil", action: compose)
    }
    ToolbarItem(placement: .topBarLeading) { demoMenu }
    ToolbarItem(placement: .secondaryAction) {
      Menu("Account", systemImage: "person.crop.circle") { accountItems }
    }
  }

  @ViewBuilder
  private var accountItems: some View {
    if let profile = env.session.profile {
      Text("@\(profile.username)")
    }
    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
      Task { await env.session.signOut() }
    }
  }

  /// Fixture mode only: simulated controls to show both sides of the exchange and the failure states.
  @ViewBuilder
  private var demoMenu: some View {
    if env.mode == .fixture {
      Menu {
        if let peer = env.demoPeerName {
          Button("View as \(peer)", systemImage: "person.2") { Task { await env.switchDemoAccount() } }
        }
        Button("Fail the next send", systemImage: "exclamationmark.triangle") { Task { await env.failNextDemoSend() } }
        Button(env.isDemoOffline ? "Go back online" : "Simulate offline", systemImage: env.isDemoOffline ? "wifi" : "wifi.slash") {
          Task { await env.setDemoOffline(!env.isDemoOffline) }
        }
      } label: {
        Label("Demo", systemImage: "theatermasks")
      }
      .accessibilityIdentifier("demo-menu")
    }
  }
}
