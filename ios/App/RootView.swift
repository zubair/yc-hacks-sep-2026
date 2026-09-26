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
    .safeAreaInset(edge: .top, spacing: 0) {
      if env.mode == .fixture { DemoBanner() }
    }
    .hingePosture(feeding: env.presentation)
    .task { await env.session.restore() }
    .onChange(of: env.session.isBusy) { _, busy in env.presentation.setSuppressed(busy, reason: .authenticating) }
    .onChange(of: scenePhase) { _, phase in if phase != .active { env.compose.persistNow() } }
  }
}

private struct DemoBanner: View {
  var body: some View {
    Label("Demo · fixture data · sends are simulated", systemImage: "testtube.2")
      .font(.caption.weight(.semibold))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .background(.yellow.opacity(0.9))
      .foregroundStyle(.black)
      .accessibilityLabel("Demo mode. Fixture data. Sends are simulated.")
  }
}
