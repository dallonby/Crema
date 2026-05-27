import Foundation
import SwiftUI
import CremaKit

/// Cache + paginator for the community browse feed. Owns:
/// - the visible list of `ProfileDTO`s
/// - cursor for "load more"
/// - per-profile like state (so toggling updates the UI instantly)
/// - a small `Set` of liked-by-me ids fetched once at sign-in
///
/// Two browse modes: `.recent` (chronological) and `.author(id)` (one
/// user's profiles). Switch by calling `refresh(mode:)`.
@MainActor
@Observable
final class CommunityProfileStore {
    enum Mode: Hashable, Sendable {
        case recent
        case author(String)
    }

    private(set) var profiles: [ShareAPIClient.ProfileDTO] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var mode: Mode = .recent
    private var cursor: String?
    private var loadedAtLeastOnce = false
    /// Profile ids the current user has liked. Used for filled-vs-outline
    /// heart icons. Lazily populated as the user likes things in this
    /// session; doesn't persist (the backend is the source of truth).
    private(set) var likedIDs: Set<String> = []

    private let client: ShareAPIClient

    init(client: ShareAPIClient) {
        self.client = client
    }

    /// Reset the feed and pull the first page. Call when the browse sheet
    /// appears or the user switches authors.
    func refresh(mode: Mode = .recent) async {
        self.mode = mode
        cursor = nil
        profiles = []
        loadedAtLeastOnce = false
        await loadMore()
    }

    /// Pull the next page (no-op when there's nothing more).
    func loadMore() async {
        if isLoading { return }
        if loadedAtLeastOnce && cursor == nil { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page: ShareAPIClient.BrowsePage
            switch mode {
            case .recent:
                page = try await client.browse(cursor: cursor)
            case .author(let id):
                page = try await client.browse(cursor: cursor, authorId: id)
            }
            profiles.append(contentsOf: page.profiles)
            cursor = page.nextCursor
            loadedAtLeastOnce = true
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    func like(_ p: ShareAPIClient.ProfileDTO) async {
        // Optimistic — flip the heart, fix on response.
        likedIDs.insert(p.id)
        bump(id: p.id, delta: +1)
        do {
            let r = try await client.like(profileId: p.id)
            set(likeCount: r.likesCount, on: p.id)
        } catch {
            likedIDs.remove(p.id)
            bump(id: p.id, delta: -1)
        }
    }

    func unlike(_ p: ShareAPIClient.ProfileDTO) async {
        likedIDs.remove(p.id)
        bump(id: p.id, delta: -1)
        do {
            let r = try await client.unlike(profileId: p.id)
            set(likeCount: r.likesCount, on: p.id)
        } catch {
            likedIDs.insert(p.id)
            bump(id: p.id, delta: +1)
        }
    }

    private func bump(id: String, delta: Int) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        let p = profiles[i]
        profiles[i] = mutated(p) { $0.likesCount += delta }
    }

    private func set(likeCount: Int, on id: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i] = mutated(profiles[i]) { $0.likesCount = likeCount }
    }

    /// `ProfileDTO` is value-typed but its stored properties are `let` (it
    /// came from a Codable decode). We can't mutate in place — rebuild via
    /// re-decode through a mutable intermediate. Cheap; runs only on
    /// user-driven like toggles.
    private func mutated(_ p: ShareAPIClient.ProfileDTO,
                         _ change: (inout MutableProfile) -> Void) -> ShareAPIClient.ProfileDTO {
        var m = MutableProfile(from: p)
        change(&m)
        return m.dto
    }

    private struct MutableProfile {
        var id: String
        var name: String
        var description: String?
        var beanName: String?
        var equipment: String?
        var profileJson: BrewProfile
        var likesCount: Int
        var downloadsCount: Int
        var createdAt: Date
        var author: ShareAPIClient.UserDTO

        init(from p: ShareAPIClient.ProfileDTO) {
            id = p.id; name = p.name; description = p.description
            beanName = p.beanName; equipment = p.equipment
            profileJson = p.profileJson
            likesCount = p.likesCount; downloadsCount = p.downloadsCount
            createdAt = p.createdAt; author = p.author
        }

        var dto: ShareAPIClient.ProfileDTO {
            // Round-trip through JSON to materialise the immutable DTO.
            // Cheap (single small object) and avoids reflective hacks.
            let dict: [String: Any] = [
                "id": id,
                "name": name,
                "description": description as Any,
                "beanName": beanName as Any,
                "equipment": equipment as Any,
                "profileJson": (try? JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(profileJson))) ?? [:],
                "likesCount": likesCount,
                "downloadsCount": downloadsCount,
                "createdAt": ISO8601DateFormatter().string(from: createdAt),
                "author": [
                    "id": author.id,
                    "displayName": author.displayName,
                    "avatarUrl": author.avatarUrl as Any,
                ],
            ]
            let cleaned = dict.compactMapValues { $0 is NSNull ? nil : $0 }
            let data = try! JSONSerialization.data(withJSONObject: cleaned)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try! dec.decode(ShareAPIClient.ProfileDTO.self, from: data)
        }
    }
}
