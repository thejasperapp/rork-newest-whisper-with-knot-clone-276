import SwiftUI

/// Formatting is deferred until opened and runs off the UI actor. Each retained
/// character is available, but no single SwiftUI Text lays out a multi-MB log.
struct WhisperKnotExactEvidenceView: View {
    nonisolated enum Source: Sendable {
        case text(String)
        case json(WhisperKnotReceiptJSON)
        case log(bot: String, conversationID: String, proposalID: String)
    }
    let title: String
    let source: Source
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var parts: [String] = []
    @State private var issue: String?
    @State private var loading = true
    @State private var invalidated = false
    @State private var generation = AccountStorage.generation
    @State private var consentRevision = WhisperKnotContextPermission.revision
    private var valid: Bool {
        !invalidated && generation == AccountStorage.generation && consentRevision == WhisperKnotContextPermission.revision && WhisperKnotContextPermission.allowed && !Task.isCancelled
    }

    var body: some View {
        List {
            if loading { ProgressView("Reading retained evidence") }
            if let issue { Text(issue).font(.subheadline).foregroundStyle(.secondary) }
            if !parts.isEmpty {
                Section {
                    ForEach(parts.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            if parts.count > 1 { Text("Part \(index + 1) of \(parts.count)").font(.caption2).foregroundStyle(.secondary) }
                            Text(verbatim: parts[index]).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }.listRowSeparator(.hidden)
                    }
                }
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active, valid, parts.isEmpty else { return }
            loading = true
            defer { loading = false }
            do {
                let data: Data?
                if case .log(let bot, let conversationID, let proposalID) = source {
                    data = try await WhisperKnotShellEvidenceService.fetch("log", bot: bot, conversationID: conversationID, proposalID: proposalID)
                } else { data = nil }
                let value = try await Self.prepare(source, data: data)
                guard valid, scenePhase == .active else { return }
                parts = value; issue = nil
            } catch {
                if valid, scenePhase == .active { issue = "This evidence is unavailable or no longer retained. Nothing was run again." }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in clear() }
    }
    private func clear() { invalidated = true; parts = []; dismiss() }

    @concurrent private static func prepare(_ source: Source, data: Data?) async throws -> [String] {
        try Task.checkCancellation()
        let text: String
        switch source {
        case .text(let value): text = value
        case .json(let value): text = value.formatted
        case .log:
            guard let data, let value = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
            text = value
        }
        var parts: [String] = [], start = text.startIndex
        while start < text.endIndex {
            try Task.checkCancellation()
            let end = text.index(start, offsetBy: 4096, limitedBy: text.endIndex) ?? text.endIndex
            parts.append(String(text[start..<end])); start = end
        }
        return parts.isEmpty ? [""] : parts
    }
}
