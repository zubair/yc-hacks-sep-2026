import Foundation
import Observation
import UIKit
import PostcardCore
import PostcardServices

/// Composition root. Picks fixture or Supabase mode from configuration and owns the long-lived objects.
@MainActor
@Observable
final class AppEnvironment {
  enum Mode: Equatable { case fixture, supabase }

  let mode: Mode
  let service: any PostcardService
  /// Set only in fixture mode: the same object as `service`, for demo-only controls.
  let demo: FixturePostcardService?
  let session: SessionCoordinator
  let presentation: PostcardPresentationController
  let compose: ComposeViewModel
  let inbox: InboxViewModel
  let haptics: any HapticsPlaying
  private(set) var isDemoOffline = false
  private var lastAccountId: UUID?

  init(mode: Mode, service: any PostcardService, demo: FixturePostcardService? = nil, draftStore: any DraftStoring, haptics: any HapticsPlaying, defaultPhoto: Data? = nil) {
    self.mode = mode
    self.service = service
    self.demo = demo
    self.haptics = haptics
    session = SessionCoordinator(service: service)
    presentation = PostcardPresentationController(haptics: haptics)
    compose = ComposeViewModel(service: service, presentation: presentation, draftStore: draftStore, session: session, defaultPhoto: defaultPhoto)
    inbox = InboxViewModel(service: service)
  }

  static func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
    let configuration = AppConfiguration.fromBundle()
    let draftStore = FileDraftStore.default
    // UI tests and demos can start clean; `-forceDemo` guarantees fixture mode so tests never reach a backend.
    if arguments.contains("-resetDemo") { draftStore.clear() }
    if !arguments.contains("-forceDemo"), let url = configuration.supabaseURL, let key = configuration.publishableKey {
      return AppEnvironment(mode: .supabase, service: SupabasePostcardService(url: url, publishableKey: key), draftStore: draftStore, haptics: SystemHaptics())
    }
    // Demo mode skips the sign-in screen: the fixture session starts as Alex so the Duo flow is one tap away.
    // Live mode (Local.xcconfig present) still goes through PostcardAuthView.
    let fixture = FixturePostcardService(signedIn: true)
    let samplePhoto = UIImage(named: "DemoPhoto")?.jpegData(compressionQuality: 0.85)
    let environment = AppEnvironment(mode: .fixture, service: fixture, demo: fixture, draftStore: draftStore, haptics: SystemHaptics(), defaultPhoto: samplePhoto)
    // Skip the seed under UI tests (`-resetDemo`): they address the postcard themselves.
    if !arguments.contains("-resetDemo") {
      environment.compose.seedDemoDraftIfEmpty(recipient: FixturePostcardService.recipient, destination: "Cinque Terre")
    }
    return environment
  }

  // MARK: Demo-only controls (fixture mode). Clearly simulated; never available in live mode.

  /// The other demo account, so one device can show both sides of the exchange.
  var demoPeerName: String? {
    guard demo != nil, let profile = session.profile else { return nil }
    return profile.id == FixturePostcardService.sender.id
      ? FixturePostcardService.recipient.displayName
      : FixturePostcardService.sender.displayName
  }

  func switchDemoAccount() async {
    // Offline, the restore would fail and strand the demo on the "can't connect" screen.
    guard let demo, !compose.isSending, !isDemoOffline else { return }
    await demo.switchDemoUser()
    await session.restore()
  }

  /// On sign-out or a switch to a different account (including the demo switch), nothing from the previous
  /// account (conversations, message previews, or the unsent draft) may remain visible or sendable.
  /// `.loading` and `.unavailable` are not account changes: an offline relaunch keeps the draft.
  func sessionChanged(to state: SessionCoordinator.State) {
    switch state {
    case .signedIn(let profile):
      if let previous = lastAccountId, previous != profile.id { clearAccountData() }
      lastAccountId = profile.id
    case .signedOut:
      if lastAccountId != nil { clearAccountData() }
      lastAccountId = nil
    case .loading, .unavailable:
      break
    }
  }

  private func clearAccountData() {
    inbox.reset()
    compose.discardDraft()
  }

  func failNextDemoSend() async {
    await demo?.failOneSend()
  }

  func setDemoOffline(_ offline: Bool) async {
    guard let demo else { return }
    await demo.setOffline(offline)
    isDemoOffline = offline
    await inbox.load()
  }
}
