import SwiftUI
import CremaKit

/// Post-brew feedback sheet — "How was it?". Collects the user's measured yield,
/// taste, and optional comments, then either records the shot to history
/// (skipping suggestions) or hands off to the suggestions sheet.
///
/// Designed for the non-Bluetooth-scale crowd: the friction of manually
/// weighing the cup becomes a learning loop. For Acaia owners later we'll
/// auto-fill the measured yield from the connected scale.
struct ShotFeedbackSheet: View {
    let profile: BrewProfile
    let actualTimeS: Double
    let curve: [ShotLog.Sample]

    let history: ShotHistory
    let tipPreferences: TipPreferences
    let library: ProfileLibrary

    @Environment(\.dismiss) private var dismiss

    @State private var yieldText: String = ""
    @State private var acidity: Double = 0
    @State private var strength: Double = 0
    @State private var comments: String = ""

    @State private var pendingSuggestions: [TweakSuggestion] = []
    @State private var savedLog: ShotLog?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                    .safeAreaPadding(.top)
                summaryStrip
                yieldSection
                tasteSection
                commentsSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 520, idealHeight: 640)
        #endif
        .sheet(item: $savedLog) { log in
            SuggestionsSheet(
                profile: profile,
                log: log,
                tipPreferences: tipPreferences,
                library: library,
                onClose: { dismiss() }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            tappableHeaderButton("Skip", role: .secondary) {
                // Skip means don't record this shot at all.
                dismiss()
            }
            Spacer()
            Text("How was it?")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            tappableHeaderButton(needsSuggestions ? "Save & Suggest" : "Save", role: .primary) {
                let log = makeLog()
                history.record(log)
                if needsSuggestions {
                    pendingSuggestions = ProfileTweakSuggester.suggest(for: profile, log: log)
                        .filter { !tipPreferences.isDismissed($0.id) }
                    if pendingSuggestions.isEmpty {
                        dismiss()
                    } else {
                        savedLog = log   // triggers the suggestions sheet
                    }
                } else {
                    dismiss()
                }
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 18) {
            stat(label: "Profile", value: profile.name)
            stat(label: "Target", value: "\(Int(profile.targetVolumeMl ?? 0)) g")
            stat(label: "Time", value: String(format: "%.0f s", actualTimeS))
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.6)
                .foregroundStyle(CremaColor.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.cream)
        }
    }

    @ViewBuilder
    private var yieldSection: some View {
        SectionHeader("Yield")
        HStack(spacing: 10) {
            TextField("Measured weight", text: $yieldText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.cream)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CremaColor.surface.opacity(0.6))
                )
            Text("g")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
            Spacer()
            Text("target \(Int(profile.targetVolumeMl ?? 0)) g")
                .font(.system(size: 11, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.secondary)
        }
    }

    @ViewBuilder
    private var tasteSection: some View {
        SectionHeader("Taste")
        VStack(alignment: .leading, spacing: 10) {
            TasteSegmented(
                value: $acidity,
                left: "Sour", middle: "Balanced", right: "Bitter"
            )
            TasteSegmented(
                value: $strength,
                left: "Weak", middle: "Balanced", right: "Strong"
            )
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        SectionHeader("Notes")
        TextField("Optional — e.g. fresh beans, channelling, …",
                  text: $comments, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(CremaColor.cream)
            .lineLimit(2...5)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CremaColor.surface.opacity(0.6))
            )
    }

    // MARK: - Helpers

    private var measuredYield: Double? {
        Double(yieldText.replacingOccurrences(of: ",", with: "."))
    }

    private var needsSuggestions: Bool {
        // Only run the rule engine if we have something to react to.
        measuredYield != nil || abs(acidity) > 0.25 || abs(strength) > 0.25
    }

    private func makeLog() -> ShotLog {
        ShotLog(
            timestamp: .now,
            profileID: profile.id,
            profileName: profile.name,
            targetYieldG: Double(profile.targetVolumeMl ?? 0),
            measuredYieldG: measuredYield,
            actualTimeS: actualTimeS,
            taste: .init(acidity: acidity, strength: strength),
            comments: comments,
            curve: curve
        )
    }
}

// MARK: - Reusable bits

/// Header button with a 44-pt-tall hit target — fixes the "Cancel is super
/// flakey" problem we hit when these were bare Text labels.
private enum HeaderButtonRole { case primary, secondary }

@ViewBuilder
private func tappableHeaderButton(_ label: String, role: HeaderButtonRole, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 14, weight: role == .primary ? .semibold : .regular, design: .rounded))
            .foregroundStyle(role == .primary ? CremaColor.crema : CremaColor.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

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

/// Three-state segmented picker for taste axes. Center = balanced (value 0),
/// edges = ±1.
private struct TasteSegmented: View {
    @Binding var value: Double
    let left: String
    let middle: String
    let right: String

    var body: some View {
        HStack(spacing: 6) {
            chip(label: left,   tagValue: -1)
            chip(label: middle, tagValue: 0)
            chip(label: right,  tagValue: 1)
        }
    }

    private func chip(label: String, tagValue: Double) -> some View {
        let selected = abs(value - tagValue) < 0.25
        return Button(action: { value = tagValue }) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(selected ? CremaColor.bg : CremaColor.cream)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? CremaColor.crema : CremaColor.surface.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
