import SwiftUI
import UniformTypeIdentifiers

/// A separate system export presentation; the owning reader retains its original
/// pin until the picker closes. Export always copies, never moves the original.
struct WhisperKnotFileExport: UIViewControllerRepresentable {
    let urls: [URL]
    var finished: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ view: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: () -> Void
        init(finished: @escaping () -> Void) { self.finished = finished }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finished() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finished() }
    }
}

struct WhisperKnotMarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .black; view.textColor = .white
        view.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .init(top: 20, left: 16, bottom: 28, right: 16)
        view.autocorrectionType = .no; view.autocapitalizationType = .none
        view.smartQuotesType = .no; view.smartDashesType = .no
        view.keyboardDismissMode = .interactive
        view.accessibilityLabel = "Markdown edited copy"
        view.text = text; view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text { view.text = text }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) { text.wrappedValue = textView.text }
    }
}

/// Disposable protected copy, outside the immutable original store. Nothing here
/// changes a delivery's ID, filename, hash, receipt or server record.
enum WhisperKnotEditedCopy {
    @concurrent static func write(_ text: String, originalName: String) async throws -> URL {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KnotEdited-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        do {
            var directory = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let stem = (originalName as NSString).deletingPathExtension
            let url = directory.appendingPathComponent(stem + "-edited-copy.md")
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            try Task.checkCancellation()
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    static func remove(_ url: URL?) {
        guard let url, url.deletingLastPathComponent().lastPathComponent.hasPrefix("KnotEdited-") else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
