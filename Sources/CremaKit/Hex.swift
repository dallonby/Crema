import Foundation

extension Data {
    /// Parse a hex string into bytes. Spaces are tolerated, case-insensitive.
    /// Returns `nil` if the string has odd length or contains non-hex characters.
    public init?(hex: String) {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        self.init(bytes)
    }

    /// Uppercase hex string with no separators (e.g. `"01030000002584 11"` → `"0103000000258411"`).
    public var hex: String {
        map { String(format: "%02X", $0) }.joined()
    }

    /// Same as `hex`, but space-separated bytes — useful for logging packets.
    public var hexSpaced: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
