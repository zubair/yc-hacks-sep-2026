import Foundation
import Observation
import PostcardCore

@MainActor
@Observable
final class ConversationViewModel {
  private(set) var messages: [PostcardMessage] = []
  private(set) var photoURLs: [UUID: URL] = [:]
  private(set) var isLoading = false
  var errorMessage: String?

  private let service: any PostcardService
  private let conversationId: UUID

  init(service: any PostcardService, conversationId: UUID) {
    self.service = service
    self.conversationId = conversationId
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let page = try await service.messages(conversationId: conversationId, before: nil, limit: 50)
      merge(page)
      errorMessage = nil
      await resolvePhotos()
    } catch {
      errorMessage = UserFacingError.describe(error)
    }
  }

  func observeUpdates() async {
    while !Task.isCancelled {
      do {
        let stream = try await service.conversationUpdates()
        for try await id in stream where id == conversationId {
          await load()
        }
      } catch {
        if Task.isCancelled { return }
      }
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { await load() }
    }
  }

  /// Merge by UUID so duplicate realtime events never duplicate rows.
  private func merge(_ incoming: [PostcardMessage]) {
    var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    for message in incoming { byId[message.id] = message }
    messages = byId.values.sorted { $0.createdAt > $1.createdAt }
  }

  /// Signed URLs expire (≤ 5 min), so re-resolve on every load rather than caching forever.
  private func resolvePhotos() async {
    for message in messages {
      if let url = try? await service.photoURL(path: message.photoPath) {
        photoURLs[message.id] = url
      }
    }
  }
}
