import Foundation

/// Epoch-qualified snapshot keys make a late extension write invisible after account changes.
nonisolated final class WhisperWidgetSnapshotDefaults: @unchecked Sendable {
    private let defaults: UserDefaults
    private let epoch: String
    init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
        epoch = defaults.string(forKey: "whisper_snapshot_epoch") ?? "initial"
    }
    private func key(_ key: String) -> String {
        if key.hasPrefix("whisper_session_") || key == "whisper_snapshot_epoch" { return key }
        return "whisper_snapshot:\(epoch):\(key)"
    }
    private var isCurrent: Bool { epoch == (defaults.string(forKey: "whisper_snapshot_epoch") ?? "initial") }
    func set(_ value: Any?, forKey name: String) { if isCurrent { defaults.set(value, forKey: key(name)) } }
    func removeObject(forKey name: String) { defaults.removeObject(forKey: key(name)) }
    func string(forKey name: String) -> String? { isCurrent ? defaults.string(forKey: key(name)) : nil }
    func data(forKey name: String) -> Data? { isCurrent ? defaults.data(forKey: key(name)) : nil }
    func integer(forKey name: String) -> Int { isCurrent ? defaults.integer(forKey: key(name)) : 0 }
    func double(forKey name: String) -> Double { isCurrent ? defaults.double(forKey: key(name)) : 0 }
    func bool(forKey name: String) -> Bool { isCurrent && defaults.bool(forKey: key(name)) }
}
