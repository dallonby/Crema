import SwiftUI
import CremaKit

/// The hero visualization. Three live series (pressure / flow / volume) drawn over
/// a ghost of the target profile. Custom `Canvas` instead of Swift Charts so we can
/// own the ghost overlay, the playhead, value pills, and stage-aware coloring.
struct ShotChart: View {
    let samples: ArraySlice<ShotSample>
    let profile: BrewProfile
    let playhead: Double
    let totalDuration: Double

    // Y-axis ceilings — computed from data + profile, with sensible minimums so the
    // chart doesn't shrink-wrap so tight that a small overshoot pops off the top.
    private var maxPressure: Double {
        let dataPeak = samples.map(\.pressureBar).max() ?? 0
        let profilePeak = profile.stages.map(\.pressureBar).max() ?? 0
        return max(6.0, min(12.0, max(dataPeak, profilePeak) * 1.25))
    }
    private var maxFlow: Double {
        // Locked at 8 mL/s — espresso flow basically never goes above this
        // even during preinfusion peaks (typical max is 5-6 mL/s as water
        // floods a dry puck). Letting this rescale dynamically as samples
        // arrive in live mode causes the flow line to visibly "bounce" — every
        // new high-water-mark repositions every previously-drawn point.
        8.0
    }
    private var maxVolume: Double {
        // Anchor to the profile's target volume so the y-axis is STABLE through
        // the whole shot — no silent rescaling as samples arrive. Pad ~25% above
        // target so the line approaches but doesn't kiss the top of the chart.
        // Falls back to a generous default for profiles without a target set.
        let target = profile.targetVolumeMl.map(Double.init) ?? 80
        let dataPeak = samples.map(\.volumeMl).max() ?? 0
        return max(target * 1.25, dataPeak * 1.05)
    }

    var body: some View {
        Canvas { ctx, size in
            // Left margin holds pressure labels; right margin holds volume labels.
            let plot = CGRect(x: 38, y: 14, width: size.width - 80, height: size.height - 42)
            drawGrid(ctx: ctx, in: plot)
            drawWaitGaps(ctx: ctx, in: plot)
            drawVolumeTarget(ctx: ctx, in: plot)
            drawGhostProfile(ctx: ctx, in: plot)
            drawLiveSeries(ctx: ctx, in: plot)
            drawPlayhead(ctx: ctx, in: plot)
            drawValuePills(ctx: ctx, in: plot)
            drawAxisLabels(ctx: ctx, in: plot)
        }
        // No drawingGroup() — it forces Metal rasterization which interacts badly
        // with the high-frequency sample appends in live mode (causes the
        // "squished straight lines" effect because the rasterized layer lags
        // the underlying data). The plain Canvas renders crisp on retina/iOS
        // and updates smoothly per sample.
    }

    /// Faint dashed horizontal line at the volume target — marathon-finish-line
    /// reference for "where am I heading."
    private func drawVolumeTarget(ctx: GraphicsContext, in r: CGRect) {
        guard let target = profile.targetVolumeMl.map(Double.init) else { return }
        let y = yVolume(target, in: r).rounded() + 0.5
        var line = Path()
        line.move(to: CGPoint(x: r.minX, y: y))
        line.addLine(to: CGPoint(x: r.maxX, y: y))
        ctx.stroke(line, with: .color(CremaColor.cream.opacity(0.18)),
                   style: StrokeStyle(lineWidth: 0.75, dash: [3, 4]))
        let label = Text("target \(Int(target)) mL")
            .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundColor(CremaColor.cream.opacity(0.5))
        ctx.draw(label, at: CGPoint(x: r.maxX - 4, y: y - 8), anchor: .trailing)
    }

    // MARK: - Grid

