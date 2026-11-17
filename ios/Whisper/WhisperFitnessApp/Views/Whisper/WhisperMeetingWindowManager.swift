import SwiftUI
import UIKit

/// Hosts the meeting room in its own window (same pattern as
/// `WhisperCallWindowManager`) and adds in-app picture-in-picture: the gray
/// chevron collapses the meeting into a draggable corner tile so the rest of
/// the app stays fully usable while the call keeps running. Tapping the tile
/// brings the meeting back full screen.
@MainActor
@Observable
final class WhisperMeetingWindow {
    static let shared = WhisperMeetingWindow()

    private(set) var meeting: WhisperMeetingRow?
    var minimized: Bool = false
    /// Global frame of the mini tile — while minimized the passthrough
    /// window only accepts touches inside this rect.
    var tileFrame: CGRect = .zero

    private var window: UIWindow?
    var mediaInUse: Bool = false

    private init() {}

    var isPresenting: Bool { window != nil }

    private func bestScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    /// Presents the meeting room over everything. Re-presenting the same
    /// meeting just restores it from the mini tile.
    func present(_ row: WhisperMeetingRow) {
        let calls = WhisperCallService.shared
        if row.isGroupCall {
            calls.joinGroupCall(room: row)
            return
        }
        if let call = calls.active {
            if call.roomID != row.id { calls.lastErrorMessage = "Leave this call before opening another meeting." }
            WhisperCallWindowManager.shared.restore()
            return
        }
        guard !calls.isStarting else { return }
        if let current = meeting, current.id == row.id, window != nil {
            restore()
            return
        }
        guard window == nil, !mediaInUse else {
            restore()
            let alert = UIAlertController(title: "Finish the open meeting first", message: "Leave your current meeting before opening another. Your call has not been interrupted.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            if let host = window?.rootViewController, host.presentedViewController == nil { host.present(alert, animated: true) }
            return
        }
        guard let scene = bestScene() else { return }

        meeting = row
        minimized = false
        tileFrame = .zero

        let host = UIHostingController(rootView: WhisperMeetingWindowRoot(meeting: row).scrollIndicators(.hidden))
        host.view.backgroundColor = .clear
        host.overrideUserInterfaceStyle = .dark

        let w = WhisperPassthroughWindow(windowScene: scene)
        w.rootViewController = host
        // Below the call window (.alert + 1) so incoming calls stay on top.
        w.windowLevel = .alert
        w.backgroundColor = .clear
        w.alpha = 0
        w.isHidden = false
        w.makeKeyAndVisible()
        window = w

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            w.alpha = 1
        }
    }

    /// Collapses the meeting into the draggable corner tile.
    func minimize() {
        guard window != nil, !minimized else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            minimized = true
        }
        // Hand key status back to the app so text fields keep working.
        if let scene = window?.windowScene {
            scene.windows
                .first { $0 !== window && !$0.isHidden && $0.windowLevel == .normal }?
                .makeKey()
        }
    }

    /// Brings the meeting back full screen from the tile.
    func restore() {
        guard window != nil, minimized else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            minimized = false
        }
        window?.makeKey()
    }

    /// Fades the meeting window out and releases it. Idempotent.
    func close() {
        meeting = nil
        minimized = false
        tileFrame = .zero
        guard let w = window else { return }
        window = nil
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            w.alpha = 0
        } completion: { _ in
            w.isHidden = true
            w.rootViewController = nil
        }
    }
}

/// While minimized, only the mini tile accepts touches — everything else
/// falls straight through to the app underneath.
final class WhisperPassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = super.hitTest(point, with: event) else { return nil }
        let manager = WhisperMeetingWindow.shared
        guard manager.minimized else { return result }
        return manager.tileFrame.insetBy(dx: -10, dy: -10).contains(point) ? result : nil
    }
}

