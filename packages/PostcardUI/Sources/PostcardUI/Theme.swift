import SwiftUI

public enum PostcardTheme {
    public static let paper = Color(red: 0.974, green: 0.955, blue: 0.912)
    public static let ink = Color(red: 0.105, green: 0.255, blue: 0.205)
    public static let mutedInk = Color(red: 0.34, green: 0.40, blue: 0.34)
    public static let accent = Color(red: 0.72, green: 0.22, blue: 0.16)
    public static let line = Color(red: 0.77, green: 0.77, blue: 0.67)
}

struct PaperButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? PostcardTheme.paper : PostcardTheme.ink)
            .background(prominent ? PostcardTheme.ink : PostcardTheme.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PostcardTheme.ink.opacity(prominent ? 0 : 0.35)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PaperField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PostcardTheme.line))
    }
}
