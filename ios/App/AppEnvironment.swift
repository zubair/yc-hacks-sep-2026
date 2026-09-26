import Foundation
import Observation
import PostcardCore
import PostcardServices

/// Composition root. Picks fixture or Supabase mode from configuration and owns the long-lived objects.
@MainActor
@Observable
final class AppEnvironment {
  enum Mode: Equatable { case fixture, supabase }

  let mode: Mode
  let service: any PostcardService
  let session: SessionCoordinator
  let presentation: PostcardPresentationController
  let compose: ComposeViewModel
  let inbox: InboxViewModel
  let haptics: any HapticsPlaying

  init(mode: Mode, service: any PostcardService, draftStore: any DraftStoring, haptics: any HapticsPlaying) {
    self.mode = mode
    self.service = service
    self.haptics = haptics
    session = SessionCoordinator(service: service)
    presentation = PostcardPresentationController(haptics: haptics)
    compose = ComposeViewModel(service: service, presentation: presentation, draftStore: draftStore, session: session)
    inbox = InboxViewModel(service: service)
  }

  static func bootstrap() -> AppEnvironment {
    let configuration = AppConfiguration.fromBundle()
    let draftStore = FileDraftStore.default
    if let url = configuration.supabaseURL, let key = configuration.publishableKey {
      return AppEnvironment(mode: .supabase, service: SupabasePostcardService(url: url, publishableKey: key), draftStore: draftStore, haptics: SystemHaptics())
    }
    // Demo mode skips the sign-in screen: the fixture session starts as Alice so the Duo flow is one tap away.
    // Live mode (Local.xcconfig present) still goes through PostcardAuthView.
    let fixture = FixturePostcardService(scenario: .standard, signedInAs: FixturePostcardService.alice)
    return AppEnvironment(mode: .fixture, service: fixture, draftStore: draftStore, haptics: SystemHaptics())
  }
}
