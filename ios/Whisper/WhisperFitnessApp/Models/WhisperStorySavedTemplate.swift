import Foundation

/// Personal reusable layers only; never silently includes the Story's background media.
nonisolated struct WhisperStorySavedTemplate: Codable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var stickers: [WhisperStorySticker]
    var referenceWidth: Double

    func layers(for width: Double) -> [WhisperStorySticker] {
        stickers.map { layer in
            var copy = layer
            copy.id = UUID().uuidString
            if copy.cardWidthFraction == nil { copy.scale *= width / max(1, referenceWidth) }
            return copy
        }
    }
}
