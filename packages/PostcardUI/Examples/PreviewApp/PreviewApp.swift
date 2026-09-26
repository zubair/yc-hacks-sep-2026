import SwiftUI
import UIKit
import PostcardCore
import PostcardUI

// Local UI harness. All callbacks mutate local fixture state; no service is linked.
private enum Fixtures {
    static let id = "00000000-0000-0000-0000-000000000001"
    static let recipient = "00000000-0000-0000-0000-000000000002"
    static let messageID = "00000000-0000-0000-0000-000000000003"
    static func decode<T: Decodable>(_ value: [String: Any], as: T.Type = T.self) -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
    static var photo: Data? { Bundle.main.url(forResource: "coast", withExtension: "jpg").flatMap { try? Data(contentsOf: $0) } }
    static var profile: PostcardProfile { decode(["id": recipient, "username": "olivia", "displayName": "Olivia"]) }
    static var draft: PostcardDraft {
        var values: [String: Any] = ["id": id, "recipientId": recipient, "recipientName": "Olivia", "senderName": "Alex",
            "destination": "Cinque Terre", "message": "Wish you were here.\n\nThe sea really is this blue. We found a little place by the water and stayed until the light turned gold.\n\nSaving a seat for you."]
        if let photo { values["photoData"] = photo.base64EncodedString() }
        return decode(values)
    }
    static var messageJSON: [String: Any] { ["id": messageID, "conversationId": id,
        "senderId": id, "recipientId": recipient, "senderName": "Alex", "recipientName": "Olivia",
        "destination": "Cinque Terre", "message": draft.message, "photoPath": "fixture/coast.jpg", "createdAt": "2026-09-26T10:00:00Z"] }
    static var message: PostcardMessage { decode(messageJSON) }
    static var conversation: PostcardConversation {
        decode(["id": id, "peer": ["id": recipient, "username": "olivia", "displayName": "Olivia"],
                "latestMessage": messageJSON, "updatedAt": "2026-09-26T10:00:00Z"])
    }
}

@main struct PreviewApp: App {
    var body: some Scene { WindowGroup { Gallery() } }
}

private struct Gallery: View {
    @State private var draft = Fixtures.draft
    @State private var state: PostcardPresentationState = .front
    @State private var route = "front"
    @State private var lookup: PostcardProfile?
    @State private var sendCount = 0
    @State private var error: String?
    @State private var authNotice: String?
    @State private var compact = false
    @State private var largeText = false
    @State private var exportNotice: String?
    private let args = ProcessInfo.processInfo.arguments
    var body: some View {
        NavigationStack {
            Group {
                if route == "auth" {
                    PostcardAuthView(notice: authNotice, isDemo: true,
                        onSignIn: { _, _ in authNotice = "Demo sign-in received." },
                        onSignUp: { _, _, _, _ in authNotice = "Check your email to confirm your account, then sign in." })
                } else if route == "inbox" || route == "empty" {
                    PostcardInboxView(conversations: route == "empty" ? [] : [Fixtures.conversation], isDemo: true,
                        onSelect: { _ in route = "conversation" }, onCompose: { route = "front" }, onRefresh: {})
                } else if route == "conversation" {
                    PostcardConversationView(messages: [Fixtures.message], photoURLs: [:],
                        photoData: Fixtures.photo.map { [Fixtures.message.id: $0] } ?? [:], isDemo: true,
                        title: "Between you & Olivia", onReply: { route = "front" }, onRefresh: {})
                } else {
                    PostcardComposerView(draft: $draft, state: state, error: error, recipientLookupResult: lookup, isDemo: true,
                        onLookupRecipient: { query in lookup = query == "olivia" ? Fixtures.profile : nil },
                        onSelectRecipient: { profile in draft.recipientId = profile.id; draft.recipientName = profile.displayName },
                        onChoosePhoto: { draft.photoData = Fixtures.photo },
                        onOpen: { state = .writing }, onSeal: { state = .sealed },
                        onSend: { sendCount += 1; state = .sent }, onRetry: { error = nil })
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Screens") {
                        Button("Save reference image") { saveReference() }
                        Toggle("Compact preview (390 pt)", isOn: $compact)
                        Toggle("Accessibility text", isOn: $largeText)
                        Divider()
                        ForEach(["front", "writing", "sealed", "inbox", "empty", "conversation", "auth"], id: \.self) { name in
                            Button(name.capitalized) { select(name) }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(exportNotice ?? "Fixture harness · sends: \(sendCount)").font(.caption)
                    .foregroundStyle(PostcardStyle.muted).padding(8).frame(maxWidth: .infinity)
                    .background(PostcardStyle.paper).accessibilityIdentifier("send-count")
            }
        }.frame(width: compact ? 390 : nil)
            .frame(maxWidth: .infinity).background(PostcardStyle.paper)
            .environment(\.dynamicTypeSize, (largeText || args.contains("--large-text")) ? .accessibility3 : .large)
            .onAppear {
                if let index = args.firstIndex(of: "--screen"), args.indices.contains(index + 1) { select(args[index + 1]) }
                if args.contains("--error") { error = "You’re offline. Your postcard is safe. Try again when you’re connected." }
                if args.contains("--long-message") { draft.message = String(repeating: "A memory worth keeping. ", count: 160) }
            }
    }
    private func saveReference() {
        let filename = "\(route)-\(state)-\(compact ? "compact" : "wide")\(largeText ? "-large-text" : "")"
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
            let width = compact ? min(390, window.bounds.width) : window.bounds.width
            let rect = CGRect(x: 0, y: 0, width: width, height: window.bounds.height)
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
                context.cgContext.translateBy(x: -(window.bounds.width - width) / 2, y: 0)
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            #if targetEnvironment(macCatalyst)
            let folder = URL(fileURLWithPath: "/tmp/postcard-ui-references", isDirectory: true)
            #else
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("References", isDirectory: true)
            #endif
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try image.pngData()?.write(to: folder.appendingPathComponent(filename + ".png"))
                print("Saved reference: \(filename)")
            } catch { exportNotice = "Reference export failed: \(error.localizedDescription)" }
        }
    }
    private func select(_ name: String) {
        route = name
        state = name == "writing" ? .writing : (name == "sealed" ? .sealed : .front)
    }
}
