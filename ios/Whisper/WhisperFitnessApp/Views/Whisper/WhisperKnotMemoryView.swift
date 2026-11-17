import SwiftUI
import Supabase

/// View and edit the workspace-root MEMORY.md that Knot reads through its shell.
/// The server resolves the account workspace; nothing here is injected into turns.
struct WhisperKnotMemoryView: View {
    let bot: WhisperKnotBot
    let conversationID: UUID
    private enum Phase: Equatable { case loading, ready, failed(String) }
    @State private var phase: Phase = .loading
    @State private var text = ""
    @State private var saved = ""
    @State private var exists = false
    @State private var saving = false
    @State private var editing = false
    @State private var notice: String?
    @FocusState private var focused: Bool

    private var dirty: Bool { text != saved }
    private var byteCount: Int { text.utf8.count }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Reading memory…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Memory unavailable", systemImage: "brain")
                } description: { Text(message) } actions: {
                    Button("Try again") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            case .ready:
                editor
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Memory").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if phase == .ready {
                ToolbarItem(placement: .primaryAction) {
                    if editing {
                        Button(saving ? "Saving…" : "Save") { Task { await save() } }
                            .disabled(!dirty || saving || byteCount > 200_000).fontWeight(.semibold)
                    } else {
                        Button("Edit") { editing = true; focused = true }
                    }
                }
                if editing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { text = saved; editing = false; focused = false }.disabled(saving)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .task { await load() }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text("MEMORY.md").font(.subheadline.monospaced().weight(.medium))
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
                    .font(.caption.monospacedDigit()).foregroundStyle(byteCount > 200_000 ? .red : .secondary)
            }
            if editing {
                TextEditor(text: $text)
                    .font(.system(.callout, design: .monospaced))
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            } else if text.isEmpty {
                ContentUnavailableView {
                    Label(exists ? "Memory is empty" : "No memory yet", systemImage: "brain")
                } description: {
                    Text("Knot writes facts and preferences here as you work together. You can add your own too.")
                } actions: {
                    Button("Add a note") { editing = true; focused = true }.buttonStyle(.bordered)
                }.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(text).font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            }
            Text(notice ?? "Shared across your Knots. Knot reads this file when it’s relevant; it’s never sent automatically.")
                .font(.caption).foregroundStyle(notice == nil ? .secondary : .primary)
                .contentTransition(.opacity)
        }
        .padding(20)
        .frame(maxWidth: 680).frame(maxWidth: .infinity)
    }

    private func call(_ body: [String: Any]) async throws -> [String: Any] {
        let generation = AccountStorage.generation
        let auth = try await SupabaseService.shared.client.auth.session
        guard generation == AccountStorage.generation else { throw CancellationError() }
        var request = URLRequest(url: URL(string: WhisperKnotBackend.origin + "/knot/shell/memory")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "X-Whisper-Authorization")
        var payload = body
        payload["bot"] = bot.rawValue; payload["conversationID"] = conversationID.uuidString.lowercased()
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard generation == AccountStorage.generation else { throw CancellationError() }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if status == 413 { throw MemoryError(message: "Memory is limited to 200 KB.") }
        guard (200..<300).contains(status) else { throw MemoryError(message: "Knot’s workspace couldn’t be reached. Your memory wasn’t changed.") }
        return object
    }
    private struct MemoryError: Error { let message: String }

    private func load() async {
        phase = .loading
        do {
            let result = try await call(["action": "read"])
            text = result["text"] as? String ?? ""; saved = text
            exists = result["exists"] as? Bool ?? false
            phase = .ready
        } catch is CancellationError {
        } catch {
            phase = .failed((error as? MemoryError)?.message ?? "Knot’s workspace couldn’t be reached.")
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        do {
            let result = try await call(["action": "write", "text": text])
            guard result["saved"] as? Bool == true else { throw MemoryError(message: "The save couldn’t be confirmed.") }
            withAnimation { saved = text; exists = true; editing = false; notice = "Saved." }
            focused = false
        } catch is CancellationError {
        } catch {
            withAnimation { notice = (error as? MemoryError)?.message ?? "The save couldn’t be confirmed." }
        }
    }
}
