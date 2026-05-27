import SwiftUI
import CremaKit

/// Visual node editor — the centerpiece chart with one draggable node per stage.
/// Drag horizontally to change a stage's duration. Drag vertically to change its
/// setpoint (interpreted as pressure or flow per the stage's priority). Tap an
/// empty area of the chart to add a new stage. Tap a node to select it and
/// reveal the per-stage controls (priority toggle, pause-after, delete).
///
/// Lives alongside the list editor; both bind to the same `EditableProfile` so
/// flipping between them is instant.
struct ProfileNodeEditor: View {
    @Bindable var editing: EditableProfile
    @Binding var selectedStageID: UUID?

    @State private var draggingStageID: UUID?
    /// Per-stage drag origin captured ONCE at gesture start. Includes the
    /// starting duration so we don't read mutating state during the drag —
    /// reading `stage.duration` mid-drag created a positive-feedback loop
    /// where every tick re-inflated the next (10 px of slow drag could
    /// snowball into 45 s of movement).
    @State private var dragOrigin: (duration: Double, value: Double)?
    /// Locked `totalDuration` snapshot taken at drag start. Used to keep the
    /// chart's horizontal scale STABLE during a drag — otherwise the chart
    /// rescales under your finger as the dragged stage grows/shrinks, which
    /// feels chaotic ("expand and contract far too quickly").
    @State private var dragLockedTotalT: Double?

