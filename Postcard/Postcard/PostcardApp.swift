import SwiftUI
import UIKit
import PhotosUI

private let paper = Color(red: 0.96, green: 0.945, blue: 0.91)
private let ink = Color(red: 0.16, green: 0.22, blue: 0.20)
private let vermilion = Color(red: 0.79, green: 0.23, blue: 0.14)

@main
struct PostcardApp: App {
    var body: some Scene { WindowGroup { PostcardHome() } }
}

struct PostcardHome: View {
    @State private var opened = false
    @State private var sealed = false
    @State private var showSend = false
    @State private var exportImage: UIImage?
    @AppStorage("postcard.message") private var message = "Somewhere between the sea and the sky, I thought of you.\n\nThe days are slow here. The coffee is strong. You would love it.\n\nWish you were here,\nM."
    @AppStorage("postcard.recipient") private var recipient = "Grandma"
    @AppStorage("postcard.destination") private var destination = "Cinque Terre"
    @State private var photoSelection: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var photoError = false
    @State private var frontImage: UIImage?
    @State private var demoRunning = false
    @State private var hasOpened = false

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
                    }.foregroundStyle(ink.opacity(0.55)).padding(.top, 4)
                    Spacer(minLength: 0)
                    Group {
                        if opened {
                            PostcardBack(message: $message, recipient: $recipient, wide: wide, destination: destination)
                                .disabled(demoRunning)
                                .transition(.modifier(active: CardTurn(angle: -85), identity: CardTurn(angle: 0)).combined(with: .opacity))
                        } else {
                            PostcardFront(sealed: sealed, photo: selectedImage, destination: destination)
                                .rotationEffect(.degrees(sealed ? 0 : -2))
                                .transition(.modifier(active: CardTurn(angle: 85), identity: CardTurn(angle: 0)).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: opened && wide ? 950 : 380)
                    .shadow(color: ink.opacity(0.12), radius: 24, x: 0, y: 15)
                    .padding(.horizontal, wide ? 30 : 7)
                    Spacer(minLength: 0)
                    VStack(spacing: 9) {
                        Text(sealed ? "Ready to make their day." : opened ? "Distance, in your own words." : "Wish you were here.")
                            .font(.system(size: wide ? 32 : 29, weight: .regular, design: .serif))
                        Text(sealed ? "Your postcard is sealed. Choose how it travels." : opened ? "Close your postcard to seal it with love." : "Open a postcard. Leave a little of yourself.")
                            .font(.system(size: 12)).foregroundStyle(ink.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                    if !opened && !sealed {
                        PhotosPicker(selection: $photoSelection, matching: .images) {
                            Label("Use your travel photo", systemImage: "photo")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.7))
                        }.disabled(demoRunning)
                    }
                    controls.disabled(demoRunning)
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill").font(.system(size: 8))
                        TextField("Your destination", text: $destination).tracking(2)
                            .multilineTextAlignment(.center).frame(maxWidth: 210)
                    }.font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(ink.opacity(0.6))
                        .padding(.bottom, 5)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, wide ? 32 : 23)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(minHeight: max(geometry.size.height - 18, 0))
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .onAppear {
                if wide { opened = true; hasOpened = true }
            }
            .onHingeChange { oldContext, newContext in
                guard !demoRunning, let hinge = newContext.hinge else { return }
                if hinge.status == .closed {
                    if hasOpened && opened { seal() }
                } else if hinge.status == .fullyOpen || hinge.status == .partiallyOpen {
                    if oldContext.hinge?.status == .closed || !hasOpened {
                        hasOpened = true
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { opened = true; sealed = false }
                    }
                }
            }
        }
        .task(id: photoSelection) {
            guard let photoSelection else { return }
            do {
                if let data = try await photoSelection.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    selectedImage = image
                    sealed = false
                } else { photoError = true }
            } catch { photoError = true }
        }
        .alert("Couldn't open that photo", isPresented: $photoError) {
            Button("OK", role: .cancel) { }
        } message: { Text("Choose another photo from your library.") }
        .sheet(isPresented: $showSend) {
            if let exportImage { SendPostcardSheet(image: exportImage, message: message, frontImage: frontImage) }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Image(systemName: "envelope.open").font(.system(size: 20, weight: .light))
                Text("postcard").font(.system(size: 30, weight: .regular, design: .serif)).tracking(-1.5)
                Circle().fill(vermilion).frame(width: 5, height: 5).offset(x: -4, y: 7)
            }
            Spacer()
            Button { runDemo() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 8))
                    Text(demoRunning ? "PLAYING" : "PLAY DEMO").font(.system(size: 8, weight: .semibold)).tracking(1.4)
                }.padding(.horizontal, 12).padding(.vertical, 11)
                    .overlay(Capsule().stroke(ink.opacity(0.2), lineWidth: 0.7))
            }.disabled(demoRunning)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if sealed {
                Button { withAnimation(.spring(response: 0.65)) { sealed = false; opened = true } } label: {
                    Image(systemName: "pencil").frame(width: 49, height: 49)
                        .overlay(Circle().stroke(ink.opacity(0.2), lineWidth: 1))
                }
            }
            Button {
                if sealed { prepareSend() }
                else if opened { seal() }
                else { hasOpened = true; UIImpactFeedbackGenerator(style: .soft).impactOccurred(); withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) { opened = true } }
            } label: {
                HStack(spacing: 12) {
                    Text(sealed ? "Send your postcard" : opened ? "Close & seal" : "Open your postcard")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: sealed ? "arrow.up.right" : opened ? "envelope.badge" : "arrow.right").font(.system(size: 12))
                }.frame(maxWidth: .infinity).frame(height: 51)
                    .background(sealed ? vermilion : ink).foregroundStyle(paper).clipShape(Capsule())
            }
        }.frame(maxWidth: 365).padding(.top, 7).padding(.bottom, 10)
    }

    private func seal() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.spring(response: 0.75, dampingFraction: 0.75)) { opened = false; sealed = true }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    @MainActor private func prepareSend() {
        let renderer = ImageRenderer(content: ExportPostcard(message: message, recipient: recipient, photo: selectedImage, destination: destination).frame(width: 1000))
        renderer.scale = 2
        exportImage = renderer.uiImage
        let frontRenderer = ImageRenderer(content: PostcardFront(sealed: true, photo: selectedImage, destination: destination).frame(width: 460))
        frontRenderer.scale = 2
        frontImage = frontRenderer.uiImage
        showSend = exportImage != nil
    }

    private func runDemo() {
        demoRunning = true
        withAnimation { opened = false; sealed = false }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { opened = true }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            try? await Task.sleep(for: .seconds(3))
            seal()
            demoRunning = false
        }
    }
}

