import SwiftUI
import PostcardCore
import PostcardUI

struct RootView: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      switch env.session.state {
      case .loading:
        ProgressView("Opening Postcard…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(PostcardStyle.paper)
      case .signedOut:
        AuthScreen()
      case .signedIn(let profile):
        // Keyed by account so a sign-in or demo account switch starts from a fresh inbox and navigation stack.
        MainScreen().id(profile.id)
      case .unavailable(let message):
        SessionUnavailableView(message: message, isRetrying: env.session.isBusy) {
          Task { await env.session.retryRestore() }
        }
      }
    }
    .hingePosture(feeding: env.presentation)
    .task { await env.session.restore() }
    .onChange(of: env.session.isBusy) { _, busy in env.presentation.setSuppressed(busy, reason: .authenticating) }
    .onChange(of: env.session.state) { _, state in env.sessionChanged(to: state) }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { env.compose.persistNow() }
      // Returning to the foreground refetches: realtime may have dropped events while suspended.
      if phase == .active, case .signedIn = env.session.state { Task { await env.inbox.load() } }
    }
  }
}

/// Launch could not confirm the session (offline or server error). The saved session and draft are kept.
private struct SessionUnavailableView: View {
  let message: String
  let isRetrying: Bool
  let onRetry: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(PostcardStyle.vermilion)
      Text("Postcard can’t connect right now").font(.system(.title2, design: .serif)).multilineTextAlignment(.center)
      Text(message).foregroundStyle(PostcardStyle.muted).multilineTextAlignment(.center)
      Button(action: onRetry) {
        if isRetrying { ProgressView() } else { Label("Try again", systemImage: "arrow.clockwise") }
      }
      .buttonStyle(.borderedProminent)
      .tint(PostcardStyle.ink)
      .disabled(isRetrying)
      .accessibilityIdentifier("retry-session")
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(PostcardStyle.paper)
    .foregroundStyle(PostcardStyle.ink)
  }
}