    private func drawGrid(ctx: GraphicsContext, in r: CGRect) {
        var minor = Path()
        var major = Path()
        // Horizontal: divisions matching the pressure scale, in 3-bar increments.
        let pressureSteps = stride(from: 0, through: Int(maxPressure.rounded(.up)), by: 3).map { Double($0) }
        for bar in pressureSteps {
            let y = yPressure(bar, in: r).rounded() + 0.5  // half-pixel for crisp lines
            if bar == 0 {
                major.move(to: CGPoint(x: r.minX, y: y))
                major.addLine(to: CGPoint(x: r.maxX, y: y))
            } else {
                minor.move(to: CGPoint(x: r.minX, y: y))
                minor.addLine(to: CGPoint(x: r.maxX, y: y))
            }
        }
        // Vertical: every 5s
        var t = 0.0
        while t <= totalDuration + 0.01 {
            let x = xFor(t, in: r).rounded() + 0.5
            minor.move(to: CGPoint(x: x, y: r.minY))
            minor.addLine(to: CGPoint(x: x, y: r.maxY))
            t += 5
        }
        ctx.stroke(minor, with: .color(CremaColor.hairline.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 0.5))
        ctx.stroke(major, with: .color(CremaColor.hairline.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 0.8))
    }

    private func drawAxisLabels(ctx: GraphicsContext, in r: CGRect) {
        // Time labels every 5s
        var t = 0.0
        while t <= totalDuration + 0.01 {
            let x = xFor(t, in: r)
            let text = Text("\(Int(t))s")
                .font(CremaFont.axisLabel)
                .foregroundColor(CremaColor.secondary)
            ctx.draw(text, at: CGPoint(x: x, y: r.maxY + 14), anchor: .center)
            t += 5
        }
        // Y axis: pressure labels in crema
        let pressureSteps = stride(from: 0, through: Int(maxPressure.rounded(.up)), by: 3).map { Double($0) }
        for bar in pressureSteps {
            let y = yPressure(bar, in: r)
            let text = Text("\(Int(bar))")
                .font(CremaFont.axisLabel)
                .foregroundColor(CremaColor.crema.opacity(0.55))
            ctx.draw(text, at: CGPoint(x: r.minX - 16, y: y), anchor: .center)
        }
        // tiny "bar" unit label at top of axis
        let unit = Text("bar")
            .font(.system(size: 8, weight: .medium, design: .rounded).smallCaps())
            .foregroundColor(CremaColor.crema.opacity(0.4))
        ctx.draw(unit, at: CGPoint(x: r.minX - 16, y: r.minY - 4), anchor: .center)

        // Right-side volume axis in cream — three ticks (0, target/2, target).
        let target = profile.targetVolumeMl.map(Double.init) ?? maxVolume
        let volSteps: [Double] = [0, target / 2, target]
        for v in volSteps {
            let y = yVolume(v, in: r)
            let text = Text("\(Int(v))")
                .font(CremaFont.axisLabel)
                .foregroundColor(CremaColor.cream.opacity(0.45))
            ctx.draw(text, at: CGPoint(x: r.maxX + 18, y: y), anchor: .center)
        }
        let volUnit = Text("mL")
            .font(.system(size: 8, weight: .medium, design: .rounded).smallCaps())
            .foregroundColor(CremaColor.cream.opacity(0.35))
        ctx.draw(volUnit, at: CGPoint(x: r.maxX + 18, y: r.minY - 4), anchor: .center)
    }

    // MARK: - Wait gaps (pump off — preinfusion bloom etc.)

