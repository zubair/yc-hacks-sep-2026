import Foundation
import CoreGraphics

/// The traveler's postcard as saved on this device. It never leaves the phone
/// until the traveler taps Publish.
struct PostcardDraft: Codable, Equatable {
    var recipient = "Grandma"
    var sender = ""
    var message = "Somewhere between the sea and the sky, I thought of you.\n\nThe days are slow here. The coffee is strong. You would love it.\n\nWish you were here,\nM."
    var destination = "Cinque Terre"
    /// Changes whenever a new photo is chosen, so the publish fingerprint notices photo swaps.
    var photoRevision: String?
    var crop = PhotoCrop()

    /// Reused on every retry of the same content so the backend can collapse duplicates.
    var idempotencyKey: String?
    var idempotencyFingerprint: String?
    /// The last successful publish. It only counts while the fingerprint still matches.
    var publishedURL: URL?
    var publishedFingerprint: String?

    static let messageLimit = 5_000

    /// A stable digest of everything the recipient will see.
    var contentFingerprint: String {
        let parts = [recipient, sender, message, destination, photoRevision ?? "bundled-coast",
                     String(format: "%.3f|%.3f|%.3f", crop.zoom, crop.offsetX, crop.offsetY)]
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in parts.joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// The published link for the content as it is now, or nil once anything was edited.
    var currentPublishedURL: URL? {
        publishedFingerprint == contentFingerprint ? publishedURL : nil
    }

    /// Same content → same key (safe retries). Edited content → a fresh key.
    mutating func keyForPublishing() -> String {
        let fingerprint = contentFingerprint
        if let idempotencyKey, idempotencyFingerprint == fingerprint { return idempotencyKey }
        let key = UUID().uuidString
        idempotencyKey = key
        idempotencyFingerprint = fingerprint
        return key
    }

    var validationProblem: String? {
        if recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add who this postcard is for." }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Write a few words first." }
        if message.count > Self.messageLimit { return "Messages can be up to \(Self.messageLimit) characters." }
        return nil
    }
}

/// How the traveler framed their photo inside the postcard window.
/// `zoom` ≥ 1; offsets run from -1 (left/top edge) to 1 (right/bottom edge).
struct PhotoCrop: Codable, Equatable {
    var zoom: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0

    static let maxZoom = 3.0
    /// Width ÷ height of the photo window on the postcard front.
    static let frontAspect = 0.92

    /// The rectangle of the source image (in points) that fills the postcard window.
    func cropRect(imageSize: CGSize, aspect: Double = PhotoCrop.frontAspect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        var base = imageSize
        if imageSize.width / imageSize.height > aspect {
            base.width = imageSize.height * aspect
        } else {
            base.height = imageSize.width / aspect
        }
        let z = min(max(zoom, 1), Self.maxZoom)
        let size = CGSize(width: base.width / z, height: base.height / z)
        let maxDX = (imageSize.width - size.width) / 2
        let maxDY = (imageSize.height - size.height) / 2
        let center = CGPoint(x: imageSize.width / 2 + clamp(offsetX) * maxDX,
                             y: imageSize.height / 2 + clamp(offsetY) * maxDY)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Moves the framing so the photo follows the finger: a drag of `translation`
    /// points across a preview `previewWidth` points wide.
    func panned(by translation: CGSize, previewWidth: CGFloat, imageSize: CGSize) -> PhotoCrop {
        let rect = cropRect(imageSize: imageSize)
        guard previewWidth > 0, rect.width > 0 else { return self }
        let pixelsPerPoint = rect.width / previewWidth
        let maxDX = (imageSize.width - rect.width) / 2
        let maxDY = (imageSize.height - rect.height) / 2
        var next = self
        if maxDX > 0.5 { next.offsetX = clamp(offsetX - Double(translation.width * pixelsPerPoint / maxDX)) }
        if maxDY > 0.5 { next.offsetY = clamp(offsetY - Double(translation.height * pixelsPerPoint / maxDY)) }
        return next
    }

    func zoomed(to value: Double) -> PhotoCrop {
        var next = self
        next.zoom = min(max(value, 1), Self.maxZoom)
        return next
    }

    private func clamp(_ value: Double) -> Double { min(max(value, -1), 1) }
}

/// Saves the draft and the chosen photo in Application Support, so both survive relaunches.
struct DraftStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("PostcardDraft", isDirectory: true)
        }
    }

    private var draftURL: URL { directory.appendingPathComponent("draft.json") }
    private var photoURL: URL { directory.appendingPathComponent("photo.jpg") }

    func loadDraft() -> PostcardDraft? {
        guard let data = try? Data(contentsOf: draftURL) else { return nil }
        return try? JSONDecoder().decode(PostcardDraft.self, from: data)
    }

    func loadPhotoData() -> Data? { try? Data(contentsOf: photoURL) }

    func save(_ draft: PostcardDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: draftURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func savePhoto(_ data: Data?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data {
            try data.write(to: photoURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else if FileManager.default.fileExists(atPath: photoURL.path) {
            try FileManager.default.removeItem(at: photoURL)
        }
    }
}
