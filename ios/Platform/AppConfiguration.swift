import Foundation

/// Reads `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` injected through Config/*.xcconfig → Info.plist.
struct AppConfiguration: Equatable, Sendable {
  var supabaseURL: URL?
  var publishableKey: String?

  var isConfigured: Bool { supabaseURL != nil && publishableKey != nil }

  static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
    let info = bundle.infoDictionary ?? [:]
    return AppConfiguration(rawURL: info["SUPABASE_URL"] as? String, rawKey: info["SUPABASE_PUBLISHABLE_KEY"] as? String)
  }

  init(rawURL: String?, rawKey: String?) {
    let trimmedURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let trimmedKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    supabaseURL = trimmedURL.isEmpty ? nil : URL(string: trimmedURL)
    publishableKey = trimmedKey.isEmpty ? nil : trimmedKey
  }
}
