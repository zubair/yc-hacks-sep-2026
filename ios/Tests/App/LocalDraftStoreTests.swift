import Foundation
import PostcardCore
import Testing
@testable import Postcard

@Suite("Local draft persistence")
struct LocalDraftStoreTests {
    @Test func relaunchPreservesDraftAndIgnoresStaleWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "draft.json")
        let store = LocalDraftStore(fileURL: url)
        var draft = PostcardDraft()
        draft.message = "See you soon"
        draft.photoData = Data([0xFF, 0xD8, 0xFF])
        try await store.save(draft, revision: 2)

        var stale = draft
        stale.message = "Old text"
        try await store.save(stale, revision: 1)

        let reopened = LocalDraftStore(fileURL: url)
        let loaded = try await reopened.load()
        #expect(loaded == draft)
    }
}
