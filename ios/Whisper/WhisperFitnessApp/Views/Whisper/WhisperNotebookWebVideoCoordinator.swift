import WebKit

final class WhisperNotebookWebVideoCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var model: WhisperRecordingArchiveViewModel?
    var loadedURL: URL?
    init(model: WhisperRecordingArchiveViewModel) { self.model = model }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in
            guard let view = message.webView else { return }
            let position = message.body as? Double
            let failed = (message.body as? String) == "failed"
            self?.model?.updateWebPlayback(position: position, failed: failed, view: view)
        }
    }
    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        Task { @MainActor in
            decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self, weak webView] in
            guard let webView else { return }
            self?.model?.updateWebPlayback(position: nil, failed: true, view: webView)
        }
    }
}
