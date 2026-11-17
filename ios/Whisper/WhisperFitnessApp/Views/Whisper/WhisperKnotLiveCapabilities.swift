import SwiftUI

nonisolated struct WhisperKnotLiveCapabilities: Decodable, Sendable {
    struct Tool: Decodable, Identifiable, Sendable {
        let name: String
        let method: String
        let path: String
        let purpose: String
        var id: String { name }
    }
    struct Skills: Decodable, Sendable { let location: String; let index: String }
    struct Memory: Decodable, Sendable { let file: String; let location: String }
    let ok: Bool
    let service: String
    let server_time: String
    let tools: [Tool]
    let skills: Skills
    let memory: Memory
}

/// Read-only discovery. Endpoint presence is not permission to execute it.
struct WhisperKnotLiveCapabilitiesPanel: View {
    @State private var value: WhisperKnotLiveCapabilities?
    @State private var loading = true
    @State private var invalidated = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live shell connection").font(.headline)
            if let value {
                Text("Reported by the running shell").font(.subheadline).foregroundStyle(.secondary)
                DisclosureGroup("Server endpoints · \(value.tools.count)") {
                    ForEach(value.tools) { tool in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tool.name.replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline.weight(.medium))
                            Text(tool.purpose).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                }
                Text("The model receives only endpoints the executor can safely use for this conversation. Fresh workspace commands run automatically in the active chat with nothing to enable. This does not grant access to personal products or device files.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Create reads the live skill index and at most two skill guides. Converse and Answer read zero skills. Workspace memory is read and updated automatically through actual commands, not a bundled copy.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if loading { ProgressView("Reading live capabilities") }
            else { Text("Live capabilities are unavailable. No saved catalog has been substituted.").font(.subheadline).foregroundStyle(.secondary) }
        }
        .task {
            defer { loading = false }
            do {
                let data = try await WhisperKnotShellEvidenceService.fetch("capabilities")
                let decoded = try JSONDecoder().decode(WhisperKnotLiveCapabilities.self, from: data)
                guard !invalidated, !Task.isCancelled, decoded.ok, decoded.service == "knot-sidecar" else { return }
                value = decoded
            } catch { value = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in invalidated = true; value = nil; loading = false }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in invalidated = true; value = nil; loading = false }
    }
}
