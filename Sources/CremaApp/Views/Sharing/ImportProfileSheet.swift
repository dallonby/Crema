import SwiftUI
import CremaKit

/// Preview before a community / file-imported profile lands in the library.
/// User can read the recipe, see the author, then "Add to my library" to
/// commit. Cancel just dismisses.
struct ImportProfileSheet: View {
    let profile: ShareAPIClient.ProfileDTO
    @Bindable var library: ProfileLibrary
    @Bindable var session: SignedInUser
    let onDone: () -> Void

    @State private var added = false
    @State private var confirmingReport = false
    @State private var confirmingBlock = false
    @State private var moderationFeedback: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    titleCard
                    if let desc = profile.description {
                        Text(desc)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(CremaColor.cream.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(card)
                    }
                    stagesCard
                    metaCard
                }
                .padding(20)
            }
            footer
        }
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button("Cancel", action: onDone)
                .foregroundStyle(CremaColor.secondary)
                .font(.system(size: 13, weight: .medium, design: .rounded))
            Spacer()
            Text("Import")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Spacer()
            // Skip the moderation menu for local-only profiles (no real
            // author to block / report). They're identified by their
            // pseudo-id prefix.
            if !profile.id.hasPrefix("local-") && session.isSignedIn {
                Menu {
                    Button("Report this profile", systemImage: "flag",
                            role: .destructive) { confirmingReport = true }
                    Button("Block @\(profile.author.displayName)",
                            systemImage: "hand.raised",
                            role: .destructive) { confirmingBlock = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CremaColor.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
        .confirmationDialog(
            "Report this profile?",
            isPresented: $confirmingReport, titleVisibility: .visible
        ) {
            Button("Report", role: .destructive) {
                Task {
                    do {
                        try await session.client.report(profileId: profile.id, reason: nil)
                        moderationFeedback = "Reported. We'll review within 24 h."
                    } catch {
                        moderationFeedback = "Couldn't submit report: \(error)"
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reports are reviewed within 24 hours.")
        }
        .confirmationDialog(
            "Block @\(profile.author.displayName)?",
            isPresented: $confirmingBlock, titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task {
                    do {
                        try await session.client.block(userId: profile.author.id)
                        moderationFeedback = "Blocked."
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        onDone()
                    } catch {
                        moderationFeedback = "Couldn't block: \(error)"
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see profiles from this user again.")
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profile.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(CremaColor.crema)
                Text("by \(profile.author.displayName)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
            }
            HStack(spacing: 14) {
                stat("\(profile.likesCount)", icon: "heart.fill")
                stat("\(profile.downloadsCount)", icon: "arrow.down.circle.fill")
            }
            .foregroundStyle(CremaColor.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private func stat(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
        }
    }

    private var stagesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STAGES")
                .font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                .tracking(0.7)
                .foregroundStyle(CremaColor.secondary)
            ForEach(profile.profileJson.stages) { stage in
                HStack {
                    Capsule()
                        .fill(stage.priority == .pressure ? CremaColor.crema : CremaColor.matcha)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                        Text(detail(stage))
                            .font(.system(size: 11, design: .rounded).monospacedDigit())
                            .foregroundStyle(CremaColor.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            HStack {
                Text("Total")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
                Spacer()
                Text("\(Int(profile.profileJson.totalDuration)) s")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CremaColor.cream)
            }
            .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private func detail(_ s: BrewStage) -> String {
        let value = s.priority == .pressure
            ? String(format: "%.1f bar", s.pressureBar)
            : String(format: "%.1f mL/s", s.flowMlPerSec)
        var bits = [value, String(format: "%.0f s", s.duration)]
        if s.waitAfter > 0 { bits.append(String(format: "+%.0f s wait", s.waitAfter)) }
        return bits.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private var metaCard: some View {
        if profile.beanName != nil || profile.equipment != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let bean = profile.beanName {
                    HStack {
                        Text("BEAN").font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                            .tracking(0.7).foregroundStyle(CremaColor.secondary)
                        Spacer()
                        Text(bean).font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                    }
                }
                if let eq = profile.equipment {
                    HStack {
                        Text("EQUIPMENT").font(.system(size: 10, weight: .semibold, design: .rounded).smallCaps())
                            .tracking(0.7).foregroundStyle(CremaColor.secondary)
                        Spacer()
                        Text(eq).font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(CremaColor.cream)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CremaColor.hairline.opacity(0.4), lineWidth: 0.5))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let moderationFeedback {
                Text(moderationFeedback)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
            }
            HStack {
                Spacer()
                Button(action: addToLibrary) {
                HStack(spacing: 6) {
                    Image(systemName: added ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(added ? "Added to library" : "Add to my library")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(CremaColor.bg)
                .padding(.horizontal, 22).frame(minHeight: 46)
                .background(Capsule().fill(LinearGradient(
                    colors: [CremaColor.cremaBright, CremaColor.crema],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )))
                .shadow(color: CremaColor.crema.opacity(0.5), radius: 8, y: 3)
            }
                .buttonStyle(.plain)
                .disabled(added)
                Spacer()
            }
        }
        .padding(.bottom, 20)
    }

    private func addToLibrary() {
        // Bring in with a fresh UUID so we don't collide with anything
        // already in the library (e.g. the user's own upload).
        let p = profile.profileJson
        let imported = BrewProfile(
            id: UUID(),
            name: p.name,
            stages: p.stages,
            mode: p.mode,
            target: p.target,
            targetVolumeMl: p.targetVolumeMl,
            grinder: p.grinder
        )
        library.add(imported, setActive: true)
        added = true
        // Brief delay so the user sees the success state before the sheet
        // closes.
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            onDone()
        }
    }
}
