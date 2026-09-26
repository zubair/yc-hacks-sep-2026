import SwiftUI
import PostcardUI

struct AuthScreen: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    NavigationStack {
      PostcardAuthView(
        isLoading: env.session.isBusy,
        errorMessage: env.session.errorMessage,
        infoMessage: env.session.infoMessage ?? (env.mode == .fixture ? "Demo accounts: alice@demo, bob@demo, eve@demo · any password" : nil),
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