    private func drawWaitGaps(ctx: GraphicsContext, in r: CGRect) {
        var cursor = 0.0
        for stage in profile.stages {
            cursor += stage.duration
            if stage.waitAfter > 0 {
                let x0 = xFor(cursor, in: r)
                let x1 = xFor(cursor + stage.waitAfter, in: r)
                let rect = CGRect(x: x0, y: r.minY, width: x1 - x0, height: r.height)
                // Soft inner fill + crisper top/bottom edge
                ctx.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [
                        CremaColor.waitGray.opacity(0.04),
                        CremaColor.waitGray.opacity(0.22),
                        CremaColor.waitGray.opacity(0.04)
                    ]),
                    startPoint: CGPoint(x: 0, y: r.minY),
                    endPoint:   CGPoint(x: 0, y: r.maxY)))
            }
            cursor += stage.waitAfter
        }
    }

    // MARK: - Ghost profile (target)

    private func drawGhostProfile(ctx: GraphicsContext, in r: CGRect) {
        // Iterate stages directly and draw each as one explicit horizontal segment.
        // This is the *target* — a step function, by definition. Densely sampling
        // BrewProfile.pressure(at:) used to produce a one-sample "leak" from the
        // prior stage's setpoint at every same-priority transition (e.g. the
        // PREINFUSE 6.1 bar briefly showing at the start of SOAK 2.3 bar).
        let style = StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
        var cursor = 0.0
        for stage in profile.stages {
            let stageEnd = cursor + stage.duration
            let x0 = xFor(cursor, in: r)
            let x1 = xFor(stageEnd, in: r)

            if stage.priority == .pressure && stage.pressureBar > 0 {
                let y = yPressure(stage.pressureBar, in: r)
                var p = Path()
                p.move(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x1, y: y))
                ctx.stroke(p, with: .color(CremaColor.crema.opacity(0.42)), style: style)
            }
            if stage.priority == .flow && stage.flowMlPerSec > 0 {
                let y = yFlow(stage.flowMlPerSec, in: r)
                var p = Path()
                p.move(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x1, y: y))
                ctx.stroke(p, with: .color(CremaColor.matcha.opacity(0.42)), style: style)
            }
            cursor = stageEnd + stage.waitAfter
        }
    }

    // MARK: - Live series

    private func drawLiveSeries(ctx: GraphicsContext, in r: CGRect) {
        guard samples.count > 1 else { return }

        // Build the three live paths from sample points, smoothed with Catmull-Rom
        // so the 3.4Hz × 0.1-bar-quantized data renders as silky curves instead of
        // right-angle staircases. The cursor dots still land on the raw sample values.
        let pressurePts = samples.map { CGPoint(x: xFor($0.t, in: r),
                                                 y: yPressure($0.pressureBar, in: r)) }
        let flowPts     = samples.map { CGPoint(x: xFor($0.t, in: r),
                                                 y: yFlow($0.flowMlPerSec, in: r)) }
        let volumePts   = samples.map { CGPoint(x: xFor($0.t, in: r),
                                                 y: yVolume($0.volumeMl, in: r)) }
        // Pre-filter widths tuned to each series: pressure/flow lightly so transitions
        // stay crisp; volume more aggressively because its quantization is more visible.
        let pressureLine = Path.smoothLine(through: pressurePts.ySmoothed(window: 3))
        let flowLine     = Path.smoothLine(through: flowPts.ySmoothed(window: 3))
        let volumeLine   = Path.smoothLine(through: volumePts.ySmoothed(window: 5))

        // Flow area fill — subtle gradient underneath
        var flowFill = flowLine
        flowFill.addLine(to: CGPoint(x: xFor(samples.last!.t, in: r), y: r.maxY))
        flowFill.addLine(to: CGPoint(x: xFor(samples.first!.t, in: r), y: r.maxY))
        flowFill.closeSubpath()
        ctx.fill(flowFill, with: .linearGradient(
            Gradient(colors: [CremaColor.matcha.opacity(0.35), CremaColor.matcha.opacity(0.0)]),
            startPoint: CGPoint(x: 0, y: r.minY),
            endPoint:   CGPoint(x: 0, y: r.maxY)))

        // Glow underlayer (blur) — gives the live trace a Decent-like neon feel.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.stroke(pressureLine, with: .color(CremaColor.crema.opacity(0.55)),
                         style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            layer.stroke(flowLine, with: .color(CremaColor.matcha.opacity(0.45)),
                         style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }

        // Flow stroke
        ctx.stroke(flowLine, with: .color(CremaColor.matchaBright),
                   style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))

        // Pressure stroke (drawn on top — primary axis)
        ctx.stroke(pressureLine, with: .color(CremaColor.cremaBright),
                   style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))

        // Volume — solid cream line, thin but visible
        ctx.stroke(volumeLine, with: .color(CremaColor.cream.opacity(0.72)),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Playhead

    private func drawPlayhead(ctx: GraphicsContext, in r: CGRect) {
        let x = xFor(playhead, in: r).rounded() + 0.5

        // Vertical line — gradient fading toward bottom
        var line = Path()
        line.move(to: CGPoint(x: x, y: r.minY))
        line.addLine(to: CGPoint(x: x, y: r.maxY))
        ctx.stroke(line, with: .linearGradient(
            Gradient(colors: [
                CremaColor.cream.opacity(0.0),
                CremaColor.cream.opacity(0.45),
                CremaColor.cream.opacity(0.15)
            ]),
            startPoint: CGPoint(x: 0, y: r.minY),
            endPoint:   CGPoint(x: 0, y: r.maxY)),
            style: StrokeStyle(lineWidth: 1))

        // Cursor dots with strong halos
        if let s = samples.last {
            drawCursorDot(ctx: ctx, at: CGPoint(x: x, y: yPressure(s.pressureBar, in: r)),
                          color: CremaColor.cremaBright)
            drawCursorDot(ctx: ctx, at: CGPoint(x: x, y: yFlow(s.flowMlPerSec, in: r)),
                          color: CremaColor.matchaBright)
            drawCursorDot(ctx: ctx, at: CGPoint(x: x, y: yVolume(s.volumeMl, in: r)),
                          color: CremaColor.cream, small: true)
        }
    }

    private func drawCursorDot(ctx: GraphicsContext, at p: CGPoint, color: Color, small: Bool = false) {
        let outer: CGFloat = small ? 14 : 20
        let inner: CGFloat = small ? 6 : 9
        // outer halo
        ctx.fill(
            Path(ellipseIn: CGRect(x: p.x - outer/2, y: p.y - outer/2, width: outer, height: outer)),
            with: .color(color.opacity(0.22))
        )
        // mid ring
        ctx.fill(
            Path(ellipseIn: CGRect(x: p.x - inner/2 - 1, y: p.y - inner/2 - 1,
                                    width: inner + 2, height: inner + 2)),
            with: .color(CremaColor.bg)
        )
        // dot
        ctx.fill(
            Path(ellipseIn: CGRect(x: p.x - inner/2, y: p.y - inner/2, width: inner, height: inner)),
            with: .color(color)
        )
    }

    // MARK: - Value pills near the cursor

    private func drawValuePills(ctx: GraphicsContext, in r: CGRect) {
        guard let s = samples.last else { return }
        let x = xFor(playhead, in: r)

        // Decide whether pill sits to the right or left of the cursor based on room.
        let pillSide: PillSide = (x > r.maxX - 80) ? .left : .right

        drawPill(ctx: ctx, at: CGPoint(x: x, y: yPressure(s.pressureBar, in: r)),
                 text: String(format: "%.1f bar", s.pressureBar),
                 tint: CremaColor.crema, side: pillSide)
        drawPill(ctx: ctx, at: CGPoint(x: x, y: yFlow(s.flowMlPerSec, in: r)),
                 text: String(format: "%.1f mL/s", s.flowMlPerSec),
                 tint: CremaColor.matcha, side: pillSide)
    }

    private enum PillSide { case left, right }

    private func drawPill(ctx: GraphicsContext, at anchor: CGPoint, text: String,
                          tint: Color, side: PillSide) {
        let resolved = ctx.resolve(
            Text(text)
                .font(CremaFont.valuePill)
                .foregroundColor(CremaColor.cream)
        )
        let textSize = resolved.measure(in: CGSize(width: 200, height: 30))
        let pad: CGFloat = 7
        let w = textSize.width + pad * 2
        let h: CGFloat = 18

        let gap: CGFloat = 14
        let x: CGFloat = (side == .right) ? anchor.x + gap : anchor.x - gap - w
        let y: CGFloat = anchor.y - h / 2

        let rect = CGRect(x: x, y: y, width: w, height: h)
        let shape = Path(roundedRect: rect, cornerRadius: 9, style: .continuous)
        ctx.fill(shape, with: .color(tint.opacity(0.9)))
        ctx.stroke(shape, with: .color(tint.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 0.5))
        ctx.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    // MARK: - Coordinate transforms

    private func xFor(_ t: Double, in r: CGRect) -> CGFloat {
        let denom = max(0.001, totalDuration)
        return r.minX + r.width * CGFloat(t / denom)
    }
    private func yPressure(_ bar: Double, in r: CGRect) -> CGFloat {
        let clamped = max(0, min(maxPressure, bar))
        return r.maxY - r.height * CGFloat(clamped / maxPressure)
    }
    private func yFlow(_ mlps: Double, in r: CGRect) -> CGFloat {
        let clamped = max(0, min(maxFlow, mlps))
        return r.maxY - r.height * CGFloat(clamped / maxFlow)
    }
    private func yVolume(_ ml: Double, in r: CGRect) -> CGFloat {
        let clamped = max(0, min(maxVolume, ml))
        return r.maxY - r.height * CGFloat(clamped / maxVolume)
    }
}
