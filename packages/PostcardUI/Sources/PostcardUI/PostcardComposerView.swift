import SwiftUI
import PostcardCore
import PostcardMotion

/// Controlled composer. Only callbacks ask the host to change presentation or send.
public struct PostcardComposerView: View {
    @Binding private var draft: PostcardDraft
    private let state: PostcardPresentationState
    private let error: String?
    private let recipientLookupResult: PostcardProfile?
    private let isLookingUpRecipient: Bool
    private let recipientLookupMessage: String?
    private let isDemo: Bool
    private let onLookupRecipient: (String) -> Void
    private let onSelectRecipient: (PostcardProfile) -> Void
    private let onChoosePhoto: () -> Void
    private let onOpen: () -> Void
    private let onSeal: () -> Void
    private let onSend: () -> Void
    private let onRetry: () -> Void
    @State private var username = ""
    @FocusState private var messageFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(draft: Binding<PostcardDraft>, state: PostcardPresentationState,
                error: String? = nil, recipientLookupResult: PostcardProfile? = nil,
                isLookingUpRecipient: Bool = false, recipientLookupMessage: String? = nil,
                isDemo: Bool = false,
                onLookupRecipient: @escaping (String) -> Void,
                onSelectRecipient: @escaping (PostcardProfile) -> Void,
                onChoosePhoto: @escaping () -> Void, onOpen: @escaping () -> Void,
                onSeal: @escaping () -> Void, onSend: @escaping () -> Void,
                onRetry: @escaping () -> Void) {
        _draft = draft; self.state = state; self.error = error
        self.recipientLookupResult = recipientLookupResult
        self.isLookingUpRecipient = isLookingUpRecipient
        self.recipientLookupMessage = recipientLookupMessage; self.isDemo = isDemo
        self.onLookupRecipient = onLookupRecipient; self.onSelectRecipient = onSelectRecipient
        self.onChoosePhoto = onChoosePhoto; self.onOpen = onOpen; self.onSeal = onSeal
        self.onSend = onSend; self.onRetry = onRetry
    }

    private var busy: Bool { state == .sending || state == .sent }
    private var isOpen: Bool { state == .writing }
    private var issue: String? { PostcardFormRules.sendIssue(draft) }
    private var title: String {
        switch state {
        case .writing: "Make it personal."
        case .sealed: "Sealed with love."
        case .sending: "On its way."
        case .sent: isDemo ? "A little closer. (Demo)" : "A little closer."
        default: "Wish you were here."
        }
    }

