import Foundation
import SwiftUI
import Supabase

/// Pulls the current user's progress photos from Supabase (synced there by
/// Whisper) so photos taken on another device show up on this device.
///
/// Whisper writes one row per photo to `public.jasper_progress_photos`
/// (metadata) and stores the JPEG bytes in the private `progress-photos`
/// bucket at `progress-photos/<user_id>/<file>.jpg`. We read the metadata
/// table, mint a 1-hour signed URL for each path, download the bytes, and
/// publish the result as `ProgressPhoto` values so the existing profile UI
/// can render them with zero changes.
@MainActor
@Observable
final class WhisperProgressPhotoRemoteService {
    static let shared = WhisperProgressPhotoRemoteService()

    /// Photos hydrated from Supabase storage. Stable across refreshes — we
    /// dedupe by `storage_path` so repeated refreshes don't rebuild bytes.
    private(set) var photos: [ProgressPhoto] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    private static let bucket = "progress-photos"
    private static let signedURLTTL = 3600
    private let client = SupabaseService.shared.client

    /// Keyed by `storage_path` so a re-fetch can skip already-downloaded bytes.
    private var cache: [String: ProgressPhoto] = [:]

    /// Public so coach-facing views can hold a per-client instance without
    /// stomping on `shared` (which is reserved for the signed-in user).
    init() {}

    /// Re-fetches the metadata rows for the signed-in user, downloads any
    /// new photo bytes, and replaces `photos` with the merged result.
    func refresh() async {
        guard let session = try? await client.auth.session else {
            photos = []
            cache.removeAll()
            return
        }
        let uid = session.user.id.uuidString.lowercased()
        await refresh(forUserID: uid, isOwner: true)
    }

    /// Coach-facing variant: fetch a specific client's photos. RLS
    /// (`is_coach_of(user_id)`) must permit the read on both the metadata
    /// table and the storage bucket.
    func refresh(forUserID userID: String) async {
        // Compare against the signed-in user so we only apply the
        // visibility filter when reading *someone else's* photos.
        let normalized = userID.lowercased()
        var isOwner = false
        if let session = try? await client.auth.session {
            isOwner = session.user.id.uuidString.lowercased() == normalized
        }
        await refresh(forUserID: normalized, isOwner: isOwner)
    }

    /// Per Whisper's spec, `visibility` is one of `private | friends | public`.
    /// Owners see all of their own photos; anyone else (coach, friend feed)
    /// must respect the row-level visibility.
    private func refresh(forUserID userID: String, isOwner: Bool) async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let rows: [WhisperProgressPhotoRow]
        do {
            var query = client
                .from("jasper_progress_photos")
                .select()
                .eq("user_id", value: userID)
            if !isOwner {
                query = query.in("visibility", values: ["friends", "public"])
            }
            rows = try await query
                .order("recorded_on", ascending: false, nullsFirst: false)
                .limit(60)
                .execute()
                .value
        } catch {
            lastError = "Couldn't read jasper_progress_photos: \(error.localizedDescription)"
            return
        }

        var built: [ProgressPhoto] = []
        for row in rows {
            guard let path = row.storage_path, !path.isEmpty else { continue }
            if let cached = cache[path] {
                built.append(cached)
                continue
            }
            guard let photo = await downloadPhoto(forRow: row, path: path) else { continue }
            cache[path] = photo
            built.append(photo)
        }

        // Drop cache entries for rows that no longer exist remotely.
        let currentPaths = Set(rows.compactMap { $0.storage_path })
        cache = cache.filter { currentPaths.contains($0.key) }

        photos = built.sorted { $0.date > $1.date }
    }

    func clear() {
        photos = []
        cache.removeAll()
        lastError = nil
    }

    // MARK: - Helpers

    private func downloadPhoto(forRow row: WhisperProgressPhotoRow, path: String) async -> ProgressPhoto? {
        do {
            let signed = try await client.storage
                .from(Self.bucket)
                .createSignedURL(path: path, expiresIn: Self.signedURLTTL)
            let (data, response) = try await URLSession.shared.data(from: signed)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("[Whisper] progress photo download HTTP \(http.statusCode) for \(path)")
                return nil
            }
            guard !data.isEmpty else { return nil }
            return ProgressPhoto(
                id: Self.stableID(forPath: path),
                date: Self.parseDate(row.recorded_on),
                imageData: data,
                pose: Self.parsePose(row.pose),
                weight: row.weight_kg,
                note: row.note
            )
        } catch {
            print("[Whisper] progress photo signed URL/download error for \(path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Deterministic UUID from the storage path so the same remote photo
    /// always lands at the same `ProgressPhoto.id`, enabling dedupe vs.
    /// the local `ProgressPhotoService` store.
    private nonisolated static func stableID(forPath path: String) -> UUID {
        var hash: UInt64 = 1469598103934665603
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let high = hash
        var hash2: UInt64 = 14695981039346656037 &+ hash
        for byte in path.reversed().map({ UInt8(ascii: $0) }) {
            hash2 ^= UInt64(byte)
            hash2 = hash2 &* 1099511628211
        }
        let low = hash2
        let bytes: [UInt8] = [
            UInt8((high >> 56) & 0xFF), UInt8((high >> 48) & 0xFF),
            UInt8((high >> 40) & 0xFF), UInt8((high >> 32) & 0xFF),
            UInt8((high >> 24) & 0xFF), UInt8((high >> 16) & 0xFF),
            UInt8((high >> 8)  & 0xFF), UInt8(high & 0xFF),
            UInt8((low  >> 56) & 0xFF), UInt8((low  >> 48) & 0xFF),
            UInt8((low  >> 40) & 0xFF), UInt8((low  >> 32) & 0xFF),
            UInt8((low  >> 24) & 0xFF), UInt8((low  >> 16) & 0xFF),
            UInt8((low  >> 8)  & 0xFF), UInt8(low  & 0xFF)
        ]
        return UUID(uuid: (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private nonisolated static func parsePose(_ raw: String?) -> PhotoPose {
        let key = (raw ?? "").lowercased()
        switch key {
        case "side", "right", "left": return .side
        case "back", "rear":           return .back
        default:                       return .front
        }
    }

    private nonisolated static func parseDate(_ raw: String?) -> Date {
        guard let raw, !raw.isEmpty else { return Date() }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(identifier: "UTC")
        return day.date(from: raw) ?? Date()
    }
}

private extension UInt8 {
    init(ascii char: Character) {
        self = char.asciiValue ?? 0
    }
}
