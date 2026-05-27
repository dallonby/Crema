import SwiftUI
import CremaKit

/// Profile library browser — list of user profiles with mini curve previews.
/// Tap to activate, swipe to delete, edit to open the guided editor, +
/// button to create a new one.
struct ProfilesView: View {
    @Bindable var library: ProfileLibrary
    /// Optional — when present, enables Share button per row + Browse button
    /// in the footer. Omitted on screens where sharing isn't relevant
    /// (currently always passed, but the optionality keeps tests / previews
    /// simple).
    var session: SignedInUser?
    @Environment(\.dismiss) private var dismiss

    @State private var editingProfile: EditableProfile?
    @State private var newProfile: EditableProfile?
    @State private var pendingDelete: BrewProfile?
    @State private var sharingProfile: BrewProfile?
    @State private var showBrowse = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .safeAreaPadding(.top)   // iPhone Dynamic Island / notch
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(library.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.id == library.activeProfileID,
                            canShare: session != nil,
                            onTap: {
                                library.setActive(profile.id)
                                dismiss()
                            },
                            onEdit: {
                                editingProfile = EditableProfile.from(profile)
                            },
                            onShare: session == nil ? nil : {
                                sharingProfile = profile
                            },
                            onDelete: library.profiles.count > 1 ? {
                                pendingDelete = profile
                            } : nil
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            footer
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 540, idealHeight: 720)
        #endif
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .modifier(EditorPresentation(item: $editingProfile) { editing in
            ProfileEditView(
                editing: editing,
                onSave: { library.update($0) },
                onCancel: {}
            )
        })
        .modifier(EditorPresentation(item: $newProfile) { editing in
            ProfileEditView(
                editing: editing,
                onSave: { library.add($0, setActive: true) },
                onCancel: {}
            )
        })
        .sheet(item: $sharingProfile) { profile in
            if let session {
                ShareProfileSheet(profile: profile, session: session,
                                   onDismiss: { sharingProfile = nil })
            }
        }
        .sheet(isPresented: $showBrowse) {
            if let session {
                BrowseCommunitySheet(session: session, library: library,
                                       onDismiss: { showBrowse = false })
            }
        }
        .confirmationDialog(
            "Delete this profile?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { profile in
            Button("Delete \"\(profile.name)\"", role: .destructive) {
                library.remove(profile.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Text("Profiles")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.crema)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)         // 44pt min tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: { newProfile = EditableProfile() }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New profile")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(CremaColor.crema)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(
                    Capsule().fill(CremaColor.crema.opacity(0.16))
                        .overlay(Capsule().strokeBorder(CremaColor.crema.opacity(0.35), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            Spacer()
            if session != nil {
                Button(action: { showBrowse = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Community")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(CremaColor.matchaBright)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(
                        Capsule().fill(CremaColor.matcha.opacity(0.16))
                            .overlay(Capsule().strokeBorder(CremaColor.matcha.opacity(0.35), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CremaColor.surface.opacity(0.7))
    }
}

// MARK: - Editor presentation

/// Presents the profile editor full-screen on iOS (the landscape split layout
/// needs the full screen width — a form sheet caps at ~540pt and boxes the
/// chart in) and as a regular sheet on macOS.
private struct EditorPresentation<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder var sheetContent: (Item) -> Sheet

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $item, content: sheetContent)
        #else
        content.sheet(item: $item, content: sheetContent)
        #endif
    }
}

// MARK: - Row

private struct ProfileRow: View {
    let profile: BrewProfile
    let isActive: Bool
    let canShare: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onShare: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ProfilePreviewMini(profile: profile)
                    .frame(width: 110, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CremaColor.bg.opacity(0.6))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(CremaColor.crema)
                        }
                        Text(profile.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                            .lineLimit(1)
                    }
                    Text(metaLine)
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(CremaColor.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Menu {
                    Button("Edit", systemImage: "slider.horizontal.3", action: onEdit)
                    if let onShare {
                        Button("Share…", systemImage: "square.and.arrow.up", action: onShare)
                    }
                    if let onDelete {
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CremaColor.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isActive ? CremaColor.crema.opacity(0.4) : CremaColor.hairline.opacity(0.5),
                                       lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var metaLine: String {
        var bits: [String] = []
        if let v = profile.targetVolumeMl { bits.append("\(v) mL target") }
        bits.append(String(format: "%.0f s", profile.totalDuration))
        bits.append("\(profile.stages.count) stage\(profile.stages.count == 1 ? "" : "s")")
        return bits.joined(separator: "  ·  ")
    }
}

/// Tiny ghost-only chart preview — same `ShotChart` view in compact mode
/// (no axis labels, no target text, no margins) so the curves fill the frame
/// cleanly even at ~110×64.
private struct ProfilePreviewMini: View {
    let profile: BrewProfile

    var body: some View {
        ShotChart(
            samples: [][...],
            profile: profile,
            playhead: -1,
            totalDuration: max(profile.totalDuration, 1),
            compact: true
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
