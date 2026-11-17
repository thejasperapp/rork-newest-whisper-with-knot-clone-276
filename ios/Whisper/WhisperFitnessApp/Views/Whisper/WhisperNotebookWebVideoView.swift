import SwiftUI
import WebKit

/// A contained WebKit media surface for browser-recorded WebM, with no website navigation or persistent cookies.
struct WhisperNotebookWebVideoView: UIViewRepresentable {
    let url: URL
    let model: WhisperRecordingArchiveViewModel

    func makeCoordinator() -> WhisperNotebookWebVideoCoordinator { WhisperNotebookWebVideoCoordinator(model: model) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.userContentController.add(context.coordinator, name: "recording")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .black
        view.accessibilityLabel = "Meeting video"
        model.webPlayer = view
        context.coordinator.loadedURL = url
        view.loadHTMLString(html, baseURL: nil)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        model.webPlayer = view
        view.loadHTMLString(html, baseURL: nil)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: WhisperNotebookWebVideoCoordinator) {
        view.evaluateJavaScript("document.querySelector('video')?.pause();", completionHandler: nil)
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "recording")
        view.navigationDelegate = nil
        view.loadHTMLString("", baseURL: nil)
        if coordinator.model?.webPlayer === view { coordinator.model?.webPlayer = nil }
    }
    private var html: String {
        let source = url.absoluteString.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; media-src https:; style-src 'unsafe-inline'; script-src 'unsafe-inline'"><style>html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}video{display:block;width:100%;height:100%;object-fit:contain}</style></head><body><video aria-label="Meeting video" controls playsinline preload="metadata" src="\(source)"></video><script>
        const v=document.querySelector('video');
        const send=x=>window.webkit.messageHandlers.recording.postMessage(x);
        v.addEventListener('error',()=>send('failed'));
        v.addEventListener('timeupdate',()=>send(v.currentTime));
        document.addEventListener('visibilitychange',()=>{if(document.hidden)v.pause()});
        window.seekRecording=t=>{if(!Number.isFinite(t))return;const seek=()=>{v.currentTime=t;v.play().catch(()=>send('failed'))};if(v.readyState)seek();else v.addEventListener('loadedmetadata',seek,{once:true})};
        </script></body></html>
        """
    }
}
