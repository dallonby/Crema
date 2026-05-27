import Foundation
import AuthenticationServices

/// Thin async-throws wrapper around `ASAuthorizationController` so callers
/// can write `let cred = try await AppleSignInController().request()` instead
/// of juggling delegate methods + manual completion-handler bridging.
///
/// On success returns the raw identity token (a JWT). The token gets POSTed
/// to our backend's `/auth/sign-in-with-apple`, which verifies it against
/// Apple's public keys and trades it for our own session JWT.
@MainActor
final class AppleSignInController: NSObject,
        ASAuthorizationControllerDelegate,
        ASAuthorizationControllerPresentationContextProviding {

    struct Result {
        /// The Apple identity JWT — opaque blob, gets verified server-side.
        let identityToken: String
        /// Apple only returns this on the very first sign-in for a given
        /// app/user pair. Cache it the first time so subsequent sign-ins
        /// don't lose it.
        let displayName: String?
    }

    private var continuation: CheckedContinuation<Result, Error>?

    func request() async throws -> Result {
        let provider = ASAuthorizationAppleIDProvider()
        let req = provider.createRequest()
        req.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [req])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithAuthorization auth: ASAuthorization) {
        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: SignInError.missingIdentityToken)
            continuation = nil
            return
        }
        let name: String? = {
            guard let n = cred.fullName else { return nil }
            let parts = [n.givenName, n.familyName].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()
        continuation?.resume(returning: Result(identityToken: token, displayName: name))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first ?? ASPresentationAnchor()
        #else
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #endif
    }

    enum SignInError: Error { case missingIdentityToken }
}

#if os(iOS)
import UIKit
#else
import AppKit
#endif
