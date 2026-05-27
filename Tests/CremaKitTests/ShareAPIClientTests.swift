import Testing
import Foundation
@testable import CremaKit

/// `ShareAPIClient` tests. Uses a `URLProtocol` subclass to intercept all
/// HTTP traffic and serve canned responses — no network, no backend.
///
/// The canned responses mirror the actual JSON shapes documented in
/// `docs/API.md` (verified against a live server run). This is the lock
/// that ensures we won't silently break decoding when the server's
/// response shape evolves without coordination.
@Suite("ShareAPIClient", .serialized)
struct ShareAPIClientTests {

    /// Helper to build a client wired to MockProtocol with a given token.
    private func makeClient(token: String? = nil) -> ShareAPIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockProtocol.self]
        cfg.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: cfg)
        return ShareAPIClient(
            config: .init(baseURL: URL(string: "https://test.local")!),
            session: session,
            sessionTokenProvider: { token }
        )
    }

    // MARK: - sign-in

    @Test("signInWithApple decodes the canonical response shape")
    func signInWithAppleDecodes() async throws {
        MockProtocol.respond(to: "/auth/sign-in-with-apple") { _ in
            (200, """
            {
              "sessionToken": "eyJtest",
              "user": {
                "id": "k7Fp2nLmAB",
                "displayName": "Dave",
                "avatarUrl": null
              }
            }
            """.data(using: .utf8)!)
        }
        let client = makeClient()
        let r = try await client.signInWithApple(identityToken: "fake", displayName: "Dave")
        #expect(r.sessionToken == "eyJtest")
        #expect(r.user.id == "k7Fp2nLmAB")
        #expect(r.user.displayName == "Dave")
        #expect(r.user.avatarUrl == nil)
    }

    @Test("signInWithGoogle decodes the same shape")
    func signInWithGoogleDecodes() async throws {
        MockProtocol.respond(to: "/auth/sign-in-with-google") { _ in
            (200, """
            {
              "sessionToken": "google-session",
              "user": {
                "id": "g0gleUser1",
                "displayName": "Pat",
                "avatarUrl": "https://lh3/avatar.png"
              }
            }
            """.data(using: .utf8)!)
        }
        let client = makeClient()
        let r = try await client.signInWithGoogle(identityToken: "fake", displayName: nil)
        #expect(r.user.id == "g0gleUser1")
        #expect(r.user.avatarUrl == "https://lh3/avatar.png")
    }

    // MARK: - profiles

    @Test("fetch decodes profile DTO including nested profileJson")
    func fetchProfileDecodes() async throws {
        MockProtocol.respond(to: "/profiles/k7Fp2nLm") { _ in
            (200, sampleProfileResponse.data(using: .utf8)!)
        }
        let client = makeClient(token: "session")
        let p = try await client.fetch(id: "k7Fp2nLm")
        #expect(p.id == "k7Fp2nLm")
        #expect(p.name == "Auto · Yirgacheffe")
        #expect(p.likesCount == 3)
        #expect(p.profileJson.stages.count == 3)
        #expect(p.author.displayName == "Dave")
    }

    @Test("browse paginates by cursor")
    func browseDecodes() async throws {
        MockProtocol.respond(to: "/profiles") { _ in
            (200, """
            {
              "profiles": [\(sampleProfileObject)],
              "nextCursor": null
            }
            """.data(using: .utf8)!)
        }
        let client = makeClient(token: "session")
        let firstPage = try await client.browse()
        #expect(firstPage.profiles.count == 1)
        #expect(firstPage.nextCursor == nil)

        MockProtocol.respond(to: "/profiles") { _ in
            (200, "{ \"profiles\": [], \"nextCursor\": null }".data(using: .utf8)!)
        }
        let nextPage = try await client.browse(cursor: "2026-05-27")
        #expect(nextPage.profiles.isEmpty)
    }

    @Test("upload returns the deep link the backend issued")
    func uploadDecodesResponse() async throws {
        MockProtocol.respond(to: "/profiles") { _ in
            (201, """
            {
              "profile": \(sampleProfileObject),
              "url": "https://test.local/p/k7Fp2nLm",
              "deepLink": "crema://profile/k7Fp2nLm"
            }
            """.data(using: .utf8)!)
        }
        let client = makeClient(token: "session")
        let r = try await client.upload(ShareableProfile(
            profile: BrewProfile.classicEspresso,
            beanName: "Yirgacheffe"
        ))
        #expect(r.deepLink == "crema://profile/k7Fp2nLm")
        #expect(r.url == "https://test.local/p/k7Fp2nLm")
        #expect(r.profile.id == "k7Fp2nLm")
    }

    @Test("like + unlike round-trip count")
    func likeUnlike() async throws {
        MockProtocol.respond(to: "/profiles/abc/like") { req in
            (200, "{ \"likesCount\": \(req.httpMethod == "POST" ? 5 : 4) }".data(using: .utf8)!)
        }
        let client = makeClient(token: "session")
        let liked = try await client.like(profileId: "abc")
        #expect(liked.likesCount == 5)
        let unliked = try await client.unlike(profileId: "abc")
        #expect(unliked.likesCount == 4)
    }

    @Test("401 maps to APIError.unauthorized")
    func unauthorizedMaps() async throws {
        MockProtocol.respond(to: "/users/me") { _ in
            (401, "{\"error\":\"missing bearer token\"}".data(using: .utf8)!)
        }
        let client = makeClient(token: "fake")
        do {
            _ = try await client.me()
            #expect(Bool(false), "should have thrown")
        } catch let e as ShareAPIClient.APIError {
            if case .unauthorized = e { /* ok */ }
            else { #expect(Bool(false), "wrong error variant: \(e)") }
        }
    }
}

