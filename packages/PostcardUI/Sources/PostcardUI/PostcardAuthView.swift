import SwiftUI

public struct PostcardAuthView: View {
    private let isLoading: Bool
    private let error: String?
    private let notice: String?
    private let isDemo: Bool
    private let onSignIn: (String, String) -> Void
    private let onSignUp: (String, String, String, String) -> Void
    @State private var creatingAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var submitted = false
    @FocusState private var focused: Field?
    private enum Field { case email, password, username, displayName }

    public init(isLoading: Bool = false, error: String? = nil, notice: String? = nil,
                isDemo: Bool = false,
                onSignIn: @escaping (String, String) -> Void,
                onSignUp: @escaping (String, String, String, String) -> Void) {
        self.isLoading = isLoading; self.error = error; self.notice = notice
        self.isDemo = isDemo; self.onSignIn = onSignIn; self.onSignUp = onSignUp
    }

    private var validation: String? {
        if creatingAccount {
            return PostcardFormRules.signupIssue(email: email, password: password, username: username, displayName: displayName)
        }
        if !PostcardFormRules.validEmail(email) { return "Enter a valid email address." }
        if password.isEmpty { return "Enter your password." }
        return nil
    }

    public var body: some View {
        PaperScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DemoLabel(isDemo: isDemo)
                    PostcardHero()
                    PostcardHeading(eyebrow: "A note worth keeping",
                                    title: creatingAccount ? "Your world, shared." : "Welcome, wanderer.",
                                    subtitle: "Some moments deserve more than a message.")
                    Picker("Account action", selection: $creatingAccount) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }.pickerStyle(.segmented).disabled(isLoading)
                    if let notice { PostcardNotice(text: notice).accessibilityIdentifier("auth-notice") }
                    if let error { PostcardNotice(text: error, isError: true) }
                    if submitted, let validation { PostcardNotice(text: validation, isError: true) }
                    VStack(alignment: .leading, spacing: 16) {
                        fieldLabel("EMAIL")
                        TextField("you@example.com", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused, equals: .email).modifier(AuthField())
                            .accessibilityLabel("Email").accessibilityIdentifier("auth-email")
                        if creatingAccount {
                            fieldLabel("USERNAME")
                            TextField("Your unique username", text: $username)
                                .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focused, equals: .username).modifier(AuthField())
                                .accessibilityLabel("Username").accessibilityIdentifier("auth-username")
                            fieldLabel("YOUR NAME")
                            TextField("The name on your postcards", text: $displayName).textContentType(.name)
                                .focused($focused, equals: .displayName).modifier(AuthField())
                                .accessibilityLabel("Display name").accessibilityIdentifier("auth-name")
                        }
                        fieldLabel("PASSWORD")
                        SecureField(creatingAccount ? "At least 8 characters" : "Your password", text: $password)
                            .textContentType(creatingAccount ? .newPassword : .password)
                            .focused($focused, equals: .password).modifier(AuthField())
                            .accessibilityLabel("Password").accessibilityIdentifier("auth-password")
                    }.disabled(isLoading)
                    Button(action: submit) {
                        if isLoading { ProgressView("Please wait…").tint(PostcardStyle.card) }
                        else { Text(creatingAccount ? "Create your account" : "Come on in") }
                    }.buttonStyle(PostcardButtonStyle()).disabled(isLoading).accessibilityIdentifier("auth-submit")
                    Text(creatingAccount ? "If email confirmation is enabled, check your inbox before signing in." : "A familiar face. A faraway place. A postcard from you.")
                        .font(.caption).foregroundStyle(PostcardStyle.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }.navigationTitle("Postcard").navigationBarTitleDisplayMode(.inline)
            .onChange(of: creatingAccount) { _, _ in submitted = false }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } } }
    }
    private func fieldLabel(_ value: String) -> some View {
        Text(value).font(.caption.weight(.semibold)).foregroundStyle(PostcardStyle.muted)
    }
    private func submit() {
        guard !isLoading else { return }
        submitted = true
        guard validation == nil else { return }
        focused = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if creatingAccount {
            onSignUp(cleanEmail, password, PostcardFormRules.normalizedUsername(username), displayName.trimmingCharacters(in: .whitespacesAndNewlines))
        } else { onSignIn(cleanEmail, password) }
    }
}

private struct AuthField: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(14).background(PostcardStyle.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(PostcardStyle.rule, lineWidth: 0.5))
    }
}
