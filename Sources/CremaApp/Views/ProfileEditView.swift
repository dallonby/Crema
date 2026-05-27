import SwiftUI
import CremaKit

/// Multi-stage profile editor. Top: live chart preview. Middle: recipe basics
/// (name, dose, yield, ratio). Bottom: an ordered list of stage cards — each
/// collapsible, each independently flow- or pressure-priority, each with its
/// own duration / setpoint / wait-after / label.
///
/// Stages can be added, deleted, and reordered via card menus. The chart on
/// top rebuilds on every edit so the curve reshapes in real time.
struct ProfileEditView: View {
    @Bindable var editing: EditableProfile
    let onSave: (BrewProfile) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    enum Mode: String, Hashable { case visual, list }
    @State private var mode: Mode = .visual
    @State private var selectedStageID: UUID?

    var body: some View {
        GeometryReader { geo in
            // Wide enough for a side-by-side layout? Triggers on iPad landscape
            // and macOS, falls back to stacked on iPhone / iPad portrait.
            let isWide = geo.size.width > 820 && mode == .visual
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 10)
                    .safeAreaPadding(.top)

                if isWide {
                    splitLayout
                } else {
                    stackedLayout
                }
            }
            .background(CremaColor.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 640, idealHeight: 760)
        #endif
    }

    /// Stacked vertical scroll — iPhone, iPad portrait, and List mode.
    private var stackedLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                modePicker
                if mode == .visual {
                    visualEditor
                } else {
                    preview
                }
                recipeSection
                grinderSection
                if mode == .list {
                    stagesSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    /// Landscape split — chart fills the left ~60%, controls scroll on the
    /// right ~40%. Only used in Visual mode where the chart is the hero.
    private var splitLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                modePicker
                visualEditor
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recipeSection
                    grinderSection
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
            .frame(width: 380)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Label("Visual", systemImage: "chart.xyaxis.line").tag(Mode.visual)
            Label("List", systemImage: "list.bullet").tag(Mode.list)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var visualEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("PROFILE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
                Spacer()
                Text(visualHint)
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.secondary)
                Button(action: {
                    editing.addStage()
                    selectedStageID = editing.stages.last?.id
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add stage")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(CremaColor.crema)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(CremaColor.crema.opacity(0.16))
                            .overlay(Capsule().strokeBorder(CremaColor.crema.opacity(0.35), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
            }
            ProfileNodeEditor(editing: editing, selectedStageID: $selectedStageID)
                .frame(height: 280)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
                )

            if let selected = editing.stages.first(where: { $0.id == selectedStageID }) {
                SelectedStageBar(
                    stage: selected,
                    canDelete: editing.canRemoveAnyStage,
                    onDelete: {
                        let id = selected.id
                        editing.remove(stageID: id)
                        selectedStageID = nil
                    },
                    onDeselect: { selectedStageID = nil }
                )
            } else {
                Text("Tap a node to edit it · Drag to reshape · Tap empty space to add a stage")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .animation(.smooth(duration: 0.22), value: selectedStageID)
    }

    private var visualHint: String {
        let compiled = editing.compile()
        return "\(compiled.stages.count) stage\(compiled.stages.count == 1 ? "" : "s")  ·  \(Int(compiled.totalDuration)) s  ·  \(Int(compiled.targetVolumeMl ?? 0)) mL"
    }

    // MARK: - Header / preview / recipe

    private var header: some View {
        HStack {
            sheetHeaderButton("Cancel", primary: false) {
                onCancel(); dismiss()
            }
            Spacer()
            Text("Edit profile")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            sheetHeaderButton("Save", primary: true) {
                onSave(editing.compile())
                dismiss()
            }
        }
    }

    /// 44pt-tall hit target so taps reliably land — bare-text buttons in the
    /// header were "super flakey" (user report).
    @ViewBuilder
    private func sheetHeaderButton(_ label: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: primary ? .semibold : .regular, design: .rounded))
                .foregroundStyle(primary ? CremaColor.crema : CremaColor.secondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        let compiled = editing.compile()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PREVIEW")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
                Spacer()
                Text(String(format: "%.0f s · %.0f mL target · %d stage\(compiled.stages.count == 1 ? "" : "s")",
                            compiled.totalDuration,
                            Double(compiled.targetVolumeMl ?? 0),
                            compiled.stages.count))
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.secondary)
            }
            ShotChart(
                samples: [][...],
                profile: compiled,
                playhead: -1,
                totalDuration: max(compiled.totalDuration, 1)
            )
            .frame(height: 200)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
            )
        }
    }

    @ViewBuilder
    private var recipeSection: some View {
        SectionHeader("Recipe")
        EditorRow(label: "Name") {
            TextField("Profile name", text: $editing.name)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(CremaColor.cream)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CremaColor.surface.opacity(0.6))
                )
        }
        SliderRow(label: "Dose", value: $editing.doseG, range: 12...22, step: 0.5,
                  format: { String(format: "%.1f g", $0) }, accent: CremaColor.cream)
        // Yield range scales with dose: 1:1 ristretto to 1:10 long shot.
        // Dynamic max so heavier doses can reach correspondingly heavier yields
        // (22 g dose → up to 220 g yield) without hitting an arbitrary cap.
        SliderRow(label: "Target yield", value: $editing.targetYieldG,
                  range: editing.doseG ... editing.doseG * 10, step: 1,
                  format: { String(format: "%.0f g", $0) }, accent: CremaColor.cream)
            // Auto-clamp yield into the new range when dose changes — otherwise
            // a previously-set yield can sit outside the slider's bounds, leaving
            // the thumb visually pegged until the user touches it.
            .onChange(of: editing.doseG) { _, newDose in
                let lo = newDose
                let hi = newDose * 10
                editing.targetYieldG = min(hi, max(lo, editing.targetYieldG))
            }
        Text(String(format: "Ratio 1 : %.2f", editing.targetYieldG / max(editing.doseG, 1)))
            .font(.system(size: 11, design: .rounded).monospacedDigit())
            .foregroundStyle(CremaColor.secondary)
    }

    // MARK: - Grinder section

    @ViewBuilder
    private var grinderSection: some View {
        HStack {
            SectionHeader("Grinder")
            Spacer()
            Toggle("", isOn: $editing.grinderEnabled)
                .labelsHidden()
                .tint(CremaColor.crema)
        }
        if editing.grinderEnabled {
            VStack(alignment: .leading, spacing: 12) {
                SliderRow(label: "Grind size",
                          value: $editing.grinderSizeMicrons,
                          range: 30...500, step: 1,
                          format: { String(format: "%.0f µm", $0) },
                          accent: CremaColor.crema)
                SliderRow(label: "Motor speed",
                          value: $editing.grinderRPM,
                          range: 200...1200, step: 10,
                          format: { String(format: "%.0f rpm", $0) },
                          accent: CremaColor.matcha)
                HStack {
                    Toggle("Single-dose mode", isOn: $editing.grinderSingleDose)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                        .tint(CremaColor.crema)
                    Spacer()
                }
                Text("Settings are sent to the machine when you tap **Set grinder** before brewing.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Text("Save grinder settings with this profile to push grind size and RPM to your machine before brewing.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
        }
    }

    // MARK: - Stages section

    @ViewBuilder
    private var stagesSection: some View {
        HStack {
            SectionHeader("Stages")
            Spacer()
            Button(action: { editing.addStage() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add stage")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(CremaColor.crema)
            }
            .buttonStyle(.plain)
        }

        VStack(spacing: 10) {
            ForEach(Array(editing.stages.enumerated()), id: \.element.id) { index, stage in
                StageCard(
                    stage: stage,
                    index: index,
                    stageCount: editing.stages.count,
                    canDelete: editing.canRemoveAnyStage,
                    onMoveUp:   { editing.moveStage(id: stage.id, by: -1) },
                    onMoveDown: { editing.moveStage(id: stage.id, by:  1) },
                    onDelete:   { editing.remove(stageID: stage.id) }
                )
            }
        }
    }
}

// MARK: - Stage card

private struct StageCard: View {
    @Bindable var stage: EditableStage
    let index: Int
    let stageCount: Int
    let canDelete: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    private var accent: Color {
        stage.priority == .pressure ? CremaColor.crema : CremaColor.matcha
    }

    private var summaryText: String {
        let value = stage.priority == .pressure
            ? String(format: "%.1f bar", stage.pressureBar)
            : String(format: "%.1f mL/s", stage.flowMlPerSec)
        let main = "\(value) · \(stage.duration.formatted(.number.precision(.fractionLength(0...1)))) s"
        if stage.waitAfter > 0 {
            return main + " + \(stage.waitAfter.formatted(.number.precision(.fractionLength(0...1)))) s wait"
        }
        return main
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedHeader
            if stage.isExpanded {
                Divider()
                    .overlay(CremaColor.hairline.opacity(0.5))
                expandedBody
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(alignment: .leading) {
            // Colored left edge indicates priority at a glance.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 6)
                .padding(.leading, 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var collapsedHeader: some View {
        // Not a Button — using onTapGesture so the inner Menu can capture
        // its own taps without nested-Button hit-test conflicts (the Menu
        // would swallow the row's tap otherwise on iOS).
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.secondary)
                .frame(width: 16)
                .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stage.label.isEmpty ? "Stage \(index + 1)" : stage.label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                        .lineLimit(1)
                    Text(stage.priority == .pressure ? "PRESSURE" : "FLOW")
                        .font(.system(size: 9, weight: .semibold, design: .rounded).smallCaps())
                        .tracking(0.6)
                        .foregroundStyle(accent)
                }
                Text(summaryText)
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { stage.isExpanded.toggle() }

            Spacer(minLength: 0)
                .contentShape(Rectangle())
                .onTapGesture { stage.isExpanded.toggle() }

            Menu {
                if index > 0 {
                    Button("Move up", systemImage: "arrow.up", action: onMoveUp)
                }
                if index < stageCount - 1 {
                    Button("Move down", systemImage: "arrow.down", action: onMoveDown)
                }
                if canDelete {
                    Divider()
                    Button("Delete stage", systemImage: "trash", role: .destructive, action: onDelete)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CremaColor.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CremaColor.secondary)
                .rotationEffect(.degrees(stage.isExpanded ? 90 : 0))
                .frame(width: 28, height: 32)
                .contentShape(Rectangle())
                .onTapGesture { stage.isExpanded.toggle() }
                .animation(.snappy(duration: 0.18), value: stage.isExpanded)
        }
        .padding(.vertical, 12)
        .padding(.trailing, 4)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Priority segmented picker — one of the two key controls.
            Picker("Priority", selection: $stage.priority) {
                Text("Pressure").tag(BrewStage.Priority.pressure)
                Text("Flow").tag(BrewStage.Priority.flow)
            }
            .pickerStyle(.segmented)

            // Setpoint slider — only one is meaningful depending on priority.
            // We always render the active one so the row doesn't reshape on
            // priority toggle.
            if stage.priority == .pressure {
                SliderRow(label: "Pressure", value: $stage.pressureBar,
                          range: 0...9, step: 0.1,
                          format: { String(format: "%.1f bar", $0) },
                          accent: CremaColor.crema)
            } else {
                SliderRow(label: "Flow", value: $stage.flowMlPerSec,
                          range: 0.1...8.0, step: 0.1,
                          format: { String(format: "%.1f mL/s", $0) },
                          accent: CremaColor.matcha)
            }

            SliderRow(label: "Duration", value: $stage.duration,
                      range: 1...60, step: 0.5,
                      format: { String(format: "%.1f s", $0) },
                      accent: CremaColor.cream)

            SliderRow(label: "Pause after", value: $stage.waitAfter,
                      range: 0...30, step: 0.5,
                      format: { $0 == 0 ? "none" : String(format: "%.1f s", $0) },
                      accent: CremaColor.secondary)

            EditorRow(label: "Label") {
                TextField("Stage label", text: $stage.label)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CremaColor.surface.opacity(0.6))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Reusable bits

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded).smallCaps())
            .tracking(0.6)
            .foregroundStyle(CremaColor.secondary)
            .padding(.top, 4)
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Spacer()
                Text(format(value))
                    .font(.system(size: 13, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
            }
            Slider(value: $value, in: range, step: step)
                .tint(accent)
        }
    }
}

private struct EditorRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.6)
                .foregroundStyle(CremaColor.secondary)
            content()
        }
    }
}
