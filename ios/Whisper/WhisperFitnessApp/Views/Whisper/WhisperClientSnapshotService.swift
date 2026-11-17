import Foundation
import Supabase
import UIKit

/// Aggregated, JSON-encodable snapshot of a client's recent fitness data.
/// Uploaded to `whisper_client_snapshots.payload` so any of their accepted
/// coaches can review nutrition, sleep, steps, weight, progress photo
/// cadence and recent workouts without needing direct device access.
nonisolated struct WhisperClientSnapshot: Codable, Sendable, Hashable {
    // Nutrition (today)
    var caloriesToday: Int
    var caloriesGoal: Int
    var proteinToday: Double
    var proteinGoal: Double
    var carbsToday: Double
    var carbsGoal: Double
    var fatToday: Double
    var fatGoal: Double
    var waterCount: Int
    var loggingStreak: Int

    // Health (HealthKit summary)
    var sleepHours: Double
    var steps: Int
    var activeCalories: Double
    var activeMinutes: Int
    var restingHeartRate: Double
    var bodyMassLbs: Double
    var bodyFatPct: Double

    // Progress photos
    var photoSets: Int
    var daysSinceFirstPhoto: Int
    var lastPhotoDate: String?

    // Recent workouts
    struct Workout: Codable, Sendable, Hashable {
        let type: String
        let durationMinutes: Int
        let calories: Int
        let date: String
    }
    var recentWorkouts: [Workout]

    // Client-supplied note
    var note: String

    // ISO-8601 timestamp; used for the "Updated x ago" line in the coach UI.
    var capturedAt: String

    static let empty = WhisperClientSnapshot(
        caloriesToday: 0, caloriesGoal: 0,
        proteinToday: 0, proteinGoal: 0,
        carbsToday: 0, carbsGoal: 0,
        fatToday: 0, fatGoal: 0,
        waterCount: 0, loggingStreak: 0,
        sleepHours: 0, steps: 0, activeCalories: 0,
        activeMinutes: 0, restingHeartRate: 0,
        bodyMassLbs: 0, bodyFatPct: 0,
        photoSets: 0, daysSinceFirstPhoto: 0, lastPhotoDate: nil,
        recentWorkouts: [],
        note: "",
        capturedAt: ""
    )
}

nonisolated struct WhisperClientSnapshotInsert: Codable, Sendable {
    let user_id: String
    let username: String
    let payload: WhisperClientSnapshot
    let photo_front_url: String?
    let photo_side_url: String?
    let photo_back_url: String?
    let updated_at: String
}

nonisolated struct WhisperClientSnapshotRow: Codable, Sendable, Identifiable {
    let user_id: String
    let username: String
    let payload: WhisperClientSnapshot?
    let photo_front_url: String?
    let photo_side_url: String?
    let photo_back_url: String?
    let updated_at: String?
    nonisolated var id: String { user_id }
}

/// Builds the local user's snapshot from Whisper's existing services and
/// uploads it to Supabase whenever the user has at least one accepted coach.
/// Also exposes `fetchSnapshot(forClient:)` so the coach side can pull a
/// specific client's payload + photos.
@MainActor
@Observable
final class WhisperClientSnapshotService {
    static let shared = WhisperClientSnapshotService()

    private let client = SupabaseService.shared.client
    private static let bucket = "whisper-media"

    var isUploading: Bool = false
    var lastUploadedAt: Date?
    var lastError: String?

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    // MARK: - Local snapshot

    /// Reads Whisper's local services on the main actor and produces a
    /// snapshot ready to upload.
    func buildLocalSnapshot(note: String = "") -> WhisperClientSnapshot {
        let nutrition = NutritionViewModel()
        let shared = UserDefaults(suiteName: "group.com.mydailywhisper.whisper")
        let sleepHours = shared?.double(forKey: "widget_sleepHours") ?? 0
        let steps = shared?.integer(forKey: "widget_steps") ?? 0
        let activeCalories = Double(shared?.integer(forKey: "widget_calories") ?? 0)
        let photos = ProgressPhotoService.shared
        let iso = ISO8601DateFormatter()
        let recent: [WhisperClientSnapshot.Workout] = []
        return WhisperClientSnapshot(
            caloriesToday: nutrition.totalCalories,
            caloriesGoal: nutrition.goals.calories,
            proteinToday: nutrition.totalProtein,
            proteinGoal: nutrition.goals.protein,
            carbsToday: nutrition.totalCarbs,
            carbsGoal: nutrition.goals.carbs,
            fatToday: nutrition.totalFat,
            fatGoal: nutrition.goals.fat,
            waterCount: nutrition.waterCount,
            loggingStreak: nutrition.loggingStreak,
            sleepHours: sleepHours,
            steps: steps,
            activeCalories: activeCalories,
            activeMinutes: 0,
            restingHeartRate: 0,
            bodyMassLbs: 0,
            bodyFatPct: 0,
            photoSets: photos.totalPhotoSets,
            daysSinceFirstPhoto: photos.daysSinceFirstPhoto ?? 0,
            lastPhotoDate: photos.photos.first.map { iso.string(from: $0.date) },
            recentWorkouts: recent,
            note: note,
            capturedAt: iso.string(from: Date())
        )
    }

