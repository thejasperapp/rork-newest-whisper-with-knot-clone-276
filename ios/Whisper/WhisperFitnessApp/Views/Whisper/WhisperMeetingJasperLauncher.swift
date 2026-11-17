import SwiftUI

/// Reuses the original mint shell and living mascot, without coupling the launcher to capture.
struct WhisperMeetingJasperLauncher: View {
    let size: CGSize
    let insets: EdgeInsets
    let bottomClearance: CGFloat
    let isVisible: Bool
    let mode: WhisperEmberCoachMode
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag: CGSize = .zero
    @State private var placement: CGPoint = CGPoint(x: 0, y: 1)
    @State private var measuredSize: CGSize = CGSize(width: 140, height: 74)
    @State private var hasEntered: Bool = false

    private var bounds: CGRect {
        let x = insets.leading + 16 + measuredSize.width / 2
        let y = insets.top + 62 + measuredSize.height / 2
        return CGRect(x: x, y: y,
            width: max(0, size.width - insets.trailing - 16 - measuredSize.width / 2 - x),
            height: max(0, size.height - bottomClearance - measuredSize.height / 2 - y))
    }
    private var restingPoint: CGPoint {
        CGPoint(x: bounds.minX + bounds.width * placement.x, y: bounds.minY + bounds.height * placement.y)
    }
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(bounds.maxX, max(bounds.minX, point.x)), y: min(bounds.maxY, max(bounds.minY, point.y)))
    }

    var body: some View {
        let point = clamped(CGPoint(x: restingPoint.x + drag.width, y: restingPoint.y + drag.height))
        Button {
            guard drag == .zero else { return }
            Haptics.tap()
            onOpen()
        } label: {
            Text("Ask Jasper")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(WhisperEmberPillPalette.ink(for: mode))
                .lineLimit(1)
                .padding(.horizontal, 20)
                .frame(minHeight: 34)
                .background { WhisperEmberMintShell(shape: Capsule(), mode: mode) }
                .background(alignment: .top) {
                    WhisperEmberMascot(size: 50, isActive: false, expression: .calm, coachMode: mode, cyclesExpressions: !reduceMotion)
                        .phaseAnimator([false, true]) { face, phase in
                            face.offset(y: reduceMotion ? 0 : phase ? 2 : -2)
                        } animation: { _ in .easeInOut(duration: 1.7) }
                        .offset(y: -26)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .padding(.top, 30)
                .padding(.bottom, 5)
                .frame(minHeight: 74)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { measuredSize = $0 }
        .highPriorityGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .named("meetingJasperDrag"))
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    let end = clamped(CGPoint(x: restingPoint.x + value.translation.width, y: restingPoint.y + value.translation.height))
                    placement = CGPoint(x: bounds.width > 0 ? (end.x - bounds.minX) / bounds.width : 0,
                                        y: bounds.height > 0 ? (end.y - bounds.minY) / bounds.height : 1)
                    Haptics.soft()
                }
        )
        .accessibilityLabel("Ask Jasper")
        .accessibilityHint("Opens private meeting questions. Drag to move, or use position actions.")
        .accessibilityAction(named: "Move to bottom left") { move(x: 0, y: 1) }
        .accessibilityAction(named: "Move to bottom right") { move(x: 1, y: 1) }
        .accessibilityAction(named: "Move to top left") { move(x: 0, y: 0) }
        .accessibilityAction(named: "Move to top right") { move(x: 1, y: 0) }
        .opacity(isVisible && hasEntered ? 1 : 0)
        .allowsHitTesting(isVisible && hasEntered)
        .accessibilityHidden(!isVisible)
        .offset(y: hasEntered || reduceMotion ? 0 : 150)
        .position(point)
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "meetingJasperDrag")
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.68).delay(0.5)) { hasEntered = true }
        }
    }

    private func move(x: CGFloat, y: CGFloat) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            placement = CGPoint(x: x, y: y)
        }
    }
}
