import XCTest
import SwiftUI
import UIKit
@testable import Whisper

@MainActor
final class WhisperTabRenderingTests: XCTestCase {
    func testNavigationContentIsVisibleBeforeIncomingTabIsSelected() async throws {
        try await checkPages(source: 0, target: 3, direction: 1)
    }

    func testAllOtherAdjacentPagesRenderInBothDirections() async throws {
        let order = WhisperRootTabSwipePolicy.order
        for index in 0..<(order.count - 1) {
            if index != 0 { try await checkPages(source: order[index], target: order[index + 1], direction: 1) }
            try await checkPages(source: order[index + 1], target: order[index], direction: -1)
        }
    }

    private func checkPages(source: Int, target: Int, direction: Int) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let pager = WhisperTabPagingState()
        let host = UIHostingController(rootView: Fixture(pager: pager, selection: source, incoming: target))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; pager.reset() }
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        let initialReady = await waitForPixel(in: window, x: window.bounds.width * 0.25, channel: 0)
        XCTAssertTrue(initialReady, "Selected navigation page must render first")
        XCTAssertEqual(pager.begin(selection: source, direction: direction), target)
        for progress: CGFloat in [0.1, 0.5, 0.9] {
            let width = window.bounds.width
            pager.update(translation: -CGFloat(direction) * WhisperTabPagingState.stride(width: width) * progress, width: width)
            let visible = await waitForPixel(in: window, x: width * (direction == 1 ? 0.985 : 0.015), channel: 1)
            XCTAssertEqual(pager.source, source, "Do not select early to force rendering")
            XCTAssertTrue(visible, "Incoming \(target) content missing at \(progress), direction \(direction)")
            let sourceVisible = await waitForPixel(in: window, x: width * (direction == 1 ? 0.015 : 0.985), channel: 0)
            XCTAssertTrue(sourceVisible, "Outgoing content must remain visible")
            let gapX = direction == 1 ? width - WhisperTabPagingState.stride(width: width) * progress + 6 : WhisperTabPagingState.stride(width: width) * progress - 6
            let gapVisible = await waitForPixel(in: window, x: gapX, channel: nil)
            XCTAssertTrue(gapVisible, "The 12-point gutter must stay black, without overlapping navigation backgrounds")
        }
        pager.reset()
        let restored = await waitForPixel(in: window, x: window.bounds.width * 0.25, channel: 0)
        XCTAssertTrue(restored, "Cancelling must restore the original page")
    }

    private func waitForPixel(in window: UIWindow, x: CGFloat, channel: Int?) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        repeat {
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
            var captured = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                captured = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            if captured, let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) {
                var rgba = [UInt8](repeating: 0, count: 4)
                let sampled = rgba.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.translateBy(x: -floor(x), y: -floor(window.bounds.height / 2))
                    context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                    return true
                }
                if sampled {
                    if let channel {
                        if rgba[channel] > 220 && (0..<3).filter({ $0 != channel }).allSatisfy({ rgba[$0] < 40 }) { return true }
                    } else if rgba.prefix(3).allSatisfy({ $0 < 30 }) { return true }
                }
            }
            try? await Task.sleep(for: .milliseconds(25))
        } while ContinuousClock.now < deadline
        return false
    }

    private struct Fixture: View {
        let pager: WhisperTabPagingState
        let selection: Int
        let incoming: Int
        private var pages: [Int: AnyView] {
            Dictionary(uniqueKeysWithValues: WhisperRootTabSwipePolicy.order.map { tab in
                (tab, AnyView(NavigationStack {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<12, id: \.self) { row in
                                Rectangle().fill(Color(.sRGB, red: tab == selection ? 1 : 0, green: tab == incoming ? 1 : 0, blue: tab != selection && tab != incoming ? 1 : 0, opacity: 1))
                                    .frame(height: 100)
                                    .overlay { Text("Page \(tab), row \(row)").foregroundStyle(.black) }
                            }
                        }
                    }.toolbar(.hidden, for: .navigationBar)
                }))
            })
        }
        var body: some View {
            GeometryReader { geometry in
                WhisperTabPager(pages: pages, selection: selection, pager: pager, insets: geometry.safeAreaInsets, isInteractive: true)
                    .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                    .padding(.top, -geometry.safeAreaInsets.top)
                    .padding(.bottom, -geometry.safeAreaInsets.bottom)
                .clipShape(WhisperPagingClip(radius: 0, top: geometry.safeAreaInsets.top, bottom: geometry.safeAreaInsets.bottom))
                .background(Color.black.ignoresSafeArea())
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { Text("Stationary tabs").frame(height: 48) }
        }
    }
}
