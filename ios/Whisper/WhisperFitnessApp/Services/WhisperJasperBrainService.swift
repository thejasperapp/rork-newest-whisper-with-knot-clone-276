import Foundation
import Supabase

/// Jasper Brain — ONE shared intelligence config for iOS + web.
///
/// Admins edit voice/grammar, formatting, knowledge, and guardrail sections
/// at /jasper-brain on the website; this service composes them into the
/// IDENTICAL block the web client builds and Jasper folds it into system
/// prompts. Plain DB read cached 5 minutes, fetched only when a Jasper call
/// actually happens; nil when empty or unreachable so Jasper behaves exactly
/// as shipped.
@MainActor
final class WhisperJasperBrainService {
    static let shared = WhisperJasperBrainService()
    private init() {}

    private let client = SupabaseService.shared.client
    private var cached: (block: String, at: Date)?
    private var inFlight: Task<String, Never>?

    nonisolated private struct Row: Codable, Sendable {
        let section: String
        let content: String?
    }

    /// Section order — must match the web composer byte-for-byte.
    private static let order: [(id: String, title: String)] = [
        ("voice", "Voice & grammar"),
        ("formatting", "Formatting & cards"),
        ("knowledge", "Whisper knowledge"),
        ("guardrails", "Guardrails"),
    ]

    private static let header =
        "=== JASPER TEAM BRAIN (live shared rules — identical on iOS and web; follow them exactly) ==="

    /// The composed team-rules block, or nil when the brain is empty.
    func block() async -> String? {
        if let cached, Date().timeIntervalSince(cached.at) < 300 {
            return cached.block.isEmpty ? nil : cached.block
        }
        if let inFlight {
            let text = await inFlight.value
            return text.isEmpty ? nil : text
        }
        let client = self.client
        let task = Task<String, Never> {
            do {
                let rows: [Row] = try await client
                    .from("jasper_brain")
                    .select("section,content")
                    .execute()
                    .value
                var bySection: [String: String] = [:]
                for row in rows {
                    bySection[row.section] = row.content ?? ""
                }
                var parts: [String] = []
                for meta in Self.order {
                    let content = (bySection[meta.id] ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { continue }
                    parts.append("[\(meta.title)]\n\(String(content.prefix(1200)))")
                }
                guard !parts.isEmpty else { return "" }
                return Self.header + "\n" + parts.joined(separator: "\n\n")
            } catch {
                // Table missing or offline — Jasper behaves exactly as shipped.
                return ""
            }
        }
        inFlight = task
        let text = await task.value
        inFlight = nil
        cached = (text, Date())
        return text.isEmpty ? nil : text
    }
}
