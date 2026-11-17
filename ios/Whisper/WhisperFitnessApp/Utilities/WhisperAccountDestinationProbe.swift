import SwiftUI
import UIKit

/// Acknowledges a prepared destination when it actually attaches and lays out.
struct WhisperAccountDestinationProbe: UIViewRepresentable {
    let generation: UUID?

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.generation = generation
        view.scheduleAcknowledgement()
    }

    final class Probe: UIView {
        var generation: UUID?
        private var scheduled: Bool = false
        override func didMoveToWindow() { super.didMoveToWindow(); scheduleAcknowledgement() }
        override func layoutSubviews() { super.layoutSubviews(); scheduleAcknowledgement() }

        func scheduleAcknowledgement() {
            guard !scheduled, generation != nil, window != nil else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                guard let generation = self.generation, self.window != nil else { return }
                WhisperAccountTransition.shared.destinationDidLayout(generation: generation)
            }
        }
    }
}
