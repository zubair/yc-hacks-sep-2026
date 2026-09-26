import Foundation
import PostcardServices

struct AppRuntime {
    var service: any PostcardService
    var mode: PostcardRuntimeMode

    static func make(bundle: Bundle = .main) -> AppRuntime {
        let localConfig = bundle.url(forResource: "LocalConfig", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] }
        let urlText = localConfig?["SUPABASE_URL"]
        let key = localConfig?["SUPABASE_PUBLISHABLE_KEY"]
        if let urlText, let key, !key.isEmpty, !key.hasPrefix("YOUR_"),
           let url = URL(string: urlText),
           url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host)) {
            return AppRuntime(
                service: SupabasePostcardService(url: url, publishableKey: key),
                mode: .live
            )
        }
        return AppRuntime(service: FixturePostcardService(), mode: .demo)
    }
}
