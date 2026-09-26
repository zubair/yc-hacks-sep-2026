import SwiftUI
import PostcardCore
import PostcardMotion

/// The host loads photo bytes. URL inputs describe available signed resources; this view never downloads them.
public struct PostcardConversationView: View {
    private let messages: [PostcardMessage]
    private let photoURLs: [UUID: URL]
    private let photoData: [UUID: Data]
    private let photoErrors: [UUID: String]
    private let isLoading: Bool
    private let error: String?
    private let isDemo: Bool
    private let title: String
    private let onReply: () -> Void
    private let onRefresh: () -> Void
    private let onRetryPhoto: (UUID) -> Void

    public init(messages: [PostcardMessage], photoURLs: [UUID: URL],
                photoData: [UUID: Data] = [:], photoErrors: [UUID: String] = [:],
                isLoading: Bool = false, error: String? = nil, isDemo: Bool = false,
                title: String = "Your correspondence",
                onReply: @escaping () -> Void, onRefresh: @escaping () -> Void,
                onRetryPhoto: @escaping (UUID) -> Void = { _ in }) {
        self.messages = messages; self.photoURLs = photoURLs; self.photoData = photoData
        self.photoErrors = photoErrors; self.isLoading = isLoading; self.error = error
        self.isDemo = isDemo; self.title = title; self.onReply = onReply
        self.onRefresh = onRefresh; self.onRetryPhoto = onRetryPhoto
    }

    public var body: some View {
        PaperScreen {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    DemoLabel(isDemo: isDemo)
                    PostcardHeading(eyebrow: "Postcard / from their world", title: title,
                                    subtitle: "A place for the words worth keeping.")
                    if let error { PostcardNotice(text: error, isError: true) }
                    if isLoading { ProgressView("Opening your post…").frame(maxWidth: .infinity) }
                    if messages.isEmpty && !isLoading {
                        PostcardNotice(text: "No postcards here yet. Send the first hello.")
                    }
                    ForEach(messages.sorted { $0.createdAt > $1.createdAt }, id: \.id) { message in
                        ReceivedPostcard(message: message, data: photoData[message.id],
                                         hasURL: photoURLs[message.id] != nil, photoError: photoErrors[message.id],
                                         onRetryPhoto: { onRetryPhoto(message.id) })
                    }
                    Button(action: onReply) { Label("Write back", systemImage: "arrowshape.turn.up.left") }
                        .buttonStyle(PostcardButtonStyle()).accessibilityIdentifier("reply-postcard")
                    Button("Refresh conversation", action: onRefresh)
                        .frame(maxWidth: .infinity, minHeight: 44).disabled(isLoading)
                }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }.navigationTitle("Correspondence").navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReceivedPostcard: View {
    let message: PostcardMessage
    let data: Data?
    let hasURL: Bool
    let photoError: String?
    let onRetryPhoto: () -> Void
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("From \(message.senderName)").font(.headline)
                Text(message.createdAt, format: .dateTime.month(.wide).day().year())
                    .font(.caption).foregroundStyle(PostcardStyle.muted)
            }
            PostcardFlipContainer(isOpen: isOpen, duration: 0.8) {
                VStack(spacing: 0) {
                    if let data {
                        PostcardFront(photoData: data, destination: message.destination,
                                      recipient: message.recipientName, sealed: true)
                    } else {
                        VStack(spacing: 18) {
                            Image(systemName: "photo").font(.largeTitle)
                            Text(photoError ?? (hasURL ? "Your photograph is loading." : "The photograph isn’t available yet."))
                                .multilineTextAlignment(.center).foregroundStyle(PostcardStyle.muted)
                            Button("Load photograph", action: onRetryPhoto).frame(minHeight: 44)
                        }.padding(32).frame(maxWidth: .infinity).background(PostcardStyle.card)
                    }
                }.accessibilityHidden(isOpen).allowsHitTesting(!isOpen)
            } back: {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        Text("\(message.recipientName),").font(.system(.title2, design: .serif))
                        Spacer()
                        PostcardStamp()
                    }
                    Text(message.message).font(.system(.title3, design: .serif)).lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("received-message")
                    Text("With love,\n\(message.senderName)").font(.system(.title3, design: .serif))
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(PostcardStyle.card)
                    .accessibilityHidden(!isOpen).allowsHitTesting(isOpen)
            }
            Button { isOpen.toggle() } label: {
                Label(isOpen ? "See photograph" : "Read their note", systemImage: "arrow.triangle.2.circlepath")
            }.buttonStyle(PostcardButtonStyle(secondary: true)).accessibilityIdentifier("flip-received-\(message.id)")
        }
    }
}
