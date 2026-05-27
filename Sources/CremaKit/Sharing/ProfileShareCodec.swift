import Foundation

/// On-disk and on-wire envelope for a shared brew profile.
///
/// Wrapping `BrewProfile` in an envelope (rather than serialising the bare
/// profile) gives us a place to put:
/// - a schema version, so a future field rename doesn't break old shares,
/// - human-readable metadata the receiving device shows in the import
///   preview (bean, equipment, author note),
/// - the canonical sender identity at the moment of sharing — useful when
///   the same profile gets passed peer-to-peer multiple hops away from its
///   community-library origin.
public struct ShareableProfile: Sendable, Codable, Equatable {
    /// Schema version. Bump when a breaking shape change lands.
    public var version: Int
    /// The profile itself — passed through verbatim.
    public var profile: BrewProfile
    /// Optional metadata. Backend `POST /profiles` reads these into its
    /// own columns; AirDrop/file shares carry them in-band.
    public var beanName: String?
    public var equipment: String?
    public var description: String?
    /// Display name of the person sharing (best effort — clients should
    /// populate when known).
    public var sharedByName: String?

    public init(
        profile: BrewProfile,
        beanName: String? = nil,
        equipment: String? = nil,
        description: String? = nil,
        sharedByName: String? = nil,
        version: Int = 1
    ) {
        self.version = version
        self.profile = profile
        self.beanName = beanName
        self.equipment = equipment
        self.description = description
        self.sharedByName = sharedByName
    }
}

/// Encoders / decoders + small file utility — these are the only places
/// that talk JSON for profile sharing, so everyone agrees on date format,
/// pretty-printing, key strategy etc.
public enum ProfileShareCodec {

    /// File extension we register with the OS so .crema files open in Crema.
    public static let fileExtension = "crema"
    /// UTType for the file. Declared in iOS Info.plist + macOS Info.plist
    /// (project.yml has the entries).
    public static let utType = "coffee.crema.profile"

    public static func encode(_ shareable: ShareableProfile) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(shareable)
    }

    public static func decode(_ data: Data) throws -> ShareableProfile {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(ShareableProfile.self, from: data)
    }

    /// Write to a `<profile-name>.crema` file in the temp dir. Returns the
    /// URL the caller can hand to a UIActivityViewController / NSSavePanel /
    /// AirDrop.
    public static func writeTempFile(_ shareable: ShareableProfile) throws -> URL {
        let data = try encode(shareable)
        let safeName = shareable.profile.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "profile" : safeName)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    public static func read(_ url: URL) throws -> ShareableProfile {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }
}
