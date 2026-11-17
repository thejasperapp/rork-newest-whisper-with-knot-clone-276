import SwiftUI

/// Covers attributed links and preview cards, including retained native tab hosts.
struct WhisperNotesLinkHandling: ViewModifier {
    var handlesIncomingLinks = true
    @State private var failedLink: WhisperNotesLink?
    @State private var showError: Bool = false
    @State private var isOpening: Bool = false

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                if WhisperNotesLink.isNotesURL(url) {
                    handle(url)
                    return .handled
                }
                return WhisperInAppBrowser.shared.presentWebPage(url) ? .handled : .systemAction
            })
            .onOpenURL { url in
                if handlesIncomingLinks, WhisperNotesLink.isNotesURL(url) { handle(url) }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if handlesIncomingLinks, let url = activity.webpageURL, WhisperNotesLink.isNotesURL(url) { handle(url) }
            }
            .alert("Couldn't open Whisper Notes", isPresented: $showError) {
                if let failedLink {
                    Button("Try again") { open(failedLink) }
                }
                Button("Cancel", role: .cancel) { failedLink = nil }
            } message: {
                Text(failedLink == nil ? "This Notes link isn't valid. Ask the sender to share a new link from Whisper Notes." : "The app and website couldn't be opened. Try again. Your conversation is unchanged.")
            }
    }

    private func handle(_ url: URL) {
        guard let link = WhisperNotesLink.parse(url) else {
            failedLink = nil
            showError = true
            return
        }
        open(link)
    }

    private func open(_ link: WhisperNotesLink) {
        guard !isOpening else { return }
        isOpening = true
        let generation = AccountStorage.generation
        Task {
            let didOpen = await WhisperNotesHandoff.open(link)
            isOpening = false
            guard generation == AccountStorage.generation else { return }
            if !didOpen { failedLink = link; showError = true }
        }
    }
}
