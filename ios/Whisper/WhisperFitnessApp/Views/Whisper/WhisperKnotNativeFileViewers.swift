import SwiftUI
import PDFKit
import QuickLook
import WebKit
import UniformTypeIdentifiers

struct WhisperKnotNativePDF: UIViewRepresentable {
    let url: URL
    let pages: Int
    @Binding var currentPage: Int
    let failed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(page: $currentPage) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.backgroundColor = .black
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount == pages else {
            DispatchQueue.main.async(execute: failed); return view
        }
        // Native text selection, continuous scrolling, pinch zoom and full pages.
        view.document = document
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { context.coordinator.page = $currentPage }
    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator); view.document = nil
    }
    final class Coordinator: NSObject {
        var page: Binding<Int>
        init(page: Binding<Int>) { self.page = page }
        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView, let document = view.document, let current = view.currentPage else { return }
            let number = document.index(for: current) + 1
            guard number > 0, number <= document.pageCount, number != page.wrappedValue else { return }
            page.wrappedValue = number
        }
    }
}

struct WhisperKnotQuickLook: UIViewControllerRepresentable {
    let url: URL
    let failed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let view = QLPreviewController()
        guard QLPreviewController.canPreview(url as NSURL) else { DispatchQueue.main.async(execute: failed); return view }
        view.dataSource = context.coordinator
        return view
    }
    func updateUIViewController(_ view: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

struct WhisperKnotFullText: UIViewRepresentable {
    let text: String
    let markdown: Bool
    let monospaced: Bool
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = true
        view.dataDetectorTypes = []; view.backgroundColor = .systemBackground
        view.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 24, right: 16)
        view.adjustsFontForContentSizeCategory = true
        update(view)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        if context.coordinator.text != text || context.coordinator.markdown != markdown {
            update(view); context.coordinator.text = text; context.coordinator.markdown = markdown
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(text: text, markdown: markdown) }
    private func update(_ view: UITextView) {
        view.font = monospaced ? .monospacedSystemFont(ofSize: 15, weight: .regular) : .preferredFont(forTextStyle: .body)
        view.textColor = .label
        if markdown { view.attributedText = Self.formattedMarkdown(text) }
        else { view.text = text }
    }
    /// Native text only: no remote images, HTML, scripts or automatic links.
    private static func formattedMarkdown(_ source: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        var fenced = false
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fenced.toggle(); continue }
            var value = line, style: UIFont.TextStyle = .body, prefix = "", indent: CGFloat = 0
            var heading = false
            if !fenced {
                let hashes = line.prefix(while: { $0 == "#" }).count
                if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                    value = String(line.dropFirst(hashes + 1)); heading = true
                    style = hashes == 1 ? .title1 : hashes == 2 ? .title2 : .title3
                } else if let range = line.range(of: "^\\s*[-+*]\\s+", options: .regularExpression) {
                    value = String(line[range.upperBound...]); prefix = "•  "; indent = 18
                } else if let range = line.range(of: "^\\s*[0-9]+[.)]\\s+", options: .regularExpression) {
                    value = String(line[range.upperBound...]); prefix = String(line[range]).trimmingCharacters(in: .whitespaces) + "  "; indent = 24
                } else if trimmed.hasPrefix("> ") {
                    value = String(trimmed.dropFirst(2)); prefix = "│  "; indent = 18
                }
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4; paragraph.paragraphSpacing = heading ? 12 : 8
            paragraph.paragraphSpacingBefore = heading && output.length > 0 ? 18 : 0
            paragraph.headIndent = indent
            let base = UIFont.preferredFont(forTextStyle: style)
            let baseFont = heading ? UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor, size: 0) : base
            let rendered = NSMutableAttributedString(string: prefix, attributes: [.font: baseFont, .foregroundColor: UIColor.label])
            if !fenced, let inline = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                for run in inline.runs {
                    let segment = String(inline[run.range].characters)
                    let intent = run.inlinePresentationIntent ?? []
                    var traits: UIFontDescriptor.SymbolicTraits = heading ? [.traitBold] : []
                    if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                    if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                    let font = intent.contains(.code) ? UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.9, weight: .regular) : UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor, size: 0)
                    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
                    if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    rendered.append(NSAttributedString(string: segment, attributes: attributes))
                }
            } else {
                rendered.append(NSAttributedString(string: value, attributes: [.font: UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.9, weight: .regular), .foregroundColor: UIColor.label]))
            }
            rendered.append(NSAttributedString(string: "\n"))
            rendered.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: rendered.length))
            output.append(rendered)
        }
        return output
    }
    final class Coordinator {
        var text: String; var markdown: Bool
        init(text: String, markdown: Bool) { self.text = text; self.markdown = markdown }
    }
}

struct WhisperKnotZoomImage: UIViewRepresentable {
    let url: URL
    let failed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let view = ImageScrollView(image: context.coordinator.image)
        view.minimumZoomScale = 1; view.maximumZoomScale = 8; view.delegate = context.coordinator
        view.backgroundColor = .secondarySystemBackground
        let image = context.coordinator.image
        image.image = UIImage(contentsOfFile: url.path); image.contentMode = .scaleAspectFit
        if image.image == nil { DispatchQueue.main.async(execute: failed) }
        image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }
    func updateUIView(_ view: UIScrollView, context: Context) { if view.zoomScale == 1 { context.coordinator.image.frame = view.bounds } }
    final class ImageScrollView: UIScrollView {
        let image: UIImageView
        init(image: UIImageView) { self.image = image; super.init(frame: .zero); addSubview(image) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func layoutSubviews() { super.layoutSubviews(); if zoomScale == 1 { image.frame = bounds; contentSize = bounds.size } }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let image = UIImageView()
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    }
}
