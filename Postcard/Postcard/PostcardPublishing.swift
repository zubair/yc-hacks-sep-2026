import Foundation
import Security

// Publishing client for Pranav's proposed v1 contract (Postcard/TEAM_PROMPTS.md):
//   POST /api/postcards   multipart: photo, recipient, sender, message, destination
//                         header:    Idempotency-Key
//                         → 2xx { "id": String, "url": "https://…" }
// A successful publish means the link is ready to share. It never means delivered.
// No backend credentials live in the app; an optional user token can be injected.

struct PublishRequest {
    var photoJPEG: Data
    var recipient: String
    var sender: String
    var message: String
    var destination: String
    var idempotencyKey: String
}

struct PublishedPostcard: Decodable, Equatable {
    let id: String
    let url: URL
}

enum PublishError: Error, Equatable {
    case offline
    case timedOut
    case rejected(status: Int, message: String?)
    case server(status: Int)
    case invalidResponse(String)
    case notConfigured

    var userMessage: String {
        switch self {
        case .offline: return "You’re offline. Your postcard is saved. Try again when you’re connected."
        case .timedOut: return "The connection timed out. Your postcard is saved. Try again."
        case .rejected(_, let message): return message ?? "The postcard service couldn’t accept this postcard."
        case .server: return "The postcard service is having trouble. Your postcard is saved. Try again."
        case .invalidResponse: return "The postcard service sent an unexpected reply. Your postcard is saved."
        case .notConfigured: return "Publishing isn’t set up in this build yet."
        }
    }

    /// Worth offering Retry for. Rejections need the traveler to change something first.
    var isRetryable: Bool {
        switch self {
        case .rejected: return false
        default: return true
        }
    }
}

protocol PostcardPublishing {
    /// Shown in the UI so a fixture link is never mistaken for a real one.
    var label: String? { get }
    func publish(_ request: PublishRequest) async throws -> PublishedPostcard
}

enum PostcardPublisherFactory {
    /// Uses the real service when `PostcardAPIBaseURL` is set in Info.plist (or via
    /// `-PostcardAPIBaseURL https://…` at launch). Otherwise uses the labeled fixture.
    /// Launch with `-PostcardFixtureMode offline|fail|slow` to exercise error paths.
    static func make(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> PostcardPublishing {
        let raw = defaults.string(forKey: "PostcardAPIBaseURL")
            ?? bundle.object(forInfoDictionaryKey: "PostcardAPIBaseURL") as? String
        if let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
           url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" {
            return HTTPPostcardPublisher(baseURL: url)
        }
        let mode = FixturePostcardPublisher.Mode(rawValue: defaults.string(forKey: "PostcardFixtureMode") ?? "") ?? .success
        return FixturePostcardPublisher(mode: mode)
    }
}

struct HTTPPostcardPublisher: PostcardPublishing {
    let baseURL: URL
    var session: URLSession = .shared
    /// A signed-in user's token, if Pranav's backend requires one. Never a service key.
    var authToken: (() async -> String?)? = nil
    var label: String? { nil }

    func publish(_ request: PublishRequest) async throws -> PublishedPostcard {
        let boundary = "postcard-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/postcards"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(request.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        if let token = await authToken?() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body = Self.multipartBody(request, boundary: boundary)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: urlRequest, from: body)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw PublishError.offline
            case .timedOut: throw PublishError.timedOut
            default: throw PublishError.server(status: 0)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw PublishError.invalidResponse("not HTTP") }
        switch http.statusCode {
        case 200...299:
            guard let published = try? JSONDecoder().decode(PublishedPostcard.self, from: data) else {
                throw PublishError.invalidResponse("expected { id, url }")
            }
            guard published.url.scheme == "https" else { throw PublishError.invalidResponse("url must be HTTPS") }
            return published
        case 400...499:
            throw PublishError.rejected(status: http.statusCode, message: Self.errorMessage(in: data))
        default:
            throw PublishError.server(status: http.statusCode)
        }
    }

    static func multipartBody(_ request: PublishRequest, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        for (name, value) in [("recipient", request.recipient), ("sender", request.sender),
                              ("message", request.message), ("destination", request.destination)] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n")
            append("Content-Type: text/plain; charset=utf-8\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"postcard.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(request.photoJPEG)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Accepts `{ "error": { "message" } }`, `{ "error": "…" }` or `{ "message": "…" }`.
    /// The contract only promises "structured errors", so parse leniently.
    static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let error = object["error"] as? String { return error }
        return object["message"] as? String
    }
}

/// FIXTURE ONLY. Stands in for the backend until Pranav's endpoint is live.
/// Links it returns look real but open nothing; the UI labels them as fixtures.
final class FixturePostcardPublisher: PostcardPublishing {
    enum Mode: String { case success, offline, fail, slow }

    let mode: Mode
    private var issued: [String: PublishedPostcard] = [:]
    private let lock = NSLock()

    init(mode: Mode = .success) { self.mode = mode }

    var label: String? { "Test link (fixture). The postcard service isn’t connected yet." }

    func publish(_ request: PublishRequest) async throws -> PublishedPostcard {
        try await Task.sleep(for: .seconds(mode == .slow ? 6 : 1.2))
        switch mode {
        case .offline: throw PublishError.offline
        case .fail: throw PublishError.server(status: 503)
        case .success, .slow: break
        }
        guard !request.photoJPEG.isEmpty else { throw PublishError.rejected(status: 400, message: "Add a photo first.") }
        lock.lock(); defer { lock.unlock() }
        // Same idempotency key → same card, like the real service.
        if let existing = issued[request.idempotencyKey] { return existing }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let card = PublishedPostcard(id: "fixture-\(token.prefix(8))",
                                     url: URL(string: "https://postcard.example/p/\(token)")!)
        issued[request.idempotencyKey] = card
        return card
    }
}
