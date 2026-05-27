import Foundation
import AuthenticationServices
import CryptoKit

/// Google Sign-In via `ASWebAuthenticationSession` + manual OAuth 2.0 PKCE
/// flow. No SDK dependency — just URLSession + system browser.
///
/// Returns the `id_token` (a JWT) which the backend verifies against
/// Google's JWKS the same way it does for Apple. Backend then trades it
/// for our own session JWT.
///
/// Configuration the user must provide:
/// - **Google Cloud Console** → APIs & Services → Credentials → Create OAuth
///   Client ID → application type **iOS** → bundle id `coffee.crema.app`.
///   That gives you a Client ID like `12345-abc.apps.googleusercontent.com`
///   and a reversed-client-id `com.googleusercontent.apps.12345-abc`.
/// - Plug both into `Config` below (or wire to a config plist later).
/// - Add the reversed-client-id as a URL scheme in Info.plist so the
///   browser redirect back into the app works (the `CFBundleURLSchemes`
///   entry).
/// - On the backend, set `GOOGLE_CLIENT_IDS` env to include the iOS
///   client id (and Android / web later).
@MainActor
final class GoogleSignInController: NSObject,
        ASWebAuthenticationPresentationContextProviding {

    public struct Config: Sendable {
        public let clientID: String          // 12345-abc.apps.googleusercontent.com
        public let reversedClientID: String  // com.googleusercontent.apps.12345-abc
        public init(clientID: String, reversedClientID: String) {
            self.clientID = clientID
            self.reversedClientID = reversedClientID
        }
    }

    struct Result {
        let idToken: String
        let displayName: String?
        let email: String?
    }

    private let config: Config
    private var webAuthSession: ASWebAuthenticationSession?

    init(config: Config) { self.config = config }

    /// Run the full flow. Throws if the user cancels or any step fails.
    func request() async throws -> Result {
        let (verifier, challenge) = makePKCEPair()
        let state = randomURLSafeString(length: 24)
        let redirectURI = "\(config.reversedClientID):/oauth2redirect"

        // 1. Authorize URL — kick off the browser flow
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            URLQueryItem(name: "client_id",             value: config.clientID),
            URLQueryItem(name: "redirect_uri",          value: redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: "openid email profile"),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = auth.url else { throw GoogleSignInError.badConfig }

        // 2. Wait for the redirect carrying the auth code
        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let scheme = config.reversedClientID
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { url, error in
                if let error { cont.resume(throwing: error); return }
                guard let url else { cont.resume(throwing: GoogleSignInError.noCallback); return }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            if !session.start() { cont.resume(throwing: GoogleSignInError.couldNotStartSession) }
        }

        // 3. Parse the callback: ?code=…&state=…
        let cb = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard cb?.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw GoogleSignInError.stateMismatch
        }
        guard let code = cb?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.noAuthCode
        }

        // 4. Exchange code for tokens (POST to token endpoint with PKCE verifier)
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let formBody: [(String, String)] = [
            ("client_id",     config.clientID),
            ("code",          code),
            ("code_verifier", verifier),
            ("grant_type",    "authorization_code"),
            ("redirect_uri",  redirectURI),
        ]
        req.httpBody = encodeForm(formBody).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleSignInError.tokenExchangeFailed(
                String(data: data, encoding: .utf8) ?? "?")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)

        // 5. Optional: peek at the ID token to pull display name + email.
        //    Not security-sensitive (server re-verifies the signature).
        let claims = decodeJWTClaims(token.id_token)
        return Result(
            idToken: token.id_token,
            displayName: claims?["name"] as? String,
            email: claims?["email"] as? String
        )
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first ?? ASPresentationAnchor()
        #else
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #endif
    }

    // MARK: - Helpers

    private struct TokenResponse: Decodable {
        let id_token: String
        let access_token: String?
        let token_type: String?
        let expires_in: Int?
    }

    private func makePKCEPair() -> (verifier: String, challenge: String) {
        let verifier = randomURLSafeString(length: 64)
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64URLEncodedString()
        return (verifier, challenge)
    }

    private func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func encodeForm(_ pairs: [(String, String)]) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return pairs.map { k, v in
            let key = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let val = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(key)=\(val)"
        }.joined(separator: "&")
    }

    private func decodeJWTClaims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let claims = String(parts[1])
        // Base64url → base64 (add padding)
        var b64 = claims.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    enum GoogleSignInError: Error {
        case badConfig
        case noCallback
        case couldNotStartSession
        case stateMismatch
        case noAuthCode
        case tokenExchangeFailed(String)
    }
}

private extension Data {
    /// base64url (RFC 4648 §5) — no padding, '+' → '-', '/' → '_'.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#if os(iOS)
import UIKit
#else
import AppKit
#endif
