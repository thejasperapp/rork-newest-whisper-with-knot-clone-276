import Foundation
import Supabase
import UIKit

// MARK: - Row

nonisolated struct WhisperCloudBackdrop: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let url: String
    let prompt: String?
    let created_at: String?
}

/// Syncs Jasper-generated meeting backdrops through Supabase so the SAME
/// library appears on web and iOS. Rows live in `whisper_meeting_backdrops`
/// (supabase/meeting-backdrops.sql); images live in the public
/// `meeting-backdrops` bucket. Everything is best-effort — the local
/// backdrop store keeps working when the migration hasn't run yet.
@MainActor
@Observable
final class WhisperBackdropCloudService {
    static let shared = WhisperBackdropCloudService()
    private let client = SupabaseService.shared.client
    private init() {}

    var items: [WhisperCloudBackdrop] = []

    func refresh() async {
        guard client.auth.currentUser != nil else { return }
        do {
            let rows: [WhisperCloudBackdrop] = try await client
                .from("whisper_meeting_backdrops")
                .select()
                .order("created_at", ascending: false)
                .limit(12)
                .execute()
                .value
            items = rows
        } catch {
            // Table missing (migration not run) or offline — local-only mode.
        }
    }

    /// Uploads generated backdrop data and records it in the shared library.
    func upload(data: Data, prompt: String) async {
        guard let uid = client.auth.currentUser?.id.uuidString.lowercased() else { return }
        let path = "\(uid)/\(Int(Date().timeIntervalSince1970 * 1000))-backdrop.jpg"
        do {
            _ = try await client.storage
                .from("meeting-backdrops")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false)
                )
            let publicURL = try client.storage
                .from("meeting-backdrops")
                .getPublicURL(path: path)
            struct Insert: Encodable {
                let user_id: String
                let url: String
                let prompt: String?
            }
            _ = try await client
                .from("whisper_meeting_backdrops")
                .insert(Insert(
                    user_id: uid,
                    url: publicURL.absoluteString,
                    prompt: String(prompt.prefix(300))
                ))
                .execute()
            await refresh()
        } catch {
            // Best-effort — the locally saved copy still works on this device.
        }
    }

    /// Removes a backdrop from the shared library (+ best-effort storage file).
    func remove(_ item: WhisperCloudBackdrop) async {
        _ = try? await client
            .from("whisper_meeting_backdrops")
            .delete()
            .eq("id", value: item.id)
            .execute()
        if let range = item.url.range(of: "/meeting-backdrops/") {
            let raw = String(item.url[range.upperBound...])
            let path = raw.removingPercentEncoding ?? raw
            _ = try? await client.storage
                .from("meeting-backdrops")
                .remove(paths: [path])
        }
        items.removeAll { $0.id == item.id }
    }

    /// Downloads a synced backdrop (cached per item) and applies it through
    /// the local effects pipeline. Returns the local path on success.
    func apply(_ item: WhisperCloudBackdrop) async -> String? {
        let cached = WhisperVideoEffects.backgroundsDirectory()
            .appendingPathComponent("cloud-\(item.id).jpg")
        if let image = UIImage(contentsOfFile: cached.path) {
            WhisperVideoEffects.shared.setBackdrop(image, persistPath: cached.path)
            return cached.path
        }
        guard let url = URL(string: item.url) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try? data.write(to: cached)
            guard let image = UIImage(contentsOfFile: cached.path) else { return nil }
            WhisperVideoEffects.shared.setBackdrop(image, persistPath: cached.path)
            return cached.path
        } catch {
            return nil
        }
    }
}
