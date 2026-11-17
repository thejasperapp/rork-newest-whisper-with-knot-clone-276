import SwiftUI
import UIKit

/// UITextView supplies native selection, dictation, IME and undo without rebuilding the editor.
struct WhisperNotebookTextView: UIViewRepresentable {
    @Binding var text: String
    let kind: String
    let revision: Int
    let highlights: [WhisperNotebookHighlight]
    let label: String
    let onSelection: (WhisperNotebookHighlight?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.accessibilityLabel = label
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        guard view.markedTextRange == nil else { return }
        context.coordinator.isRendering = true
        defer { context.coordinator.isRendering = false }
        if view.text != text { view.text = text }
        guard context.coordinator.renderedText != text || context.coordinator.renderedHighlights != highlights else { return }
        context.coordinator.renderedText = text; context.coordinator.renderedHighlights = highlights
        let selection = view.selectedRange
        let offset = view.contentOffset
        let full = NSRange(location: 0, length: (view.text as NSString).length)
        view.textStorage.beginEditing()
        view.textStorage.addAttributes([.foregroundColor: UIColor.label, .font: UIFont.preferredFont(forTextStyle: .body)], range: full)
        view.textStorage.removeAttribute(.backgroundColor, range: full)
        for item in highlights where item.kind == kind && item.matches(text) {
            view.textStorage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.27), range: NSRange(location: item.start, length: item.end - item.start))
        }
        view.textStorage.endEditing()
        if NSMaxRange(selection) <= full.length { view.selectedRange = selection }
        view.setContentOffset(offset, animated: false)
        view.typingAttributes = [.foregroundColor: UIColor.label, .font: UIFont.preferredFont(forTextStyle: .body)]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: WhisperNotebookTextView
        var isRendering: Bool = false
        var renderedText: String?
        var renderedHighlights: [WhisperNotebookHighlight] = []
        var lastSelection: NSRange?
        var lastRevision: Int = -1
        init(_ parent: WhisperNotebookTextView) { self.parent = parent }
        nonisolated func textViewDidChange(_ textView: UITextView) {
            // UIKit delivers text editing delegates on the main thread. Commit before navigation can change the draft.
            MainActor.assumeIsolated {
                guard !self.isRendering, textView.markedTextRange == nil else { return }
                self.parent.text = textView.text
            }
        }
        nonisolated func textViewDidChangeSelection(_ textView: UITextView) {
            MainActor.assumeIsolated {
                guard !self.isRendering else { return }
                let range = textView.selectedRange, text = textView.text as NSString
                guard self.lastSelection != range || self.lastRevision != self.parent.revision else { return }
                self.lastSelection = range; self.lastRevision = self.parent.revision
                guard range.length > 0, NSMaxRange(range) <= text.length else { self.parent.onSelection(nil); return }
                self.parent.onSelection(.init(id: UUID().uuidString.lowercased(), kind: self.parent.kind, start: range.location, end: NSMaxRange(range), text: text.substring(with: range), revision: self.parent.revision, origin: "manual", stale: false))
            }
        }
    }
}
