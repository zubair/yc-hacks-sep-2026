import SwiftUI
import UIKit
import PostcardCore

public struct PostcardConversationView: View {
    private let peer: PostcardProfile
    private let messages: [PostcardMessage]
    private let photoURLs: [UUID: URL]
    private let isLoading: Bool
    private let error: String?
    private let onReply: () -> Void
    private let onRefresh: () -> Void

    public init(
        peer: PostcardProfile, messages: [PostcardMessage], photoURLs: [UUID: URL],
        isLoading: Bool, error: String?, onReply: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.peer = peer
        self.messages = messages
        self.photoURLs = photoURLs
        self.isLoading = isLoading
        self.error = error
        self.onReply = onReply
        self.onRefresh = onRefresh
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(peer.displayName)
                            .font(.system(size: 32, weight: .bold, design: .serif))
                        Text("@\(peer.username)")
                            .foregroundStyle(PostcardTheme.mutedInk)
                    }
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Refresh conversation")
                }
                if let error {
                    Text(error).foregroundStyle(PostcardTheme.accent)
                    Button("Try again", action: onRefresh)
                }
                if isLoading && messages.isEmpty { ProgressView("Loading conversation") }
                if !isLoading && messages.isEmpty {
                    Text("No postcards yet. Write the first one.")
                        .foregroundStyle(PostcardTheme.mutedInk)
                }
                ForEach(messages) { item in
                    VStack(alignment: .leading, spacing: 14) {
                        if let url = photoURLs[item.id] {
                            Group {
                                if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFit()
                                        case .failure:
                                            Label("Photo unavailable. Refresh to retry.", systemImage: "photo")
                                                .foregroundStyle(PostcardTheme.mutedInk)
                                        default:
                                            ProgressView("Loading photo")
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(item.message)
                            .font(.system(.body, design: .serif))
                            .textSelection(.enabled)
                        HStack {
                            Text("From \(item.senderName)")
                            Spacer()
                            Text(item.createdAt, style: .date)
                        }
                        .font(.caption)
                        .foregroundStyle(PostcardTheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.09), radius: 9, y: 4)
                    .accessibilityElement(children: .combine)
                }
                Button("Write to \(peer.displayName)", action: onReply)
                    .buttonStyle(PaperButtonStyle(prominent: true))
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
