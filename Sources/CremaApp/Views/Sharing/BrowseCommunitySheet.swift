import SwiftUI
import CremaKit

/// "Community" tab — paginated list of recent shared profiles. Tap a row
/// to preview + add to library. Heart to like. Pull (or scroll to bottom)
/// to load more.
struct BrowseCommunitySheet: View {
    @Bindable var session: SignedInUser
    @Bindable var library: ProfileLibrary
    let onDismiss: () -> Void

    @State private var store: CommunityProfileStore?
    @State private var previewing: ShareAPIClient.ProfileDTO?

    var body: some View {
        VStack(spacing: 0) {
            header
            if !session.isSignedIn {
                SignInView(session: session) {
                    setupStore()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let store {
                content(store: store)
            } else {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CremaColor.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            if session.isSignedIn { setupStore() }
        }
        .sheet(item: $previewing) { p in
            ImportProfileSheet(profile: p, library: library,
                                 session: session,
                                 onDone: { previewing = nil; onDismiss() })
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Community")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(CremaColor.cream)
                Text("Recipes shared by other coffee nerds")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(CremaColor.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CremaColor.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(CremaColor.surface.opacity(0.6)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func setupStore() {
        let s = CommunityProfileStore(client: session.client)
        self.store = s
        Task { await s.refresh() }
    }

    @ViewBuilder
    private func content(store: CommunityProfileStore) -> some View {
        if store.profiles.isEmpty && !store.isLoading && store.error == nil {
            emptyState
        } else {
            List {
                if let err = store.error {
                    InlineErrorBanner(
                        message: err,
                        onRetry:  { Task { await store.refresh() } },
                        onDismiss: { Task { await MainActor.run { store.clearError() } } }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12))
                }
                ForEach(store.profiles) { p in
                    ProfileRow(
                        profile: p,
                        liked: store.likedIDs.contains(p.id),
                        onTap:   { previewing = p },
                        onLike:  { Task { await store.like(p) } },
                        onUnlike:{ Task { await store.unlike(p) } }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onAppear {
                        // Load next page when the second-to-last row appears.
                        if p.id == store.profiles.dropLast().last?.id {
                            Task { await store.loadMore() }
                        }
                    }
                }
                if store.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await store.refresh() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(CremaColor.secondary)
            Text("No profiles yet")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CremaColor.cream)
            Text("Be the first to share. Tap a profile in your library → Share → Upload.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(CremaColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProfileRow: View {
    let profile: ShareAPIClient.ProfileDTO
    let liked: Bool
    let onTap: () -> Void
    let onLike: () -> Void
    let onUnlike: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CremaColor.cream)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(profile.author.displayName)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(CremaColor.secondary)
                        if let bean = profile.beanName {
                            Text("·").foregroundStyle(CremaColor.secondary)
                            Text(bean)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(CremaColor.secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(CremaColor.crema)
                        Text("\(profile.profileJson.stages.count) stage\(profile.profileJson.stages.count == 1 ? "" : "s")")
                            .font(.system(size: 10, design: .rounded).monospacedDigit())
                            .foregroundStyle(CremaColor.secondary)
                        Text("·").foregroundStyle(CremaColor.secondary)
                        Text("\(Int(profile.profileJson.totalDuration)) s")
                            .font(.system(size: 10, design: .rounded).monospacedDigit())
                            .foregroundStyle(CremaColor.secondary)
                    }
                }
                Spacer()
                Button(action: liked ? onUnlike : onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(liked ? CremaColor.crema : CremaColor.secondary)
                        Text("\(profile.likesCount)")
                            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(CremaColor.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CremaColor.hairline.opacity(0.4), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }
}
