import XCTest
import Foundation
import WebKit
import UIKit
import CryptoKit
@testable import Whisper

/// Offline renderer checks in the isolated unit-test host. These are NOT
/// delivered artifacts, authenticated QA tasks, touch tests or A1–A5 acceptance.
final class WhisperKnotHTMLSessionTests: XCTestCase {
    @MainActor func testNavigationKeepsOnlyTheExactOriginalAndItsFragments() {
        let original = URL(fileURLWithPath: "/private/artifact/portfolio.html")
        XCTAssertTrue(WhisperKnotHTMLSession.isOriginalNavigation(original, original: original))
        XCTAssertTrue(WhisperKnotHTMLSession.isOriginalNavigation(URL(string: original.absoluteString + "#work")!, original: original))
        for other in ["file:///private/other.html", "file:///private/artifact/other.html", "file:///private/artifact/portfolio.html?replace=1", "file://remote/private/artifact/portfolio.html", "https://example.com", "data:text/html,other", "javascript:alert(1)"] {
            XCTAssertFalse(WhisperKnotHTMLSession.isOriginalNavigation(URL(string: other)!, original: original), other)
        }
    }
    @MainActor func testOnlyExplicitSafeExternalLinkSchemesAreEligibleForTheExistingBrowserPolicy() {
        for link in ["https://example.com/path", "http://example.com", "mailto:qa@example.com", "tel:1234"] {
            XCTAssertTrue(WhisperKnotHTMLSession.isExternalLink(URL(string: link)!), link)
        }
        for link in ["file:///private/other.html", "javascript:alert(1)", "data:text/html,other", "whisper://internal", "https://user:password@example.com", "about:blank"] {
            XCTAssertFalse(WhisperKnotHTMLSession.isExternalLink(URL(string: link)!), link)
        }
    }
    @MainActor func testRealFileJavaScriptDOMAndScrollSurviveHostTransferWithoutChangingOriginal() async throws {
        guard AccountStorage.currentUserID == "guest" else { throw XCTSkip("Requires a fresh isolated guest unit-test host; no real account is modified") }
        // A random local test identity is not a server account or delivery. The
        // test never creates a card, signs in, invokes Knot or accesses a workspace.
        let owner = UUID().uuidString.lowercased(), conversation = UUID(), profile = UUID()
        AccountStorage.currentUserID = owner
        AccountStorage.set(true, forKey: "knot_ai_consent_v4")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KnotHTMLTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("counter.html")
        let source = Data("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Offline fixture</title></head>
        <body><button id="add" onclick="document.getElementById('count').textContent=String(++window.count);localStorage.setItem('count',String(window.count))">Add one</button><output id="count">0</output><div style="height:4000px">Local content</div>
        <script>window.count=0;window.loadIdentity=Math.random();</script></body></html>
        """.utf8)
        try source.write(to: original)
        let hash = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        let document = WhisperKnotDocument(id: String(repeating: "a", count: 64), name: "counter.html", format: "html", title: "Offline fixture", deliveryLabel: nil, contentType: "text/html", size: source.count, sha256: hash, pages: 1, proofPages: [], createdAt: "2026-11-14T10:00:00Z", expiresAt: "2026-11-15T10:00:00Z", proposalID: UUID().uuidString, review: "not_requested", sampled: false, sourceMessageID: nil, sourcePath: nil, bundle: nil)
        let lease = try WhisperKnotOriginalStore.lease(conversation)
        let pin = try WhisperKnotOriginalStore.pin(document, bot: "main", conversationID: conversation)
        let session = WhisperKnotHTMLSession(original: original, lease: lease, pin: pin, profile: profile)
        let root = UIViewController(), window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root; window.isHidden = false
        let inline = WhisperKnotHTMLHost(session: session, priority: 1)
        inline.frame = CGRect(x: 0, y: 0, width: 320, height: 320); root.view.addSubview(inline)
        defer {
            inline.removeFromSuperview(); window.isHidden = true
            session.invalidate()
            AccountStorage.removeObject(forKey: "knot_ai_consent_v4")
            AccountStorage.currentUserID = "guest"
            try? FileManager.default.removeItem(at: directory)
            WKWebsiteDataStore.remove(forIdentifier: profile) { _ in }
        }
        // Keep the strong WKWebView reference in the helper's scope so it has
        // been released before the profile-removal cleanup runs above.
        try await exercisePage(session, original: original, source: source, root: root, inline: inline)
    }
    @MainActor private func exercisePage(_ session: WhisperKnotHTMLSession, original: URL, source: Data, root: UIViewController, inline: WhisperKnotHTMLHost) async throws {
        try await awaitPage(session, stage: "initial")
        let web = try XCTUnwrap(session.webView)
        XCTAssertEqual(web.url?.standardizedFileURL.path, original.standardizedFileURL.path)
        XCTAssertTrue(web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertTrue(web.configuration.websiteDataStore.isPersistent)
        let loadID = try await web.evaluateJavaScript("window.loadIdentity") as? Double
        _ = try await web.evaluateJavaScript("document.getElementById('add').click();document.getElementById('add').click();window.scrollTo(0,200)")
        let count = try await web.evaluateJavaScript("document.getElementById('count').textContent") as? String
        XCTAssertEqual(count, "2")
        let expanded = WhisperKnotHTMLHost(session: session, priority: 2)
        expanded.frame = root.view.bounds; root.view.addSubview(expanded)
        XCTAssertTrue(web.superview === expanded)
        expanded.removeFromSuperview()
        XCTAssertTrue(web.superview === inline)
        inline.removeFromSuperview()
        XCTAssertNil(web.superview)
        root.view.addSubview(inline)
        XCTAssertTrue(web.superview === inline)
        let sameLoad = try await web.evaluateJavaScript("window.loadIdentity") as? Double
        let sameCount = try await web.evaluateJavaScript("window.count") as? Int
        let scroll = try await web.evaluateJavaScript("window.scrollY") as? Double
        XCTAssertEqual(sameLoad, loadID, "Remount must not reload the DOM")
        XCTAssertEqual(sameCount, 2)
        XCTAssertGreaterThan(scroll ?? 0, 0)
        let network = try await web.callAsyncJavaScript("try { await fetch('https://example.com/'); return 'unexpected'; } catch { return 'blocked'; }", arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(network, "blocked")
        let saved = try await web.evaluateJavaScript("localStorage.getItem('count')") as? String
        XCTAssertEqual(saved, "2")
        session.restart()
        try await awaitPage(session, stage: "restart")
        let resetCount = try await web.evaluateJavaScript("window.count") as? Int
        let retainedStorage = try await web.evaluateJavaScript("localStorage.getItem('count')") as? String
        XCTAssertEqual(resetCount, 0, "Only explicit Restart resets the page")
        XCTAssertEqual(retainedStorage, "2")
        XCTAssertEqual(try Data(contentsOf: original), source, "Runtime policy and restart must not rewrite delivered bytes")
        session.invalidate()
        XCTAssertNil(session.webView)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "View invalidation does not delete the original")
    }
    @MainActor private func awaitPage(_ session: WhisperKnotHTMLSession, stage: String) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while session.loading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(session.loading, "Local WebKit page did not finish before the bounded deadline")
        XCTAssertFalse(session.failed, "The actual file renderer failed at \(stage): \(session.failureCode ?? "no diagnostic")")
    }
}
