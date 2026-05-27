import SwiftUI
import CremaKit
#if os(iOS)
import UIKit
#endif

/// Share-out sheet for a single profile. Three paths:
/// - Upload to the community backend → get a `crema://` deep link and a
///   web URL. Copy / share via the system share sheet.
/// - Generate a QR code embedding the deep link (for in-person sharing).
/// - Export as a `.crema` file (AirDrop / Messages / Save to Files).
///
/// The latter two work without sign-in or network. The community upload
/// requires sign-in.
struct ShareProfileSheet: View {
    let profile: BrewProfile
    @Bindable var session: SignedInUser
    let onDismiss: () -> Void

    @State private var uploadedURL: URL?
    @State private var uploadedDeepLink: URL?
    @State private var uploading = false
    @State private var uploadError: String?
    @State private var qrImage: Image?
    @State private var fileURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    if !session.isSignedIn {
                        SignInView(session: session, onSignedIn: {})
                    } else {
                        uploadCard
                        if let url = uploadedURL {
                            linkCard(url: url)
                        }
                    }
                    Divider().overlay(CremaColor.hairline.opacity(0.5))
                    qrCard
                    fileCard
                }
                .padding(20)
            }
        }
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { prepareLocalShares() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share profile")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Text(profile.name)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CremaColor.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(CremaColor.surface.opacity(0.6)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Community link", systemImage: "globe")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text("Upload to the Crema community and get a shareable URL anyone can open in the app.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
            Button(action: upload) {
                HStack(spacing: 6) {
                    if uploading {
                        ProgressView().controlSize(.small).tint(CremaColor.bg)
                    } else {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(uploading ? "Uploading…" : "Upload & get link")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(CremaColor.bg)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(Capsule().fill(CremaColor.crema))
            }
            .buttonStyle(.plain)
            .disabled(uploading)
            if let uploadError {
                Text(uploadError)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.danger)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private func linkCard(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LINK")
                .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.7)
                .foregroundStyle(CremaColor.secondary)
            Text(url.absoluteString)
                .font(.system(size: 13, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.cream)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(CremaColor.surface.opacity(0.6)))
            HStack(spacing: 8) {
                Button(action: { copyToClipboard(url.absoluteString) }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Capsule().fill(CremaColor.surface.opacity(0.6)))
                }.buttonStyle(.plain)
                Button(action: { systemShare(url.absoluteString) }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Capsule().fill(CremaColor.surface.opacity(0.6)))
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var qrCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("QR code", systemImage: "qrcode")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            if let img = qrImage {
                img.interpolation(.none)
                    .resizable().scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(Color.white)
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity)
            }
            Text(uploadedDeepLink == nil
                 ? "Upload to community first, then scan with another iPhone or iPad to install this profile instantly."
                 : "Point another Crema device's camera at this code to install.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Export as file", systemImage: "doc.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text("AirDrop, message, or save the profile as a `.crema` file. The other device opens it in Crema directly.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
            if let url = fileURL {
                #if os(iOS)
                ShareLink(item: url) {
                    Label("AirDrop / share file", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                        .padding(.horizontal, 14).frame(minHeight: 38)
                        .background(Capsule().fill(CremaColor.surface.opacity(0.6)))
                }
                #else
                Button(action: { systemShareFile(url) }) {
                    Label("Save .crema file", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                        .padding(.horizontal, 14).frame(minHeight: 38)
                        .background(Capsule().fill(CremaColor.surface.opacity(0.6)))
                }.buttonStyle(.plain)
                #endif
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CremaColor.hairline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Actions

    private func prepareLocalShares() {
        // Write a temp .crema file regardless of upload state.
        do {
            let s = ShareableProfile(profile: profile,
                                      sharedByName: session.user?.displayName)
            fileURL = try ProfileShareCodec.writeTempFile(s)
        } catch { /* swallow — file share just won't appear */ }
    }

    private func upload() {
        uploading = true
        uploadError = nil
        Task {
            do {
                let s = ShareableProfile(profile: profile,
                                          sharedByName: session.user?.displayName)
                let resp = try await session.client.upload(s)
                let url = URL(string: resp.url)!
                let deep = URL(string: resp.deepLink)!
                uploadedURL = url
                uploadedDeepLink = deep
                qrImage = QRCode.image(for: deep.absoluteString)
                uploading = false
            } catch {
                uploadError = String(describing: error)
                uploading = false
            }
        }
    }

    private func copyToClipboard(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }

    private func systemShare(_ s: String) {
        #if os(iOS)
        let av = UIActivityViewController(activityItems: [s], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?
            .keyWindow?.rootViewController?
            .present(av, animated: true)
        #else
        let picker = NSSharingServicePicker(items: [s])
        if let window = NSApp.keyWindow {
            picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
        }
        #endif
    }

    private func systemShareFile(_ url: URL) {
        #if os(macOS)
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow {
            picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
        }
        #endif
    }
}

#if os(macOS)
import AppKit
#endif
