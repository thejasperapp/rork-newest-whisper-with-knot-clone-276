import Testing
import Foundation
@testable import Whisper

struct WhisperJasperTuningTests {
    @Test func movingAChoiceBetweenListsRemovesDuplicates() {
        var tuning = WhisperJasperTuning()
        tuning.add("  Practical   steps\n", less: false)
        tuning.add("practical steps", less: false)
        #expect(tuning.moreOf == ["practical steps"])
        tuning.add("Practical steps", less: true)
        #expect(tuning.moreOf.isEmpty)
        #expect(tuning.lessOf == ["Practical steps"])
        tuning.remove("Practical steps", less: true)
        #expect(tuning.lessOf.isEmpty)
    }

    @Test func zeroStrengthDoesNotSendSavedPreferences() {
        var tuning = WhisperJasperTuning(strength: 0, moreOf: ["Deeper explanations"], lessOf: ["Jargon"])
        #expect(tuning.promptInstruction == WhisperJasperTuning.baselineInstruction)
        #expect(!tuning.promptInstruction.contains("Deeper explanations"))
        #expect(tuning.moreOf == ["Deeper explanations"])
        tuning.strength = 1
        #expect(tuning.promptInstruction.contains("Deeper explanations"))
        #expect(tuning.promptInstruction.contains("Jargon"))
        #expect(tuning.promptInstruction.contains("100% (strong preference)"))
    }

    @Test func choicesAreBoundedAndNormalized() {
        var tuning = WhisperJasperTuning(strength: .infinity)
        tuning.add("   \n", less: false)
        #expect(tuning.moreOf.isEmpty)
        tuning.add(String(repeating: "a", count: 200), less: false)
        #expect(tuning.moreOf.first?.count == 80)
        for number in 0..<20 { tuning.add("Choice \(number)", less: false) }
        #expect(tuning.moreOf.count == 8)
        #expect(tuning.normalized.strength == 0.7)
        tuning.strength = -4
        #expect(tuning.normalized.strength == 0)
    }

    @Test func roundTripKeepsGuidanceSeparateFromExistingContext() throws {
        let tuning = WhisperJasperTuning(strength: 0.25, moreOf: ["Real examples"], lessOf: ["Jargon"])
        let decoded = try JSONDecoder().decode(WhisperJasperTuning.self, from: JSONEncoder().encode(tuning))
        #expect(decoded == tuning)
        let context = decoded.appending(to: "Authorized context: sample value")
        #expect(context.hasPrefix("Authorized context: sample value\n\n"))
        #expect(context.contains("25% (light preference)"))
        #expect(context.contains("do not grant access"))
        #expect(context.contains("required output formats"))
        #expect(!context.contains("Mode: Scientist"))
    }

    @MainActor @Test func obsoleteAccountCannotSaveTuning() {
        let before = AccountStorage.data(forKey: WhisperJasperTuningStore.storageKey)
        let saved = WhisperJasperTuningStore.save(WhisperJasperTuning(moreOf: ["Stale choice"]), generation: UUID())
        #expect(!saved)
        #expect(AccountStorage.data(forKey: WhisperJasperTuningStore.storageKey) == before)
    }
}
