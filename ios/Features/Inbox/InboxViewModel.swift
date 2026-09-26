import Foundation
import Observation
import PostcardCore

@MainActor
@Observable
final class InboxViewModel {
  private(set) var conversations: [PostcardConversation] = []
  private(set) var isLoading = false
  var errorMessage: String?

  private let service: any PostcardService

  init(service: any PostcardService) { self.service = service }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      conversations = try await service.conversations()
      errorMessage = nil
    } catch {
      errorMessage = UserFacingError.describe(error)
    }
  }

  /// Runs until the calling task is cancelled. Each event means "refetch"; reconnects refetch too.
  func observeUpdates() async {
    while !Task.isCancelled {
      do {
        let stream = try await service.conversationUpdates()
        for try await _ in stream {
          await load()
        }
      } catch {
        if Task.isCancelled { return }
      }
      // Dropped stream: back off, then reconnect and refetch so nothing is lost.
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { await load() }
    }
  }
}
