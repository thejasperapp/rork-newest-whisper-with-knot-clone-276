import SwiftUI
import WebKit
import CryptoKit
import Observation

/// A single live page for one immutable original, not a thumbnail or a browser
/// pool. A card and its expanded viewer borrow the same view/DOM/scroll position.
@MainActor @Observable final class WhisperKnotHTMLSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let original: URL
    let lease: WhisperKnotOriginalStore.Lease
    private(set) var loading = true
    private(set) var failed = false
    // Bounded internal diagnostics: no file paths, authored text or URLs.
    private(set) var failureCode: String?
    @ObservationIgnored private var currentNavigation: WKNavigation?
    @ObservationIgnored private(set) var webView: WKWebView?
    @ObservationIgnored private var pin: UUID?
    @ObservationIgnored private var hosts: [UUID: WeakHost] = [:]
    @ObservationIgnored private var loadRevision = UUID()
    @ObservationIgnored var lastUsed = Date()
    private struct WeakHost { weak var value: WhisperKnotHTMLHost? }

    init(original: URL, lease: WhisperKnotOriginalStore.Lease, pin: UUID, profile: UUID) {
        self.original = original.standardizedFileURL
        self.lease = lease
        self.pin = pin
        super.init()
        let configuration = WKWebViewConfiguration()
        // Never share Safari, account, or another artifact's cookies/storage.
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // Runtime policy only: the stored delivery is never rewritten. The
        // content blocker is installed BEFORE loading, and CSP also disallows
        // connect/frames/forms/workers. No app message handler is installed.
        let policy = """
        (() => {
          const add = () => {
            const root = document.head || document.documentElement;
            if (!root) return false;
            const meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = "default-src 'none'; script-src file: 'unsafe-inline' 'unsafe-eval'; style-src file: 'unsafe-inline'; img-src file: data: blob:; media-src file: data: blob:; font-src file: data:; connect-src 'none'; frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
            root.prepend(meta); return true;
          };
          if (!add()) { const observer = new MutationObserver(() => { if (add()) observer.disconnect(); }); observer.observe(document, {childList:true, subtree:true}); }
        })();
        """
        configuration.userContentController.addUserScript(.init(source: policy, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self; view.uiDelegate = self
        view.isOpaque = false; view.backgroundColor = .systemBackground
        view.isUserInteractionEnabled = true
        view.scrollView.isScrollEnabled = true
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = false
        view.accessibilityIdentifier = "knot-live-html"
        webView = view
        start()
    }

    var valid: Bool { lease.valid && webView != nil }
    var attached: Bool { hosts.values.contains { $0.value?.window != nil } }

    private func start() {
        guard valid, let view = webView else { return }
        loading = true; failed = false; failureCode = nil
        currentNavigation = nil
        let revision = UUID(); loadRevision = revision
        // WebKit content rules accept only a regex subset: alternation is not
        // supported. Separate allow rules keep compilation and fail-closed policy.
        let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file:"},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "knot-file-local-only-v2", encodedContentRuleList: rules) { [weak self, weak view] list, _ in
            guard let self, let view, self.valid, revision == self.loadRevision else { return }
            guard let list else { self.loading = false; self.failed = true; self.failureCode = "content_rules"; return }
            view.configuration.userContentController.add(list)
            // The exact hash-verified Application Support original, not a temp
            // HTML string, copy, scheme URL, server URL or regenerated document.
            self.currentNavigation = view.loadFileURL(self.original, allowingReadAccessTo: self.original.deletingLastPathComponent())
            if self.currentNavigation == nil { self.loading = false; self.failed = true; self.failureCode = "file_load_not_started" }
        }
    }
    func restart() {
        guard valid else { return }
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllContentRuleLists()
        start()
    }
    func attach(_ host: WhisperKnotHTMLHost) {
        hosts[host.id] = WeakHost(value: host); lastUsed = Date(); mount()
    }
    func detach(_ host: WhisperKnotHTMLHost) {
        hosts.removeValue(forKey: host.id)
        if webView?.superview === host { webView?.removeFromSuperview() }
        mount()
    }
    private func mount() {
        guard valid, let view = webView else { return }
        hosts = hosts.filter { $0.value.value != nil }
        let host = hosts.values.compactMap(\.value).filter { $0.window != nil }.max { $0.priority < $1.priority }
        guard let host else { view.removeFromSuperview(); return }
        if view.superview !== host { view.removeFromSuperview(); host.addSubview(view) }
        view.frame = host.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    func invalidate() {
        loadRevision = UUID(); currentNavigation = nil; loading = false; failed = true
        if let view = webView {
            view.stopLoading(); view.removeFromSuperview()
            view.navigationDelegate = nil; view.uiDelegate = nil
            view.configuration.userContentController.removeAllUserScripts()
        }
        webView = nil; hosts = [:]
        WhisperKnotOriginalStore.releasePin(pin); pin = nil
    }

    /// Only the original's fragment navigation can replace the current location.
    /// Relative links to other local files, forms, downloads and JS redirects
    /// cannot turn the artifact into an app-file browser or a remote website.
    static func isOriginalNavigation(_ url: URL, original: URL) -> Bool {
        guard url.isFileURL, url.query == nil, url.host == nil || url.host == "" || url.host == "localhost" else { return false }
        return url.standardizedFileURL.path == original.standardizedFileURL.path
    }
    static func isExternalLink(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil else { return false }
        switch url.scheme?.lowercased() {
        case "http", "https": return url.host?.isEmpty == false
        case "mailto", "tel": return !url.path.isEmpty
        default: return false
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard valid, let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == true, !action.shouldPerformDownload,
           Self.isOriginalNavigation(url, original: original), action.navigationType != .formSubmitted, action.navigationType != .formResubmitted {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        // Only explicit human link activations can leave the preview, and only
        // through Whisper's existing system-browser / mail / phone policy.
        if action.navigationType == .linkActivated, Self.isExternalLink(url) { WhisperInAppBrowser.shared.open(url) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard valid, let navigation, navigation === currentNavigation else { return }
        loading = false; failed = false; failureCode = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { report(error, navigation: navigation) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { report(error, navigation: navigation) }
    private func report(_ error: any Error, navigation: WKNavigation?) {
        // Stop/Restart and blocked secondary navigation can finish later. They
        // cannot overwrite the state of the current exact-original load.
        guard valid, let navigation, navigation === currentNavigation else { return }
        let error = error as NSError
        guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
        loading = false; failed = true
        failureCode = "\(error.domain):\(error.code)"
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Be honest about process loss; do not silently replay a game/action.
        guard valid else { return }; loading = false; failed = true; failureCode = "web_content_process_terminated"
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}

/// Native host, not a Button overlay. Its recognizer lets WebKit receive every
/// touch while preventing ancestor chat pan/swipe recognizers from stealing a
/// canvas drag. Chat navigation stays reachable outside the page and in chrome.
final class WhisperKnotHTMLHost: UIView {
    let id = UUID()
    let priority: Int
    var session: WhisperKnotHTMLSession
    init(session: WhisperKnotHTMLSession, priority: Int) {
        self.session = session; self.priority = priority
        super.init(frame: .zero)
        clipsToBounds = true
        let touch = PageTouchOwnership()
        touch.cancelsTouchesInView = false; touch.delaysTouchesBegan = false; touch.delaysTouchesEnded = false
        touch.delegate = touch; addGestureRecognizer(touch)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { session.detach(self) } else { session.attach(self) }
    }
    override func layoutSubviews() { super.layoutSubviews(); for view in subviews { view.frame = bounds } }
    private final class PageTouchOwnership: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private func ancestor(_ other: UIGestureRecognizer) -> Bool {
            guard let host = view, let parent = other.view else { return false }
            return parent !== host && host.isDescendant(of: parent)
        }
        override func canPrevent(_ other: UIGestureRecognizer) -> Bool { ancestor(other) }
        override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { !ancestor(other) }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { state = state == .possible ? .began : .changed }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { if event.allTouches?.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) != false { state = .ended } }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    }
}

struct WhisperKnotLiveHTML: UIViewRepresentable {
    let session: WhisperKnotHTMLSession
    var expanded = false
    func makeUIView(context: Context) -> WhisperKnotHTMLHost { WhisperKnotHTMLHost(session: session, priority: expanded ? 2 : 1) }
    func updateUIView(_ view: WhisperKnotHTMLHost, context: Context) {
        if view.session !== session { view.session.detach(view); view.session = session; session.attach(view) }
    }
    static func dismantleUIView(_ view: WhisperKnotHTMLHost, coordinator: ()) { view.session.detach(view) }
}

@MainActor enum WhisperKnotHTMLSessions {
    private static var sessions: [String: WhisperKnotHTMLSession] = [:]
    private static let pendingKey = "KnotHTMLProfilesPendingRemoval-v1"
    private static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func indexKey(_ owner: String) -> String { "KnotHTMLProfiles-v1-" + digest(owner.lowercased()) }
    private static func artifactKey(_ document: WhisperKnotDocument, bot: String, conversationID: UUID) -> String {
        // Saving a received original changes its storage ID, never this DM's page.
        conversationID.uuidString.lowercased() + ":" + bot + ":" + (bot == WhisperKnotDMArtifacts.storageBot ? document.sha256 : document.id)
    }

    static func open(_ document: WhisperKnotDocument, bot: String, conversationID: UUID) async throws -> WhisperKnotHTMLSession {
        guard document.valid, document.format == "html" else { throw WhisperKnotFileError.preview }
        let lease = try WhisperKnotOriginalStore.lease(conversationID, directMessage: bot == WhisperKnotDMArtifacts.storageBot)
        let artifact = artifactKey(document, bot: bot, conversationID: conversationID), key = lease.owner + ":" + artifact
        purgeInvalid()
        if let value = sessions[key], value.valid { value.lastUsed = Date(); return value }
        let pin = try WhisperKnotOriginalStore.pin(document, bot: bot, conversationID: conversationID)
        do {
            let original = try await WhisperKnotOriginalStore.original(document, bot: bot, conversationID: conversationID)
            // All verified local dependencies must exist at their relative paths
            // before WebKit starts. Loading only the entry silently breaks games.
            if document.bundle != nil { _ = try await WhisperKnotOriginalStore.bundle(document, bot: bot, conversationID: conversationID) }
            guard lease.valid, !Task.isCancelled else { throw CancellationError() }
            // The full viewer and inline card may have awaited the same bytes.
            if let value = sessions[key], value.valid { WhisperKnotOriginalStore.releasePin(pin); return value }
            drainRemovals()
            var profiles = UserDefaults.standard.dictionary(forKey: indexKey(lease.owner)) as? [String: String] ?? [:]
            let profile = profiles[artifact].flatMap(UUID.init(uuidString:)) ?? UUID()
            profiles[artifact] = profile.uuidString
            UserDefaults.standard.set(profiles, forKey: indexKey(lease.owner))
            let value = WhisperKnotHTMLSession(original: original, lease: lease, pin: pin, profile: profile)
            sessions[key] = value
            // Bound parked WebKit processes, not files or delivery cards. Visible
            // sessions are never evicted. Relaunch/recovery uses the same original.
            let parked = sessions.filter { $0.key != key && !$0.value.attached }.sorted { $0.value.lastUsed < $1.value.lastUsed }
            for (oldKey, old) in parked.prefix(max(0, parked.count - 3)) { old.invalidate(); sessions.removeValue(forKey: oldKey) }
            return value
        } catch { WhisperKnotOriginalStore.releasePin(pin); throw error }
    }
    private static func purgeInvalid() {
        for (key, value) in sessions where !value.valid { value.invalidate(); sessions.removeValue(forKey: key) }
    }
    static func clear(owner: String, conversationID: UUID? = nil) {
        let owner = owner.lowercased(), prefix = conversationID.map { $0.uuidString.lowercased() + ":" }
        for (key, value) in sessions where value.lease.owner == owner && (conversationID == nil || value.lease.conversationID == conversationID) {
            value.invalidate(); sessions.removeValue(forKey: key)
        }
        var profiles = UserDefaults.standard.dictionary(forKey: indexKey(owner)) as? [String: String] ?? [:]
        var pending = Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
        for (key, id) in profiles where prefix == nil || key.hasPrefix(prefix!) { pending.insert(id); profiles.removeValue(forKey: key) }
        if profiles.isEmpty { UserDefaults.standard.removeObject(forKey: indexKey(owner)) }
        else { UserDefaults.standard.set(profiles, forKey: indexKey(owner)) }
        // Tombstones survive a process exit or OS removal error. New sessions
        // receive a new UUID and cannot reopen outgoing-account page storage.
        UserDefaults.standard.set(Array(pending), forKey: pendingKey)
        drainRemovals()
    }
    private static func drainRemovals() {
        for text in UserDefaults.standard.stringArray(forKey: pendingKey) ?? [] {
            guard let id = UUID(uuidString: text) else { continue }
            let store = WKWebsiteDataStore(forIdentifier: id)
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                WKWebsiteDataStore.remove(forIdentifier: id) { error in
                    guard error == nil else { return }
                    let remaining = (UserDefaults.standard.stringArray(forKey: pendingKey) ?? []).filter { $0 != text }
                    UserDefaults.standard.set(remaining, forKey: pendingKey)
                }
            }
        }
    }
}
