import Testing
import SwiftUI
import UIKit
@testable import Whisper

@MainActor
struct WhisperJasperIntelligenceTests {
    @Test func capsuleKeepsOpaqueWhiteFillAndWarmDirectionalRimInBothThemes() throws {
        for scheme: ColorScheme in [.light, .dark] {
            let renderer = ImageRenderer(content: WhisperJasperIntelligenceShell(shape: Capsule())
                .frame(width: 260, height: 50).environment(\.colorScheme, scheme))
            renderer.scale = 2
            let image = try #require(renderer.uiImage?.cgImage)
            let center = try pixel(image, x: 260, y: 50)
            #expect(center[0] > 245 && center[1] > 245 && center[2] > 245 && center[3] == 255)
            let left = try pixel(image, x: 1, y: 50)
            let right = try pixel(image, x: 518, y: 50)
            #expect(left[0] > left[1] && left[0] > left[2])
            #expect(right[0] > right[2] && right[1] > left[1])
        }
    }

    @Test func pearlHeadPeeksAboveAnOpaquePillOnFirstRender() throws {
        let renderer = ImageRenderer(content: WhisperJasperIntelligencePill()
            .frame(width: 320).environment(\.dynamicTypeSize, .large)
            .environment(\.whisperMediaActive, false))
        renderer.scale = 1
        let image = try #require(renderer.uiImage?.cgImage)
        #expect(image.width == 320 && image.height == 60)
        let head = try pixel(image, x: 160, y: 10)
        #expect(head[0] > 225 && head[3] > 245)
        let eye = try pixel(image, x: 154, y: 16)
        #expect(eye[0] < 50 && eye[1] < 50 && eye[3] > 245)
        let capsule = try pixel(image, x: 160, y: 30)
        #expect(capsule[0] > 245 && capsule[1] > 245 && capsule[3] == 255)
    }

    @Test func pillFitsNarrowColumnsAndAllowsLargeTextToGrowVertically() throws {
        for width: CGFloat in [240, 320, 390] {
            let renderer = ImageRenderer(content: WhisperJasperIntelligencePill()
                .environment(\.dynamicTypeSize, .accessibility3)
                .environment(\.whisperMediaActive, false))
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            renderer.scale = 1
            let image = try #require(renderer.uiImage?.cgImage)
            #expect(image.width <= Int(width))
            #expect(image.height > 60)
        }
    }

    @Test func renderingAnalysisEntryDoesNotReadPrivateContext() throws {
        var reads = 0
        let renderer = ImageRenderer(content: JasperAnalysisDock(
            focus: "Summarize authorized content", buildContext: { reads += 1; return "private context" })
            .frame(width: 320).environment(\.whisperMediaActive, false))
        renderer.scale = 1
        let image = try #require(renderer.uiImage?.cgImage)
        #expect(image.width == 320 && image.height == 60)
        #expect(reads == 0)
    }

    @Test func capsuleUsesOriginalAnalysisAndChatHeaderHeights() throws {
        for compact in [false, true] {
            let renderer = ImageRenderer(content: WhisperJasperIntelligencePill(
                compact: compact, showsPeek: false, title: "Jasper's read", reservesPeekSpace: false)
                .environment(\.dynamicTypeSize, .large))
            renderer.scale = 1
            let image = try #require(renderer.uiImage?.cgImage)
            #expect(image.height == (compact ? 36 : 34))
        }
    }

    @Test func canonicalGhostKeepsFiftyPointSlotAndTwentySixPointPeek() throws {
        let renderer = ImageRenderer(content: WhisperJasperIntelligencePill(title: "Jasper's read")
            .frame(width: 320).environment(\.dynamicTypeSize, .large)
            .environment(\.whisperMediaActive, false))
        renderer.scale = 1
        let image = try #require(renderer.uiImage?.cgImage)
        #expect(image.height == 60)
        let canonical = ImageRenderer(content: WhisperEmberMascot(size: 50, usesIntelligenceStyle: true)
            .frame(width: 50, height: 50, alignment: .top)
            .environment(\.whisperMediaActive, false))
        canonical.scale = 1
        let expected = try #require(canonical.uiImage?.cgImage)
        for y in [4, 10, 16, 22] {
            for x in [5, 10, 19, 25, 30, 40, 45] {
                let actualPixel = try pixel(image, x: 135 + x, y: y)
                let expectedPixel = try pixel(expected, x: x, y: y)
                for channel in 0..<4 { #expect(abs(Int(actualPixel[channel]) - Int(expectedPixel[channel])) <= 4) }
            }
        }
        let whiteCover = try pixel(image, x: 151, y: 29)
        #expect(whiteCover[0] > 245 && whiteCover[1] > 245 && whiteCover[3] == 255)
    }

    @Test func compactHeaderReservesTheGhostPeekInsideItsBounds() throws {
        let renderer = ImageRenderer(content: WhisperJasperIntelligencePill(compact: true)
            .frame(width: 208).environment(\.dynamicTypeSize, .large)
            .environment(\.whisperMediaActive, false))
        renderer.scale = 1
        let image = try #require(renderer.uiImage?.cgImage)
        #expect(image.width == 208 && image.height == 60)
        let head = try pixel(image, x: 104, y: 7)
        #expect(head[0] > 225 && head[1] > 225 && head[2] > 225 && head[3] > 245)
        let cover = try pixel(image, x: 104, y: 27)
        #expect(cover[0] > 245 && cover[3] == 255)
    }

    @Test func standaloneMarkUsesCanonicalGhostAndDatingHeartEyes() throws {
        for smitten in [false, true] {
            let palette: WhisperEmberMascotPalette? = smitten ? .cupidPink : nil
            let actual = ImageRenderer(content: WhisperJasperIntelligenceMark(palette: palette, smitten: smitten)
                .frame(width: 100, height: 100).environment(\.whisperMediaActive, false))
            let expected = ImageRenderer(content: WhisperEmberMascot(size: 100,
                expression: smitten ? .happy : .calm, palette: palette, smitten: smitten, usesIntelligenceStyle: true)
                .frame(width: 100, height: 100, alignment: .top).environment(\.whisperMediaActive, false))
            actual.scale = 1; expected.scale = 1
            let image = try #require(actual.uiImage?.cgImage)
            let canonical = try #require(expected.uiImage?.cgImage)
            // Includes the scalloped lower body and both eye shapes, not just a white head center.
            for y in [10, 23, 27, 31, 36, 65, 80, 90, 97] {
                for x in [5, 20, 31, 35, 38, 50, 55, 60, 65, 80, 95] {
                    let a = try pixel(image, x: x, y: y)
                    let b = try pixel(canonical, x: x, y: y)
                    for channel in 0..<4 { #expect(abs(Int(a[channel]) - Int(b[channel])) <= 4) }
                }
            }
        }
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (y * image.width + x) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
