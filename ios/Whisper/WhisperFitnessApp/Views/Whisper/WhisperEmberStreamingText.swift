import SwiftUI

/// Typewriter-style streaming text. Reveals characters gradually so Jasper's
/// replies feel generated live without needing token streaming on the backend.
struct WhisperEmberStreamingText: View {
    let text: String
    var font: Font = .subheadline
    var color: Color = .primary
    /// Characters per second to reveal. ~90 cps feels fast but readable.
    var charsPerSecond: Double = 90
    /// Skip the animation for very short replies (avoids janky 1-word reveals).
    var minCharsToAnimate: Int = 16
    var onFinished: (() -> Void)? = nil

    @State private var visibleCount: Int = 0
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Text(visiblePrefix)
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { start() }
            .onChange(of: text) { _, _ in start() }
            .onDisappear { revealTask?.cancel() }
    }

    private var visiblePrefix: String {
        if visibleCount >= text.count { return text }
        let idx = text.index(text.startIndex, offsetBy: max(0, min(visibleCount, text.count)))
        return String(text[..<idx])
    }

    private func start() {
        revealTask?.cancel()
        if text.count < minCharsToAnimate {
            visibleCount = text.count
            onFinished?()
            return
        }
        visibleCount = 0
        let interval = UInt64(1_000_000_000.0 / max(20, charsPerSecond))
        let total = text.count
        revealTask = Task { @MainActor in
            while visibleCount < total {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                visibleCount = min(total, visibleCount + 2)
            }
            onFinished?()
        }
    }
}
