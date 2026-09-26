import SwiftUI
import PostcardCore

struct RootView: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      switch env.session.state {
      case .loading:
        ProgressView("Opening Postcard…")
      case .signedOut:
        AuthScreen()
      case .signedIn:
        MainScreen()
      }
    }
    .hingePosture(feeding: env.presentation)
    .task { await env.session.restore() }
    .onChange(of: env.session.isBusy) { _, busy in env.presentation.setSuppressed(busy, reason: .authenticating) }
    .onChange(of: scenePhase) { _, phase in if phase != .active { env.compose.persistNow() } }
  }
}
