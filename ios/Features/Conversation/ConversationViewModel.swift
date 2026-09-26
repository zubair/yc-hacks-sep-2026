import Foundation
import Observation
import PostcardCore
import PostcardServices

@MainActor
@Observable
final class ConversationViewModel {
  private(set) var messages: [PostcardMessage] = []
  private(set) var photoURLs: [UUID: URL] = [:]
  private(set) var photoData: [UUID: Data] = [:]
  private(set) var photoErrors: [UUID: String] = [:]
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
    do {
      let page = try await service.messages(conversationId: conversationId, before: nil, limit: 50)
      merge(page)
      errorMessage = nil
    } catch {
      errorMessage = UserFacingError.describe(error)
    }
    isLoading = false
    await resolveMissingPhotos()
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

  func retryPhoto(id: UUID) async {
    guard let message = messages.first(where: { $0.id == id }) else { return }
    await resolvePhoto(for: message)
  }

  /// Messages and their photos are immutable, so downloaded bytes are kept for the life of the screen. Only photos
  /// without bytes are fetched, each through a freshly signed URL (they expire within 5 minutes).
  private func resolveMissingPhotos() async {
    for message in messages where photoData[message.id] == nil {
      await resolvePhoto(for: message)
    }
  }

  private func resolvePhoto(for message: PostcardMessage) async {
    do {
      let url = try await service.photoURL(path: message.photoPath)
      photoURLs[message.id] = url
      let data: Data
      if url.isFileURL {
        data = try Data(contentsOf: url)
      } else {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (downloaded, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
          throw PostcardServiceError.server("The photograph couldn't be loaded.")
        }
        data = downloaded
      }
      photoData[message.id] = data
      photoErrors[message.id] = nil
    } catch {
      photoURLs[message.id] = nil
      photoErrors[message.id] = UserFacingError.describe(error)
    }
  }
}