/// Root content of the meeting window: the full meeting room (kept alive
/// while minimized so WebRTC, transcription and state all survive) plus the
/// draggable mini tile on top.
private struct WhisperMeetingWindowRoot: View {
    let meeting: WhisperMeetingRow

    private var manager: WhisperMeetingWindow { WhisperMeetingWindow.shared }

    var body: some View {
        ZStack {
            // NOTE: no `.ignoresSafeArea()` here — the call stage already
            // full-bleeds internally, and stripping the window's safe area
            // used to distort the recap notes screen (content laid out wider
            // than the physical screen, text cut off at both edges).
            WhisperMeetingRoomView(
                meeting: meeting,
                supportsMinimize: true,
                onRequestClose: { if WhisperMeetingWindow.shared.meeting?.id == meeting.id { WhisperMeetingWindow.shared.close() } }
            )
            .opacity(manager.minimized ? 0 : 1)
            .allowsHitTesting(!manager.minimized)

            if manager.minimized {
                WhisperMeetingMiniTile(meeting: meeting)
                    .transition(.scale(scale: 0.55, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: manager.minimized)
    }
}

/// The floating in-app PiP tile — shows the local camera, drags anywhere
/// (snapping to the nearest side), and restores the meeting on tap.
private struct WhisperMeetingMiniTile: View {
    let meeting: WhisperMeetingRow

    /// Committed tile center; nil → default bottom-right corner.
    @State private var center: CGPoint?
    @State private var drag: CGSize = .zero

    private let tileSize = CGSize(width: 122, height: 172)
    private let margin: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let defaultCenter = CGPoint(
                x: geo.size.width - tileSize.width / 2 - margin,
                y: geo.size.height - tileSize.height / 2 - 108
            )
            let base = center ?? defaultCenter
            let current = CGPoint(x: base.x + drag.width, y: base.y + drag.height)

            tile
                .frame(width: tileSize.width, height: tileSize.height)
                .position(current)
                .onTapGesture {
                    Haptics.tap()
                    WhisperMeetingWindow.shared.restore()
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            drag = value.translation
                            report(centeredAt: CGPoint(
                                x: base.x + value.translation.width,
                                y: base.y + value.translation.height
                            ))
                        }
                        .onEnded { value in
                            let raw = CGPoint(
                                x: base.x + value.translation.width,
                                y: base.y + value.translation.height
                            )
                            let snapped = snap(raw, in: geo.size)
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                                center = snapped
                                drag = .zero
                            }
                            report(centeredAt: snapped)
                        }
                )
                .onAppear { report(centeredAt: current) }
        }
        .ignoresSafeArea()
    }

    private var tile: some View {
        ZStack {
            Color(white: 0.09)
            WhisperLiveVideoView(
                source: .local,
                mirror: !WhisperLiveRTCService.shared.isScreenSharing,
                fit: WhisperLiveRTCService.shared.isScreenSharing
            )
            .allowsHitTesting(false)
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear, .clear, Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(WhisperRecordingConsentService.shared.isRecording ? Color.red : Color.white.opacity(0.7))
                        .frame(width: 5, height: 5)
                    Text(WhisperRecordingConsentService.shared.isRecording ? "RECORDING" : meeting.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("Tap to return")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Clamps vertically and snaps horizontally to the nearest side.
    private func snap(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let halfW = tileSize.width / 2
        let halfH = tileSize.height / 2
        let x = point.x < size.width / 2
            ? halfW + margin
            : size.width - halfW - margin
        let minY = halfH + 66
        let maxY = size.height - halfH - 44
        let y = min(max(point.y, minY), maxY)
        return CGPoint(x: x, y: y)
    }

    private func report(centeredAt point: CGPoint) {
        WhisperMeetingWindow.shared.tileFrame = CGRect(
            x: point.x - tileSize.width / 2,
            y: point.y - tileSize.height / 2,
            width: tileSize.width,
            height: tileSize.height
        )
    }
}
