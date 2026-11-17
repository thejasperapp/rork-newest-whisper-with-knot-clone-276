import SwiftUI

/// Screen-scoped authorization stays with the caller; arrows and swipes share
/// the same renderer, and an already committed gesture never animates twice.
@MainActor
final class WhisperBackAction {
    var animate: ((@escaping () -> Void) -> Void)?
    var captureLocal: (() -> Void)?
    var makeVerticalReveal: (() -> WhisperBackRevealSession?)?
    private var isCommitting: Bool = false
    private let generation = AccountStorage.generation

    func captureLocalPredecessor() { captureLocal?() }

    func perform(_ action: @escaping () -> Void) {
        guard generation == AccountStorage.generation else { return }
        if isCommitting { action() }
        else if let animate { animate(action) }
        else { action() }
    }

    func commit(_ action: () -> Void) {
        guard !isCommitting else { return }
        isCommitting = true
        defer { isCommitting = false }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { action() }
    }
}
