import SwiftUI
import CremaKit

/// Inline error banner — shown at the top of sheets / scroll views when a
/// network operation fails. Includes a small dismiss button and an
/// optional retry callback. Auto-fades in/out via the binding's animation.
///
/// Usage:
/// ```swift
/// if let err = store.error {
///   InlineErrorBanner(message: err, onRetry: { Task { await store.refresh() } })
/// }
/// ```
struct InlineErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(CremaColor.danger)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(friendlyMessage)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                    .fixedSize(horizontal: false, vertical: true)
                if let onRetry {
                    Button(action: onRetry) {
                        Text("Retry")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CremaColor.crema)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 8)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CremaColor.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CremaColor.danger.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CremaColor.danger.opacity(0.35), lineWidth: 0.5))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Map common URLError / API error strings into friendlier copy.
    /// Falls back to the raw message if no rule matches — better to show
    /// the truth than swallow useful debug info.
    private var friendlyMessage: String {
        let lower = message.lowercased()
        if lower.contains("network connection") || lower.contains("offline")
            || lower.contains("not connected to the internet") {
            return "You're offline. Check your connection."
        }
        if lower.contains("unauthorized") || lower.contains("401") {
            return "Sign-in expired. Please sign in again from Settings."
        }
        if lower.contains("could not connect") || lower.contains("connection refused") {
            return "Can't reach the backend. Check the URL in Settings."
        }
        if lower.contains("timed out") {
            return "Request timed out. The backend might be cold-starting."
        }
        if lower.contains("not found") || lower.contains("404") {
            return "Profile not found — it may have been deleted."
        }
        return message
    }
}
