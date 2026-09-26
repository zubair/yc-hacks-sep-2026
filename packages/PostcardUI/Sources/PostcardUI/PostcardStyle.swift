import SwiftUI

/// Fixed paper palette; screens intentionally use a light paper surface in either system appearance.
public enum PostcardStyle {
    public static let paper = Color(red: 0.96, green: 0.94, blue: 0.88)
    public static let card = Color(red: 1.0, green: 0.985, blue: 0.95)
    public static let ink = Color(red: 0.13, green: 0.25, blue: 0.21)
    public static let muted = Color(red: 0.36, green: 0.39, blue: 0.33)
    public static let vermilion = Color(red: 0.66, green: 0.22, blue: 0.14)
    public static let rule = Color(red: 0.77, green: 0.77, blue: 0.69)
}

struct PaperScreen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PostcardStyle.paper.ignoresSafeArea())
            .foregroundStyle(PostcardStyle.ink)
            .tint(PostcardStyle.ink)
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
    }
}

struct PostcardHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(2)
                .foregroundStyle(PostcardStyle.vermilion)
            Text(title).font(.system(.largeTitle, design: .serif)).accessibilityAddTraits(.isHeader)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(PostcardStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PostcardButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .foregroundStyle(secondary ? PostcardStyle.ink : PostcardStyle.card)
            .background(secondary ? PostcardStyle.card : PostcardStyle.ink,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(PostcardStyle.ink.opacity(secondary ? 0.2 : 0), lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct PostcardNotice: View {
    let text: String
    var isError = false
    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.circle" : "info.circle")
            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isError ? PostcardStyle.vermilion : PostcardStyle.muted)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(PostcardStyle.card, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
    }
}

struct PostcardStamp: View {
    var label = "WITH LOVE"
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "sun.max").font(.title2)
            Text(label).font(.system(size: 8, weight: .bold)).tracking(1)
        }
        .foregroundStyle(PostcardStyle.vermilion)
        .frame(width: 62, height: 74)
        .background(PostcardStyle.vermilion.opacity(0.07))
        .overlay(Rectangle().strokeBorder(PostcardStyle.vermilion, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .rotationEffect(.degrees(7))
        .accessibilityHidden(true)
    }
}

struct LabeledInput: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(PostcardStyle.muted)
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.body).padding(12)
                .background(PostcardStyle.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(PostcardStyle.rule, lineWidth: 0.5))
                .accessibilityLabel(title)
        }
    }
}

struct DemoLabel: View {
    let isDemo: Bool
    var body: some View {
        if isDemo {
            Label("Demo · no messages are sent", systemImage: "sparkles")
                .font(.caption).foregroundStyle(PostcardStyle.muted)
                .padding(.vertical, 8).frame(maxWidth: .infinity)
                .accessibilityIdentifier("demo-label")
        }
    }
}
