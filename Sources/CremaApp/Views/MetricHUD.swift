import SwiftUI

/// The four-tile "watch face" beneath the chart. Reads like an instrument panel:
/// big ultralight numerals, tiny caps captions, monospaced digits so they don't jitter.
/// Each tile sits on Liquid Glass (macOS 26) with a thin accent rail bottom-aligned
/// to its semantic color (pressure = crema, flow = matcha, etc.).
struct MetricHUD: View {
    let pressure: Double
    let flow: Double
    let volume: Double
    let elapsed: Double

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    var body: some View {
        if isCompact {
            // iPhone portrait: 2x2 grid so each tile gets ~half the width and
            // the ultralight 46pt numerals don't get clipped.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    pressureTile
                    flowTile
                }
                HStack(spacing: 8) {
                    volumeTile
                    timeTile
                }
            }
        } else {
            HStack(spacing: 10) {
                pressureTile
                flowTile
                volumeTile
                timeTile
            }
        }
    }

    private var pressureTile: some View {
        tile(value: String(format: "%.1f", pressure), unit: "bar",
             caption: "Pressure", accent: CremaColor.crema)
    }
    private var flowTile: some View {
        tile(value: String(format: "%.1f", flow), unit: "mL/s",
             caption: "Pump flow", accent: CremaColor.matcha)
    }
    private var volumeTile: some View {
        tile(value: String(format: "%.0f", volume), unit: "mL",
             caption: "Pumped", accent: CremaColor.cream)
    }
    private var timeTile: some View {
        tile(value: timeString(elapsed), unit: "s",
             caption: "Time", accent: CremaColor.cream)
    }

    private func tile(value: String, unit: String, caption: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                Text(caption)
                    .font(CremaFont.hudCaption)
                    .foregroundStyle(CremaColor.secondary)
                    .tracking(0.8)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(CremaFont.hudNumber(46))
                    .foregroundStyle(accent)
                    // No .contentTransition(.numericText()) — at the ~3.4 Hz
                    // sample cadence the interpolation takes longer than the
                    // gap between samples, so the displayed value lags behind
                    // and visually "bounces" between old and new. The native
                    // monospaced-digit refresh feels instant and matches the
                    // cursor pills on the chart.
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CremaColor.secondary)
                        .padding(.bottom, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .cremaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: accent)
        .overlay(alignment: .bottom) {
            // Thin accent rail at the bottom of the tile
            Rectangle()
                .fill(LinearGradient(colors: [accent.opacity(0), accent.opacity(0.55), accent.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .padding(.horizontal, 18)
        }
    }

    private func timeString(_ t: Double) -> String {
        let s = max(0, t)
        let whole = Int(s)
        let tenths = Int((s - Double(whole)) * 10)
        return String(format: "%d.%d", whole, tenths)
    }
}
