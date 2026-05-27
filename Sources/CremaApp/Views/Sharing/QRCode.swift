import SwiftUI
import CoreImage.CIFilterBuiltins

/// CoreImage-backed QR code rendering — no third-party dep. Returns a
/// SwiftUI `Image` from a string input. Sized large enough that the QR
/// scanner can read it even at modest display sizes (medium error
/// correction is enough for a `crema://profile/<8-char-id>` URL).
enum QRCode {
    static func image(for text: String) -> Image? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(iOS)
        return Image(uiImage: UIImage(cgImage: cg))
        #else
        return Image(nsImage: NSImage(cgImage: cg,
                                       size: NSSize(width: scaled.extent.width,
                                                    height: scaled.extent.height)))
        #endif
    }
}

#if os(iOS)
import UIKit
#else
import AppKit
#endif
