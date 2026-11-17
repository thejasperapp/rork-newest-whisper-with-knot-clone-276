import Foundation

/// Stable publication identity lets an ambiguous network reply be reconciled before retry.
nonisolated struct WhisperPendingThreadPart: Identifiable {
    let id: String = UUID().uuidString.lowercased()
    let body: String
}
