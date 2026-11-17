import SwiftUI
import UIKit

/// Measures this cover's attached view, not the feed's inherited SwiftUI safe area.
struct WhisperStoryViewportProbe: UIViewRepresentable {
    let onChange: (WhisperStoryViewportGeometry) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.setNeedsLayout()
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: Void) {
        uiView.onChange = nil
        uiView.revision += 1
    }

    final class ProbeView: UIView {
        var onChange: ((WhisperStoryViewportGeometry) -> Void)?
        var revision: Int = 0
        private var lastGeometry: WhisperStoryViewportGeometry?

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            backgroundColor = .clear
            keyboardLayoutGuide.followsUndockedKeyboard = false
            // A constraint dependent on the guide makes dock/undock and height
            // changes participate in layout, without global keyboard notifications.
            let marker = UIView()
            marker.isUserInteractionEnabled = false
            marker.translatesAutoresizingMaskIntoConstraints = false
            addSubview(marker)
            NSLayoutConstraint.activate([
                marker.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
                marker.leadingAnchor.constraint(equalTo: leadingAnchor),
                marker.widthAnchor.constraint(equalToConstant: 0),
                marker.heightAnchor.constraint(equalToConstant: 0)
            ])
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            revision += 1
            lastGeometry = nil
            setNeedsLayout()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window, bounds.width > 0, bounds.height > 0 else { return }
            // Intersection avoids double insetting an already-safe presentation,
            // while restoring physical status/home clearance if a host omitted it.
            let windowSafe = convert(window.safeAreaLayoutGuide.layoutFrame, from: window)
            let localSafe = bounds.intersection(safeAreaLayoutGuide.layoutFrame).intersection(windowSafe)
            guard !localSafe.isNull, localSafe.width > 0, localSafe.height > 0 else { return }
            let geometry = WhisperStoryViewportGeometry(bounds: bounds, safeFrame: localSafe,
                                                         keyboardFrame: keyboardLayoutGuide.layoutFrame)
            guard geometry != lastGeometry else { return }
            lastGeometry = geometry
            revision += 1
            let currentRevision = revision
            // Publish after UIKit's layout transaction, never during SwiftUI updates.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.revision == currentRevision else { return }
                self.onChange?(geometry)
            }
        }
    }
}