    // MARK: - Upload

    /// Uploads the local snapshot to Supabase. Safe to call even when the
    /// user has no coaches — it'll still keep the row fresh, but the row
    /// is only ever read by accepted coaches per RLS.
    @discardableResult
    func uploadIfNeeded(force: Bool = false, note: String = "") async -> Bool {
        guard isRemote, !Task.isCancelled else { return false }
        let epoch = AccountStorage.generation
        let ownerID = AccountStorage.currentUserID
        if !force {
            // Skip uploads when the user has no accepted coaches AND we've
            // already uploaded in the last 30 min — cheap throttle.
            let hasCoaches = !WhisperCoachRequestService.shared.myCoaches.isEmpty
            if !hasCoaches, let last = lastUploadedAt, Date().timeIntervalSince(last) < 1800 {
                return false
            }
        }
        isUploading = true
        defer { isUploading = false }

        let snapshot = buildLocalSnapshot(note: note)
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "client"

        // Upload latest progress photo per pose (small, 256-wide JPEG).
        async let front = uploadLatestPhoto(pose: .front, ownerID: ownerID, epoch: epoch)
        async let side = uploadLatestPhoto(pose: .side, ownerID: ownerID, epoch: epoch)
        async let back = uploadLatestPhoto(pose: .back, ownerID: ownerID, epoch: epoch)
        let (frontURL, sideURL, backURL) = await (front, side, back)
        guard epoch == AccountStorage.generation, !Task.isCancelled else { return false }

        let insert = WhisperClientSnapshotInsert(
            user_id: ownerID,
            username: username,
            payload: snapshot,
            photo_front_url: frontURL,
            photo_side_url: sideURL,
            photo_back_url: backURL,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await client
                .from("whisper_client_snapshots")
                .upsert(insert, onConflict: "user_id")
                .execute()
            guard epoch == AccountStorage.generation, !Task.isCancelled else { return false }
            lastUploadedAt = Date()
            lastError = nil
            return true
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("relation") && msg.contains("does not exist") {
                lastError = "Snapshot table missing. Owner: run the WhisperCoachRequestService SQL block."
            } else {
                lastError = "Couldn't upload snapshot: \(error.localizedDescription)"
            }
            print("[Whisper] snapshot upload error: \(error)")
            return false
        }
    }

    private func uploadLatestPhoto(pose: PhotoPose, ownerID: String, epoch: UUID) async -> String? {
        guard epoch == AccountStorage.generation, !Task.isCancelled else { return nil }
        let photos = ProgressPhotoService.shared.photos
            .filter { $0.pose == pose }
            .sorted { $0.date > $1.date }
        guard let latest = photos.first else { return nil }
        guard let image = UIImage(data: latest.imageData) else { return nil }
        let resized = image.preparingThumbnail(of: CGSize(width: 480, height: 720)) ?? image
        guard let jpeg = resized.jpegData(compressionQuality: 0.72) else { return nil }
        let path = "\(ownerID)/coach-snapshot/\(pose.rawValue.lowercased()).jpg"
        do {
            _ = try await client.storage
                .from(Self.bucket)
                .upload(
                    path,
                    data: jpeg,
                    options: FileOptions(
                        cacheControl: "60",
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )
            guard epoch == AccountStorage.generation, !Task.isCancelled else { return nil }
            let url = try client.storage.from(Self.bucket).getPublicURL(path: path)
            // Cache-bust so coaches see the new photo immediately.
            return url.absoluteString + "?v=\(Int(Date().timeIntervalSince1970))"
        } catch {
            print("[Whisper] snapshot photo upload error: \(error)")
            return nil
        }
    }

    // MARK: - Coach-side fetch

    func fetchSnapshot(forClient userID: String) async -> WhisperClientSnapshotRow? {
        guard isRemote else { return nil }
        do {
            let row: WhisperClientSnapshotRow = try await client
                .from("whisper_client_snapshots")
                .select()
                .eq("user_id", value: userID)
                .single()
                .execute()
                .value
            return row
        } catch {
            print("[Whisper] snapshot fetch error: \(error)")
            return nil
        }
    }
}

