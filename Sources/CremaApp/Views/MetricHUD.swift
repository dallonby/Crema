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

    var body: some View {
        HStack(spacing: 10) {
            tile(value: String(format: "%.1f", pressure), unit: "bar",
                 caption: "Pressure", accent: CremaColor.crema)
            tile(value: String(format: "%.1f", flow), unit: "mL/s",
                 caption: "Pump flow", accent: CremaColor.matcha)
            tile(value: String(format: "%.0f", volume), unit: "mL",
                 caption: "Pumped", accent: CremaColor.cream)
            tile(value: timeString(elapsed), unit: "s",
                 caption: "Time", accent: CremaColor.cream)
        }
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
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: value)
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
