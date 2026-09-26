import SwiftUI
import PostcardCore
import PostcardServices
import PostcardUI

/// The screen is the postcard. Closed: the front. Open: the back, spread across the fold. Closed again: sealed, ready to send.
/// Presentation state comes from the Duo controller; this view only renders it and forwards explicit actions.
/// Accessibility identifiers match ios/Tests/UI/PostcardFlowUITests.swift.
struct PostcardExperienceView: View {
  @Environment(AppEnvironment.self) private var env
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.horizontalSizeClass) private var widthClass
  @FocusState private var noteFocused: Bool
  @State private var username = ""
  let onChoosePhoto: () -> Void

  private var state: PostcardPresentationState { env.presentation.state }
  private var draft: PostcardDraft { env.compose.draft }
  private var recipient: String { draft.recipientName.isEmpty ? "someone you love" : draft.recipientName }
  private var destination: String { draft.destination.isEmpty ? "somewhere lovely" : draft.destination }
  private var sender: String { draft.senderName.isEmpty ? (env.session.profile?.displayName ?? "you") : draft.senderName }

  var body: some View {
    ZStack {
      PostcardStyle.paper.ignoresSafeArea()
      switch state {
      case .writing:
        backSpread.transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity))
      case .front, .sealed, .sending, .sent:
        front.transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.45), value: state)
    .onChange(of: state) { _, next in if next != .writing { noteFocused = false } }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { noteFocused = false }
      }
    }
  }

  // MARK: Front (closed)

  private var front: some View {
    VStack(spacing: 10) {
      ZStack(alignment: .bottomLeading) {
        photo
        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: -2) {
          Text("Greetings from").font(PostcardFonts.hand(24))
          Text(destination).font(PostcardFonts.serif(46, weight: .medium)).minimumScaleFactor(0.5).lineLimit(1)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .padding(22)
      }
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(alignment: .topTrailing) {
        HStack(alignment: .top, spacing: 4) {
          if state == .front {
            Postmark(title: destination, subtitle: Date().postmarkText)
          } else {
            Postmark(title: "Sealed", subtitle: "WITH LOVE ♥", footer: "postcard")
          }
          PostageStamp()
        }
        .padding(16)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(state == .front ? "Postcard front. Greetings from \(destination), for \(recipient)." : "Sealed postcard for \(recipient).")
      .accessibilityIdentifier(state == .front ? "front" : "sealed")
      .contentShape(Rectangle())
      .onTapGesture { if state == .front { env.presentation.open(source: .manual) } }

      footer
    }
    .padding(14)
  }

  @ViewBuilder
  private var footer: some View {
    switch state {
    case .front:
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          if draft.recipientId != nil {
            Text("For \(draft.recipientName)").font(PostcardFonts.serif(15)).italic().foregroundStyle(PostcardStyle.ink)
              .accessibilityIdentifier("selected-recipient")
          } else {
            Text("For someone you know").font(PostcardFonts.serif(15)).italic().foregroundStyle(PostcardStyle.muted)
          }
          Spacer()
          Button {
            env.presentation.open(source: .manual)
          } label: {
            HStack(spacing: 6) { Text("Open to write"); Image(systemName: "arrow.right") }.font(PostcardFonts.serif(15)).italic()
          }
          .buttonStyle(.plain).foregroundStyle(PostcardStyle.ink)
          .accessibilityIdentifier("open-postcard")
          .accessibilityHint("Or open the device")
        }
        addressLine
      }
      .padding(.horizontal, 6)
    case .sealed, .sending:
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Ready to send").font(PostcardFonts.serif(30, weight: .medium)).foregroundStyle(PostcardStyle.ink)
          Text("To \(recipient)").font(.footnote).tracking(1.5).foregroundStyle(PostcardStyle.muted)
          if let error = env.compose.errorMessage {
            Text(error).font(.footnote).foregroundStyle(PostcardStyle.vermilion).fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("composer-error")
          }
        }
        Spacer(minLength: 12)
        Button {
          Task { await env.compose.canRetrySend ? env.compose.retry() : env.compose.send() }
        } label: {
          HStack(spacing: 8) {
            if state == .sending { ProgressView().tint(PostcardStyle.card) }
            Text(state == .sending ? "Sending…" : (env.compose.canRetrySend ? "Try again" : "Continue"))
            if state != .sending { Image(systemName: "arrow.right") }
          }
          .font(.body.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 12)
          .background(PostcardStyle.ink, in: Capsule()).foregroundStyle(PostcardStyle.card)
        }
        .buttonStyle(.plain)
        .disabled(!env.compose.canSend)
        .accessibilityLabel(env.compose.canRetrySend ? "Try sending again" : "Send postcard to \(recipient)")
        .accessibilityIdentifier(env.compose.canRetrySend ? "retry-postcard" : "send-postcard")
      }
      .padding(.horizontal, 6)
    case .sent:
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 2) {
          Label("Sent to \(recipient)", systemImage: "checkmark.seal.fill").font(PostcardFonts.serif(26, weight: .medium)).foregroundStyle(PostcardStyle.ink)
            .accessibilityIdentifier("sent-state")
          Text(env.mode == .fixture ? "Demo · simulated send" : "Stored. They'll find it in their inbox.").font(.footnote).foregroundStyle(PostcardStyle.muted)
        }
        Spacer(minLength: 12)
        Button("Write another") { env.compose.startNewDraft() }
          .font(.body.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 12)
          .background(PostcardStyle.vermilion, in: Capsule()).foregroundStyle(PostcardStyle.card)
          .buttonStyle(.plain)
      }
      .padding(.horizontal, 6)
    case .writing:
      EmptyView()
    }
  }

  /// Exact-username lookup on the front margin. The app performs the lookup; selecting binds the recipient into the draft.
  private var addressLine: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: "at").foregroundStyle(PostcardStyle.muted)
        TextField("recipient's username", text: $username)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .font(.subheadline)
          .onSubmit { Task { await env.compose.lookup(username: username) } }
          .accessibilityLabel("Recipient username")
          .accessibilityIdentifier("recipient-username")
        Button("Find", systemImage: "magnifyingglass") { Task { await env.compose.lookup(username: username) } }
          .labelStyle(.titleOnly).font(.subheadline.weight(.semibold)).foregroundStyle(PostcardStyle.ink)
          .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || env.compose.isLookingUp)
          .accessibilityIdentifier("find-recipient")
        if env.compose.isLookingUp { ProgressView().controlSize(.small) }
      }
      .padding(.horizontal, 12).padding(.vertical, 8)
      .background(PostcardStyle.card, in: Capsule())
      .overlay(Capsule().strokeBorder(PostcardStyle.rule, lineWidth: 0.5))
      if let profile = env.compose.lookupResult {
        Button {
          env.compose.select(recipient: profile)
          username = ""
        } label: {
          Label("Address to \(profile.displayName) · @\(profile.username)", systemImage: "person.crop.circle.badge.checkmark")
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.plain).foregroundStyle(PostcardStyle.vermilion)
        .accessibilityIdentifier("select-recipient")
      } else if let message = env.compose.lookupMessage {
        Text(message).font(.footnote).foregroundStyle(PostcardStyle.muted)
      }
    }
  }

  private var photo: some View {
    Group {
      if let data = draft.photoData, let image = UIImage(data: data) {
        Color.clear.overlay(Image(uiImage: image).resizable().scaledToFill())
      } else {
        ZStack {
          PostcardStyle.ink.opacity(0.08)
          Button(action: onChoosePhoto) {
            VStack(spacing: 10) {
              Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40, weight: .light))
              Text("Choose a photo").font(PostcardFonts.serif(20))
            }
            .foregroundStyle(PostcardStyle.ink)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }

  // MARK: Back (open) — spread across the fold

  @ViewBuilder
  private var backSpread: some View {
    @Bindable var compose = env.compose
    Group {
      if #available(iOS 27.1, *) {
        // iPhone Duo: the arrangement places the note and the address on either side of an active fold
        // (book pose side by side, table pose top and bottom) and stacks them on the closed display.
        ArrangementView {
          notePane(text: $compose.draft.message)
        } secondary: {
          addressPane
        }
        .arrangementViewStyle(.split)
      } else if widthClass == .regular {
        HStack(spacing: 0) {
          notePane(text: $compose.draft.message)
          Divider()
          addressPane
        }
      } else {
        VStack(spacing: 0) {
          notePane(text: $compose.draft.message)
          Divider()
          addressPane
        }
      }
    }
    .background(PostcardStyle.card)
    .overlay(PaperGrain().allowsHitTesting(false))
    // `.contain` keeps the children's own identifiers (message-editor, seal-postcard); without it the container's
    // identifier replaces every child's.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("writing")
  }

  private func notePane(text: Binding<String>) -> some View {
    ZStack(alignment: .topLeading) {
      if text.wrappedValue.isEmpty {
        Text("\(draft.recipientName.isEmpty ? "Hello" : draft.recipientName),\nWish you were here.")
          .font(PostcardFonts.hand(28)).foregroundStyle(PostcardStyle.muted.opacity(0.55))
          .padding(.top, 8).padding(.leading, 5)
          .allowsHitTesting(false)
      }
      TextEditor(text: text)
        .font(PostcardFonts.hand(28))
        .foregroundStyle(PostcardStyle.ink)
        .scrollContentBackground(.hidden)
        .focused($noteFocused)
        .accessibilityLabel("Your message")
        .accessibilityIdentifier("message-editor")
    }
    .padding(EdgeInsets(top: 28, leading: 28, bottom: 64, trailing: 24))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .overlay(alignment: .bottomLeading) {
      Button {
        noteFocused = true
      } label: {
        Label("Write a note", systemImage: "pencil").font(.footnote).tracking(1).foregroundStyle(PostcardStyle.muted)
      }
      .buttonStyle(.plain)
      .padding(24)
    }
    .overlay(alignment: .bottomTrailing) {
      Text("\(draft.message.unicodeScalars.count) / 5000").font(.caption2).foregroundStyle(PostcardStyle.muted.opacity(0.7)).padding(24)
    }
  }

  private var addressPane: some View {
    @Bindable var compose = env.compose
    return VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 6) {
        Spacer()
        Postmark(title: destination, subtitle: Date().postmarkText)
        PostageStamp()
      }
      Spacer(minLength: 16)
      Text("TO").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(PostcardStyle.muted)
      Text(draft.recipientName.isEmpty ? "Add a recipient on the front" : draft.recipientName)
        .font(PostcardFonts.serif(40, weight: .medium)).foregroundStyle(draft.recipientName.isEmpty ? PostcardStyle.muted : PostcardStyle.ink)
        .minimumScaleFactor(0.5).lineLimit(1)
        .accessibilityLabel("Recipient: \(recipient)")
      Rectangle().fill(PostcardStyle.ink.opacity(0.6)).frame(height: 1).padding(.top, 6)
      HStack(spacing: 6) {
        Text("FROM").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(PostcardStyle.muted)
        Text(sender).font(.footnote).foregroundStyle(PostcardStyle.ink)
      }
      .padding(.top, 10)
      HStack(spacing: 6) {
        Image(systemName: "mappin").font(.caption).foregroundStyle(PostcardStyle.muted)
        TextField("Where are you?", text: $compose.draft.destination)
          .textInputAutocapitalization(.words).font(.footnote).foregroundStyle(PostcardStyle.ink)
          .accessibilityLabel("Destination")
      }
      .padding(.top, 8)
      Spacer(minLength: 16)
      HStack {
        Text("Close to seal").font(.footnote).tracking(1.5).foregroundStyle(PostcardStyle.muted)
        Spacer()
        Button {
          env.presentation.seal(source: .manual)
        } label: {
          Text("Prepare to send").font(.body.weight(.medium)).padding(.horizontal, 20).padding(.vertical, 11)
            .overlay(Capsule().strokeBorder(PostcardStyle.ink.opacity(0.5), lineWidth: 1))
            .foregroundStyle(PostcardStyle.ink)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("seal-postcard")
        .accessibilityHint("Seals the postcard. Sending still needs Continue.")
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// Faint paper texture so the spread reads as card stock rather than flat color.
private struct PaperGrain: View {
  var body: some View {
    Canvas { context, size in
      var generator = SeededGenerator(seed: 7)
      for _ in 0..<Int(size.width * size.height / 900) {
        let x = CGFloat.random(in: 0..<size.width, using: &generator)
        let y = CGFloat.random(in: 0..<size.height, using: &generator)
        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(PostcardStyle.ink.opacity(0.05)))
      }
    }
    .accessibilityHidden(true)
  }
}

private struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
  mutating func next() -> UInt64 {
    state ^= state << 13; state ^= state >> 7; state ^= state << 17
    return state
  }
}
