import SwiftUI
import UIKit
import PhotosUI

private let paper = Color(red: 0.96, green: 0.945, blue: 0.91)
private let card = Color(red: 0.995, green: 0.985, blue: 0.956)
private let ink = Color(red: 0.16, green: 0.22, blue: 0.20)
private let vermilion = Color(red: 0.79, green: 0.23, blue: 0.14)

@main
struct PostcardApp: App {
    var body: some Scene {
        WindowGroup {
            // The stack hosts the keyboard toolbar; its bar stays hidden to keep the paper look.
            NavigationStack { PostcardHome().toolbar(.hidden, for: .navigationBar) }
        }
    }
}

struct PostcardHome: View {
    @State private var editor = PostcardEditor()
    @State private var flow = PostcardFlow()
    @State private var showImageFallback = false
    @State private var showLinkHandoff = false
    @State private var showFraming = false
    @State private var exportImage: UIImage?
    @State private var frontImage: UIImage?
    @State private var photoSelection: PhotosPickerItem?
    @State private var photoError = false
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var controlFont: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var captionFont: CGFloat = 13

    private var opened: Bool { flow.stage == .writing }
    private var sealed: Bool { flow.stage == .sealed }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 650
            ZStack {
                paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: wide ? 22 : 18) {
                        header
                        HStack(spacing: 7) {
                            Circle().fill(vermilion).frame(width: 5, height: 5)
                            Text(sealed ? "SEALED WITH A LITTLE LOVE" : opened ? "A FEW WORDS. A WHOLE WORLD." : "A LITTLE PIECE OF SOMEWHERE.")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2)
                        }
                        .foregroundStyle(ink.opacity(0.55)).padding(.top, 4)
                        .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        cardFace(wide: wide)
                        Spacer(minLength: 0)
                        VStack(spacing: 9) {
                            Text(sealed ? "Ready to make their day." : opened ? "Distance, in your own words." : "Wish you were here.")
                                .font(.system(size: wide ? 32 : 29, weight: .regular, design: .serif))
                                .multilineTextAlignment(.center)
                            Text(sealed ? "Your postcard is sealed. Publish it to get a link for \(recipientName)." : opened ? "Close your postcard to seal it with love." : "Open a postcard. Leave a little of yourself.")
                                .font(.system(size: captionFont)).foregroundStyle(ink.opacity(0.62))
                                .multilineTextAlignment(.center)
                        }
                        if !opened && !sealed { photoControls }
                        controls
                        if sealed { publishStatus }
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, wide ? 32 : 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .frame(minHeight: max(geometry.size.height - 18, 0))
                    .disabled(flow.demoRunning)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .onAppear { flow.layoutChanged(wide: wide) }
            .onHingeChange { oldContext, newContext in
                guard let hinge = newContext.hinge else { return }
                let old = oldContext.hinge.map { FoldPosture($0.status == .closed) }
                flow.hingeChanged(from: old, to: FoldPosture(hinge.status == .closed))
            }
        }
        .task(id: photoSelection) {
            guard let photoSelection else { return }
            do {
                if let data = try await photoSelection.loadTransferable(type: Data.self), editor.setPhoto(data: data) {
                    flow.photoChanged()
                } else { photoError = true }
            } catch { photoError = true }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { editor.saveNow() } }
        .onChange(of: showImageFallback || showLinkHandoff || showFraming) { _, busy in flow.isFrozen = busy }
        .alert("Couldn’t open that photo", isPresented: $photoError) {
            Button("OK", role: .cancel) { }
        } message: { Text("Choose another photo from your library.") }
        .sheet(isPresented: $showImageFallback) {
            if let exportImage {
                SendPostcardSheet(image: exportImage, message: exportMessage, frontImage: frontImage)
            }
        }
        .sheet(isPresented: $showLinkHandoff) {
            if case .ready(let url) = editor.phase {
                LinkHandoffSheet(url: url, recipient: recipientName, shareText: editor.shareText(for: url),
                                 fixtureLabel: editor.publisher.label) {
                    showLinkHandoff = false
                    // Let the link sheet finish dismissing before presenting the image sheet.
                    Task { try? await Task.sleep(for: .milliseconds(600)); prepareImageFallback() }
                }
            }
        }
        .sheet(isPresented: $showFraming) {
            if let source = editor.sourcePhoto {
                FramingEditor(image: source, crop: editor.draft.crop) { editor.setCrop($0) }
            }
        }
    }

    private var recipientName: String {
        let name = editor.draft.recipient.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "them" : name
    }

    @ViewBuilder private func cardFace(wide: Bool) -> some View {
        @Bindable var bindable = editor
        Group {
            if opened {
                PostcardBack(draft: $bindable.draft, wide: wide)
                    .transition(flow.turnTransition(angle: -85))
            } else {
                PostcardFront(sealed: sealed, photo: editor.framedPhoto, destination: editor.draft.destination)
                    .rotationEffect(.degrees(sealed ? 0 : -2))
                    .transition(flow.turnTransition(angle: 85))
            }
        }
        .frame(maxWidth: opened && wide ? 950 : 380)
        .shadow(color: ink.opacity(0.12), radius: 24, x: 0, y: 15)
        .padding(.horizontal, wide ? 30 : 4)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Image(systemName: "envelope.open").font(.system(size: 20, weight: .light))
                Text("postcard").font(.system(size: 30, weight: .regular, design: .serif)).tracking(-1.5)
                Circle().fill(vermilion).frame(width: 5, height: 5).offset(x: -4, y: 7)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Postcard")
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { flow.playDemo() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 9))
                    Text(flow.demoRunning ? "PLAYING" : "PLAY DEMO").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .overlay(Capsule().stroke(ink.opacity(0.2), lineWidth: 0.7))
            }
            .disabled(flow.demoRunning || editor.isPublishing)
            .accessibilityLabel(flow.demoRunning ? "Demo playing" : "Play demo")
            .accessibilityHint("Previews opening and sealing the postcard. Nothing is sent.")
        }
    }

    private var photoControls: some View {
        HStack(spacing: 18) {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Label(editor.photo == nil ? "Use your travel photo" : "Change photo", systemImage: "photo")
                    .frame(minHeight: 44)
            }
            .accessibilityHint("Choose a photo for the front of the postcard")
            Button { showFraming = true } label: {
                Label("Adjust framing", systemImage: "crop").frame(minHeight: 44)
            }
            .accessibilityHint("Zoom and move the photo inside the postcard")
        }
        .font(.system(size: captionFont, weight: .medium))
        .foregroundStyle(ink.opacity(0.8))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if sealed {
                Button { flow.edit() } label: {
                    Image(systemName: "pencil").frame(width: 51, height: 51)
                        .overlay(Circle().stroke(ink.opacity(0.2), lineWidth: 1))
                }
                .accessibilityLabel("Edit postcard")
                .disabled(editor.isPublishing)
            }
            Button(action: primaryAction) {
                HStack(spacing: 12) {
                    if editor.isPublishing { ProgressView().tint(paper) }
                    Text(primaryTitle).font(.system(size: controlFont, weight: .medium))
                    if !editor.isPublishing { Image(systemName: primarySymbol).font(.system(size: controlFont - 2)) }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity).frame(minHeight: 52)
                .background(sealed ? vermilion : ink).foregroundStyle(paper).clipShape(Capsule())
            }
            .disabled(editor.isPublishing)
            .accessibilityHint(sealed ? "Uploads your postcard and gives you a link to share. Nothing is sent until you choose." : "")
        }
        .frame(maxWidth: 400).padding(.top, 7).padding(.bottom, sealed ? 0 : 10)
    }

    private var primaryTitle: String {
        switch flow.stage {
        case .front: return "Open your postcard"
        case .writing: return "Close & seal"
        case .sealed:
            switch editor.phase {
            case .idle: return "Publish & get link"
            case .publishing: return "Publishing…"
            case .ready: return "Share link"
            case .failed(let error): return error.isRetryable ? "Try again" : "Publish & get link"
            }
        }
    }

    private var primarySymbol: String {
        switch flow.stage {
        case .front: return "arrow.right"
        case .writing: return "envelope.badge"
        case .sealed:
            if case .ready = editor.phase { return "square.and.arrow.up" }
            if case .failed = editor.phase { return "arrow.clockwise" }
            return "arrow.up.right"
        }
    }

    private func primaryAction() {
        switch flow.stage {
        case .front: flow.open()
        case .writing: flow.seal()
        case .sealed:
            if case .ready = editor.phase { showLinkHandoff = true; return }
            Task {
                await editor.publish()
                if case .ready = editor.phase { showLinkHandoff = true }
            }
        }
    }

    @ViewBuilder private var publishStatus: some View {
        VStack(spacing: 10) {
            switch editor.phase {
            case .idle:
                EmptyView()
            case .publishing:
                Text("Uploading your postcard. Keep the app open.")
                    .accessibilityAddTraits(.updatesFrequently)
            case .ready(let url):
                Label("Ready to share", systemImage: "checkmark.seal")
                    .font(.system(size: captionFont, weight: .semibold)).foregroundStyle(ink)
                Text(url.absoluteString).font(.system(size: captionFont - 1, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                if let label = editor.publisher.label {
                    Text(label).font(.system(size: captionFont - 1, weight: .semibold)).foregroundStyle(vermilion)
                }
            case .failed(let error):
                Label(error.userMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(vermilion)
            }
            Button("Save or send as an image instead", action: prepareImageFallback)
                .font(.system(size: captionFont, weight: .medium)).underline()
                .frame(minHeight: 44)
                .disabled(editor.isPublishing)
            if let problem = editor.saveProblem { Text(problem).foregroundStyle(vermilion) }
        }
        .font(.system(size: captionFont))
        .foregroundStyle(ink.opacity(0.7))
        .multilineTextAlignment(.center)
        .padding(.bottom, 10)
    }

    private var exportMessage: String {
        let draft = editor.draft
        let signature = draft.sender.trimmingCharacters(in: .whitespaces)
        return "Dear \(draft.recipient),\n\n\(draft.message)" + (signature.isEmpty ? "" : "\n\n— \(signature)")
    }

    @MainActor private func prepareImageFallback() {
        let draft = editor.draft
        let renderer = ImageRenderer(content: ExportPostcard(draft: draft, photo: editor.framedPhoto)
            .frame(width: 1000).fixedSize(horizontal: false, vertical: true))
        renderer.scale = 2
        exportImage = renderer.uiImage
        let frontRenderer = ImageRenderer(content: PostcardFront(sealed: true, photo: editor.framedPhoto, destination: draft.destination).frame(width: 460))
        frontRenderer.scale = 2
        frontImage = frontRenderer.uiImage
        showImageFallback = exportImage != nil
    }
}

// MARK: - Fold flow (integration seam for Zubair's DuoInteractionController)

/// Posture reduced to what the flow needs. Layout follows reserved regions; the hinge only drives transitions.
enum FoldPosture: Equatable {
    case closed, open
    init(_ isClosed: Bool) { self = isClosed ? .closed : .open }
}

/// The single owner of front → writing → sealed transitions. When
/// `DuoInteractionController` lands on `feature/duo-interaction`, replace this
/// type with it (same surface: `stage`, `open()`, `seal()`, `edit()`,
/// `hingeChanged(from:to:)`, `isFrozen`, `playDemo()`); the views need no other change.
/// Nothing here publishes or sends.
@MainActor @Observable
final class PostcardFlow {
    enum Stage { case front, writing, sealed }

    private(set) var stage: Stage = .front
    private(set) var demoRunning = false
    /// True while a sheet or composer is up, so a fold can't change the card underneath it.
    var isFrozen = false
    private var hasOpened = false
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    func turnTransition(angle: Double) -> AnyTransition {
        reduceMotion ? .opacity : .modifier(active: CardTurn(angle: angle), identity: CardTurn(angle: 0)).combined(with: .opacity)
    }

    func open() {
        guard stage != .writing else { return }
        hasOpened = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        animate(.spring(response: 0.7, dampingFraction: 0.85)) { self.stage = .writing }
    }

    func seal() {
        guard stage == .writing else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        animate(.spring(response: 0.75, dampingFraction: 0.75)) { self.stage = .sealed }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    func edit() { open() }

    func photoChanged() {
        if stage == .sealed { animate(.default) { self.stage = .front } }
    }

    /// Wide space means the inner display is open: start on the message.
    func layoutChanged(wide: Bool) {
        if wide && !hasOpened { hasOpened = true; stage = .writing }
    }

    func hingeChanged(from old: FoldPosture?, to new: FoldPosture) {
        guard !demoRunning, !isFrozen else { return }
        switch new {
        case .closed:
            if hasOpened { seal() }
        case .open:
            if old == .closed || !hasOpened { open() }
        }
    }

    /// Reliable stage demo: front → writing → sealed. Never publishes.
    func playDemo() {
        guard !demoRunning else { return }
        demoRunning = true
        animate(.default) { self.stage = .front }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            self.open()
            try? await Task.sleep(for: .seconds(3))
            self.seal()
            self.demoRunning = false
        }
    }

    private func animate(_ animation: Animation, _ body: @escaping () -> Void) {
        if reduceMotion { withAnimation(.easeInOut(duration: 0.25), body) } else { withAnimation(animation, body) }
    }
}

private struct CardTurn: ViewModifier {
    var angle: Double
    func body(content: Content) -> some View {
        content.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
    }
}

// MARK: - Card faces

struct PostcardFront: View {
    var sealed = false
    var photo: UIImage? = nil
    var destination = "Cinque Terre"
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .overlay {
                        (photo.map { Image(uiImage: $0) } ?? Image("Coast")).resizable().scaledToFill()
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.53)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    Text("GREETINGS FROM").font(.system(size: 9, weight: .medium)).tracking(3.5)
                    Text(destination.isEmpty ? "Somewhere\nbeautiful." : destination + ".")
                        .font(.system(size: 53, weight: .regular, design: .serif)).tracking(-2).lineSpacing(-6)
                        .minimumScaleFactor(0.45).lineLimit(3)
                }.foregroundStyle(.white).padding(23)
                VStack {
                    HStack { Spacer(); Stamp().rotationEffect(.degrees(9)) }
                    Spacer()
                }.padding(15)
                if sealed {
                    VStack {
                        Spacer()
                        HStack { Spacer(); postmark.padding(16) }
                    }.transition(.scale(scale: 1.8).combined(with: .opacity))
                }
            }
            .aspectRatio(PhotoCrop.frontAspect, contentMode: .fit)
            HStack {
                Text("VIA AIR MAIL").font(.system(size: 9, weight: .semibold)).tracking(3)
                Spacer()
                Text("A MOMENT, MAILED.").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(1.5)
            }.foregroundStyle(ink.opacity(0.7)).padding(.horizontal, 15).padding(.vertical, 16)
        }
        .padding(9).background(card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Postcard front. Greetings from \(destination.isEmpty ? "somewhere beautiful" : destination).\(sealed ? " Sealed with love." : "")")
    }

    private var postmark: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.85), lineWidth: 1.5)
            Circle().stroke(.white.opacity(0.65), lineWidth: 0.5).padding(5)
            VStack(spacing: 4) {
                Text("SEALED WITH").font(.system(size: 6, weight: .bold)).tracking(1)
                Image(systemName: "heart.fill").font(.system(size: 19))
                Text("LOVE").font(.system(size: 8, weight: .bold)).tracking(2)
            }.foregroundStyle(.white)
        }.frame(width: 78, height: 78).rotationEffect(.degrees(-15))
    }
}

