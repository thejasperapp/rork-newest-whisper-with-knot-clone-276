import Foundation

/// Bounded, account-qualified personal templates. No discovery or participation claims.
@MainActor enum WhisperStoryTemplateStore {
    private static let key = "whisper.story.personalTemplates.v1"
    static func load() -> [WhisperStorySavedTemplate] {
        guard let data = AccountStorage.data(forKey: key), data.count <= 1_000_000 else { return [] }
        return (try? JSONDecoder().decode([WhisperStorySavedTemplate].self, from: data)) ?? []
    }
    static func save(_ template: WhisperStorySavedTemplate, generation: UUID) -> Bool {
        guard generation == AccountStorage.generation, UUID(uuidString: AccountStorage.currentUserID) != nil else { return false }
        var values = load().filter { $0.id != template.id }
        values.insert(template, at: 0)
        guard let data = try? JSONEncoder().encode(Array(values.prefix(30))), data.count <= 1_000_000 else { return false }
        AccountStorage.set(data, forKey: key)
        return true
    }
    static func remove(_ id: String, generation: UUID) {
        guard generation == AccountStorage.generation, let data = try? JSONEncoder().encode(load().filter { $0.id != id }) else { return }
        AccountStorage.set(data, forKey: key)
    }
}
