import SwiftUI
import CremaKit

/// Browse + manage past brews. List of `ShotLog` rows with timestamp, profile
/// name snapshot, yield delta, taste tags, and inline comments. Per-row delete
/// via the menu, footer "Clear all" for the nuclear option, and an inline
/// comment editor.
struct ShotHistoryView: View {
    @Bindable var history: ShotHistory
    @Environment(\.dismiss) private var dismiss

    @State private var pendingClearAll = false
    @State private var editingShotID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
                .safeAreaPadding(.top)
            ScrollView {
                if history.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 10) {
                        ForEach(history.shots) { shot in
                            ShotHistoryRow(
                                shot: shot,
                                isEditing: editingShotID == shot.id,
                                onTapComments: {
                                    editingShotID = editingShotID == shot.id ? nil : shot.id
                                },
                                onCommitComments: { new in
                                    history.updateComments(shot.id, comments: new)
                                    editingShotID = nil
                                },
                                onDelete: { history.remove(shot.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            if !history.isEmpty {
                footer
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 540, idealHeight: 720)
        #endif
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Clear all shot history?",
            isPresented: $pendingClearAll
        ) {
            Button("Delete \(history.shots.count) shot\(history.shots.count == 1 ? "" : "s")",
                   role: .destructive) {
                history.clearAll()
                pendingClearAll = false
            }
            Button("Cancel", role: .cancel) { pendingClearAll = false }
        } message: {
            Text("This permanently removes every saved shot. The profiles themselves are kept.")
        }
    }

    private var header: some View {
        HStack {
            Text("Shot history")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.crema)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(CremaColor.secondary)
            Text("No shots logged yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text("Pull a brew, then tap Save & Suggest at the end to keep it here.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var footer: some View {
        HStack {
            Button(role: .destructive, action: { pendingClearAll = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                    Text("Clear all")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(CremaColor.danger)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("\(history.shots.count) shot\(history.shots.count == 1 ? "" : "s") logged")
                .font(.system(size: 11, design: .rounded).monospacedDigit())
                .foregroundStyle(CremaColor.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CremaColor.surface.opacity(0.7))
    }
}

// MARK: - Row

private struct ShotHistoryRow: View {
    let shot: ShotLog
    let isEditing: Bool
    let onTapComments: () -> Void
    let onCommitComments: (String) -> Void
    let onDelete: () -> Void

    @State private var draftComments: String = ""

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private var yieldText: String {
        if let m = shot.measuredYieldG {
            return String(format: "%.0f g", m)
        }
        return "—"
    }
    private var yieldAccent: Color {
        guard let m = shot.measuredYieldG, shot.targetYieldG > 0 else { return CremaColor.secondary }
        let pct = abs(m - shot.targetYieldG) / shot.targetYieldG
        if pct < 0.05 { return CremaColor.connected }   // on target
        if pct < 0.15 { return CremaColor.crema }       // close
        return CremaColor.danger                         // way off
    }
    private var tasteText: String {
        var tags: [String] = []
        if shot.taste.acidity <= -0.4 { tags.append("sour") }
        if shot.taste.acidity >=  0.4 { tags.append("bitter") }
        if shot.taste.strength <= -0.4 { tags.append("weak") }
        if shot.taste.strength >=  0.4 { tags.append("strong") }
        return tags.isEmpty ? "balanced" : tags.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(shot.profileName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                    Text(Self.dateFormatter.string(from: shot.timestamp))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(CremaColor.secondary)
                }
                Spacer()
                statTile(label: "Yield", value: yieldText,
                         subtitle: "target \(Int(shot.targetYieldG))", accent: yieldAccent)
                statTile(label: "Time", value: "\(Int(shot.actualTimeS)) s",
                         subtitle: nil, accent: CremaColor.cream)
                statTile(label: "Taste", value: tasteText,
                         subtitle: nil, accent: CremaColor.matcha)

                Menu {
                    Button("Edit comments", systemImage: "pencil", action: onTapComments)
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
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

            if isEditing {
                TextField("Add a note for this shot…", text: $draftComments, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                    .lineLimit(2...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CremaColor.surface.opacity(0.6))
                    )
                HStack {
                    Spacer()
                    Button("Save note") { onCommitComments(draftComments) }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.crema)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                }
            } else if !shot.comments.isEmpty {
                Text(shot.comments)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CremaColor.hairline.opacity(0.5), lineWidth: 0.5))
        )
        .onAppear { draftComments = shot.comments }
    }

    private func statTile(label: String, value: String, subtitle: String?, accent: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.5)
                .foregroundStyle(CremaColor.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.secondary.opacity(0.7))
            }
        }
    }
}