struct Stamp: View {
    var body: some View {
        ZStack {
            Rectangle().fill(paper)
            Rectangle().strokeBorder(paper, style: StrokeStyle(lineWidth: 5, dash: [2, 3]))
            VStack(spacing: 3) {
                Text("POSTCARD POST").font(.system(size: 5, weight: .bold)).tracking(0.4)
                Image(systemName: "sun.max").font(.system(size: 25, weight: .ultraLight))
                HStack { Text("AIR MAIL"); Spacer(); Text("♡") }.font(.system(size: 5, weight: .bold))
            }.foregroundStyle(paper).padding(6).background(vermilion).padding(5)
        }
        .frame(width: 58, height: 72)
        .accessibilityHidden(true)
    }
}

struct PostcardBack: View {
    @Binding var draft: PostcardDraft
    var wide: Bool
    @FocusState private var focus: Field?
    @ScaledMetric(relativeTo: .body) private var noteSize: CGFloat = 19
    @ScaledMetric(relativeTo: .title3) private var nameSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 10

    private enum Field: Hashable { case message, recipient, sender, destination }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("POST CARD").font(.system(size: 15, weight: .regular, design: .serif)).tracking(5)
                Spacer()
                Text("№ 001").font(.system(size: 9, design: .monospaced)).foregroundStyle(ink.opacity(0.4))
            }
            .accessibilityHidden(true)
            Rectangle().fill(ink.opacity(0.14)).frame(height: 0.5)
            if wide {
                HStack(alignment: .top, spacing: 28) {
                    note.frame(maxWidth: .infinity)
                    Rectangle().fill(ink.opacity(0.13)).frame(width: 0.7)
                    address.frame(maxWidth: .infinity)
                }.frame(minHeight: 280)
            } else {
                note
                Rectangle().fill(ink.opacity(0.14)).frame(height: 0.5)
                address
            }
            HStack {
                Image(systemName: "heart").font(.system(size: 9))
                Text("SENT SLOWLY. FELT DEEPLY.").font(.system(size: 7, design: .monospaced)).tracking(1.5)
                Spacer()
            }
            .foregroundStyle(ink.opacity(0.35))
            .accessibilityHidden(true)
        }
        .padding(wide ? 32 : 22)
        .background(card)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: labelSize, weight: .semibold)).tracking(2).foregroundStyle(ink.opacity(0.55))
            .accessibilityHidden(true)
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel("YOUR WORDS")
                Spacer()
                if draft.message.count > PostcardDraft.messageLimit - 500 {
                    Text("\(draft.message.count) / \(PostcardDraft.messageLimit)")
                        .font(.system(size: labelSize, design: .monospaced))
                        .foregroundStyle(draft.message.count > PostcardDraft.messageLimit ? vermilion : ink.opacity(0.5))
                }
            }
            // Grows with the message instead of scrolling inside a fixed box, so long notes stay readable.
            TextField("Write something only they would understand…", text: $draft.message, axis: .vertical)
                .font(.custom("Georgia-Italic", size: wide ? noteSize + 4 : noteSize, relativeTo: .body))
                .lineSpacing(5).lineLimit((wide ? 9 : 7)...)
                .foregroundStyle(ink).tint(vermilion)
                .focused($focus, equals: .message)
                .accessibilityLabel("Message")
        }
    }

    private var address: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("DELIVER TO")
                    TextField("Someone you miss", text: $draft.recipient)
                        .font(.system(size: nameSize, design: .serif)).tint(vermilion)
                        .textContentType(.name).submitLabel(.next)
                        .focused($focus, equals: .recipient)
                        .onSubmit { focus = .sender }
                        .accessibilityLabel("Recipient")
                }
                Spacer()
                Stamp().rotationEffect(.degrees(5))
            }
            Rectangle().fill(ink.opacity(0.15)).frame(height: 0.6)
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("FROM")
                TextField("Your name", text: $draft.sender)
                    .font(.system(size: nameSize - 2, design: .serif)).tint(vermilion)
                    .textContentType(.givenName).submitLabel(.next)
                    .focused($focus, equals: .sender)
                    .onSubmit { focus = .destination }
                    .accessibilityLabel("Sender")
            }
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("WRITING FROM")
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.system(size: labelSize)).foregroundStyle(vermilion.opacity(0.8))
                    TextField("Your destination", text: $draft.destination)
                        .font(.custom("Georgia-Italic", size: nameSize - 4, relativeTo: .body)).tint(vermilion)
                        .textContentType(.addressCity).submitLabel(.done)
                        .focused($focus, equals: .destination)
                        .onSubmit { focus = nil }
                        .accessibilityLabel("Destination")
                }
            }
            if wide { Spacer(); Image(systemName: "sun.horizon").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(vermilion.opacity(0.5)).accessibilityHidden(true) }
        }
    }
}

