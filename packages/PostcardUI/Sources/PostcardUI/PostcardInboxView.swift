import SwiftUI
import PostcardCore

public struct PostcardInboxView: View {
    private let conversations: [PostcardConversation]
    private let isLoading: Bool
    private let error: String?
    private let isDemo: Bool
    private let onSelect: (PostcardConversation) -> Void
    private let onCompose: () -> Void
    private let onRefresh: () -> Void

    public init(conversations: [PostcardConversation], isLoading: Bool = false,
                error: String? = nil, isDemo: Bool = false,
                onSelect: @escaping (PostcardConversation) -> Void,
                onCompose: @escaping () -> Void, onRefresh: @escaping () -> Void) {
        self.conversations = conversations; self.isLoading = isLoading; self.error = error
        self.isDemo = isDemo; self.onSelect = onSelect; self.onCompose = onCompose; self.onRefresh = onRefresh
    }

    public var body: some View {
        PaperScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    DemoLabel(isDemo: isDemo)
                    PostcardHeading(eyebrow: "Postcard / your collection", title: "Good things arrive.",
                                    subtitle: "Little pieces of the world, just for you.")
                    Button(action: onCompose) { Label("Write a postcard", systemImage: "square.and.pencil") }
                        .buttonStyle(PostcardButtonStyle()).accessibilityIdentifier("compose-postcard")
                    if let error {
                        PostcardNotice(text: error, isError: true)
                        Button("Refresh inbox", action: onRefresh).buttonStyle(PostcardButtonStyle(secondary: true)).disabled(isLoading)
                    }
                    if isLoading { ProgressView("Checking your post…").frame(maxWidth: .infinity) }
                    if conversations.isEmpty && !isLoading {
                        VStack(spacing: 18) {
                            PostcardStamp(label: "HELLO")
                            Text(error == nil ? "Your first hello awaits." : "Your postcards will return.")
                                .font(.system(.title2, design: .serif)).multilineTextAlignment(.center)
                            Text(error == nil ? "Send someone a moment from your day. Their reply will feel like a little getaway." : "Refresh when you’re connected again.")
                                .font(.body).foregroundStyle(PostcardStyle.muted).multilineTextAlignment(.center)
                        }.padding(32).frame(maxWidth: .infinity)
                            .background(PostcardStyle.card, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("empty-inbox")
                    }
                    LazyVStack(spacing: 16) {
                        ForEach(conversations, id: \.id) { conversation in
                            Button { onSelect(conversation) } label: { row(conversation) }
                                .buttonStyle(.plain).accessibilityIdentifier("conversation-\(conversation.id)")
                        }
                    }
                    if error == nil {
                        Button(action: onRefresh) { Label("Check for postcards", systemImage: "arrow.clockwise") }
                            .frame(maxWidth: .infinity, minHeight: 44).disabled(isLoading)
                    }
                }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Postcards").navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ conversation: PostcardConversation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(conversation.peer.displayName).font(.system(.title2, design: .serif))
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").foregroundStyle(PostcardStyle.vermilion)
            }
            if let message = conversation.latestMessage {
                Text(message.destination.isEmpty ? "A moment to remember" : message.destination.uppercased())
                    .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(PostcardStyle.vermilion)
                Text(message.message).font(.body).foregroundStyle(PostcardStyle.muted).lineLimit(3)
            } else {
                Text("Start your correspondence.").foregroundStyle(PostcardStyle.muted)
            }
            Divider().overlay(PostcardStyle.rule)
            Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption).foregroundStyle(PostcardStyle.muted)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(PostcardStyle.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PostcardStyle.rule, lineWidth: 0.5))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the complete conversation")
    }
}
