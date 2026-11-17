import Foundation
import Supabase

/// Mirrors local `AccountStorage` blobs to a Supabase `user_data` table so the
/// user's programs, nutrition, saved meals, achievements, etc. follow them
/// across devices via their Supabase account (in addition to CloudKit).
///
/// Required Supabase setup (run once in the SQL editor):
///
/// ```sql
/// create table if not exists public.user_data (
///   user_id uuid not null references auth.users(id) on delete cascade,
///   data_key text not null,
///   data_blob bytea,
///   updated_at timestamptz not null default now(),
///   primary key (user_id, data_key)
/// );
/// alter table public.user_data enable row level security;
/// create policy "user_data owner read"   on public.user_data for select using  (auth.uid() = user_id);
/// create policy "user_data owner insert" on public.user_data for insert with check (auth.uid() = user_id);
/// create policy "user_data owner update" on public.user_data for update using  (auth.uid() = user_id);
/// create policy "user_data owner delete" on public.user_data for delete using  (auth.uid() = user_id);
/// ```
@Observable
class SupabaseSyncService {
    static let shared = SupabaseSyncService()

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case synced
        case error(String)
    }

    private(set) var status: SyncStatus = .idle

    private let client = SupabaseService.shared.client

    /// Same blob keys CloudKit mirrors, so both backends stay aligned.
    private let syncKeys: [String] = [
        "jasper_nutrition_meals",
        "jasper_nutrition_goals",
        "workoutSessionHistory",
        "journalEntries",
        "savedWorkoutPrograms",
        "savedMobilityPrograms",
        "userFitnessProfile",
        "dashboardWidgetOrder",
        "dashboardPreferences",
        "notificationPreferences",
        "periodTrackingLogs",
        "weekCheckIns",
        "savedMeals",
        "jasper_achievements",
        "summerEvent_challenges",
        "jasper_friends",
        "summerEvent_blitzRuns",
        "jasper_diet_plans",
        "jasper_macro_survey",
        "habitStreaks",
        "social_follow_state",
        "ember_memory_facts_v1",
    ]

    private init() {}

    // MARK: - Push

    /// Upload every tracked blob to Supabase. Skipped if `userID` is not a real Supabase id.
    func pushAll(userID: String) async {
        guard isRemoteUser(userID) else { return }
        let generation = AccountStorage.generation
        status = .syncing
        await withTaskGroup(of: Void.self) { group in
            for key in syncKeys {
                group.addTask { await self.pushBlob(userID: userID, storageKey: key) }
            }
        }
        guard generation == AccountStorage.generation, isRemoteUser(userID) else { return }
        status = .synced
    }

    /// Upload a single blob. No-op if there is nothing locally for that key.
    func pushBlob(userID: String, storageKey: String) async {
        guard isRemoteUser(userID),
              let data = AccountStorage.data(forKey: storageKey),
              !data.isEmpty else { return }
        nonisolated struct Row: Encodable {
            let user_id: String
            let data_key: String
            let data_blob: String
            let updated_at: String
        }
        let row = Row(
            user_id: userID,
            data_key: storageKey,
            data_blob: data.base64EncodedString(),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            _ = try await client.from("user_data")
                .upsert(row, onConflict: "user_id,data_key")
                .execute()
        } catch {
            print("[SupaSync] Failed to push \(storageKey): \(error)")
        }
    }

    // MARK: - Pull

    /// Fetch every tracked blob from Supabase and merge into local storage when
    /// the cloud copy is newer (or local is missing).
    func pullAll(userID: String) async {
        guard isRemoteUser(userID) else { return }
        let generation = AccountStorage.generation
        status = .syncing
        nonisolated struct Row: Decodable {
            let data_key: String
            let data_blob: String?
            let updated_at: String?
        }
        do {
            let rows: [Row] = try await client.from("user_data")
                .select("data_key,data_blob,updated_at")
                .eq("user_id", value: userID)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation, isRemoteUser(userID) else { return }
            let iso = ISO8601DateFormatter()
            for row in rows {
                guard syncKeys.contains(row.data_key),
                      let b64 = row.data_blob,
                      let data = Data(base64Encoded: b64),
                      !data.isEmpty else { continue }

                let cloudDate = row.updated_at.flatMap { iso.date(from: $0) }
                let localModKey = "\(row.data_key)_lastModified"
                let localModDate = UserDefaults.standard.object(forKey: AccountStorage.key(localModKey)) as? Date
                let localData = AccountStorage.data(forKey: row.data_key)

                if localData == nil || localData?.isEmpty == true {
                    AccountStorage.set(data, forKey: row.data_key)
                } else if let cloudDate, (localModDate == nil || cloudDate > localModDate!) {
                    AccountStorage.set(data, forKey: row.data_key)
                }
                if let cloudDate {
                    AccountStorage.set(cloudDate, forKey: localModKey)
                }
            }
            status = .synced
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, isRemoteUser(userID) else { return }
            print("[SupaSync] Failed to pull")
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func isRemoteUser(_ userID: String) -> Bool {
        !Task.isCancelled && userID != "guest" && !userID.hasPrefix("local_")
            && userID.caseInsensitiveCompare(AccountStorage.currentUserID) == .orderedSame
            && client.auth.currentUser?.id.uuidString.caseInsensitiveCompare(userID) == .orderedSame
    }
}