/// The image fallback. Grows vertically so a long message is never clipped.
struct ExportPostcard: View {
    let draft: PostcardDraft
    var photo: UIImage? = nil

    private var messageSize: CGFloat {
        switch draft.message.count {
        case ..<400: return 24
        case ..<1200: return 20
        default: return 17
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            PostcardFront(sealed: true, photo: photo, destination: draft.destination).frame(width: 460)
            VStack(alignment: .leading, spacing: 25) {
                Text("POST CARD").font(.system(size: 19, design: .serif)).tracking(6)
                Rectangle().fill(ink.opacity(0.2)).frame(height: 1)
                Text("Dear \(draft.recipient),").font(.custom("Georgia-Italic", size: 22))
                Text(draft.message).font(.custom("Georgia-Italic", size: messageSize)).lineSpacing(messageSize * 0.4)
                    .fixedSize(horizontal: false, vertical: true)
                if !draft.sender.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("— \(draft.sender)").font(.custom("Georgia-Italic", size: 22))
                }
                Spacer(minLength: 0)
                Text("FROM \(draft.destination.uppercased()), WITH LOVE.").font(.system(size: 10, design: .monospaced)).tracking(2)
            }
            .padding(35).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(ink).frame(minHeight: 580).background(paper)
    }
}

// MARK: - Framing

