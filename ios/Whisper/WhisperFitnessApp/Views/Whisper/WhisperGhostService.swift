import SwiftUI

/// Per-post ghost tracking. When the user toggles "Ghost post" in the
/// composer, the resulting post id is added here so the feed and the
/// author's grid can render the dotted-ring "quiet share" indicator.
///
/// We intentionally no longer expose a global "ghost mode" toggle —
/// ghost is a per-post property only.
@MainActor
@Observable
final class WhisperGhostService {
    static let shared = WhisperGhostService()

    private let key = "whisper.ghostPostIDs"
    var ghostPostIDs: Set<String> = []

    private init() {
        if let raw = UserDefaults.standard.array(forKey: key) as? [String] {
            ghostPostIDs = Set(raw)
        }
    }

    func mark(_ id: String) {
        ghostPostIDs.insert(id)
        persist()
    }

    func unmark(_ id: String) {
        ghostPostIDs.remove(id)
        persist()
    }

    func isGhost(_ id: String) -> Bool {
        ghostPostIDs.contains(id)
    }

    private func persist() {
        UserDefaults.standard.set(Array(ghostPostIDs), forKey: key)
    }
}

/// Reusable dotted ring used to mark ghost posts in the feed/grid.
struct WhisperGhostRing: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat
    var lineWidth: CGFloat = 1.8

    var body: some View {
        Circle()
            .strokeBorder(
                WhisperTheme.ink(colorScheme),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    dash: [2.5, 4]
                )
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
