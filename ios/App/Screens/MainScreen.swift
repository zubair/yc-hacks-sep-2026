import SwiftUI
import PostcardCore
import PostcardUI

enum Route: Hashable {
  case compose
  case conversation(PostcardConversation)
}

struct MainScreen: View {
  @Environment(AppEnvironment.self) private var env
  @State private var path: [Route] = []

  var body: some View {
    NavigationStack(path: $path) {
      InboxScreen(path: $path)
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .compose:
            ComposeScreen()
          case .conversation(let conversation):
            ConversationScreen(conversation: conversation, path: $path)
          }
        }
    }
    .onChange(of: path) { _, routes in
      // Leaving the composer while a card is open counts as a modal-free pause: nothing to suppress,
      // but a card is only foldable while the composer is on screen.
      env.presentation.setSuppressed(!routes.contains(.compose), reason: .composerHidden)
    }
    .onAppear {
      // `--compose` launch argument opens the postcard directly (demo shortcut and screenshot automation).
      if path.isEmpty, ProcessInfo.processInfo.arguments.contains("--compose") { path = [.compose] }
      env.presentation.setSuppressed(!path.contains(.compose), reason: .composerHidden)
    }
  }
}
