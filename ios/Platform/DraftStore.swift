import Foundation
import PostcardCore

protocol DraftStoring: AnyObject, Sendable {
  func load() -> PostcardDraft?
  func save(_ draft: PostcardDraft)
  func clear()
}

/// JSON file in Application Support. Photo bytes are stored inline (≤ 10 MB by validation).
final class FileDraftStore: DraftStoring, @unchecked Sendable {
  private let url: URL
  private let queue = DispatchQueue(label: "com.bairisland.postcard.draftstore")

  init(url: URL) { self.url = url }

  static var `default`: FileDraftStore {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent("Postcard", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return FileDraftStore(url: directory.appendingPathComponent("draft.json"))
  }

  func load() -> PostcardDraft? {
    queue.sync {
      guard let data = try? Data(contentsOf: url) else { return nil }
      return try? JSONDecoder().decode(PostcardDraft.self, from: data)
    }
  }

  func save(_ draft: PostcardDraft) {
    queue.sync {
      guard let data = try? JSONEncoder().encode(draft) else { return }
      try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
  }

  func clear() {
    queue.sync { try? FileManager.default.removeItem(at: url) }
  }
}