    /// Axis ceilings — fixed so dragging doesn't get "chased" by a rescaling
    /// axis underneath.
    private let maxPressure: Double = 9.0
    private let maxFlow: Double = 8.0
    private let nodeRadius: CGFloat = 11
    /// Gesture damping. 1.0 = 1:1 — finger movement maps directly to time/
    /// value change in the chart's coordinate scale. Earlier values were
    /// lower to compensate for a compounding-feedback bug (each tick read
    /// the just-updated stage.duration to back-calculate priorTime, which
    /// re-inflated the next tick); with that bug fixed in onChanged a
    /// straight 1:1 mapping feels tactile and predictable.
    private let dragGain: Double = 1.0

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: 4, y: 12, width: geo.size.width - 8, height: geo.size.height - 28)
            // While dragging, freeze the horizontal scale so the chart geometry
            // doesn't shift under the user's finger.
            let totalT = max(dragLockedTotalT ?? editing.totalDuration, 1)

            ZStack {
                // Backdrop: faint grid + axis ticks (no labels — keep the
                // surface clean since the user is interacting with shapes).
                Canvas { ctx, _ in
                    drawGrid(ctx: ctx, in: plot)
                    drawWaitGaps(ctx: ctx, in: plot, totalT: totalT)
                    drawCurve(ctx: ctx, in: plot, totalT: totalT)
                }
                .allowsHitTesting(false)

                // Background catches taps to *deselect* only — adding stages
                // is an explicit action via the "Add stage" button (tap-to-add
                // on dead space was too easy to trigger accidentally).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { _ in
                        if selectedStageID != nil { selectedStageID = nil }
                    }

                // Stage nodes — one per stage, positioned at the stage's end
                // (cumulative time, setpoint y) coordinate.
                ForEach(stagePositions(plot: plot, totalT: totalT), id: \.stage.id) { item in
                    StageNode(
                        priority: item.stage.priority,
                        isSelected: item.stage.id == selectedStageID,
                        isDragging: item.stage.id == draggingStageID,
                        radius: nodeRadius
                    )
                    .position(item.point)
                    .gesture(dragGesture(for: item.stage, plot: plot, totalT: totalT))
                    .onTapGesture {
                        selectedStageID = (selectedStageID == item.stage.id) ? nil : item.stage.id
                    }
                }

                // Floating value pill above the active node — only when dragging
                // or selected.
                if let item = activeStageItem(plot: plot, totalT: totalT) {
                    ValuePill(stage: item.stage)
                        .position(x: item.point.x, y: max(28, item.point.y - 30))
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.smooth(duration: 0.25), value: selectedStageID)
            .animation(.smooth(duration: 0.18), value: editing.stages.map(\.id))
            // Clip so a stage dragged past the chart's right edge can't bleed
            // visually into the recipe pane next to us in the landscape split.
            // Matches the editor card's outer corner radius (set in
            // ProfileEditView.visualEditor).
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Geometry

    private struct Positioned {
        let stage: EditableStage
        let point: CGPoint
    }

    /// For each stage, its node's `(x, y)` position — x at the cumulative
    /// time at the stage's *end*, y at the stage's active setpoint.
    private func stagePositions(plot: CGRect, totalT: Double) -> [Positioned] {
        var cursor: Double = 0
        return editing.stages.map { s in
            let end = cursor + s.duration
            let x = plot.minX + plot.width * CGFloat(end / max(totalT, 0.001))
            let y = yFor(stage: s, plot: plot)
            cursor = end + s.waitAfter
            return Positioned(stage: s, point: CGPoint(x: x, y: y))
        }
    }

    private func yFor(stage: EditableStage, plot: CGRect) -> CGFloat {
        switch stage.priority {
        case .pressure:
            let f = max(0, min(1, stage.pressureBar / maxPressure))
            return plot.maxY - plot.height * CGFloat(f)
        case .flow:
            let f = max(0, min(1, stage.flowMlPerSec / maxFlow))
            return plot.maxY - plot.height * CGFloat(f)
        }
    }

    private func activeStageItem(plot: CGRect, totalT: Double) -> Positioned? {
        let id = draggingStageID ?? selectedStageID
        guard let id else { return nil }
        return stagePositions(plot: plot, totalT: totalT).first(where: { $0.stage.id == id })
    }

    // MARK: - Drag gesture

    private func dragGesture(for stage: EditableStage, plot: CGRect, totalT: Double) -> some Gesture {
        // CRITICAL: use `.global` coordinate space. The StageNode this gesture
        // is attached to is positioned via `.position(item.point)` driven by
        // the stage's data — when we update stage.duration in onChanged, the
        // node moves, and a default-coordinate-space gesture measures
        // translation relative to the moving view, creating a positive-feedback
        // loop. Global coords are anchored to the screen so translation stays
        // stable regardless of how the view underneath moves.
        //
        // Higher minimumDistance prevents micro-jitter from registering as a
        // drag (8pt ≈ a thumb-rest twitch on iPad).
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if draggingStageID != stage.id {
                    draggingStageID = stage.id
                    selectedStageID = stage.id
                    // Capture starting STATE once. All deltas are computed
                    // from these stable values + the gesture's cumulative
                    // translation. Never re-read stage.* during the drag —
                    // that's what created the runaway feedback loop.
                    dragOrigin = (
                        duration: stage.duration,
                        value: stage.priority == .pressure ? stage.pressureBar : stage.flowMlPerSec
                    )
                    dragLockedTotalT = max(editing.totalDuration, 1)
                }
                guard let origin = dragOrigin else { return }
                let lockedT = dragLockedTotalT ?? totalT

                // Vertical drag → setpoint. dragGain dampens twitchiness.
                let dy = value.translation.height
                let valueRange = stage.priority == .pressure ? maxPressure : maxFlow
                let valueDelta = -Double(dy) / Double(plot.height) * valueRange * dragGain
                var newValue = origin.value + valueDelta
                // Coarser snap = more tactile, less jittery.
                let snap = stage.priority == .pressure ? 0.25 : 0.25
                newValue = (newValue / snap).rounded() * snap
                newValue = max(0, min(valueRange, newValue))

                // Horizontal drag → duration. cumulative translation from
                // gesture start (.global coord space below) → time, added to
                // captured starting duration. No reading of stage.duration.
                let dx = value.translation.width
                let timeDelta = Double(dx) / Double(plot.width) * lockedT * dragGain
                var newDuration = origin.duration + timeDelta
                // 1.0s snap reads as deliberate without feeling sticky.
                newDuration = max(0.5, min(60, (newDuration / 1.0).rounded() * 1.0))

                // Apply.
                stage.duration = newDuration
                if stage.priority == .pressure {
                    stage.pressureBar = newValue
                } else {
                    stage.flowMlPerSec = newValue
                }
            }
            .onEnded { _ in
                draggingStageID = nil
                dragOrigin = nil
                dragLockedTotalT = nil
            }
    }

    private func cumulativeTimeAtEnd(of stage: EditableStage) -> Double {
        var t: Double = 0
        for s in editing.stages {
            t += s.duration
            if s.id == stage.id { return t }
            t += s.waitAfter
        }
        return t
    }

    // MARK: - Canvas drawing helpers

    private func drawGrid(ctx: GraphicsContext, in r: CGRect) {
        var path = Path()
        // Horizontal: 4 divisions
        for i in 0...4 {
            let y = r.minY + r.height * CGFloat(i) / 4
            path.move(to: CGPoint(x: r.minX, y: y))
            path.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        ctx.stroke(path, with: .color(CremaColor.hairline.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 0.5))
    }

    private func drawWaitGaps(ctx: GraphicsContext, in r: CGRect, totalT: Double) {
        var cursor: Double = 0
        for stage in editing.stages {
            cursor += stage.duration
            if stage.waitAfter > 0 {
                let x0 = r.minX + r.width * CGFloat(cursor / totalT)
                let x1 = r.minX + r.width * CGFloat((cursor + stage.waitAfter) / totalT)
                let rect = CGRect(x: x0, y: r.minY, width: x1 - x0, height: r.height)
                ctx.fill(Path(rect), with: .color(CremaColor.waitGray.opacity(0.18)))
            }
            cursor += stage.waitAfter
        }
    }

    /// Draws the profile curve as horizontal segments per stage, in the stage's
    /// priority color. Same "ghost target" rendering as ShotChart's drawGhostProfile.
    private func drawCurve(ctx: GraphicsContext, in r: CGRect, totalT: Double) {
        var cursor: Double = 0
        for stage in editing.stages {
            let endT = cursor + stage.duration
            let x0 = r.minX + r.width * CGFloat(cursor / totalT)
            let x1 = r.minX + r.width * CGFloat(endT / totalT)
            let y = yFor(stage: stage, plot: r)
            var p = Path()
            p.move(to: CGPoint(x: x0, y: y))
            p.addLine(to: CGPoint(x: x1, y: y))
            let color = stage.priority == .pressure ? CremaColor.crema : CremaColor.matcha
            ctx.stroke(p, with: .color(color.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            cursor = endT + stage.waitAfter
        }
    }
}

// MARK: - Node handle

private struct StageNode: View {
    let priority: BrewStage.Priority
    let isSelected: Bool
    let isDragging: Bool
    let radius: CGFloat

    private var color: Color {
        priority == .pressure ? CremaColor.crema : CremaColor.matcha
    }

    var body: some View {
        ZStack {
            // Halo — bigger and brighter when selected/dragging.
            Circle()
                .fill(color.opacity(isSelected || isDragging ? 0.45 : 0.2))
                .frame(width: (isSelected || isDragging) ? radius * 4 : radius * 2.4,
                       height: (isSelected || isDragging) ? radius * 4 : radius * 2.4)
                .blur(radius: isSelected || isDragging ? 8 : 3)
            // Outer ring
            Circle()
                .stroke(color.opacity(isSelected ? 1.0 : 0.7), lineWidth: isSelected ? 2 : 1)
                .frame(width: radius * 2.2, height: radius * 2.2)
            // Filled center — dark to read clearly against the curve segment behind.
            Circle()
                .fill(CremaColor.bg)
                .frame(width: radius * 1.6, height: radius * 1.6)
            Circle()
                .fill(color)
                .frame(width: radius, height: radius)
        }
        .scaleEffect(isDragging ? 1.15 : 1.0)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .animation(.snappy(duration: 0.12), value: isDragging)
        .frame(width: radius * 4, height: radius * 4)        // tap target
        .contentShape(Circle())
    }
}

// MARK: - Floating value pill

private struct ValuePill: View {
    let stage: EditableStage

    private var text: String {
        let value = stage.priority == .pressure
            ? String(format: "%.1f bar", stage.pressureBar)
            : String(format: "%.1f mL/s", stage.flowMlPerSec)
        return "\(value)  ·  \(stage.duration.formatted(.number.precision(.fractionLength(0...1)))) s"
    }
    private var accent: Color {
        stage.priority == .pressure ? CremaColor.crema : CremaColor.matcha
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(CremaColor.bg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(accent))
            .overlay(Capsule().strokeBorder(CremaColor.cream.opacity(0.15), lineWidth: 0.5))
            .shadow(color: accent.opacity(0.5), radius: 6)
    }
}

// MARK: - Selected-stage action bar (priority toggle / delete)

/// Floating bar that appears under the chart when a node is selected. Holds
/// the priority toggle + pause-after slider + delete button — the actions
/// that don't map directly to a drag gesture.
struct SelectedStageBar: View {
    @Bindable var stage: EditableStage
    let canDelete: Bool
    let onDelete: () -> Void
    let onDeselect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(stage.label.isEmpty ? "Stage" : stage.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Spacer()
                Picker("Priority", selection: $stage.priority) {
                    Text("Pressure").tag(BrewStage.Priority.pressure)
                    Text("Flow").tag(BrewStage.Priority.flow)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            HStack(spacing: 12) {
                Text("Pause after")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
                Slider(value: $stage.waitAfter, in: 0...20, step: 0.5)
                    .tint(CremaColor.secondary)
                Text(stage.waitAfter == 0 ? "none" : String(format: "%.1f s", stage.waitAfter))
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
                    .frame(width: 56, alignment: .trailing)
            }

            HStack(spacing: 10) {
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete stage")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CremaColor.danger)
                }
                Spacer()
                Button(action: onDeselect) {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.crema)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
