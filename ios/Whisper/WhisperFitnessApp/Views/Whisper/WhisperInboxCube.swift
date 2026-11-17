import SwiftUI
import UIKit

/// The parent tab pager yields only inside this list's visible rectangle.
/// No global tab lock is needed, and search/stories keep their own gestures.
enum WhisperInboxFlipRegion {
    private static let views = NSHashTable<UIView>.weakObjects()
    static func add(_ view: UIView) { views.add(view) }
    static func remove(_ view: UIView) { views.remove(view) }
    static func contains(_ point: CGPoint, in window: UIWindow) -> Bool {
        views.allObjects.contains { view in
            guard view.window === window, view.bounds.width > 0 else { return false }
            var ancestor: UIView? = view
            while let current = ancestor {
                if current.isHidden || current.alpha < 0.01 { return false }
                ancestor = current.superview
            }
            return view.convert(view.bounds, to: window).contains(point)
        }
    }
}
private final class WhisperInboxFlipProbe: UIView {
    var attach: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); attach?() }
}

private struct WhisperInboxFlipMarker: UIViewRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat, Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(changed: changed, ended: ended) }
    func makeUIView(context: Context) -> WhisperInboxFlipProbe {
        let view = WhisperInboxFlipProbe(); view.isUserInteractionEnabled = false
        WhisperInboxFlipRegion.add(view)
        context.coordinator.probe = view
        view.attach = { [weak coordinator = context.coordinator] in coordinator?.install() }
        return view
    }
    func updateUIView(_ view: WhisperInboxFlipProbe, context: Context) {
        context.coordinator.changed = changed; context.coordinator.ended = ended
        context.coordinator.install()
    }
    static func dismantleUIView(_ view: WhisperInboxFlipProbe, coordinator: Coordinator) {
        view.attach = nil; coordinator.remove(); WhisperInboxFlipRegion.remove(view)
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var probe: UIView?
        weak var host: UIScrollView?
        var changed: (CGFloat) -> Void
        var ended: (CGFloat, CGFloat, Bool) -> Void
        private var pan: UIPanGestureRecognizer?
        init(changed: @escaping (CGFloat) -> Void, ended: @escaping (CGFloat, CGFloat, Bool) -> Void) {
            self.changed = changed; self.ended = ended
        }
        func install() {
            guard pan == nil, let probe, probe.window != nil else { return }
            var ancestor = probe.superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
                    recognizer.delegate = self
                    recognizer.cancelsTouchesInView = true
                    recognizer.maximumNumberOfTouches = 1
                    scroll.addGestureRecognizer(recognizer)
                    // Vertical drags fail our direction check immediately, then scroll normally.
                    scroll.panGestureRecognizer.require(toFail: recognizer)
                    host = scroll; pan = recognizer
                    return
                }
                ancestor = view.superview
            }
        }
        func remove() {
            if let pan { host?.removeGestureRecognizer(pan) }
            pan = nil; host = nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let probe, probe.window != nil else { return false }
            return probe.bounds.contains(touch.location(in: probe))
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: host)
            return abs(velocity.x) > abs(velocity.y) * 1.6
        }
        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            let travel = pan.translation(in: host).x
            switch pan.state {
            case .began, .changed: changed(travel)
            case .ended: ended(travel, travel + pan.velocity(in: host).x * 0.2, false)
            case .cancelled, .failed: ended(travel, travel, true)
            default: break
            }
        }
    }
}

private struct WhisperInboxCubeLayout: Layout {
    let back: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let content = subviews[back ? 1 : 0].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? content.width, height: max(340, content.height))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

struct WhisperInboxCube<Front: View, Back: View>: View {
    @Binding var disappearing: Bool
    let active: Bool
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var translation: CGFloat = 0
    @State private var width: CGFloat = 1
    @AppStorage("whisper.inbox.swipe-discovery.v1") private var discoveredSwipe = false
    @State private var showingHint = false
    @State private var hintTravel = false
    @State private var settling = false
    @State private var settlingID = UUID()

