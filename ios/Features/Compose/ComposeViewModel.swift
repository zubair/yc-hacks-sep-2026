import Foundation
import Observation
import PhotosUI
import SwiftUI
import PostcardCore
import PostcardServices

/// Compose state: draft persistence, recipient lookup, photo import, and the only send path.
@MainActor
@Observable
final class ComposeViewModel {
  var draft: PostcardDraft {
    didSet { if draft != oldValue { scheduleSave() } }
  }
  private(set) var lookupResult: PostcardProfile?
  private(set) var isLookingUp = false
  /// Lookup feedback (no match, lookup failure). Kept apart from `errorMessage`, whose retry action re-sends.
  private(set) var lookupMessage: String?
  private(set) var isSending = false
  private(set) var lastSent: PostcardMessage?
  var errorMessage: String?
  /// True only when `errorMessage` describes a failed `service.send`. The composer's "Try again" re-sends only
  /// then; for photo or validation problems it just dismisses the message.
  private(set) var canRetrySend = false

  private let service: any PostcardService
  private let presentation: PostcardPresentationController
  private let draftStore: any DraftStoring
  private let session: SessionCoordinator
  private let photoImporter = PhotoImporter()
  /// Demo mode only: a bundled sample photo so the fixture flow needs no photo library.
  private let defaultPhoto: Data?
  private var saveTask: Task<Void, Never>?
  /// Draft ids that have already been confirmed sent, to guarantee one send per submission even across quick taps.
  private var sentDraftIds: Set<UUID> = []

  init(service: any PostcardService, presentation: PostcardPresentationController, draftStore: any DraftStoring, session: SessionCoordinator, defaultPhoto: Data? = nil) {
    self.service = service
    self.presentation = presentation
    self.draftStore = draftStore
    self.session = session
    self.defaultPhoto = defaultPhoto
    draft = draftStore.load() ?? PostcardDraft(photoData: defaultPhoto)
  }

  var canSend: Bool {
    guard !isSending, presentation.state == .writing || presentation.state == .sealed else { return false }
    // An empty signature is filled from the profile at send time, exactly as `send()` does. The demo seed runs
    // before the session loads, so without this Continue would stay disabled on the seeded draft.
    var candidate = draft
    if candidate.senderName.isEmpty { candidate.senderName = session.profile?.displayName ?? "" }
    return !candidate.senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (try? PostcardValidation.validate(candidate)) != nil
  }

  // MARK: Draft lifecycle

  func startNewDraft(recipient: PostcardProfile? = nil) {
    guard !isSending else { return }
    draft = PostcardDraft(recipientId: recipient?.id, recipientName: recipient?.displayName ?? "", senderName: session.profile?.displayName ?? "", photoData: defaultPhoto)
    lookupResult = recipient
    lookupMessage = nil
    errorMessage = nil
    canRetrySend = false
    lastSent = nil
    presentation.resetForNewDraft()
  }

  /// Entry point for "Write" and "Reply". Keeps an unsent draft the person has started (it is persisted
  /// work); starts fresh after a confirmed send or when the current draft is still blank.
  func prepareDraft(recipient: PostcardProfile? = nil) {
    guard !isSending else { return }
    let justSent = presentation.state == .sent || sentDraftIds.contains(draft.id)
    if justSent || !hasUserContent {
      startNewDraft(recipient: recipient)
    } else if let recipient, draft.recipientId != recipient.id, presentation.state != .sealed {
      select(recipient: recipient)
      lookupResult = recipient
    }
  }

  private var hasUserContent: Bool {
    !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !draft.destination.isEmpty
      || (draft.photoData != nil && draft.photoData != defaultPhoto)
  }

  /// Demo only: give a blank first draft a recipient and a place so the fold story starts immediately.
  /// The demo photo is already the default; message stays empty so the person writes it.
  func seedDemoDraftIfEmpty(recipient: PostcardProfile, destination: String) {
    guard draft.message.isEmpty, draft.recipientId == nil, draft.destination.isEmpty else { return }
    draft.recipientId = recipient.id
    draft.recipientName = recipient.displayName
    draft.destination = destination
    if draft.senderName.isEmpty { draft.senderName = session.profile?.displayName ?? "" }
    lookupResult = nil
  }

  func discardDraft() {
    guard !isSending else { return }
    saveTask?.cancel()
    draftStore.clear()
    startNewDraft()
  }

  /// A confirmed-sent draft is never written back: after relaunch it would otherwise return with its old id.
  private var isPersistable: Bool { !sentDraftIds.contains(draft.id) && presentation.state != .sent }

  func persistNow() {
    saveTask?.cancel()
    guard isPersistable else { return }
    draftStore.save(draft)
  }

  private func scheduleSave() {
    saveTask?.cancel()
    guard isPersistable else { return }
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
    lookupMessage = nil
    defer { isLookingUp = false }
    do {
      lookupResult = try await service.lookupRecipient(username: trimmed)
      if lookupResult == nil { lookupMessage = "No one with the username “\(trimmed.lowercased())”." }
    } catch {
      lookupResult = nil
      lookupMessage = UserFacingError.describe(error)
    }
  }

  func select(recipient: PostcardProfile) {
    draft.recipientId = recipient.id
    draft.recipientName = recipient.displayName
    if draft.senderName.isEmpty { draft.senderName = session.profile?.displayName ?? "" }
    lookupMessage = nil
    errorMessage = nil
  }

  // MARK: Photo

  func importPhoto(from item: PhotosPickerItem) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoImportError.unreadable }
      setPhoto(try photoImporter.makeJPEG(from: data))
    } catch {
      errorMessage = UserFacingError.describe(error)
      canRetrySend = false
    }
  }

  /// A new photo gets a new idempotency key. An earlier attempt may already have uploaded the old photo under
  /// the old draft id, and a retry with that id would reuse the old upload instead of this photo.
  func setPhoto(_ jpeg: Data) {
    guard !isSending, jpeg != draft.photoData else { return }
    draft.photoData = jpeg
    draft.id = UUID()
    errorMessage = nil
    canRetrySend = false
  }

  func dismissError() {
    errorMessage = nil
    canRetrySend = false
  }

  /// The composer's "Try again": re-send only after a failed send, otherwise just clear the message.
  func retry() async {
    if canRetrySend { await send() } else { dismissError() }
  }

  // MARK: Send — the only path that publishes

  func send() async {
    guard !isSending else { return }
    guard !sentDraftIds.contains(draft.id) else { return }
    guard draft.recipientId != nil else { return fail("Choose a recipient by username.") }
    guard draft.photoData != nil else { return fail("Add a photo to the front of your postcard.") }
    guard !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Write something on the back first.") }
    if draft.senderName.isEmpty { draft.senderName = session.profile?.displayName ?? "" }
    guard !draft.senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("Add your name to sign the postcard.") }
    do { try PostcardValidation.validate(draft) } catch { return fail(UserFacingError.describe(error)) }
    guard presentation.beginSending() else { return fail("Open your postcard before sending.") }
    let submission = draft
    isSending = true
    errorMessage = nil
    canRetrySend = false
    persistNow()
    defer { isSending = false }
    do {
      let message = try await service.send(draft: submission)
      sentDraftIds.insert(submission.id)
      lastSent = message
      saveTask?.cancel()
      presentation.sendSucceeded()
      draftStore.clear()
    } catch {
      presentation.sendFailed()
      errorMessage = UserFacingError.describe(error)
      canRetrySend = true
    }
  }

  private func fail(_ message: String) {
    errorMessage = message
    canRetrySend = false
  }
}
