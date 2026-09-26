import SwiftUI
import UIKit
import MessageUI

/// The final, user-confirmed handoff to Messages or another installed app.
struct SendPostcardSheet: View {
    let image: UIImage
    let message: String
    let frontImage: UIImage?
    init(image: UIImage, message: String, frontImage: UIImage? = nil) {
        self.image = image
        self.message = message
        self.frontImage = frontImage
    }
    @Environment(\.dismiss) private var dismiss
    @State private var destination: DeliveryDestination?
    @State private var deliveryStatus: String?
    @State private var openingPostcardURL: URL?

    private let paper = Color(red: 0.97, green: 0.95, blue: 0.89)
    private let ink = Color(red: 0.17, green: 0.20, blue: 0.18)
    private let vermilion = Color(red: 0.77, green: 0.24, blue: 0.16)
    private var messagesAvailable: Bool {
        MFMessageComposeViewController.canSendText()
            && MFMessageComposeViewController.canSendAttachments()
            && MFMessageComposeViewController.isSupportedAttachmentUTI("public.png")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text("POSTCARD / DELIVERY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .padding(12)
                            .background(ink.opacity(0.06), in: Circle())
                    }
                    .accessibilityLabel("Close delivery options")
                }
                VStack(spacing: 8) {
                    Text("A little far away.\nA little closer.")
                        .font(.system(size: 36, weight: .regular, design: .serif))
                        .tracking(-1.1)
                        .multilineTextAlignment(.center)
                    Text("Your postcard is ready to go.")
                        .font(.system(size: 14))
                        .foregroundStyle(ink.opacity(0.65))
                }
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .padding(9)
                    .background(Color.white)
                    .rotationEffect(.degrees(-2))
                    .shadow(color: ink.opacity(0.14), radius: 14, x: 0, y: 9)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                VStack(spacing: 12) {
                    if messagesAvailable {
                        Button {
                            destination = .messages
                        } label: {
                            deliveryLabel("Send with Messages", symbol: "message.fill")
                                .foregroundStyle(paper)
                                .background(vermilion, in: RoundedRectangle(cornerRadius: 14))
                        }
                        Text("Choose a recipient and confirm in Messages.")
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.65))
                    } else {
                        Label("Messages isn’t available on this device.", systemImage: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        destination = .share
                    } label: {
                        deliveryLabel("Share or save postcard", symbol: "square.and.arrow.up")
                            .foregroundStyle(messagesAvailable ? ink : paper)
                            .background(messagesAvailable ? ink.opacity(0.07) : vermilion,
                                        in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button {
                        do {
                            openingPostcardURL = try OpeningPostcardFile.create(frontImage: frontImage ?? image, message: message)
                            destination = .openingPostcard
                        } catch {
                            deliveryStatus = "Couldn’t prepare the opening postcard. You can still share the image."
                        }
                    } label: {
                        deliveryLabel("Share opening postcard", symbol: "envelope.open")
                            .foregroundStyle(ink)
                            .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    }
                    Text("An HTML keepsake they can open in a compatible browser. Messages previews may show a file instead of the animation.")
                        .font(.system(size: 11))
                        .foregroundStyle(ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                    if let deliveryStatus {
                        Text(deliveryStatus)
                            .font(.system(size: 13))
                            .foregroundStyle(ink.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                Text("SOME THINGS DESERVE MORE THAN A TEXT.")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(26)
        }
        .background(paper.ignoresSafeArea())
        .foregroundStyle(ink)
        .presentationDragIndicator(.visible)
        .sheet(item: $destination) { selected in
            switch selected {
            case .messages:
                PostcardMessageComposer(image: image, message: message) { result in
                    switch result {
                    case .sent: deliveryStatus = "Messages reports your postcard was sent."
                    case .cancelled: deliveryStatus = "Not sent. Your postcard is still here."
                    case .failed: deliveryStatus = "Messages couldn’t send this postcard. Please try sharing it."
                    @unknown default: deliveryStatus = "Your postcard is still ready to share."
                    }
                    destination = nil
                }
            case .share:
                PostcardActivitySheet(image: image, message: message) { completed, error in
                    if error != nil {
                        deliveryStatus = "Sharing couldn’t finish. Your postcard is still here."
                    } else if completed {
                        deliveryStatus = "The selected sharing action completed."
                    }
                    destination = nil
                }
            case .openingPostcard:
                if let openingPostcardURL {
                    OpeningPostcardShareSheet(url: openingPostcardURL) { completed, error in
                        if error != nil {
                            deliveryStatus = "Sharing couldn’t finish. Please try again."
                        } else if completed {
                            deliveryStatus = "The opening postcard sharing action completed."
                        }
                        destination = nil
                    }
                }
            }
        }
    }

    private func deliveryLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: 15, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    private enum DeliveryDestination: String, Identifiable {
        case messages, share, openingPostcard
        var id: String { rawValue }
    }
}

private struct PostcardActivitySheet: UIViewControllerRepresentable {
    let image: UIImage
    let message: String
    let completion: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [image, message], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async { completion(completed, error) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct PostcardMessageComposer: UIViewControllerRepresentable {
    let image: UIImage
    let message: String
    let completion: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.body = message
        if let attachment = image.pngData() {
            let added = controller.addAttachmentData(attachment, typeIdentifier: "public.png", filename: "Postcard.png")
            if !added {
                DispatchQueue.main.async { completion(.failed) }
            }
        } else {
            DispatchQueue.main.async { completion(.failed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let completion: (MessageComposeResult) -> Void
        init(completion: @escaping (MessageComposeResult) -> Void) { self.completion = completion }
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            completion(result)
        }
    }
}

/// Self-contained and offline: no remote images, scripts, tracking, or recipient account.
private enum OpeningPostcardFile {
    static func create(frontImage: UIImage, message: String) throws -> URL {
        guard let jpeg = frontImage.jpegData(compressionQuality: 0.88) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let escapedMessage = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
        let html = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="color-scheme" content="light">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>A postcard for you</title>
        <style>
        *{box-sizing:border-box}body{margin:0;background:#f5f1e7;color:#293831;font-family:Georgia,serif;min-height:100vh;padding:32px 18px;text-align:center}
        .brand{font-size:27px;letter-spacing:-1px}.brand span{color:#bd4228}h1{font-weight:400;font-size:clamp(26px,6vw,40px);letter-spacing:-1px;margin:28px 0 9px}
        .subtitle,.foot{font:11px system-ui,sans-serif;letter-spacing:1px;color:#68746a;line-height:1.7}.subtitle{margin-bottom:25px}
        .scene{perspective:1500px;width:min(100%,440px);margin:0 auto 26px}.card{position:relative;width:100%;height:570px;max-height:70vh;min-height:380px;transform-style:preserve-3d;transition:transform 1.15s cubic-bezier(.2,.65,.2,1)}
        .face{position:absolute;inset:0;backface-visibility:hidden;-webkit-backface-visibility:hidden;background:#fffcf4;border:9px solid #fffcf4;box-shadow:0 20px 45px #29383122}
        .front{transform:rotateY(0deg)}.front img{display:block;width:100%;height:100%;object-fit:contain;background:#fffcf4}.back{transform:rotateY(180deg);padding:25px;text-align:left;overflow:auto}
        .back h2{font-size:16px;font-weight:400;letter-spacing:6px;border-bottom:1px solid #29383133;padding-bottom:19px;margin:0 0 24px}.message{white-space:pre-wrap;overflow-wrap:anywhere;font-size:21px;line-height:1.65;font-style:italic;margin:0}.love{font:9px system-ui,sans-serif;letter-spacing:2px;margin-top:28px;color:#a84630}
        #open{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}#open:checked~.scene .card{transform:rotateY(-180deg)}
        .toggle{display:inline-block;cursor:pointer;background:#293831;color:#fffcf4;border-radius:40px;padding:17px 32px;font:14px system-ui,sans-serif;box-shadow:0 4px 10px #29383110}
        #open:focus-visible~.toggle{outline:3px solid #bd4228;outline-offset:5px}.close-label{display:none}#open:checked~.toggle .open-label{display:none}#open:checked~.toggle .close-label{display:inline}.foot{margin:25px auto 0;max-width:390px;font-size:10px}
        @media(prefers-reduced-motion:reduce){.card{transition:none}}@media print{.card{height:auto;max-height:none;transform:none!important}.face{position:relative;transform:none!important;box-shadow:none;backface-visibility:visible}.front img{max-height:450px}.back{margin-top:20px}.toggle,.subtitle{display:none}}
        </style></head><body>
        <div class="brand">postcard<span>.</span></div>
        <h1>Someone thought of you.</h1><div class="subtitle">A LITTLE PIECE OF SOMEWHERE.</div>
        <input type="checkbox" id="open" aria-label="Turn postcard over to read your message">
        <div class="scene"><div class="card">
        <section class="face front" aria-label="Postcard photo"><img src="data:image/jpeg;base64,\(jpeg.base64EncodedString())" alt="A travel postcard sent with love"></section>
        <section class="face back" aria-label="Your postcard message"><h2>POST CARD</h2><p class="message">\(escapedMessage)</p><p class="love">SENT WITH LOVE.</p></section>
        </div></div>
        <label class="toggle" for="open"><span class="open-label">Open your postcard ↗</span><span class="close-label">Back to the photograph ↗</span></label>
        <p class="foot">Keep this little moment. No account needed.<br>If this preview does not turn, open the file in a compatible web browser.</p>
        </body></html>
        """
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpeningPostcards", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("A postcard for you.html")
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private struct OpeningPostcardShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool, Error?) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async { completion(completed, error) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Hands a published HTTPS link to Messages or the share sheet. The upload already
/// succeeded ("Ready to share"); nothing here claims the recipient received it.
struct LinkHandoffSheet: View {
    let url: URL
    let recipient: String
    let shareText: String
    /// Non-nil while the publisher is a fixture, so a test link is never mistaken for a real one.
    let fixtureLabel: String?
    let onImageFallback: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination?
    @State private var status: String?

    private let paper = Color(red: 0.97, green: 0.95, blue: 0.89)
    private let ink = Color(red: 0.17, green: 0.20, blue: 0.18)
    private let vermilion = Color(red: 0.77, green: 0.24, blue: 0.16)
    private var messagesAvailable: Bool { MFMessageComposeViewController.canSendText() }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Text("POSTCARD / READY TO SHARE")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .tracking(2)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.medium))
                            .frame(width: 44, height: 44)
                            .background(ink.opacity(0.06), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(vermilion)
                        .accessibilityHidden(true)
                    Text("Ready to share with \(recipient).")
                        .font(.system(.title, design: .serif))
                        .multilineTextAlignment(.center)
                    Text("Your postcard is online. Send \(recipient) the link. They can open it without an account.")
                        .font(.subheadline).foregroundStyle(ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 6) {
                    Text(url.absoluteString)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity)
                        .background(ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Postcard link")
                        .accessibilityValue(url.absoluteString)
                    if let fixtureLabel {
                        Label(fixtureLabel, systemImage: "wrench.and.screwdriver")
                            .font(.footnote.weight(.semibold)).foregroundStyle(vermilion)
                            .multilineTextAlignment(.center)
                    }
                }
                VStack(spacing: 12) {
                    if messagesAvailable {
                        Button { destination = .messages } label: {
                            label("Send link with Messages", symbol: "message.fill")
                                .foregroundStyle(paper)
                                .background(vermilion, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    Button { destination = .share } label: {
                        label("Share link…", symbol: "square.and.arrow.up")
                            .foregroundStyle(messagesAvailable ? ink : paper)
                            .background(messagesAvailable ? ink.opacity(0.07) : vermilion, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button {
                        UIPasteboard.general.url = url
                        status = "Link copied."
                    } label: {
                        label("Copy link", symbol: "doc.on.doc")
                            .foregroundStyle(ink)
                            .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button("Send as an image instead", action: onImageFallback)
                        .font(.subheadline.weight(.medium)).underline()
                        .frame(minHeight: 44)
                    if let status {
                        Text(status).font(.subheadline).foregroundStyle(ink.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            }
            .padding(24)
        }
        .background(paper.ignoresSafeArea())
        .foregroundStyle(ink)
        .presentationDragIndicator(.visible)
        .sheet(item: $destination) { selected in
            switch selected {
            case .messages:
                LinkMessageComposer(messageBody: shareText) { result in
                    switch result {
                    case .sent: status = "Messages sent your link. Whether it arrives is up to Messages."
                    case .cancelled: status = "Not sent. Your link is still ready to share."
                    case .failed: status = "Messages couldn’t send it. Try Share link or Copy link."
                    @unknown default: status = "Your link is still ready to share."
                    }
                    destination = nil
                }
            case .share:
                LinkActivitySheet(text: shareText) { completed, error in
                    if error != nil { status = "Sharing couldn’t finish. Your link is still ready." }
                    else if completed { status = "Shared. The link is on its way through the app you chose." }
                    else { status = "Not shared. Your link is still ready." }
                    destination = nil
                }
            }
        }
    }

    private func label(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) { Image(systemName: symbol); Text(title) }
            .font(.headline)
            .frame(maxWidth: .infinity).frame(minHeight: 54)
            .contentShape(Rectangle())
    }

    private enum Destination: String, Identifiable {
        case messages, share
        var id: String { rawValue }
    }
}

private struct LinkActivitySheet: UIViewControllerRepresentable {
    let text: String
    let completion: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async { completion(completed, error) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct LinkMessageComposer: UIViewControllerRepresentable {
    let messageBody: String
    let completion: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.body = messageBody
        return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let completion: (MessageComposeResult) -> Void
        init(completion: @escaping (MessageComposeResult) -> Void) { self.completion = completion }
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            completion(result)
        }
    }
}
