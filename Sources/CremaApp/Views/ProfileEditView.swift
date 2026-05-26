import SwiftUI
import CremaKit

/// Guided profile editor — sliders bound to an `EditableProfile` with a live
/// preview chart on top so you see the curve reshape as you drag. Compiles
/// into a real `BrewProfile` on Save.
///
/// Deliberately opinionated for v1: fixed shape of preinfuse → bloom → extract
/// → tail, each stage optional via zeroing its slider. The full node editor
/// will land later for profiles outside this shape.
struct ProfileEditView: View {
    @Bindable var editing: EditableProfile
    let onSave: (BrewProfile) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                    .safeAreaPadding(.top)   // iPhone Dynamic Island / notch
                preview
                nameField
                doseAndYield
                preinfuseSection
                bloomSection
                extractSection
                tailSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 600, idealHeight: 760)
        #endif
    }

    // MARK: - Sections

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
        .padding(.bottom, 6)
    }

    /// Mini chart preview — shows just the ghost profile (no live trace) so the
    /// user sees what curve they're authoring. Updates instantly as sliders move.
    private var preview: some View {
        let compiled = editing.compile()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PREVIEW")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(CremaColor.secondary)
                Spacer()
                Text(String(format: "%.0f s · %.0f mL target", compiled.totalDuration, Double(compiled.targetVolumeMl ?? 0)))
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.secondary)
            }
            ShotChart(
                samples: [][...],          // ghost-only — no live trace in editor
                profile: compiled,
                playhead: -1,              // off-chart so no playhead/dots render
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

    private var nameField: some View {
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
    }

    @ViewBuilder
    private var doseAndYield: some View {
        SectionHeader("Recipe")
        SliderRow(label: "Dose", value: $editing.doseG, range: 12...22, step: 0.5,
                  format: { String(format: "%.1f g", $0) }, accent: CremaColor.cream)
        SliderRow(label: "Target yield", value: $editing.targetYieldG, range: 18...80, step: 1,
                  format: { String(format: "%.0f g", $0) }, accent: CremaColor.cream)
        Text(String(format: "Ratio 1 : %.2f", editing.targetYieldG / max(editing.doseG, 1)))
            .font(.system(size: 11, design: .rounded).monospacedDigit())
            .foregroundStyle(CremaColor.secondary)
    }

    @ViewBuilder
    private var preinfuseSection: some View {
        SectionHeader("Preinfusion")
        SliderRow(label: "Pressure", value: $editing.preinfusionBar, range: 0...9, step: 0.1,
                  format: { String(format: "%.1f bar", $0) }, accent: CremaColor.crema)
        SliderRow(label: "Time", value: $editing.preinfusionTime, range: 0...15, step: 0.5,
                  format: { String(format: "%.1f s", $0) }, accent: CremaColor.crema)
    }

    @ViewBuilder
    private var bloomSection: some View {
        SectionHeader("Bloom (pump off)")
        SliderRow(label: "Time", value: $editing.bloomTime, range: 0...20, step: 0.5,
                  format: { String(format: "%.1f s", $0) }, accent: CremaColor.secondary)
    }

    @ViewBuilder
    private var extractSection: some View {
        SectionHeader("Extract")
        SliderRow(label: "Flow", value: $editing.extractFlow, range: 0.5...5.0, step: 0.1,
                  format: { String(format: "%.1f mL/s", $0) }, accent: CremaColor.matcha)
        SliderRow(label: "Time", value: $editing.extractTime, range: 5...40, step: 0.5,
                  format: { String(format: "%.1f s", $0) }, accent: CremaColor.matcha)
    }

    @ViewBuilder
    private var tailSection: some View {
        SectionHeader("Tail (decline)")
        SliderRow(label: "Pressure", value: $editing.tailBar, range: 0...3, step: 0.1,
                  format: { String(format: "%.1f bar", $0) }, accent: CremaColor.crema)
        SliderRow(label: "Time", value: $editing.tailTime, range: 0...10, step: 0.5,
                  format: { String(format: "%.1f s", $0) }, accent: CremaColor.crema)
    }
}

// MARK: - Building blocks

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded).smallCaps())
            .tracking(0.6)
            .foregroundStyle(CremaColor.secondary)
            .padding(.top, 6)
    }
}

/// Slider with a colored thumb, a value readout, and a label.
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
