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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                    .safeAreaPadding(.top)
                preview
                recipeSection
                stagesSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 540, minHeight: 640, idealHeight: 800)
        #endif
    }

    // MARK: - Header / preview / recipe

    private var header: some View {
        HStack {
            Button("Cancel", action: { onCancel(); dismiss() })
                .foregroundStyle(CremaColor.secondary)
            Spacer()
            Text("Edit profile")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            Button("Save") {
                onSave(editing.compile())
                dismiss()
            }
            .fontWeight(.semibold)
            .foregroundStyle(CremaColor.crema)
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
        SliderRow(label: "Target yield", value: $editing.targetYieldG, range: 18...80, step: 1,
                  format: { String(format: "%.0f g", $0) }, accent: CremaColor.cream)
        Text(String(format: "Ratio 1 : %.2f", editing.targetYieldG / max(editing.doseG, 1)))
            .font(.system(size: 11, design: .rounded).monospacedDigit())
            .foregroundStyle(CremaColor.secondary)
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
