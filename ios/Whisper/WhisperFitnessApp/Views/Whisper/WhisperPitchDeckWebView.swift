import SwiftUI
import WebKit

/// In-app pitch deck viewer that renders the live web deck inside a WKWebView
/// so the recruiter never leaves the app while presenting. Mirrors the web
/// `PitchDeckOverlay` iframe pattern — the deck loads with `?embed=1` so the
/// public nav/footer are suppressed for a clean presentation surface.
struct WhisperPitchDeckWebView: View {
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let audience: WhisperPitchAudience
    /// When true, the toolbar only shows a close button; the external-browser
    /// link is hidden so the user stays inside the app.
    var inline: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WhisperPitchDeckWebViewRep(audience: audience)
            }
            .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
            .whisperEdgeBack(controller: backTransition) { backTransition.perform { dismiss() } }
            .navigationTitle("\(audience.title) deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        backTransition.perform { dismiss() }
                    } label: {
                        Image(systemName: inline ? "chevron.left" : "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .accessibilityLabel(inline ? "Back" : "Close")
                }
                if !inline {
                    ToolbarItem(placement: .topBarTrailing) {
                        Link(destination: audience.deckURL) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                        }
                        .accessibilityLabel("Open in browser")
                    }
                }
            }
        }
    }
}

/// The WKWebView wrapper that loads the pitch deck URL with `?embed=1`.
struct WhisperPitchDeckWebViewRep: UIViewRepresentable {
    let audience: WhisperPitchAudience

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        // Build the embed URL — suppresses the public nav/footer on the web
        // side so the deck renders clean inside the app.
        var components = URLComponents(url: audience.deckURL, resolvingAgainstBaseURL: false)
        let embedItem = URLQueryItem(name: "embed", value: "1")
        var items = components?.queryItems ?? []
        items.append(embedItem)
        components?.queryItems = items
        if let url = components?.url {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Inline pitch deck web view

/// Embedded pitch deck web view for use inside the Recruiter HQ Pitch tab.
/// No chrome, no external link, just the live web deck clipped to the card radius.
struct WhisperInlinePitchDeckWebView: View {
    let audience: WhisperPitchAudience

    var body: some View {
        WhisperPitchDeckWebViewRep(audience: audience)
    }
}
