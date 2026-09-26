import SwiftUI
import PostcardUI

struct AuthScreen: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    NavigationStack {
      PostcardAuthView(
        isLoading: env.session.isBusy,
        error: env.session.errorMessage,
        notice: env.session.infoMessage ?? (env.mode == .fixture ? "Demo accounts: alice@demo.com, bob@demo.com, eve@demo.com · any password" : nil),
        isDemo: env.mode == .fixture,
        onSignIn: { email, password in Task { await env.session.signIn(email: email, password: password) } },
        onSignUp: { email, password, username, displayName in
          Task { await env.session.signUp(email: email, password: password, username: username, displayName: displayName) }
        }
      )
      .navigationTitle("Welcome")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
