import SwiftUI
import AuthenticationServices
import CremaKit

/// Block presented when a share / browse action requires sign-in. Single
/// Apple-branded button → kicks off the controller → on success the
/// dismissing parent sheet re-renders with the signed-in state.
struct SignInView: View {
    @Bindable var session: SignedInUser
    let onSignedIn: () -> Void
    @State private var signingIn = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(CremaColor.crema.opacity(0.20))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(CremaColor.crema)
            }
            Text("Join the Crema community")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text("Share your tuned recipes and browse what other coffee nerds have brewed.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            SignInWithAppleButton(.signIn) { _ in
                // No-op — we drive Sign-In ourselves via the controller
                // for full async/await ergonomics. The button just looks
                // right (Apple HIG requires the specific style).
            } onCompletion: { _ in }
                .signInWithAppleButtonStyle(.white)
                .frame(width: 260, height: 48)
                .allowsHitTesting(false)
                .overlay(
                    // The branded button is decoration; this transparent tap
                    // target actually triggers the flow so we can await it.
                    Button(action: doSignIn) {
                        Color.clear.contentShape(Rectangle())
                    }
                    .disabled(signingIn)
                )

            if signingIn {
                ProgressView().controlSize(.small).tint(CremaColor.cream)
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    private func doSignIn() {
        signingIn = true
        errorText = nil
        Task {
            do {
                try await session.signInWithApple()
                signingIn = false
                onSignedIn()
            } catch {
                signingIn = false
                errorText = String(describing: error)
            }
        }
    }
}