private struct CardTurn: ViewModifier {
    var angle: Double
    func body(content: Content) -> some View {
        content.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
    }
}

struct PostcardFront: View {
    var sealed = false
    var photo: UIImage? = nil
    var destination = "Cinque Terre"
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                (photo.map { Image(uiImage: $0) } ?? Image("Coast")).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.53)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    Text("GREETINGS FROM").font(.system(size: 9, weight: .medium)).tracking(3.5)
                    Text(destination.isEmpty ? "Somewhere\nbeautiful." : destination + ".").font(.system(size: 53, weight: .regular, design: .serif)).tracking(-2).lineSpacing(-6).fixedSize(horizontal: false, vertical: true)
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
            .aspectRatio(0.92, contentMode: .fit)
            HStack {
                Text("VIA AIR MAIL").font(.system(size: 9, weight: .semibold)).tracking(3)
                Spacer()
                Text("A MOMENT, MAILED.").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(1.5)
            }.foregroundStyle(ink.opacity(0.7)).padding(.horizontal, 15).padding(.vertical, 16)
        }
        .padding(9).background(Color(red: 0.995, green: 0.985, blue: 0.956))
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
        }.frame(width: 58, height: 72)
    }
}

struct PostcardBack: View {
    @Binding var message: String
    @Binding var recipient: String
    var wide: Bool
    var destination = "Cinque Terre"
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("POST CARD").font(.system(size: 15, weight: .regular, design: .serif)).tracking(5)
                Spacer()
                Text("№ 001").font(.system(size: 9, design: .monospaced)).foregroundStyle(ink.opacity(0.4))
            }
            Rectangle().fill(ink.opacity(0.14)).frame(height: 0.5)
            if wide {
                HStack(alignment: .top, spacing: 28) {
                    note.frame(maxWidth: .infinity)
                    Rectangle().fill(ink.opacity(0.13)).frame(width: 0.7)
                    address.frame(maxWidth: .infinity)
                }.frame(height: 280)
            } else {
                note.frame(height: 220)
                Rectangle().fill(ink.opacity(0.14)).frame(height: 0.5)
                address
            }
            HStack {
                Image(systemName: "heart").font(.system(size: 9))
                Text("SENT SLOWLY. FELT DEEPLY.").font(.system(size: 7, design: .monospaced)).tracking(1.5)
                Spacer()
            }.foregroundStyle(ink.opacity(0.35))
        }.padding(wide ? 32 : 23)
            .background(Color(red: 0.995, green: 0.985, blue: 0.956))
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR WORDS").font(.system(size: 7, weight: .medium)).tracking(2).foregroundStyle(ink.opacity(0.35))
            TextEditor(text: $message)
                .font(.custom("Georgia-Italic", size: wide ? 23 : 18))
                .lineSpacing(5).scrollContentBackground(.hidden)
                .foregroundStyle(ink).tint(vermilion).padding(.leading, -5)
        }
    }

    private var address: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DELIVER TO").font(.system(size: 7, weight: .semibold)).tracking(2).foregroundStyle(ink.opacity(0.4))
                    TextField("Someone you miss", text: $recipient).font(.system(size: 20, design: .serif)).tint(vermilion)
                }
                Spacer()
                Stamp().rotationEffect(.degrees(5))
            }
            Rectangle().fill(ink.opacity(0.15)).frame(height: 0.6)
            Text("From \(destination), with love.").font(.custom("Georgia-Italic", size: 12)).foregroundStyle(ink.opacity(0.6))
            if wide { Spacer(); Image(systemName: "sun.horizon").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(vermilion.opacity(0.5)) }
        }
    }
}

struct ExportPostcard: View {
    let message: String
    let recipient: String
    var photo: UIImage? = nil
    var destination = "Cinque Terre"
    var body: some View {
        HStack(spacing: 0) {
            PostcardFront(sealed: true, photo: photo, destination: destination).frame(width: 460)
            VStack(alignment: .leading, spacing: 25) {
                Text("POST CARD").font(.system(size: 19, design: .serif)).tracking(6)
                Rectangle().fill(ink.opacity(0.2)).frame(height: 1)
                Text("Dear \(recipient),").font(.custom("Georgia-Italic", size: 22))
                Text(message).font(.custom("Georgia-Italic", size: 24)).lineSpacing(10)
                Spacer()
                Text("FROM \(destination.uppercased()), WITH LOVE.").font(.system(size: 10, design: .monospaced)).tracking(2)
            }.padding(35).frame(maxWidth: .infinity)
        }.foregroundStyle(ink).frame(height: 580).background(paper)
    }
}
