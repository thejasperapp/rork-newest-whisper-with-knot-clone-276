import XCTest
import SwiftUI
import UIKit
@testable import Whisper

@MainActor
final class WhisperVisualPolishTests: XCTestCase {
    func testEveryThemeHasReadableOpaqueBubblesInBothModes() throws {
        for scheme: ColorScheme in [.light, .dark] {
            for theme in WhisperChatAppearance.allCases {
                let palette = theme.palette(scheme)
                for mine in [false, true] {
                    let text = try luminance(palette.text(mine: mine))
                    let fill = try luminance(palette.fill(mine: mine))
                    let contrast = (max(text, fill) + 0.05) / (min(text, fill) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 4.5, "\(theme) \(scheme) mine=\(mine)")
                }
                let image = ImageRenderer(content: WhisperChatThemePreview(theme: theme)
                    .frame(width: 320, height: 250).environment(\.colorScheme, scheme)).uiImage
                XCTAssertNotNil(image)
            }
        }
    }

    func testAIThemePigmentsRemainReadableAtExtremes() throws {
        for scheme: ColorScheme in [.light, .dark] {
            for hex in ["#FFFFFF", "#000000", "#00FF00", "#FFFF00", "#FF0000", "#0000FF"] {
                var design = WhisperChatThemeDesign(theme: .tide)
                design.accent_hex = hex
                let palette = design.palette(scheme)
                for mine in [true, false] {
                    let text = try luminance(palette.text(mine: mine))
                    let fill = try luminance(palette.fill(mine: mine))
                    XCTAssertGreaterThanOrEqual((max(text,fill)+0.05)/(min(text,fill)+0.05),4.5)
                }
            }
        }
    }

    func testComposerGlassRendersAcrossThemesWithLargeText() throws {
        for scheme: ColorScheme in [.light, .dark] {
            for theme in WhisperChatAppearance.allCases {
                let content = HStack {
                    WhisperChatPlusButton(isOpen: false) {}
                    WhisperChatField(focused: true) { Text("Message").font(.body).padding(10) }
                    WhisperChatSendButton(enabled: true, sending: false) {}
                }
                .padding(8)
                .background { WhisperChatComposerGlass() }
                .environment(\.whisperChatAppearance, theme)
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, .accessibility2)
                .frame(width: 320)
                let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
                XCTAssertEqual(image.size.width, 320, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(image.size.height, 44)
            }
        }
    }

    func testHeaderShelvesWithoutMovingBottomTabsAndIgnoresInactiveScroll() {
        let shelf = WhisperHeaderShelfState()
        let bottom = WhisperTabBarVisibility.shared.isHidden
        shelf.update(old: 50, new: 70, enabled: false)
        XCTAssertFalse(shelf.isHidden)
        shelf.update(old: 50, new: 70, enabled: true)
        XCTAssertTrue(shelf.isHidden)
        XCTAssertEqual(bottom, WhisperTabBarVisibility.shared.isHidden)
        shelf.update(old: 70, new: 55, enabled: true)
        XCTAssertFalse(shelf.isHidden)
        shelf.update(old: 80, new: 120, enabled: true)
        shelf.update(old: 120, new: 12, enabled: true)
        XCTAssertFalse(shelf.isHidden)
    }

    func testTabCommitAdoptsRendererSelectionBeforeReset() async {
        let pager = WhisperTabPagingState()
        var displayed: Int = 0
        var renderedAfterCommit: [Int] = []
        var committed: Bool = false
        pager.adoptSelection = { displayed = $0 }
        pager.renderPages = { if committed { renderedAfterCommit.append(displayed) } }
        XCTAssertEqual(pager.begin(selection: 0, direction: 1), 3)
        pager.update(translation: -180, width: 390)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pager.settle(commit: true, velocity: 800, reduceMotion: true) { destination in
                XCTAssertEqual(displayed, 3, "Renderer must adopt before SwiftUI selection can reset the gesture")
                XCTAssertEqual(destination, 3)
                committed = true
                continuation.resume()
            }
        }
        XCTAssertNil(pager.source)
        XCTAssertFalse(renderedAfterCommit.isEmpty)
        XCTAssertTrue(renderedAfterCommit.allSatisfy { $0 == 3 })
    }

    func testDetachedPredecessorCannotCreateBlankReveal() {
        let surface = UIView(frame: CGRect(x: 0,y: 0,width: 390,height: 844))
        let detached = UIView(frame: surface.bounds)
        detached.backgroundColor = .gray
        XCTAssertNil(WhisperNavigationSnapshots.captureAttached(detached))
        XCTAssertNil(WhisperBackRevealSession(surface: surface, predecessor: detached))
    }

    func testRetainedHostsReceiveSelectedOnlyActivity() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let pager = WhisperTabPagingState()
        var observed: [Int: Bool] = [:]
        let pages = [0: AnyView(ActivityProbe { observed[0] = $0 }), 3: AnyView(ActivityProbe { observed[3] = $0 })]
        let host = UIHostingController(rootView: WhisperTabPager(pages: pages, selection: 0, pager: pager, insets: .init(), isInteractive: true))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; pager.reset() }
        let deadline = ContinuousClock.now + .seconds(2)
        while observed.count < 2 && ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertEqual(observed[0], true)
        XCTAssertEqual(observed[3], false, "The forwarded environment must not re-enable a retained inactive root")
    }

    private struct ActivityProbe: View {
        let report: (Bool) -> Void
        @Environment(\.whisperRootChromeActive) private var active
        var body: some View {
            Text("Retained page").onChange(of: active, initial: true) { _, value in report(value) }
        }
    }

    private func luminance(_ color: Color) throws -> Double {
        let resolved = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(a, 1, accuracy: 0.001)
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
