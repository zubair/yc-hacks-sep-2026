import Foundation
import PostcardCore

// Shared by the controls and tests. These are UI hints; backend validation remains authoritative.
enum PostcardFormRules {
    static func sendIssue(_ draft: PostcardDraft) -> String? {
        if draft.recipientId == nil { return "Choose a recipient before sending." }
        if draft.photoData?.isEmpty != false { return "Add a photo to your postcard." }
        if draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Write a little something on the back." }
        if draft.message.count > 5_000 { return "Your note is over 5,000 characters. Shorten it before sending." }
        if draft.senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add your name to sign the postcard." }
        if draft.senderName.count > 100 || draft.recipientName.count > 100 { return "Names can be up to 100 characters." }
        if draft.destination.count > 200 { return "The destination can be up to 200 characters." }
        return nil
    }
    static func normalizedUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func validUsername(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil
    }
    static func validEmail(_ value: String) -> Bool {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !value.contains(where: \.isWhitespace)
    }
    static func signupIssue(email: String, password: String, username: String, displayName: String) -> String? {
        if !validEmail(email) { return "Enter a valid email address." }
        if !validUsername(normalizedUsername(username)) { return "Use 3–30 lowercase letters, numbers, or underscores for your username." }
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayName.count > 100 { return "Enter a display name of 1–100 characters." }
        if password.count < 8 { return "Choose a password with at least 8 characters." }
        return nil
    }
}
