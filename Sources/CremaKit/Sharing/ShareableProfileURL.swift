import Foundation

/// Deep-link plumbing for profile shares. Two URL families:
///
/// - **`crema://profile/<id>`** — universal deep link. Used by .onOpenURL
///   in the app; routes to the import preview which fetches by id.
/// - **`<PUBLIC_BASE_URL>/p/<id>`** — web link. Lives on the backend, the
///   web page can preview the profile + offer App Store / "Open in Crema"
///   buttons. The associated-domains entitlement makes Universal Links
///   automatically open the app when installed.
///
/// QR codes embed the `crema://` URL when scanned in-app (no network round
/// trip when both ends have the data already), and the web URL when posted
/// publicly so non-Crema-users get a useful preview page.
public struct ShareableProfileURL: Sendable, Equatable {
    public let id: String

    public init(id: String) { self.id = id }

    /// Parse either form. Returns nil if the URL isn't a profile share.
    public init?(url: URL) {
        // crema://profile/<id>
        if url.scheme == "crema", url.host == "profile" {
            let id = url.pathComponents.dropFirst().joined(separator: "/")
            guard !id.isEmpty else { return nil }
            self.id = id
            return
        }
        // https://<base>/p/<id>
        let comps = url.pathComponents
        if comps.count >= 3, comps[1] == "p" {
            self.id = comps[2]
            return
        }
        return nil
    }

    /// crema://profile/<id> — opens the local app directly.
    public var deepLink: URL {
        URL(string: "crema://profile/\(id)")!
    }

    /// Web URL — shareable in browsers, messengers, the App Store
    /// (Universal Links bounce to the app when installed).
    public func webURL(base: URL) -> URL {
        base.appendingPathComponent("p").appendingPathComponent(id)
    }
}
