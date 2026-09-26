import SwiftUI
import UIKit
import PostcardCore
import PostcardMotion

public struct PostcardComposerView: View {
    @Binding private var draft: PostcardDraft
    private let presentationState: PostcardPresentationState
    private let error: String?
    private let recipientLookupResult: PostcardProfile?
    private let isLookingUpRecipient: Bool
    private let onLookupRecipient: (String) -> Void
    private let onSelectRecipient: (PostcardProfile) -> Void
    private let onChoosePhoto: () -> Void
    private let onOpen: () -> Void
    private let onSeal: () -> Void
    private let onSend: () -> Void
    private let onRetry: () -> Void
    @State private var username = ""
    @FocusState private var isNoteFocused: Bool
    @FocusState private var isRecipientFocused: Bool

    public init(
        draft: Binding<PostcardDraft>, presentationState: PostcardPresentationState,
        error: String?, recipientLookupResult: PostcardProfile?, isLookingUpRecipient: Bool,
        onLookupRecipient: @escaping (String) -> Void,
        onSelectRecipient: @escaping (PostcardProfile) -> Void,
        onChoosePhoto: @escaping () -> Void, onOpen: @escaping () -> Void,
        onSeal: @escaping () -> Void, onSend: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        _draft = draft
        self.presentationState = presentationState
        self.error = error
        self.recipientLookupResult = recipientLookupResult
        self.isLookingUpRecipient = isLookingUpRecipient
        self.onLookupRecipient = onLookupRecipient
        self.onSelectRecipient = onSelectRecipient
        self.onChoosePhoto = onChoosePhoto
        self.onOpen = onOpen
        self.onSeal = onSeal
        self.onSend = onSend
        self.onRetry = onRetry
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make a postcard")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                    Text("A photo, a few words, one person.")
                        .font(.subheadline)
                        .foregroundStyle(PostcardTheme.mutedInk)
                }

                PostcardFlipContainer(isOpen: presentationState == .writing) {
                    front
                } back: {
                    back
                }
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .modifier(PostcardSealEffect(isSealed: presentationState == .sealed || presentationState == .sending || presentationState == .sent))
                .accessibilityElement(children: .contain)

                if presentationState == .sent {
                    Label("Postcard stored in the conversation", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(PostcardTheme.ink)
                        .accessibilityAddTraits(.isStaticText)
                }

                recipientSection

                VStack(alignment: .leading, spacing: 12) {
                    Text("From")
                        .font(.headline)
                    TextField("Your name", text: $draft.senderName)
                        .modifier(PaperField())
                        .textContentType(.name)
                    TextField("Destination or place", text: $draft.destination)
                        .modifier(PaperField())
                    Text("Your note")
                        .font(.headline)
                    TextEditor(text: $draft.message)
                        .focused($isNoteFocused)
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .modifier(PaperField())
                        .accessibilityLabel("Postcard note")
                    Text("\(draft.message.count) / 5,000 characters")
                        .font(.caption)
                        .foregroundStyle(PostcardTheme.mutedInk)
                }

                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(PostcardTheme.accent)
                        Button("Try sending again", action: onRetry)
                            .buttonStyle(PaperButtonStyle())
                    }
                    .accessibilityElement(children: .combine)
                }

                actionButtons
            }
            .frame(maxWidth: 660)
            .padding(20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
        }
        .background(PostcardTheme.paper.ignoresSafeArea())
        .foregroundStyle(PostcardTheme.ink)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isNoteFocused = false }
            }
        }
    }

    private var front: some View {
        ZStack {
            Rectangle().fill(PostcardTheme.ink)
            if let data = draft.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).clipped()
                    .accessibilityLabel("Selected postcard photo")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44, weight: .ultraLight))
                    Text("Your favorite view goes here")
                        .font(.system(.title3, design: .serif))
                }
                .foregroundStyle(PostcardTheme.paper)
            }
            VStack {
                Spacer()
                HStack {
                    Text(draft.destination.isEmpty ? "SOMEWHERE WONDERFUL" : draft.destination.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                    Spacer()
                }
                .padding(14)
                .foregroundStyle(.white)
                .background(.black.opacity(0.48))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }

    private var back: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("DEAR \(draft.recipientName.isEmpty ? "FRIEND" : draft.recipientName.uppercased()),")
                    .font(.caption.weight(.bold)).tracking(1)
                ScrollView {
                    Text(draft.message.isEmpty ? "Your message will appear here." : draft.message)
                        .font(.system(.body, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(draft.senderName.isEmpty ? "— from you" : "— \(draft.senderName)")
                    .font(.system(.body, design: .serif).italic())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(PostcardTheme.line).frame(width: 1).padding(.horizontal, 16)
            VStack(alignment: .leading) {
                Image(systemName: "seal")
                    .font(.system(size: 34))
                    .foregroundStyle(PostcardTheme.accent)
                Spacer()
                Text(draft.recipientName.isEmpty ? "Recipient" : draft.recipientName)
                    .font(.headline)
                Text(draft.destination.isEmpty ? "A place, remembered" : draft.destination)
                    .font(.caption)
                    .foregroundStyle(PostcardTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("To")
                .font(.headline)
            HStack {
                TextField("Exact username", text: $username)
                    .focused($isRecipientFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { isRecipientFocused = false; onLookupRecipient(username) }
                    .modifier(PaperField())
                    .accessibilityLabel("Recipient username")
                Button {
                    isRecipientFocused = false
                    onLookupRecipient(username)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Find recipient")
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isLookingUpRecipient)
            }
            if isLookingUpRecipient { ProgressView("Finding recipient") }
            if let result = recipientLookupResult {
                Button {
                    isRecipientFocused = false
                    username = result.username
                    onSelectRecipient(result)
                } label: {
                    Label("\(result.displayName) · @\(result.username)", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            }
            if draft.recipientId != nil {
                Label("Selected: \(draft.recipientName)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(draft.photoData == nil ? "Choose a photo" : "Change photo", action: onChoosePhoto)
                .buttonStyle(PaperButtonStyle())
            if presentationState == .front || presentationState == .sealed {
                Button("Open postcard") { isNoteFocused = false; onOpen() }
                    .buttonStyle(PaperButtonStyle())
            }
            if presentationState == .sent {
                Button("Write another postcard") { isNoteFocused = false; onOpen() }
                    .buttonStyle(PaperButtonStyle(prominent: true))
            }
            if presentationState == .writing {
                Button("Seal postcard") { isNoteFocused = false; onSeal() }
                    .buttonStyle(PaperButtonStyle())
            }
            if presentationState == .sealed {
                Button("Send postcard") { isNoteFocused = false; onSend() }
                    .buttonStyle(PaperButtonStyle(prominent: true))
                    .disabled(draft.recipientId == nil || draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if presentationState == .sending { ProgressView("Sending postcard") }
        }
    }
}
