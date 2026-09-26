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
    return AppEnvironment(mode: .fixture, service: fixture, demo: fixture, draftStore: draftStore, haptics: SystemHaptics(), defaultPhoto: samplePhoto)
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
    guard let demo, !compose.isSending else { return }
    await demo.switchDemoUser()
    await session.restore()
    compose.startNewDraft()
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
