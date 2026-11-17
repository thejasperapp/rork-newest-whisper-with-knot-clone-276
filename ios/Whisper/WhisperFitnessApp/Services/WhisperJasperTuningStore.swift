import Foundation

/// Reads fresh account-scoped values; no singleton can retain another account's tuning.
@MainActor
enum WhisperJasperTuningStore {
    static let storageKey = "whisper.jasper.reply-tuning.v1"

    static func load() -> WhisperJasperTuning {
        guard let data = AccountStorage.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(WhisperJasperTuning.self, from: data) else {
            return WhisperJasperTuning()
        }
        return value.normalized
    }

    @discardableResult
    static func save(_ value: WhisperJasperTuning, generation: UUID) -> Bool {
        guard generation == AccountStorage.generation,
              let data = try? JSONEncoder().encode(value.normalized) else { return false }
        AccountStorage.set(data, forKey: storageKey)
        return true
    }
}
