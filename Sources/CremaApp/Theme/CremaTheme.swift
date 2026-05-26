import SwiftUI

/// Crema's visual language. Dark by default, warm neutrals, two semantic accents:
/// `crema` for pressure, `matcha` for flow. Weight uses `cream`.
enum CremaColor {
    /// Almost-black background, warm cast.
    static let bg          = Color(red: 0.039, green: 0.035, blue: 0.031)        // #0A0908
    /// Slightly raised surface for cards.
    static let surface     = Color(red: 0.102, green: 0.086, blue: 0.078)        // #1A1614
    /// Card surface, slightly warmer (used behind glass).
    static let surfaceWarm = Color(red: 0.137, green: 0.106, blue: 0.090)
    /// Subtle border / divider tone.
    static let hairline    = Color(red: 0.18,  green: 0.16,  blue: 0.15)
    /// Warm white for primary text and the weight series.
    static let cream       = Color(red: 0.961, green: 0.937, blue: 0.918)        // #F5EFEA
    /// Muted text.
    static let secondary   = Color(red: 0.541, green: 0.510, blue: 0.486)        // #8A827C
    /// Pressure (semantic).
    static let crema       = Color(red: 0.910, green: 0.518, blue: 0.235)        // #E8843C
    /// Brighter pressure highlight, used at the playhead dot.
    static let cremaBright = Color(red: 1.000, green: 0.620, blue: 0.310)
    /// Flow (semantic) — champagne gold. Same hue family as crema for a
    /// monochromatic-luxury palette, but cooler and lower-saturation so it sits
    /// quietly. Named `matcha` for legacy; semantically it's just "the flow color."
    static let matcha       = Color(red: 0.851, green: 0.722, blue: 0.447)       // #D9B872
    /// Brighter flow highlight — pale luminous gold, distinct from crema in
    /// small marks (cursor dots, HUD bullets, pills).
    static let matchaBright = Color(red: 0.957, green: 0.871, blue: 0.624)       // #F4DE9F
    /// Pre-infusion / wait gap tone.
    static let waitGray    = Color(red: 0.32,  green: 0.30,  blue: 0.28)
    /// Warm-amber tone used for divergence between target and actual.
    static let divergence  = Color(red: 0.96, green: 0.55, blue: 0.20)
    /// "Healthy live connection" indicator — calm matcha-leaning teal that
    /// doesn't compete with crema in the rest of the chrome.
    static let connected   = Color(red: 0.45, green: 0.85, blue: 0.62)
    /// Soft red for failure states. Used sparingly.
    static let danger      = Color(red: 0.92, green: 0.40, blue: 0.36)
}

/// The room the chart lives in: a warm radial glow from upper-right fading into the
/// near-black background. Feels like crema crowning at the top of a freshly-pulled cup.
enum CremaGradient {
    static let appBackground = RadialGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 0.18, green: 0.10, blue: 0.06).opacity(0.55), location: 0.0),
            .init(color: Color(red: 0.11, green: 0.07, blue: 0.05).opacity(0.35), location: 0.3),
            .init(color: CremaColor.bg, location: 1.0)
        ]),
        center: UnitPoint(x: 0.75, y: 0.15),
        startRadius: 60,
        endRadius: 1200
    )

    /// Subtle inner vignette to draw the eye toward the chart.
    static let vignette = RadialGradient(
        gradient: Gradient(colors: [
            Color.clear,
            Color.black.opacity(0.0),
            Color.black.opacity(0.35)
        ]),
        center: .center,
        startRadius: 200,
        endRadius: 900
    )

    /// Pressure trace gradient — slightly hotter at peaks.
    static let pressureStroke = LinearGradient(
        colors: [CremaColor.cremaBright, CremaColor.crema],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Flow trace gradient.
    static let flowStroke = LinearGradient(
        colors: [CremaColor.matchaBright, CremaColor.matcha],
        startPoint: .top,
        endPoint: .bottom
    )
}

enum CremaFont {
    /// Big rounded numerals for HUD readouts.
    static func hudNumber(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .ultraLight, design: .rounded)
            .monospacedDigit()
    }
    /// Caption above each HUD number.
    static let hudCaption = Font.system(size: 10, weight: .medium, design: .rounded)
        .smallCaps()
    static let headerTitle = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let headerMeta  = Font.system(size: 12, weight: .regular, design: .rounded)
        .monospacedDigit()
    static let stageLabel  = Font.system(size: 10, weight: .medium, design: .rounded)
        .smallCaps()
    /// Tiny pill labels floating near the cursor.
    static let valuePill   = Font.system(size: 10, weight: .semibold, design: .rounded)
        .monospacedDigit()
    /// Axis labels.
    static let axisLabel   = Font.system(size: 10, weight: .regular, design: .rounded)
        .monospacedDigit()
}

/// Pluggable glass background — uses Liquid Glass on macOS 26+ and falls back to
/// `.ultraThinMaterial` on older systems. One spot to tune across the whole app.
struct CremaGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint?.opacity(0.12) ?? .clear))
                    .overlay(shape.strokeBorder(CremaColor.hairline.opacity(0.6), lineWidth: 0.5))
            }
    }
}

extension View {
    /// Apply Crema's standard frosted card background.
    func cremaGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(CremaGlassBackground(shape: shape, tint: tint))
    }
}