// ---------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------

/// Just the profile object (no enclosing `{"profile": …}`) — composable into
/// either a single-fetch response or an item in a browse-paginated array.
private let sampleProfileObject = """
{
  "id": "k7Fp2nLm",
  "name": "Auto · Yirgacheffe",
  "description": "Bright + floral",
  "beanName": "Yirgacheffe",
  "equipment": "LITA-BA + Niche",
  "profileJson": {
    "id": "7E57717E-0000-0000-0000-000000000001",
    "name": "Auto · Yirgacheffe",
    "stages": [
      {"id": "11111111-1111-1111-1111-111111111111", "label": "Preinfuse", "duration": 7, "priority": "pressure", "pressureBar": 4.0, "flowMlPerSec": 0, "waitAfter": 2},
      {"id": "22222222-2222-2222-2222-222222222222", "label": "Extract",   "duration": 22, "priority": "flow",     "pressureBar": 0, "flowMlPerSec": 1.7, "waitAfter": 0},
      {"id": "33333333-3333-3333-3333-333333333333", "label": "Tail",      "duration": 4,  "priority": "pressure", "pressureBar": 1.0, "flowMlPerSec": 0, "waitAfter": 0}
    ],
    "mode": 2,
    "target": "flow",
    "targetVolumeMl": 36,
    "autoLink": 0,
    "directExtract": false,
    "variableFlow": true
  },
  "likesCount": 3,
  "downloadsCount": 12,
  "createdAt": "2026-05-27T10:30:00.000Z",
  "author": { "id": "k7Fp2nLmAB", "displayName": "Dave", "avatarUrl": null }
}
"""

private let sampleProfileResponse = "{ \"profile\": \(sampleProfileObject) }"

// ---------------------------------------------------------------
// URLProtocol mock — intercepts ALL requests in this process. Each test
// registers per-path responders via `MockProtocol.respond(to:)`.
// ---------------------------------------------------------------

final class MockProtocol: URLProtocol {
    typealias Responder = (URLRequest) -> (Int, Data)
    nonisolated(unsafe) private static var responders: [String: Responder] = [:]
    nonisolated(unsafe) private static let lock = NSLock()

    static func respond(to pathPrefix: String, _ responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        responders[pathPrefix] = responder
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responders.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "test.local"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.lock()
        let match = Self.responders.first(where: { path == $0.key })?.value
        Self.lock.unlock()
        guard let match else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "MockProtocol", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "No responder for \(path)"
                ]))
            return
        }
        let (status, body) = match(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLSession streams bodies for POST requests in some configurations;
    /// inspect via the legacy httpBody when set or pull the stream.
    func bodyStreamData() -> Data {
        if let b = httpBody { return b }
        guard let stream = httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: 4096)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
