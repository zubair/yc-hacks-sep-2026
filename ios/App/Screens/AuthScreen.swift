import SwiftUI
import PostcardUI

struct AuthScreen: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    NavigationStack {
      PostcardAuthView(
        isLoading: env.session.isBusy,
        error: env.session.errorMessage,
        notice: env.session.infoMessage ?? (env.mode == .fixture ? "Demo accounts: alex@demo.com or sam@demo.com, any password of 8+ characters. Nothing is sent." : nil),
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
