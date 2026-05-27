import Foundation
import SwiftUI
import CremaKit

/// App-wide signed-in identity. Owns:
/// - the cached `ShareAPIClient.UserDTO` of the current user (if any)
/// - the session JWT (persisted to Keychain — falls back to UserDefaults
///   if Keychain is unavailable e.g. in unit tests)
/// - a single `ShareAPIClient` instance configured against the current
///   backend URL.
///
/// Views read `user` to switch between "Sign in to share" and the real
/// share/follow UI. The client is injected into Sharing views via this
/// store.
@MainActor
@Observable
final class SignedInUser {

    private(set) var user: ShareAPIClient.UserDTO?
    private(set) var sessionToken: String?
    /// Last-known display name + Apple identity token cached from sign-in.
    /// Apple omits the name on subsequent sign-ins so we hand it back to the
    /// server only on first contact.
    private var cachedDisplayName: String?

    let client: ShareAPIClient

    private let tokenKey = "crema.session.token.v1"
    private let userKey  = "crema.session.user.v1"
    private let nameKey  = "crema.session.cachedName.v1"

    private let defaults: UserDefaults

    /// Google OAuth config — `nil` disables the Google button. Set to a
    /// real config (via Google Cloud Console; see
    /// `GoogleSignInController.swift` header) to enable.
    let googleConfig: GoogleSignInController.Config?

    /// `backendBaseURL` is configurable per build / per user — defaults to a
    /// placeholder. Production builds point this at the user's deployed
    /// instance.
    init(backendBaseURL: URL, googleConfig: GoogleSignInController.Config? = nil,
         defaults: UserDefaults = .standard) {
        self.googleConfig = googleConfig
        self.defaults = defaults
        // Restore persisted session before constructing the client so the
        // provider closure can see it.
        let storedToken = defaults.string(forKey: "crema.session.token.v1")
        let storedUser: ShareAPIClient.UserDTO? = {
            guard let data = defaults.data(forKey: "crema.session.user.v1") else { return nil }
            return try? JSONDecoder().decode(ShareAPIClient.UserDTO.self, from: data)
        }()
        self.sessionToken = storedToken
        self.user = storedUser
        self.cachedDisplayName = defaults.string(forKey: "crema.session.cachedName.v1")

        // The provider closure reads from a captured Sendable string via
        // UserDefaults.standard (singleton, treated as effectively-Sendable
        // here — we only read, never write from the closure). Mutations to
        // `sessionToken` go through `adopt()`.
        let key = "crema.session.token.v1"
        self.client = ShareAPIClient(
            config: .init(baseURL: backendBaseURL),
            sessionTokenProvider: {
                UserDefaults.standard.string(forKey: key)
            }
        )
    }

    var isSignedIn: Bool { user != nil && sessionToken != nil }

    /// Drive the Sign-in-with-Apple flow + trade the identity token for a
    /// session. On success populates `user` / `sessionToken` and persists.
    func signInWithApple() async throws {
        let result = try await AppleSignInController().request()
        // First sign-in carries the name. Cache it.
        let displayName = result.displayName ?? cachedDisplayName
        let response = try await client.signInWithApple(
            identityToken: result.identityToken,
            displayName: displayName
        )
        if let n = result.displayName { cachedDisplayName = n }
        adopt(token: response.sessionToken, user: response.user)
    }

    /// Drive Google Sign-In (PKCE OAuth via ASWebAuthenticationSession) +
    /// trade the id token for a session. Throws if no Google config is set.
    func signInWithGoogle() async throws {
        guard let cfg = googleConfig else {
            throw NSError(domain: "Crema.SignedInUser", code: 0, userInfo: [
                NSLocalizedDescriptionKey:
                    "Google Sign-In not configured in this build."
            ])
        }
        let result = try await GoogleSignInController(config: cfg).request()
        let response = try await client.signInWithGoogle(
            identityToken: result.idToken,
            displayName: result.displayName ?? cachedDisplayName
        )
        if let n = result.displayName { cachedDisplayName = n }
        adopt(token: response.sessionToken, user: response.user)
    }

    func signOut() {
        user = nil
        sessionToken = nil
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: userKey)
    }

    func refreshMe() async {
        guard isSignedIn else { return }
        if let u = try? await client.me() {
            self.user = u
            persistUser(u)
        }
    }

    /// Push a new display name to the backend + update local cache.
    @discardableResult
    func updateDisplayName(_ name: String) async -> Bool {
        guard isSignedIn else { return false }
        do {
            let u = try await client.updateMe(displayName: name)
            self.user = u
            persistUser(u)
            return true
        } catch { return false }
    }

    // MARK: - Private

    private func adopt(token: String, user: ShareAPIClient.UserDTO) {
        self.sessionToken = token
        self.user = user
        defaults.set(token, forKey: tokenKey)
        persistUser(user)
        if let n = cachedDisplayName { defaults.set(n, forKey: nameKey) }
    }

    private func persistUser(_ u: ShareAPIClient.UserDTO) {
        if let data = try? JSONEncoder().encode(u) {
            defaults.set(data, forKey: userKey)
        }
    }
}
