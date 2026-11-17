import UIKit

/// Observes the physical touch sequence without competing with any editing recognizer.
final class WhisperStoryTouchObserver: UIGestureRecognizer {
    var onFirstTouch: ((CGPoint) -> Void)?
    var onLastTouch: ((Bool) -> Void)?
    private var touches: Set<UITouch> = []
    private var cancelled: Bool = false
    private var pendingEnd: (id: UUID, cancelled: Bool)?

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let pendingEnd { flushEnd(pendingEnd.id) }
        if self.touches.isEmpty, let first = touches.min(by: { $0.timestamp < $1.timestamp }) {
            cancelled = false
            onFirstTouch?(first.location(in: view))
        }
        self.touches.formUnion(touches)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        self.cancelled = self.cancelled || cancelled
        self.touches.subtract(touches)
        guard self.touches.isEmpty else { return }
        let token = UUID()
        pendingEnd = (token, self.cancelled)
        // Let pan/pinch/rotation deliver their last delta before ending this exact edit.
        DispatchQueue.main.async { [weak self] in self?.flushEnd(token) }
        state = .failed
    }
    private func flushEnd(_ token: UUID) {
        guard let pendingEnd, pendingEnd.id == token else { return }
        self.pendingEnd = nil
        onLastTouch?(pendingEnd.cancelled)
    }

    func cancelEditing() {
        pendingEnd = nil; touches.removeAll(); cancelled = true
        onLastTouch?(true)
    }

    override func reset() { super.reset(); touches.removeAll(); cancelled = false }
}
