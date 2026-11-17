import SwiftUI

/// Only the moving wrappers observe progress. Drag samples do not rebuild the
/// feed, message index, or video hierarchy on every display frame.
@MainActor @Observable
final class WhisperTabPagingState {
    private(set) var source: Int?
    private(set) var target: Int?
    private(set) var direction: Int = 1
    var progress: CGFloat = 0 { didSet { renderPages?() } }
    @ObservationIgnored var renderPages: (() -> Void)?
    @ObservationIgnored var adoptSelection: ((Int) -> Void)?
    @ObservationIgnored var renderOwner: UUID?
    @ObservationIgnored private let settleDriver = WhisperTabSettleDriver()
    private(set) var isSettling: Bool = false
    private var operation: UUID = UUID()
    private var generation: UUID = AccountStorage.generation

    @discardableResult
    func begin(selection: Int, direction: Int) -> Int? {
        guard source == nil, !isSettling,
              let next = WhisperRootTabSwipePolicy.adjacent(to: selection, direction: direction) else { return nil }
        operation = UUID(); generation = AccountStorage.generation
        source = selection; target = next; self.direction = direction; progress = 0
        return next
    }

    func update(translation: CGFloat, width: CGFloat) {
        guard source != nil, !isSettling, generation == AccountStorage.generation else { return }
        progress = WhisperBackRevealStyle.progress(translation: -CGFloat(direction) * translation, width: Self.stride(width: width))
    }

    func settle(commit: Bool, velocity: CGFloat, reduceMotion: Bool, completion: @escaping (Int?) -> Void) {
        guard source != nil, !isSettling else { return }
        let token = operation
        let next = target
        isSettling = true
        let duration: Double = reduceMotion ? 0.1 : (abs(velocity) > 900 ? 0.24 : 0.32)
        let start = progress
        let destination: CGFloat = commit ? 1 : 0
        settleDriver.start(duration: duration, sample: { [weak self] fraction in
            guard let self, self.operation == token, self.generation == AccountStorage.generation else { return }
            self.progress = start + (destination - start) * fraction
        }, completion: { [weak self] in
            guard let self, self.operation == token, self.generation == AccountStorage.generation else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                if commit, let next { self.adoptSelection?(next) }
                completion(commit ? next : nil)
                self.reset()
            }
        })
    }

    func reset() {
        settleDriver.stop()
        operation = UUID(); source = nil; target = nil; progress = 0; isSettling = false
    }

    /// The reference keeps a 12-point black gutter between full-width pages.
    nonisolated static func stride(width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        return width + 12
    }

    nonisolated static func cornerRadius(progress: CGFloat, width: CGFloat) -> CGFloat {
        guard progress.isFinite, width.isFinite, width > 0 else { return 0 }
        let p = min(1, max(0, progress))
        let travelFromRest = min(p, 1 - p) * stride(width: width)
        return min(52, width * 0.14) * min(1, travelFromRest / 24)
    }

    nonisolated static func offset(isSource: Bool, direction: Int, progress: CGFloat, width: CGFloat) -> CGFloat {
        guard progress.isFinite, width.isFinite, width > 0 else { return 0 }
        let p = min(1, max(0, progress))
        return CGFloat(direction) * stride(width: width) * (isSource ? -p : 1 - p)
    }
}
