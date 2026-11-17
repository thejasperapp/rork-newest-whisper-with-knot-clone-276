import Foundation

/// A deliberately small, process-only LRU. Callers own account reset and
/// freshness policy; no private values are serialized or shared with widgets.
nonisolated struct WhisperRecentMemoryCache<Key: Hashable, Value> {
    let capacity: Int
    private var values: [Key: Value] = [:]
    private var recency: [Key] = []

    mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        recency.removeAll { $0 == key }
        recency.append(key)
        return value
    }

    mutating func insert(_ value: Value, for key: Key) {
        guard capacity > 0 else { return }
        values[key] = value
        recency.removeAll { $0 == key }
        recency.append(key)
        while recency.count > capacity {
            values.removeValue(forKey: recency.removeFirst())
        }
    }

    mutating func removeAll() {
        values.removeAll()
        recency.removeAll()
    }
}