    public var body: some View {
        PaperScreen {
            GeometryReader { geometry in
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            DemoLabel(isDemo: isDemo)
                            PostcardHeading(eyebrow: "Postcard / a little closer", title: title,
                                            subtitle: isOpen ? "A few words can carry you a long way." : "A moment from your world, sent to theirs.")
                            if geometry.size.width >= 760 && !typeSize.isAccessibilitySize {
                                HStack(alignment: .top, spacing: 36) {
                                    card.frame(maxWidth: .infinity)
                                    controls.frame(width: min(340, geometry.size.width * 0.4))
                                }
                            } else {
                                card
                                controls
                            }
                        }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messageFocused) { _, focused in
                        if focused { scroll.scrollTo("message-editor", anchor: .center) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !busy {
                primaryAction.padding(.horizontal, 24).padding(.vertical, 12)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    .background(PostcardStyle.paper)
            }
        }
        .navigationTitle("Your postcard").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { messageFocused = false }
            }
        }
    }

    private var card: some View {
        PostcardFlipContainer(isOpen: isOpen, duration: 0.8) {
            PostcardFront(photoData: draft.photoData, destination: draft.destination,
                          recipient: draft.recipientName, sealed: state == .sealed || busy)
                .modifier(PostcardSealEffect(isSealed: state == .sealed || busy))
                .accessibilityHidden(isOpen).allowsHitTesting(!isOpen)
        } back: {
            writingBack.accessibilityHidden(!isOpen).allowsHitTesting(isOpen)
        }
    }

    private var writingBack: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEAR").font(.caption.weight(.semibold)).tracking(2)
                    Text(draft.recipientName.isEmpty ? "someone special," : "\(draft.recipientName),")
                        .font(.system(.title2, design: .serif)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PostcardStamp()
            }
            Text("Your message").font(.caption.weight(.semibold)).foregroundStyle(PostcardStyle.muted)
            TextField("Wish you were here…", text: $draft.message, axis: .vertical)
                .font(.system(.title3, design: .serif)).lineSpacing(7).lineLimit(6...14)
                .focused($messageFocused).accessibilityLabel("Your message")
                .accessibilityIdentifier("message-editor").id("message-editor")
            Text("\(PostcardFormRules.length(draft.message).formatted()) / 5,000")
                .font(.caption).foregroundStyle(PostcardFormRules.length(draft.message) > 5000 ? PostcardStyle.vermilion : PostcardStyle.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("\(PostcardFormRules.length(draft.message)) of 5000 characters")
            Divider().overlay(PostcardStyle.rule)
            LabeledInput(title: "WITH LOVE FROM", placeholder: "Your name", text: $draft.senderName)
        }.padding(24).background(PostcardStyle.card)
            .overlay(Rectangle().stroke(PostcardStyle.rule, lineWidth: 0.5))
            .shadow(color: PostcardStyle.ink.opacity(0.08), radius: 18, y: 8)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error { PostcardNotice(text: error, isError: true).accessibilityIdentifier("composer-error") }
            if state == .sent {
                Label(isDemo ? "Demo postcard saved" : "Postcard sent", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.medium)).accessibilityIdentifier("sent-state")
                Text(isDemo ? "Saved in the demo inbox. View as the recipient to see it." : "Your postcard is saved in the conversation.")
                    .foregroundStyle(PostcardStyle.muted)
            } else if state == .sending {
                ProgressView(isDemo ? "Previewing send…" : "Sending your postcard…")
                Text("Your note is safe while we send it.").font(.subheadline).foregroundStyle(PostcardStyle.muted)
            } else {
                if state == .sealed {
                    Label("To \(draft.recipientName.isEmpty ? "someone special" : draft.recipientName)", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.medium))
                } else {
                    recipientSection
                }
                if state == .front {
                    LabeledInput(title: "GREETINGS FROM", placeholder: "A place, a feeling, a moment", text: $draft.destination)
                    Button(action: onChoosePhoto) {
                        Label(draft.photoData == nil ? "Choose a photograph" : "Change photograph", systemImage: "photo")
                    }.buttonStyle(PostcardButtonStyle(secondary: true)).accessibilityIdentifier("choose-photo")
                }
                if state == .sealed {
                    if let issue { PostcardNotice(text: issue) }
                    Button("Open to edit", action: onOpen).buttonStyle(PostcardButtonStyle(secondary: true))
                        .accessibilityIdentifier("open-postcard")
                } else if isOpen {
                    Text("Closing seals your draft. You choose when to send.")
                        .font(.caption).foregroundStyle(PostcardStyle.muted)
                }
                if error != nil {
                    Button("Try again", action: onRetry).buttonStyle(PostcardButtonStyle(secondary: true))
                        .disabled(state == .sealed && issue != nil).accessibilityIdentifier("retry-postcard")
                }
            }
        }.disabled(busy)
    }

    @ViewBuilder private var primaryAction: some View {
        if state == .sealed {
            Button(action: onSend) {
                Label(isDemo ? "Preview sending" : "Send your postcard", systemImage: "paperplane")
            }.buttonStyle(PostcardButtonStyle()).disabled(issue != nil).accessibilityIdentifier("send-postcard")
        } else if isOpen {
            Button { messageFocused = false; onSeal() } label: {
                Label("Close & seal", systemImage: "heart")
            }.buttonStyle(PostcardButtonStyle()).accessibilityIdentifier("seal-postcard")
        } else {
            Button(action: onOpen) { Label("Open your postcard", systemImage: "arrow.turn.up.right") }
                .buttonStyle(PostcardButtonStyle()).accessibilityIdentifier("open-postcard")
        }
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.recipientId != nil {
                Label("To \(draft.recipientName)", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.medium)).accessibilityIdentifier("selected-recipient")
            }
            Text("FIND SOMEONE BY USERNAME").font(.caption.weight(.semibold)).foregroundStyle(PostcardStyle.muted)
            HStack(alignment: .center, spacing: 8) {
                TextField("e.g. olivia", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    .padding(12).background(PostcardStyle.card, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Recipient username").accessibilityIdentifier("recipient-username")
                    .onSubmit { lookup() }
                Button(action: lookup) {
                    if isLookingUpRecipient { ProgressView().accessibilityLabel("Finding recipient") }
                    else { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                }.disabled(isLookingUpRecipient || !PostcardFormRules.validUsername(PostcardFormRules.normalizedUsername(username)))
                    .accessibilityLabel("Find recipient").accessibilityIdentifier("find-recipient")
            }
            if let profile = recipientLookupResult,
               profile.username.lowercased() == PostcardFormRules.normalizedUsername(username) {
                Button { onSelectRecipient(profile) } label: {
                    Label("Choose \(profile.displayName) (@\(profile.username))", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("select-recipient")
            }
            if let recipientLookupMessage {
                Text(recipientLookupMessage).font(.caption).foregroundStyle(PostcardStyle.muted)
            }
        }
    }
    private func lookup() {
        let query = PostcardFormRules.normalizedUsername(username)
        guard !isLookingUpRecipient, PostcardFormRules.validUsername(query) else { return }
        onLookupRecipient(query)
    }
}