/// Drag to move, pinch or use the slider to zoom. The preview is exactly what gets published.
struct FramingEditor: View {
    let image: UIImage
    @State var crop: PhotoCrop
    let onDone: (PhotoCrop) -> Void
    @Environment(\.dismiss) private var dismiss
    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    init(image: UIImage, crop: PhotoCrop, onDone: @escaping (PhotoCrop) -> Void) {
        self.image = image
        _crop = State(initialValue: crop)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                GeometryReader { proxy in
                    let live = crop.zoomed(to: crop.zoom * pinch)
                        .panned(by: drag, previewWidth: proxy.size.width, imageSize: image.size)
                    Image(uiImage: PostcardEditor.frame(image, crop: live, outputWidth: 700))
                        .resizable().scaledToFit()
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.8), lineWidth: 1))
                        .overlay(alignment: .topTrailing) { Stamp().scaleEffect(0.7).opacity(0.85).padding(8) }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .updating($drag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    crop = crop.panned(by: value.translation, previewWidth: proxy.size.width, imageSize: image.size)
                                }
                                .simultaneously(with: MagnifyGesture()
                                    .updating($pinch) { value, state, _ in state = value.magnification }
                                    .onEnded { value in crop = crop.zoomed(to: crop.zoom * value.magnification) })
                        )
                        .accessibilityLabel("Photo framing preview")
                        .accessibilityHint("Drag to move the photo. Pinch to zoom.")
                }
                .aspectRatio(PhotoCrop.frontAspect, contentMode: .fit)
                .padding(9).background(card)
                .shadow(color: ink.opacity(0.14), radius: 16, y: 10)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Zoom").font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Reset framing") { crop = PhotoCrop() }
                            .font(.subheadline).disabled(crop == PhotoCrop())
                    }
                    Slider(value: $crop.zoom, in: 1...PhotoCrop.maxZoom) {
                        Text("Zoom")
                    } minimumValueLabel: {
                        Image(systemName: "minus.magnifyingglass")
                    } maximumValueLabel: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .tint(vermilion)
                }
                Text("Drag the photo to choose what shows on the front.")
                    .font(.footnote).foregroundStyle(ink.opacity(0.65))
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(paper.ignoresSafeArea())
            .foregroundStyle(ink)
            .navigationTitle("Frame your photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(crop); dismiss() }.bold()
                }
            }
        }
    }
}
