import Foundation
import Observation

@MainActor @Observable
final class WhisperJasperTuningViewModel {
    private(set) var preferences: WhisperJasperTuning
    private(set) var isCurrentAccount: Bool = true
    var errorMessage: String?
    private let generation: UUID

    init() {
        generation = AccountStorage.generation
        preferences = WhisperJasperTuningStore.load()
    }

    func setStrength(_ strength: Double) {
        var value = preferences
        value.strength = strength
        save(value)
    }

    func add(_ term: String, less: Bool) {
        var value = preferences
        value.add(term, less: less)
        save(value)
    }

    func remove(_ term: String, less: Bool) {
        var value = preferences
        value.remove(term, less: less)
        save(value)
    }

    func reset() { save(WhisperJasperTuning()) }

    func invalidate() {
        isCurrentAccount = false
        preferences = WhisperJasperTuning()
        errorMessage = nil
    }

    private func save(_ value: WhisperJasperTuning) {
        guard isCurrentAccount, generation == AccountStorage.generation else { invalidate(); return }
        guard WhisperJasperTuningStore.save(value, generation: generation) else {
            errorMessage = "Couldn't save this change. Please try again."
            return
        }
        preferences = value.normalized
        errorMessage = nil
    }
}
