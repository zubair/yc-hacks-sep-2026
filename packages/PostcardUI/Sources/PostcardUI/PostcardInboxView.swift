import SwiftUI
import PostcardCore

public struct PostcardInboxView: View {
    private let conversations: [PostcardConversation]
    private let isLoading: Bool
    private let error: String?
    private let onSelect: (PostcardConversation) -> Void
    private let onCompose: () -> Void
    private let onRefresh: () -> Void

    public init(
        conversations: [PostcardConversation], isLoading: Bool, error: String?,
        onSelect: @escaping (PostcardConversation) -> Void,
        onCompose: @escaping () -> Void, onRefresh: @escaping () -> Void
    ) {
        self.conversations = conversations
        self.isLoading = isLoading
        self.error = error
        self.onSelect = onSelect
        self.onCompose = onCompose
        self.onRefresh = onRefresh
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your postcards")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Refresh inbox")
                }
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(PostcardTheme.accent)
                        Button("Try again", action: onRefresh)
                    }
                }
                if isLoading && conversations.isEmpty {
                    ProgressView("Loading postcards")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if conversations.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 42, weight: .ultraLight))
                        Text("A quiet mailbox, for now")
                            .font(.system(.title2, design: .serif))
                        Text("Send a note to someone you know. Their reply will appear here.")
                            .foregroundStyle(PostcardTheme.mutedInk)
                        Button("Write a postcard", action: onCompose)
                            .buttonStyle(PaperButtonStyle(prominent: true))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(conversations) { conversation in
                            Button { onSelect(conversation) } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: "envelope")
                                        .font(.title2)
                                        .foregroundStyle(PostcardTheme.accent)
                                        .frame(width: 40)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(conversation.peer.displayName)
                                            .font(.headline)
                                        Text(conversation.latestMessage?.message ?? "Open conversation")
                                            .font(.subheadline)
                                            .lineLimit(2)
                                            .foregroundStyle(PostcardTheme.mutedInk)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 18)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(PostcardTheme.line)
                        }
                    }
                    Button("Write another postcard", action: onCompose)
                        .buttonStyle(PaperButtonStyle(prominent: true))
                }
            }
            .frame(maxWidth: 660)
            .padding(20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
        }
        .background(PostcardTheme.paper.ignoresSafeArea())
        .foregroundStyle(PostcardTheme.ink)
    }
}
