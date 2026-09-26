import Foundation
import Observation
import PhotosUI
import SwiftUI
import PostcardCore

/// Compose state: draft persistence, recipient lookup, photo import, and the only send path.
@MainActor
@Observable
final class ComposeViewModel {
  var draft: PostcardDraft {
    didSet { if draft != oldValue { scheduleSave() } }
  }
  private(set) var lookupResult: PostcardProfile?
  private(set) var isLookingUp = false
  private(set) var isSending = false
  private(set) var lastSent: PostcardMessage?
  var errorMessage: String?

  private let service: any PostcardService
  private let presentation: PostcardPresentationController
  private let draftStore: any DraftStoring
  private let session: SessionCoordinator
  private let photoImporter = PhotoImporter()
  private var saveTask: Task<Void, Never>?
  /// Draft ids that have already been confirmed sent, to guarantee one send per submission even across quick taps.
  private var sentDraftIds: Set<UUID> = []

  init(service: any PostcardService, presentation: PostcardPresentationController, draftStore: any DraftStoring, session: SessionCoordinator) {
    self.service = service
    self.presentation = presentation
    self.draftStore = draftStore
    self.session = session
    draft = draftStore.load() ?? PostcardDraft()
  }

  var canSend: Bool {
    !isSending
      && (presentation.state == .writing || presentation.state == .sealed)
      && draft.recipientId != nil
      && draft.photoData != nil
      && !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // MARK: Draft lifecycle

  func startNewDraft(recipient: PostcardProfile? = nil) {
    guard !isSending else { return }
    draft = PostcardDraft(recipientId: recipient?.id, recipientName: recipient?.displayName ?? "", senderName: session.profile?.displayName ?? "")
    lookupResult = recipient
    errorMessage = nil
    lastSent = nil
    presentation.resetForNewDraft()
  }

  /// Demo only: give the first launch a finished front (photo, place, recipient) so the fold story starts immediately.
  func seedDemoDraftIfEmpty(recipient: PostcardProfile, destination: String, photoData: Data?) {
    guard draft.message.isEmpty, draft.photoData == nil, draft.recipientId == nil else { return }
    draft = PostcardDraft(recipientId: recipient.id, recipientName: recipient.displayName, senderName: session.profile?.displayName ?? "", destination: destination, photoData: photoData)
  }

  func discardDraft() {
    guard !isSending else { return }
    draftStore.clear()
    startNewDraft()
  }

  func persistNow() {
    saveTask?.cancel()
    draftStore.save(draft)
  }

  private func scheduleSave() {
    saveTask?.cancel()
    let snapshot = draft
    saveTask = Task { [draftStore] in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      draftStore.save(snapshot)
    }
  }

  // MARK: Recipient

  func lookup(username: String) async {
    let trimmed = username.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !isLookingUp else { return }
    isLookingUp = true
    errorMessage = nil
    defer { isLookingUp = false }
    do {
      lookupResult = try await service.lookupRecipient(username: trimmed)
      if lookupResult == nil { errorMessage = "No one with the username “\(trimmed.lowercased())”." }
    } catch {
      errorMessage = UserFacingError.describe(error)
    }
  }

  func select(recipient: PostcardProfile) {
    draft.recipientId = recipient.id
    draft.recipientName = recipient.displayName
    if draft.senderName.isEmpty { draft.senderName = session.profile?.displayName ?? "" }
    errorMessage = nil
  }

  // MARK: Photo

  func importPhoto(from item: PhotosPickerItem) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoImportError.unreadable }
      draft.photoData = try photoImporter.makeJPEG(from: data)
      errorMessage = nil
    } catch {
      errorMessage = UserFacingError.describe(error)
    }
  }

  // MARK: Send — the only path that publishes

  func send() async {
    guard !isSending else { return }
    guard !sentDraftIds.contains(draft.id) else { return }
    guard draft.recipientId != nil else { return fail("Choose a recipient by username.") }
    guard draft.photoData != nil else { return fail("Add a photo to the front of your postcard.") }
    guard !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Write something on the back first.") }
    if draft.senderName.isEmpty { draft.senderName = session.profile?.displayName ?? "" }
    guard presentation.beginSending() else { return fail("Open your postcard before sending.") }
    let submission = draft
    isSending = true
    errorMessage = nil
    persistNow()
    defer { isSending = false }
    do {
      let message = try await service.send(draft: submission)
      sentDraftIds.insert(submission.id)
      lastSent = message
      presentation.sendSucceeded()
      draftStore.clear()
    } catch {
      presentation.sendFailed()
      errorMessage = UserFacingError.describe(error)
    }
  }

  private func fail(_ message: String) {
    errorMessage = message
  }
}
