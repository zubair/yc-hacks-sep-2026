import Foundation
import Observation
import PostcardCore
import PostcardServices

@MainActor
@Observable
final class SessionCoordinator {
  /// `unavailable` means the session could not be checked (offline or server error). It is not a sign-out:
  /// the stored session is kept and the person can retry.
  enum State: Equatable { case loading, signedOut, signedIn(PostcardProfile), unavailable(String) }

  private(set) var state: State = .loading
  private(set) var isBusy = false
  var errorMessage: String?
  var infoMessage: String?

  private let service: any PostcardService

  init(service: any PostcardService) { self.service = service }

  var profile: PostcardProfile? {
    if case .signedIn(let profile) = state { return profile }
    return nil
  }

  func restore() async {
    do {
      if let profile = try await service.currentProfile() {
        state = .signedIn(profile)
      } else {
        state = .signedOut
      }
    } catch PostcardServiceError.unauthenticated {
      state = .signedOut
    } catch {
      state = .unavailable(UserFacingError.describe(error))
    }
  }

  func retryRestore() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    state = .loading
    await restore()
  }

  func signIn(email: String, password: String) async {
    await perform {
      try await service.signIn(email: email, password: password)
      guard let profile = try await service.currentProfile() else {
        throw PostcardServiceError.unauthenticated
      }
      infoMessage = nil
      state = .signedIn(profile)
    }
  }

  func signUp(email: String, password: String, username: String, displayName: String) async {
    let normalized = username.lowercased()
    guard normalized.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil else {
      errorMessage = "Usernames are 3–30 characters: a–z, 0–9, _"
      return
    }
    await perform {
      try await service.signUp(email: email, password: password, username: normalized, displayName: displayName)
      if let profile = try await service.currentProfile() {
        state = .signedIn(profile)
      } else {
        infoMessage = "Account created. Confirm your email if asked, then sign in."
        state = .signedOut
      }
    }
  }

  func signOut() async {
    await perform {
      try await service.signOut()
      state = .signedOut
    }
  }

  private func perform(_ work: () async throws -> Void) async {
    guard !isBusy else { return }
    isBusy = true
    errorMessage = nil
    defer { isBusy = false }
    do {
      try await work()
    } catch {
      errorMessage = UserFacingError.describe(error)
    }
  }
}

enum UserFacingError {
  static func describe(_ error: Error) -> String {
    switch error {
    case PostcardServiceError.unauthenticated: "Sign in to continue."
    case PostcardServiceError.forbidden: "You don't have access to that."
    case PostcardServiceError.validation(let detail): detail
    case PostcardServiceError.offline: "You're offline. Your postcard is saved; try again when connected."
    case PostcardServiceError.notFound: "Not found."
    case PostcardServiceError.server(let detail): detail
    case let error as LocalizedError: error.errorDescription ?? error.localizedDescription
    default: error.localizedDescription
    }
  }
}