    private var progress: CGFloat {
        min(1, max(0, (disappearing ? 1 : 0) - translation / max(1, width)))
    }
    var body: some View {
        WhisperInboxCubeLayout(back: disappearing) {
            front()
                .frame(maxWidth: .infinity)
                .background(WhisperTheme.surface(scheme))
                .rotation3DEffect(.degrees(reduceMotion ? 0 : -90 * progress), axis: (0, 1, 0), anchor: .trailing, perspective: 0.5)
                .offset(x: reduceMotion ? 0 : -width * progress)
                .opacity(reduceMotion ? 1 - progress : progress >= 0.999 ? 0 : 1)
                .allowsHitTesting(!disappearing && translation == 0 && !settling)
                .accessibilityHidden(disappearing)
                .environment(\.whisperMediaActive, active && !disappearing)
            back()
                .frame(maxWidth: .infinity)
                .background(WhisperTheme.surface(scheme))
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 90 * (1 - progress)), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
                .offset(x: reduceMotion ? 0 : width * (1 - progress))
                .opacity(reduceMotion ? progress : progress <= 0.001 ? 0 : 1)
                .allowsHitTesting(disappearing && translation == 0 && !settling)
                .accessibilityHidden(!disappearing)
        }
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
        .overlay(alignment: .top) {
            if showingHint && active && !disappearing {
                swipeHint.padding(.top, 32).transition(.opacity)
            }
        }
        .task(id: active) {
            guard active, !discoveredSwipe, !disappearing else { return }
            do {
                try await Task.sleep(for: .milliseconds(700))
                guard active, !discoveredSwipe, !disappearing else { return }
                discoveredSwipe = true
                withAnimation(.easeInOut(duration: 0.2)) { showingHint = true }
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { hintTravel = true }
                }
                try await Task.sleep(for: .seconds(6))
                finishDiscovery()
            } catch {
                showingHint = false; hintTravel = false
            }
        }
        .onChange(of: disappearing) { _, _ in finishDiscovery() }
        .background {
            if active {
                WhisperInboxFlipMarker { travel in
                    translation = travel
                } ended: { travel, predicted, cancelled in
                    settling = true
                    let token = UUID(); settlingID = token
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        if settlingID == token { settling = false }
                    }
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .whisperSmooth) {
                        translation = 0
                        if !cancelled, abs(travel) > 54 || abs(predicted) > width * 0.35 {
                            disappearing = travel < 0
                            Haptics.tap()
                        }
                    }
                }
            }
        }
        .onChange(of: active) { _, visible in if !visible { translation = 0; settling = false } }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.9), value: disappearing)
        .accessibilityAction(named: disappearing ? "Show messages" : "Show Flicks") { disappearing.toggle() }
    }

    private var swipeHint: some View {
        HStack(spacing: 8) {
            Button {
                finishDiscovery()
                withAnimation(.whisperSmooth) { disappearing = true }
                Haptics.tap()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Capsule().fill(.orange.opacity(0.16)).frame(width: 82, height: 36)
                        Image(systemName: "arrow.left").font(.caption.bold())
                            .foregroundStyle(.orange).offset(x: -24)
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 31, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                            .rotationEffect(.degrees(reduceMotion ? -12 : hintTravel ? -18 : 4))
                            .offset(x: reduceMotion ? 8 : hintTravel ? -16 : 22, y: 3)
                    }.accessibilityHidden(true)
                    Text("Swipe for Flicks").font(.subheadline.bold())
                        .foregroundStyle(WhisperTheme.ink(scheme))
                }
            }.buttonStyle(.plain)
            Button { finishDiscovery() } label: {
                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(WhisperTheme.ink(scheme))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Dismiss swipe hint")
        }
        .padding(.leading, 12).padding(.vertical, 6)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.orange.opacity(0.25), lineWidth: 1).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .padding(.horizontal, 16)
    }

    private func finishDiscovery() {
        discoveredSwipe = true
        withAnimation(.easeOut(duration: 0.2)) { showingHint = false }
        hintTravel = false
    }
}
