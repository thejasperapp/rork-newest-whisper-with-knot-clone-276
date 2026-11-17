import XCTest
import SwiftUI
import UIKit
@testable import Whisper

@MainActor
final class WhisperEmptyStateTests: XCTestCase {
    func testIllustrationsPaintImmediatelyAtCompactAndFullSizesInBothThemes() throws {
        for scheme: ColorScheme in [.light, .dark] {
            for height: CGFloat in [96, 120, 144, 164] {
                for symbol: String? in [nil, "photo.on.rectangle", "bubble.left.and.bubble.right", "play.rectangle", "folder", "waveform"] {
                    let renderer = ImageRenderer(content: WhisperMeetDoodle(symbol: symbol, height: height)
                        .frame(width: 300).environment(\.colorScheme, scheme))
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage?.cgImage)
                    XCTAssertEqual(image.width, 600)
                    XCTAssertEqual(image.height, Int(height * 2))
                    XCTAssertGreaterThan(try pastelPixels(image), 200, "The drawing must be visible on first render without an appearance task")
                }
            }
        }
    }

    func testEmptyStateTextExpandsForAccessibilityWithoutWideningTheCard() throws {
        for scheme: ColorScheme in [.light, .dark] {
            var normalHeight: CGFloat = 0
            for type: DynamicTypeSize in [.large, .accessibility3] {
                let renderer = ImageRenderer(content: WhisperEmptyState(icon: "bubble.left.and.bubble.right",
                    title: "No messages yet", message: "Start a conversation with someone on Whisper. Your messages will appear here.", actionTitle: "New message", action: {})
                    .frame(width: 320).fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, type))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, 320)
                XCTAssertGreaterThan(image.size.height, 250)
                if type == .large { normalHeight = image.size.height }
                else { XCTAssertGreaterThan(image.size.height, normalHeight) }
            }
        }
    }

    func testAllIllustrationCompositionsAreDistinctAndVisible() throws {
        for scheme: ColorScheme in [.light, .dark] {
            var images = Set<Data>()
            for kind in WhisperIllustrationKind.allCases {
                let renderer = ImageRenderer(content: WhisperEmptyIllustration(kind: kind, height: 144)
                    .frame(width: 300).environment(\.colorScheme, scheme))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertTrue(images.insert(try XCTUnwrap(image.pngData())).inserted, "\(kind) must not reuse another composition")
                XCTAssertGreaterThan(try pastelPixels(try XCTUnwrap(image.cgImage)), 80, "\(kind) must paint on the first frame")
            }
        }
        XCTAssertNotEqual(WhisperIllustrationKind.forSymbol("paperplane"), .photos)
        XCTAssertEqual(WhisperIllustrationKind.forSymbol("waveform"), .audio)
    }

    private func pastelPixels(_ image: CGImage) throws -> Int {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(rendered)
        var count: Int = 0
        for index: Int in stride(from: 0, to: bytes.count, by: 4) {
            let isOpaque = bytes[index + 3] > 200
            let warmth = Int(bytes[index]) - Int(bytes[index + 2])
            if isOpaque && warmth > 25 { count += 1 }
        }
        return count
    }
}
