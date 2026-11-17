import SwiftUI
import Observation

/// Only the provisional bubble observes text changes. The chat's history,
/// composer and Events projection do not depend on every provider token.
@Observable @MainActor final class WhisperKnotReplyStream {
    private(set) var displayed = ""
    @ObservationIgnored private(set) var latest = ""
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var publication: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()

    func replace(_ text: String) {
        revision = UUID(); publication?.cancel(); publication = nil
        latest = text; displayed = text
    }
    func offer(_ text: String) {
        // An explicit transport clear is terminal, not a deferred update.
        guard !text.isEmpty else { replace(""); return }
        latest = text
        schedule()
    }
    func setPaused(_ value: Bool) {
        paused = value
        if value { publication?.cancel(); publication = nil }
        else { schedule() }
    }
    func flush() {
        publication?.cancel(); publication = nil
        guard !paused, displayed != latest else { return }
        displayed = latest
    }
    private func schedule() {
        guard !paused, publication == nil, displayed != latest else { return }
        let operation = revision
        publication = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                guard let self, self.revision == operation, !self.paused else { return }
                guard self.displayed != self.latest else { self.publication = nil; return }
                // Smooth bursty provider chunks without splitting graphemes. An
                // authoritative replacement is never appended to obsolete text.
                if self.latest.hasPrefix(self.displayed) {
                    let remaining = self.latest.dropFirst(self.displayed.count)
                    let amount = min(remaining.count, max(2, (remaining.count + 7) / 8))
                    self.displayed.append(contentsOf: remaining.prefix(amount))
                } else { self.displayed = self.latest }
            }
        }
    }
}

struct WhisperKnotPendingReply: View {
    let stream: WhisperKnotReplyStream
    let progress: WhisperKnotTurnProgress
    let bot: WhisperKnotBot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(progress.updates.enumerated()), id: \.offset) { _, update in
                WhisperKnotReplyBubble(text: update, bot: bot)
            }
            WhisperKnotReplyBubble(text: stream.displayed, waiting: true, bot: bot)
        }
    }
}
