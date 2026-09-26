import Foundation
import PostcardCore

actor LocalDraftStore {
    private var fileURL: URL
    private var newestRevision: UInt64 = 0

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = directory.appending(path: "Postcard/draft.json")
        }
    }

    func load() throws -> PostcardDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(PostcardDraft.self, from: data)
    }

    func save(_ draft: PostcardDraft, revision: UInt64) throws {
        guard revision >= newestRevision else { return }
        newestRevision = revision
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(draft)
        try data.write(to: fileURL, options: .atomic)
    }
}
