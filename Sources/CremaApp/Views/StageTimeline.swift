import SwiftUI
import CremaKit

/// Bottom strip showing stages as dots connected by a thin rail.
/// All drawing happens in a single Canvas pass so rails and circles share
/// the same antialiased rendering path (the previous Rectangle-with-frame-height-1
/// rails were landing on subpixel boundaries and reading as fuzzy).
struct StageTimeline: View {
    let profile: BrewProfile
    let playhead: Double

    @State private var pulse = false

    var body: some View {
        Canvas { ctx, size in
            let dotY = size.height * 0.5 - 6      // dots a bit above center, labels below
            let stages = profile.stages
            guard !stages.isEmpty else { return }
            let count = stages.count
            // Even horizontal distribution: each dot at center of its slot.
            let slotW = size.width / CGFloat(count)
            let centers = (0..<count).map { i in
                CGPoint(x: slotW * (CGFloat(i) + 0.5), y: dotY)
            }
            let currentIdx = currentIndex
            let stagePulse = profilePulseOpacity

            // Rails between consecutive dots
            for i in 0..<count - 1 {
                let a = centers[i]
                let b = centers[i + 1]
                var rail = Path()
                let leftEdge  = CGPoint(x: a.x + 18, y: a.y)
                let rightEdge = CGPoint(x: b.x - 18, y: b.y)
                rail.move(to: leftEdge)
                rail.addLine(to: rightEdge)
                let activeRail = i < currentIdx
                ctx.stroke(rail,
                           with: .color(activeRail ? CremaColor.crema.opacity(0.65)
                                                   : CremaColor.hairline),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            // Dots
            for (i, c) in centers.enumerated() {
                let state = stateFor(i, currentIdx: currentIdx)
                if state == .current {
                    // Pulse halo
                    let haloR = 12 + 8 * stagePulse
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: c.x - haloR, y: c.y - haloR,
                                                width: haloR * 2, height: haloR * 2)),
                        with: .color(CremaColor.crema.opacity(0.18 * (1 - stagePulse)))
                    )
                }
                let r: CGFloat = state == .future ? 4.5 : 5.5
                // Fill
                ctx.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .color(state == .future ? CremaColor.bg : CremaColor.crema)
                )
                // Stroke
                let stroke = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                    width: r * 2, height: r * 2))
                ctx.stroke(stroke,
                           with: .color(state == .future ? CremaColor.hairline
                                                         : CremaColor.crema),
                           style: StrokeStyle(lineWidth: 1.2))
            }

            // Labels under dots
            for (i, c) in centers.enumerated() {
                let state = stateFor(i, currentIdx: currentIdx)
                let color: Color = {
                    switch state {
                    case .future:  return CremaColor.secondary
                    case .current: return CremaColor.cream
                    case .past:    return CremaColor.cream.opacity(0.7)
                    }
                }()
                let text = Text(stages[i].label)
                    .font(CremaFont.stageLabel)
                    .foregroundColor(color)
                ctx.draw(text, at: CGPoint(x: c.x, y: c.y + 18), anchor: .center)
            }
        }
        .onAppear { pulse = true }
    }

    // MARK: - State

    private enum StageState { case past, current, future }

    /// Drives the halo on the current-stage dot. Manual phase because Canvas does
    /// not animate StrokeStyle directly — we read a continuous time-of-day phase.
    private var profilePulseOpacity: Double {
        let t = Date().timeIntervalSinceReferenceDate
        let cycle = 1.4
        let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
        return phase  // 0 → 1 over the cycle
    }

    private var currentIndex: Int {
        var cursor = 0.0
        for (i, s) in profile.stages.enumerated() {
            cursor += s.duration + s.waitAfter
            if playhead < cursor { return i }
        }
        return profile.stages.count - 1
    }

    private func stateFor(_ idx: Int, currentIdx: Int) -> StageState {
        if idx < currentIdx { return .past }
        if idx == currentIdx && playhead < profile.totalDuration { return .current }
        return .future
    }
}
