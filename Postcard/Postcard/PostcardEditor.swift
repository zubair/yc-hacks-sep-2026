import SwiftUI
import UIKit
import Observation

/// Owns the draft, the traveler's photo, and publishing. Views bind to this;
/// fold state lives in the Duo interaction controller, not here.
@MainActor @Observable
final class PostcardEditor {
    enum PublishPhase: Equatable {
        case idle
        case publishing
        case ready(URL)
        case failed(PublishError)
    }

    var draft: PostcardDraft { didSet { if draft != oldValue { draftChanged() } } }
    private(set) var photo: UIImage? = nil
    private(set) var framedPhoto: UIImage? = nil
    private(set) var phase: PublishPhase = .idle
    var saveProblem: String? = nil

    @ObservationIgnored let publisher: PostcardPublishing
    @ObservationIgnored private let store: DraftStore
    @ObservationIgnored private var saveTask: Task<Void, Never>? = nil

    init(store: DraftStore = DraftStore(), publisher: PostcardPublishing = PostcardPublisherFactory.make()) {
        self.store = store
        self.publisher = publisher
        if ProcessInfo.processInfo.arguments.contains("-PostcardResetDraft") {
            try? store.save(PostcardDraft())
            try? store.savePhoto(nil)
        }
        draft = store.loadDraft() ?? PostcardDraft()
        if let data = store.loadPhotoData(), let image = UIImage(data: data) {
            photo = image
        } else {
            draft.photoRevision = nil
        }
        refreshFramedPhoto()
        if let url = draft.currentPublishedURL { phase = .ready(url) }
    }

    /// The bundled coast photo stands in until the traveler picks their own.
    var sourcePhoto: UIImage? { photo ?? UIImage(named: "Coast") }
    var isPublishing: Bool { phase == .publishing }

    // MARK: Photo

    func setPhoto(data: Data) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        let normalized = Self.downsample(image, maxDimension: 2400)
        guard let jpeg = normalized.jpegData(compressionQuality: 0.9) else { return false }
        do { try store.savePhoto(jpeg) } catch { saveProblem = "Couldn’t save your photo on this device." }
        photo = normalized
        draft.crop = PhotoCrop()
        draft.photoRevision = UUID().uuidString
        refreshFramedPhoto()
        return true
    }

    func setCrop(_ crop: PhotoCrop) {
        draft.crop = crop
        refreshFramedPhoto()
    }

    private func refreshFramedPhoto() {
        framedPhoto = sourcePhoto.map { Self.frame($0, crop: draft.crop, outputWidth: 1200) }
    }

    /// Renders exactly what the postcard window shows, for display, export and upload.
    static func frame(_ image: UIImage, crop: PhotoCrop, outputWidth: CGFloat) -> UIImage {
        let rect = crop.cropRect(imageSize: image.size)
        guard rect.width > 0 else { return image }
        let output = CGSize(width: outputWidth, height: (outputWidth / PhotoCrop.frontAspect).rounded())
        let scale = output.width / rect.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: output, format: format).image { _ in
            image.draw(in: CGRect(x: -rect.minX * scale, y: -rect.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
    }

    private static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let ratio = min(1, maxDimension / max(longest, 1))
        let size = CGSize(width: (image.size.width * ratio).rounded(), height: (image.size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Redrawing also bakes in EXIF orientation.
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Persistence

    private func draftChanged() {
        // Any edit after a publish means the old link shows old content.
        if case .ready = phase, draft.currentPublishedURL == nil { phase = .idle }
        if case .failed = phase { phase = .idle }
        saveTask?.cancel()
        let snapshot = draft
        let store = store
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do { try store.save(snapshot) } catch { self?.saveProblem = "Couldn’t save your draft on this device." }
        }
    }

    /// Called when the app backgrounds so nothing typed in the last moment is lost.
    func saveNow() {
        saveTask?.cancel()
        do { try store.save(draft) } catch { saveProblem = "Couldn’t save your draft on this device." }
    }

    // MARK: Publishing

    /// Explicit Publish only. Folding and the demo never call this.
    func publish() async {
        guard !isPublishing else { return }
        if let url = draft.currentPublishedURL { phase = .ready(url); return }
        if let problem = draft.validationProblem {
            phase = .failed(.rejected(status: 0, message: problem))
            return
        }
        guard let source = sourcePhoto,
              let jpeg = Self.frame(source, crop: draft.crop, outputWidth: 1600).jpegData(compressionQuality: 0.85) else {
            phase = .failed(.rejected(status: 0, message: "Add a photo first."))
            return
        }
        let key = draft.keyForPublishing()
        let fingerprint = draft.contentFingerprint
        let request = PublishRequest(photoJPEG: jpeg, recipient: draft.recipient, sender: draft.sender,
                                     message: draft.message, destination: draft.destination, idempotencyKey: key)
        phase = .publishing
        saveNow()
        do {
            let published = try await publisher.publish(request)
            // Content edited mid-upload? Keep the draft, drop the stale link.
            guard draft.contentFingerprint == fingerprint else { phase = .idle; return }
            draft.publishedURL = published.url
            draft.publishedFingerprint = fingerprint
            phase = .ready(published.url)
            saveNow()
        } catch let error as PublishError {
            phase = .failed(error)
        } catch {
            phase = .failed(.server(status: 0))
        }
    }

    func shareText(for url: URL) -> String {
        let name = draft.sender.trimmingCharacters(in: .whitespaces)
        let from = name.isEmpty ? "" : " from \(name)"
        return "A postcard for you\(from) from \(draft.destination.isEmpty ? "somewhere beautiful" : draft.destination). Tap to turn it over: \(url.absoluteString)"
    }
}
