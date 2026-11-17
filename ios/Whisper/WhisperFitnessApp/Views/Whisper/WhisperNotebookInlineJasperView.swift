import SwiftUI

struct WhisperNotebookInlineJasperView: View {
    @Bindable var model: WhisperNotebookViewModel
    let selection: WhisperNotebookHighlight?
    var externalSources: [WhisperNotebookDocument.Source]? = nil
    var externalLabel: String? = nil
    var onClearExternal: (() -> Void)? = nil
    @State private var question: String = ""
    @State private var asking: Bool = false
    @State private var approved: Bool = false
    @State private var consent: Bool = false
    @State private var pendingSnapshot: WhisperNotebookDocument?
    @State private var pendingSources: [WhisperNotebookDocument.Source] = []
    @State private var workflow: WhisperNotebookWorkflow = .enhance
    @State private var pendingQuestion: String = ""
    @State private var snapshotLabel: String = ""
    @State private var dismissed: Set<String> = []
    @State private var kept: Bool = false
    @State private var previousDraft: WhisperNotebookDocument.Result?
    @State private var canUndo: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var validSelection: WhisperNotebookHighlight? {
        guard let selection, let document = model.draft, selection.revision == document.revision else { return nil }
        let body = (selection.kind == "notes" ? document.notes : document.transcript) as NSString
        guard selection.start >= 0, selection.end > selection.start, selection.end <= body.length,
              body.substring(with: NSRange(location: selection.start, length: selection.end - selection.start)) == selection.text else { return nil }
        return selection
    }
    private var scope: String { externalLabel ?? (validSelection == nil ? "Current note · writing and pasted transcript" : "Selected passage · \(validSelection?.text.utf16.count ?? 0) characters") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    Image(systemName: "sparkle").foregroundStyle(WhisperBrandGradient.rose)
                    if let selected = validSelection, externalSources == nil { Button("Highlight", systemImage: "highlighter") { model.retainHighlight(selected) }.frame(minHeight: 44) }
                    Button("Ask Jasper") { asking.toggle() }.frame(minHeight: 44)
                    ForEach([WhisperNotebookWorkflow.enhance, .summarize, .highlights, .followups]) { action in
                        Button(action.title) { prepare(action) }.frame(minHeight: 44).disabled(model.isGenerating)
                    }
                }.font(.caption.weight(.medium))
            }.contentMargins(.horizontal, 4).scrollIndicators(.hidden)
            Text(scope).font(.caption2).foregroundStyle(.secondary)
            if externalSources != nil { Button("Use note instead") { onClearExternal?() }.font(.caption).frame(minHeight: 44) }
            if asking {
                HStack {
                    TextField("What should I take away?", text: $question, axis: .vertical).font(.subheadline).lineLimit(1...4)
                    Button("Ask") { prepare(.ask) }.frame(minWidth: 44, minHeight: 44).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isGenerating)
                }
            }
            if model.isGenerating {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(workflow == .enhance ? "Enhancing notes…" : "Reading selected passages…").font(.caption); Button("Stop") { model.cancelGeneration() }.font(.caption).frame(minHeight: 44) }
                    .padding(.horizontal, 12).background(WhisperBrandGradient.rose.opacity(0.07), in: Capsule())
            }
            if let result = model.answer, !model.isGenerating {
                resultView(result)
                    .transition(.opacity)
            }
            if canUndo { Button("Undo retained draft") { model.retainInlineDraft(previousDraft); canUndo = false; kept = false }.font(.caption).frame(minHeight: 44) }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(WhisperBrandGradient.rose.opacity(0.35)).frame(width: 2) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.isGenerating)
        .confirmationDialog("Use Jasper with this context?", isPresented: $consent, titleVisibility: .visible) {
            Button("Continue with Jasper") { approved = true; run() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("\(snapshotLabel). These passages and outline preferences are processed by cloud AI using Cloud Credits. Nothing is sent to attendees. Later Jasper taps use the scope shown here; highlighting alone sends nothing.") }
    }

    private func prepare(_ action: WhisperNotebookWorkflow) {
        guard !model.isGenerating, let document = model.draft else { return }
        guard selection == nil || validSelection != nil || externalSources != nil else { model.errorText = "The selected passage changed. Select it again before using Jasper."; return }
        guard question.utf16.count <= 600 else { model.errorText = "Use up to 600 characters for your question."; return }
        do {
            var snapshot = document
            if let selected = validSelection, externalSources == nil {
                snapshot.notes = selected.kind == "notes" ? selected.text : ""
                snapshot.transcript = selected.kind == "transcript" ? selected.text : ""
            }
            pendingSources = try externalSources ?? snapshot.sources()
            pendingSnapshot = document; pendingQuestion = action == .ask ? question : ""; workflow = action; snapshotLabel = scope
            if approved { run() } else { consent = true }
        } catch { model.errorText = error.localizedDescription }
    }
    private func run() {
        dismissed = []; kept = false
        model.generate(question: pendingQuestion.isEmpty ? nil : pendingQuestion, selectedSources: pendingSources, workflow: workflow, previewOnly: true, frozen: pendingSnapshot)
    }
    private func resultView(_ result: WhisperNotebookDocument.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(snapshotLabel) · snapshot \(result.generatedAt)\(result.revision != model.draft?.revision ? " · writing has since changed" : "")").font(.caption2).foregroundStyle(.secondary)
            if result.insufficient { Text("These passages don’t contain enough evidence to answer reliably.").font(.subheadline) }
            ForEach(result.sections, id: \.title) { section in
                Text(section.title).font(.system(.headline, design: .serif))
                ForEach(section.items.filter { !dismissed.contains($0.text) }, id: \.text) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.text).font(.subheadline).textSelection(.enabled)
                        DisclosureGroup("Sources · \(item.sourceIds.joined(separator: ", "))") {
                            ForEach(result.sources.filter { item.sourceIds.contains($0.id) }) { source in Text(source.text).font(.caption).textSelection(.enabled).padding(.vertical, 6) }
                        }.font(.caption).foregroundStyle(.secondary)
                        if workflow == .highlights {
                            HStack {
                                Button("Keep highlight") { keepQuote(item, result: result) }.disabled(externalSources != nil)
                                Button("Dismiss") { dismissed.insert(item.text) }
                            }.font(.caption).frame(minHeight: 44)
                        }
                    }
                }
            }
            if !result.insufficient, workflow != .highlights {
                Button(kept ? "Draft retained below" : "Keep draft & review follow-ups") {
                    previousDraft = model.draft?.enhancement; model.retainInlineDraft(result); kept = true; canUndo = true
                }.font(.caption.weight(.semibold)).frame(minHeight: 44).disabled(kept)
            }
        }
    }
    private func keepQuote(_ item: WhisperNotebookDocument.Item, result: WhisperNotebookDocument.Result) {
        guard let document = model.draft, document.revision == result.revision,
              let source = result.sources.first(where: { item.sourceIds.contains($0.id) && $0.text.contains(item.text) }) else { model.errorText = "The writing changed or this is not an exact quote. Select the passage again."; return }
        let body = (source.kind == "notes" ? document.notes : document.transcript) as NSString
        let range = body.range(of: item.text)
        guard range.location != NSNotFound else { return }
        let rest = NSRange(location: NSMaxRange(range), length: body.length - NSMaxRange(range))
        guard body.range(of: item.text, range: rest).location == NSNotFound else { model.errorText = "This quote appears more than once. Select the exact occurrence to highlight."; return }
        model.retainHighlight(.init(id: UUID().uuidString.lowercased(), kind: source.kind, start: range.location, end: NSMaxRange(range), text: item.text, revision: document.revision, origin: "jasper", stale: false))
        dismissed.insert(item.text)
    }
}
