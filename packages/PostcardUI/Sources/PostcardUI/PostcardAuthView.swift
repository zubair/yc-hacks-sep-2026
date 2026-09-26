import SwiftUI

public struct PostcardAuthView: View {
    private let isLoading: Bool
    private let error: String?
    private let onSignIn: (String, String) -> Void
    private let onSignUp: (String, String, String, String) -> Void
    @State private var isCreatingAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var displayName = ""

    public init(
        isLoading: Bool, error: String?,
        onSignIn: @escaping (String, String) -> Void,
        onSignUp: @escaping (String, String, String, String) -> Void
    ) {
        self.isLoading = isLoading
        self.error = error
        self.onSignIn = onSignIn
        self.onSignUp = onSignUp
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 54, weight: .ultraLight))
                    .foregroundStyle(PostcardTheme.accent)
                Text("A little note goes a long way.")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sign in to keep your postcards and send one to someone you know.")
                    .foregroundStyle(PostcardTheme.mutedInk)
                Picker("Account action", selection: $isCreatingAccount) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)
                if isCreatingAccount {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .modifier(PaperField())
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .modifier(PaperField())
                }
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .modifier(PaperField())
                SecureField("Password", text: $password)
                    .textContentType(isCreatingAccount ? .newPassword : .password)
                    .modifier(PaperField())
                if let error { Text(error).foregroundStyle(PostcardTheme.accent) }
                if isLoading {
                    ProgressView("Working on your account")
                } else {
                    Button(isCreatingAccount ? "Create account" : "Sign in") {
                        if isCreatingAccount {
                            onSignUp(email, password, username, displayName)
                        } else {
                            onSignIn(email, password)
                        }
                    }
                    .buttonStyle(PaperButtonStyle(prominent: true))
                    .disabled(email.isEmpty || password.isEmpty || (isCreatingAccount && (username.isEmpty || displayName.isEmpty)))
                }
            }
            .frame(maxWidth: 520)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(PostcardTheme.paper.ignoresSafeArea())
        .foregroundStyle(PostcardTheme.ink)
        .scrollDismissesKeyboard(.interactively)
    }
}
