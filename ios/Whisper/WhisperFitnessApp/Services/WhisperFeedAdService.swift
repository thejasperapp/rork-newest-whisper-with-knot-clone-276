import Foundation
import Observation
import Supabase

/// Ads use the same serving and billing RPCs as web, never synthetic feed posts.
@MainActor @Observable
final class WhisperFeedAdService {
    let placement: WhisperAdPlacement

    init(placement: WhisperAdPlacement = .feed) { self.placement = placement }

    private var inventory: [WhisperServedAd] = []
    var ads: [WhisperServedAd] { isCurrentViewer ? inventory : [] }
    private var generation: UUID = UUID()
    private var isCurrentViewer: Bool {
        viewerID == AccountStorage.currentUserID
            && SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == viewerID.lowercased()
    }

    /// Invalidate pending work as well as cached rows, including an A → B → A switch.
    func resetForCurrentAccount() {
        generation = UUID()
        viewerID = AccountStorage.currentUserID
        inventory = []
        impressionIDs = []
        loading = false
        fetchedAt = .distantPast
    }
    private var viewerID: String = ""
    private var impressionIDs: Set<String> = []
    private var loading: Bool = false
    private var fetchedAt: Date = .distantPast

    nonisolated private struct ServeParams: Encodable, Sendable {
        let p_placement: String
        let p_limit: Int
    }
    nonisolated private struct TrackParams: Encodable, Sendable {
        let p_ad: String
        let p_kind: String
    }

    func refresh(force: Bool = false) async {
        let uid = AccountStorage.currentUserID
        if uid != viewerID { resetForCurrentAccount() }
        let requestGeneration = generation
        guard isCurrentViewer, UUID(uuidString: uid) != nil, !Task.isCancelled, !loading,
              force || Date().timeIntervalSince(fetchedAt) > 300 else { return }
        loading = true
        defer { if requestGeneration == generation { loading = false } }
        do {
            let rows: [WhisperServedAd] = try await SupabaseService.shared.client
                .rpc("business_active_ads", params: ServeParams(p_placement: placement.rawValue, p_limit: placement.limit)).execute().value
            guard isCurrentViewer, requestGeneration == generation, !Task.isCancelled else { return }
            inventory = rows
            fetchedAt = Date()
        } catch {
            guard isCurrentViewer, requestGeneration == generation, !Task.isCancelled else { return }
            inventory = []
            // No paid inventory or an unavailable rail must never block the feed.
            print("[FeedAds] Rotation unavailable")
        }
    }

    func impression(_ id: String) async {
        guard isCurrentViewer, !Task.isCancelled, inventory.contains(where: { $0.id == id }),
              !impressionIDs.contains(id) else { return }
        let requestGeneration = generation
        impressionIDs.insert(id)
        do {
            try await track(id, kind: "impression")
        } catch {
            guard isCurrentViewer, requestGeneration == generation else { return }
            impressionIDs.remove(id)
            print("[FeedAds] Impression not recorded")
        }
    }

    func click(_ id: String) async {
        guard isCurrentViewer, !Task.isCancelled, inventory.contains(where: { $0.id == id }) else { return }
        do { try await track(id, kind: "click") }
        catch { print("[FeedAds] Click not recorded") }
    }

    private func track(_ id: String, kind: String) async throws {
        _ = try await SupabaseService.shared.client.rpc("business_track_ad",
            params: TrackParams(p_ad: id, p_kind: kind)).execute()
    }
}
