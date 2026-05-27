import SwiftUI
import CremaKit

/// Suggestions sheet — shown after "Save & Suggest" if the rule engine
/// produced any non-dismissed suggestions. Each card explains its reasoning
/// (no magic) and offers Apply / Save as variant / "Don't show again".
struct SuggestionsSheet: View {
    let profile: BrewProfile
    let log: ShotLog
    let tipPreferences: TipPreferences
    let library: ProfileLibrary
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [TweakSuggestion] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .safeAreaPadding(.top)
                if suggestions.isEmpty {
                    emptyState
                } else {
                    intro
                    ForEach(suggestions) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            onApply: { apply(suggestion, asNew: false) },
                            onSaveAsVariant: { apply(suggestion, asNew: true) },
                            onDismissForever: {
                                tipPreferences.dismiss(suggestion.id)
                                suggestions.removeAll { $0.id == suggestion.id }
                                if suggestions.isEmpty { dismissAll() }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 540, minHeight: 480, idealHeight: 620)
        #endif
        .onAppear {
            suggestions = ProfileTweakSuggester
                .suggest(for: profile, log: log)
                .filter { !tipPreferences.isDismissed($0.id) }
        }
    }

    private var header: some View {
        HStack {
            tappableHeaderButton("Close", role: .secondary) { dismissAll() }
            Spacer()
            Text("Tweak suggestions")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            tappableHeaderButton(" ", role: .primary, action: {})   // visual symmetry
                .opacity(0)
                .disabled(true)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From this shot…")
                .font(.system(size: 11, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.6)
                .foregroundStyle(CremaColor.secondary)
            Text(shotSummary)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(CremaColor.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shotSummary: String {
        var bits: [String] = []
        if let y = log.measuredYieldG {
            bits.append("\(formatNum(y)) g / \(formatNum(log.targetYieldG)) g target")
        }
        bits.append("\(Int(log.actualTimeS)) s")
        if log.taste.acidity <= -0.4 { bits.append("sour") }
        if log.taste.acidity >=  0.4 { bits.append("bitter") }
        if log.taste.strength <= -0.4 { bits.append("weak") }
        if log.taste.strength >=  0.4 { bits.append("strong") }
        return bits.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(CremaColor.connected)
            Text("Looks balanced")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text("No tweaks suggested — keep brewing!")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func formatNum(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func apply(_ suggestion: TweakSuggestion, asNew: Bool) {
        let tweaked = suggestion.apply(to: profile)
        if asNew {
            // Save a variant — clone with a new id + ` (v2)`-style suffix.
            let variantName = nextVariantName(of: profile.name)
            let variant = BrewProfile(
                id: UUID(), name: variantName,
                stages: tweaked.stages,
                mode: tweaked.mode, target: tweaked.target,
                directExtract: tweaked.directExtract,
                variableFlow: tweaked.variableFlow,
                targetVolumeMl: tweaked.targetVolumeMl,
                targetWeightG: tweaked.targetWeightG,
                autoLink: tweaked.autoLink,
                grinder: tweaked.grinder
            )
            library.add(variant, setActive: true)
        } else {
            library.update(tweaked)
        }
        dismissAll()
    }

    private func nextVariantName(of base: String) -> String {
        // "Classic Espresso" → "Classic Espresso v2", or v3 if v2 exists, etc.
        let trimmed = base.replacingOccurrences(of: #" v\d+$"#, with: "", options: .regularExpression)
        for n in 2...99 {
            let candidate = "\(trimmed) v\(n)"
            if !library.profiles.contains(where: { $0.name == candidate }) { return candidate }
        }
        return "\(trimmed) tweak"
    }

    private func dismissAll() {
        dismiss()
        onClose()
    }
}

// MARK: - Suggestion card

private struct SuggestionCard: View {
    let suggestion: TweakSuggestion
    let onApply: () -> Void
    let onSaveAsVariant: () -> Void
    let onDismissForever: () -> Void

    private var confidenceLabel: String {
        switch suggestion.confidence {
        case .high:   "High confidence"
        case .medium: "Worth trying"
        case .low:    "Possibility"
        }
    }
    private var confidenceColor: Color {
        switch suggestion.confidence {
        case .high:   CremaColor.crema
        case .medium: CremaColor.matcha
        case .low:    CremaColor.secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(confidenceColor)
                    .frame(width: 6, height: 6)
                Text(confidenceLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                    .tracking(0.6)
                    .foregroundStyle(confidenceColor)
                Spacer()
                Menu {
                    Button("Don't show this tip again", systemImage: "eye.slash",
                           role: .destructive, action: onDismissForever)
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
            }
            Text(suggestion.headline)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text(suggestion.reason)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(CremaColor.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: onSaveAsVariant) {
                    Text("Save as variant")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(
                            Capsule().fill(.ultraThinMaterial)
                                .overlay(Capsule().strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onApply) {
                    Text("Apply")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.bg)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 38)
                        .background(Capsule().fill(CremaColor.crema))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
        )
    }
}

// MARK: - Shared header button (same shape as ShotFeedbackSheet)

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
