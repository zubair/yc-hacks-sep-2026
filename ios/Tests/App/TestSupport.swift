import Foundation
import PostcardCore
@testable import Postcard

@MainActor
final class SpyHaptics: HapticsPlaying {
  var events: [HapticEvent] = []
  func play(_ event: HapticEvent) { events.append(event) }
}

final class MemoryDraftStore: DraftStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var stored: PostcardDraft?
  var saveCount = 0
  func load() -> PostcardDraft? { lock.withLock { stored } }
  func save(_ draft: PostcardDraft) { lock.withLock { stored = draft; saveCount += 1 } }
  func clear() { lock.withLock { stored = nil } }
}

/// Test-only service: counts sends and can fail on demand. Lives in tests, never in production code.
actor SpyPostcardService: PostcardService {
  var sendCalls: [PostcardDraft] = []
  var failNextSend: PostcardServiceError?
  var profile = PostcardProfile(id: UUID(), username: "tester", displayName: "Tester")
  var recipient = PostcardProfile(id: UUID(), username: "friend", displayName: "Friend")

  func setFailNextSend(_ error: PostcardServiceError?) { failNextSend = error }

  func currentProfile() async throws -> PostcardProfile? { profile }
  func signUp(email: String, password: String, username: String, displayName: String) async throws {}
  func signIn(email: String, password: String) async throws {}
  func signOut() async throws {}
  func lookupRecipient(username: String) async throws -> PostcardProfile? { username == recipient.username ? recipient : nil }
  func conversations() async throws -> [PostcardConversation] { [] }
  func messages(conversationId: UUID, before: Date?, limit: Int) async throws -> [PostcardMessage] { [] }
  func send(draft: PostcardDraft) async throws -> PostcardMessage {
    sendCalls.append(draft)
    if let failNextSend {
      self.failNextSend = nil
      throw failNextSend
    }
    return PostcardMessage(id: UUID(), conversationId: UUID(), senderId: profile.id, recipientId: draft.recipientId ?? UUID(), senderName: draft.senderName, recipientName: draft.recipientName, destination: draft.destination, message: draft.message, photoPath: "p/\(draft.id)/photo.jpg", createdAt: Date())
  }
  func photoURL(path: String) async throws -> URL { URL(fileURLWithPath: "/dev/null") }
  func conversationUpdates() async throws -> AsyncThrowingStream<UUID, Error> { AsyncThrowingStream { $0.finish() } }
}

extension PostcardDraft {
  static func ready(recipient: PostcardProfile) -> PostcardDraft {
    PostcardDraft(recipientId: recipient.id, recipientName: recipient.displayName, senderName: "Tester", destination: "Lisbon", message: "Hello from the hill.", photoData: Data([0xFF, 0xD8, 0xFF]))
  }
}
