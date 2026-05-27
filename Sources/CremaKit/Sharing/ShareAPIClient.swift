import Foundation

/// REST client for the Crema community backend. Owns the base URL + the
/// session token and exposes a tiny typed surface over what the iOS UI
/// actually needs.
///
/// Design notes:
/// - All endpoints return Decodable structs declared here, never the
///   shapes the backend privately uses. Keeps the iOS code resilient to
///   server-side renames as long as the documented response shape holds.
/// - Networking is `URLSession` with no third-party deps.
/// - Session token is read from the closure each request — lets the
///   `SignedInUser` actor own the canonical source of truth without the
///   client caching a stale copy.
public actor ShareAPIClient {
    public struct Config: Sendable {
        public var baseURL: URL
        public init(baseURL: URL) { self.baseURL = baseURL }
    }

    private var config: Config
    private let session: URLSession
    private let sessionTokenProvider: @Sendable () async -> String?

    public init(
        config: Config,
        sessionTokenProvider: @Sendable @escaping () async -> String?
    ) {
        self.config = config
        self.sessionTokenProvider = sessionTokenProvider
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
    }

    /// Testing seam — inject a pre-configured URLSession (typically one
    /// with a URLProtocol mock baked into the configuration).
    public init(
        config: Config,
        session: URLSession,
        sessionTokenProvider: @Sendable @escaping () async -> String?
    ) {
        self.config = config
        self.session = session
        self.sessionTokenProvider = sessionTokenProvider
    }

    public func updateBaseURL(_ url: URL) { self.config.baseURL = url }

    // MARK: - Wire shapes

    public struct UserDTO: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let displayName: String
        public let avatarUrl: String?
    }

    public struct ProfileDTO: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String
        public let description: String?
        public let beanName: String?
        public let equipment: String?
        public let profileJson: BrewProfile
        public let likesCount: Int
        public let downloadsCount: Int
        public let createdAt: Date
        public let author: UserDTO
    }

    public struct SignInResponse: Codable, Sendable {
        public let sessionToken: String
        public let user: UserDTO
    }

    public struct UploadResponse: Codable, Sendable {
        public let profile: ProfileDTO
        public let url: String
        public let deepLink: String
    }

    public struct BrowsePage: Codable, Sendable {
        public let profiles: [ProfileDTO]
        public let nextCursor: String?
    }

    public struct LikeResponse: Codable, Sendable {
        public let likesCount: Int
    }

    // MARK: - Auth

    public func signInWithApple(identityToken: String, displayName: String?) async throws -> SignInResponse {
        try await post("/auth/sign-in-with-apple",
                        body: ["identityToken": identityToken,
                               "displayName": displayName as Any],
                        auth: false)
    }

    public func signInWithGoogle(identityToken: String, displayName: String?) async throws -> SignInResponse {
        try await post("/auth/sign-in-with-google",
                        body: ["identityToken": identityToken,
                               "displayName": displayName as Any],
                        auth: false)
    }

    public func me() async throws -> UserDTO {
        struct R: Codable { let user: ShareAPIClient.UserDTO }
        let r: R = try await get("/users/me", auth: true)
        return r.user
    }

    public func updateMe(displayName: String) async throws -> UserDTO {
        struct R: Codable { let user: ShareAPIClient.UserDTO }
        let r: R = try await patch("/users/me",
                                    body: ["displayName": displayName],
                                    auth: true)
        return r.user
    }

    // MARK: - Profiles

    public func upload(_ s: ShareableProfile) async throws -> UploadResponse {
        // Encode `profile` to a generic JSON object so we don't double-encode
        // (the body is a single JSON document; the server expects
        // profile_json as a nested object, not a string).
        let profileData = try JSONEncoder().encode(s.profile)
        let profileObj = try JSONSerialization.jsonObject(with: profileData)
        var body: [String: Any] = [
            "name": s.profile.name,
            "profileJson": profileObj,
        ]
        if let v = s.beanName    { body["beanName"]    = v }
        if let v = s.equipment   { body["equipment"]   = v }
        if let v = s.description { body["description"] = v }
        return try await post("/profiles", body: body, auth: true)
    }

    public func fetch(id: String) async throws -> ProfileDTO {
        struct R: Codable { let profile: ProfileDTO }
        let r: R = try await get("/profiles/\(id)", auth: false)
        return r.profile
    }

    public func browse(cursor: String? = nil, authorId: String? = nil) async throws -> BrowsePage {
        var path = "/profiles?limit=30"
        if let c = cursor   { path += "&cursor=\(c.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c)" }
        if let a = authorId { path += "&author=\(a)" }
        return try await get(path, auth: false)
    }

    public func delete(id: String) async throws {
        try await deleteRequest("/profiles/\(id)", auth: true)
    }

    public func like(profileId: String) async throws -> LikeResponse {
        try await post("/profiles/\(profileId)/like", body: [:], auth: true)
    }

    public func unlike(profileId: String) async throws -> LikeResponse {
        struct R: Codable { let likesCount: Int }
        let r: R = try await deleteRequest("/profiles/\(profileId)/like", auth: true)
        return LikeResponse(likesCount: r.likesCount)
    }

    public func follow(userId: String) async throws {
        let _: [String: Bool] = try await post("/users/\(userId)/follow",
                                                body: [:], auth: true)
    }

    public func unfollow(userId: String) async throws {
        try await deleteRequest("/users/\(userId)/follow", auth: true)
    }

    // MARK: - HTTP plumbing

    private func get<R: Decodable>(_ path: String, auth: Bool) async throws -> R {
        try await send(method: "GET", path: path, body: nil, auth: auth)
    }
    private func post<R: Decodable>(_ path: String, body: [String: Any], auth: Bool) async throws -> R {
        try await send(method: "POST", path: path, body: body, auth: auth)
    }
    private func patch<R: Decodable>(_ path: String, body: [String: Any], auth: Bool) async throws -> R {
        try await send(method: "PATCH", path: path, body: body, auth: auth)
    }
    @discardableResult
    private func deleteRequest<R: Decodable>(_ path: String, auth: Bool) async throws -> R {
        try await send(method: "DELETE", path: path, body: nil, auth: auth)
    }
    private func deleteRequest(_ path: String, auth: Bool) async throws {
        struct Empty: Codable {}
        let _: Empty? = try? await send(method: "DELETE", path: path, body: nil, auth: auth)
    }

    private func send<R: Decodable>(method: String, path: String,
                                     body: [String: Any]?, auth: Bool) async throws -> R {
        let url = URL(string: path, relativeTo: config.baseURL)!.absoluteURL
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth, let token = await sessionTokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode,
                                 message: String(data: data, encoding: .utf8))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(R.self, from: data)
    }

    public enum APIError: Error, Sendable {
        case invalidResponse
        case unauthorized
        case http(status: Int, message: String?)
    }
}
