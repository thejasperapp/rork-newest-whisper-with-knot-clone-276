import Foundation

/// Client for the shared Jasper "brain" that already runs on Whisper's
/// backend. Whisper does NOT fork the ~80-file Jasper stack or rebuild the
/// system prompt — the brain is server-side and we just call it with
/// `app: "whisper"` so Whisper inherits Whisper's Jasper verbatim (and stays
/// in sync automatically when the Whisper team adds a `whisper` override).
///
/// Three endpoints (all POST, JSON):
///   - `/ember/chat`          — one Jasper turn (returns the reply text, which
///                              may end in a fenced chart/goalplan/schedule).
///   - `/interpret`           — real stats/Python over a numeric series.
///   - `/ember/system-prompt` — the exact composed prompt for an app (parity).
///
/// The CALLER owns the context: Whisper composes the `healthContext` block
/// (see `WhisperEmberHealthContext`) from the shared `jasper_*` bridge tables
/// and passes it in. The server owns the reasoning + output grammar.
nonisolated struct WhisperEmberBrainService: Sendable {
    /// Base URL of the shared Jasper brain. Lives on Whisper's backend — both
    /// apps point at the same deployment so the brain is identical.
    static let baseURL = "https://h5jwib7i6dvunvfn7onqr-backend.rork.app"

    /// Identity sent on every call. Always `whisper` — the server keys its
    /// identity/capability layers off this without us forking anything.
    static let app = "whisper"

    // MARK: - /ember/chat

    /// One conversational message in the running history sent up to the brain.
    nonisolated struct ChatMessage: Codable, Sendable, Hashable {
        let role: String   // "user" | "assistant"
        let content: String
    }

    /// Optional `/interpret` result fed back into `/ember/chat` so Jasper
    /// cites REAL computed numbers instead of estimating.
    nonisolated struct InterpreterPayload: Codable, Sendable {
        let output: String
    }

    private nonisolated struct ChatRequest: Encodable {
        let app: String
        let message: String
        let healthContext: String
        let history: [ChatMessage]
        let isWebQuery: Bool
        let interpreter: InterpreterPayload?
        let model: String?
    }

    private nonisolated struct ChatResponse: Decodable {
        let ok: Bool
        let reply: String?
        let model: String?
        let error: String?
    }

    /// One Jasper turn. Returns the raw reply text (fenced output blocks
    /// intact — the caller strips/renders them). Throws on transport or
    /// server (`ok: false`) failure so the chat UI can show a retry state.
    func chat(
        message: String,
        healthContext: String,
        history: [ChatMessage] = [],
        isWebQuery: Bool = false,
        interpreterOutput: String? = nil,
        model: String? = nil
    ) async throws -> String {
        guard let url = URL(string: "\(Self.baseURL)/ember/chat") else {
            throw EmberBrainError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // This non-streaming endpoint must not consume a full minute before
        // the engine can offer its existing fallback. True token streaming
        // requires the shared brain's server contract to be enabled first.
        request.timeoutInterval = 15

        let interpreter = interpreterOutput
            .flatMap { $0.isEmpty ? nil : InterpreterPayload(output: $0) }
        let body = ChatRequest(
            app: Self.app,
            message: message + "\n\n[Whisper native client response format]\n" + WhisperKnotMessageSkills.outputContract,
            healthContext: "ASSISTANT IDENTITY: Your name is Knot, Whisper’s friendly AI assistant, not a fitness pal or fitness-first companion. Introduce yourself as Knot even when older history uses a retired name. The separate Jasper fitness app retains its name.\n\n" + healthContext + "\n\n" + WhisperKnotMessageSkills.instruction,
            history: history,
            isWebQuery: isWebQuery,
            interpreter: interpreter,
            model: model
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw EmberBrainError.server(decoded.error ?? "Knot is unavailable (HTTP \(http.statusCode)).")
        }
        guard decoded.ok, let reply = decoded.reply, !reply.isEmpty else {
            throw EmberBrainError.server(decoded.error ?? "Knot returned an empty reply.")
        }
        return reply
    }

    // MARK: - /interpret

    /// A windowed numeric dataset to run real stats over. `series` maps a
    /// metric name → its day-by-day values; `days` are the matching labels.
    nonisolated struct Dataset: Encodable, Sendable {
        let series: [String: [Double]]
        let days: [String]
    }

    private nonisolated struct InterpretRequest: Encodable {
        let question: String
        let dataset: Dataset
    }

    private nonisolated struct InterpretResponse: Decodable {
        let ok: Bool
        let output: String?
        let error: String?
    }

    /// Runs REAL stats/Python (r-values, slopes, z-scores) on the dataset and
    /// returns the computed `output` string. Recommended FIRST step for
    /// trend / correlation / "is my X good" / "am I improving" questions —
    /// pass the result back into `chat(interpreterOutput:)`. Returns nil on
    /// any failure so the caller can fall back to a plain chat turn.
    func interpret(question: String, dataset: Dataset) async -> String? {
        guard let url = URL(string: "\(Self.baseURL)/interpret") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 40
        guard let httpBody = try? JSONEncoder().encode(
            InterpretRequest(question: question, dataset: dataset)
        ) else { return nil }
        request.httpBody = httpBody
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(InterpretResponse.self, from: data),
              decoded.ok,
              let output = decoded.output,
              !output.isEmpty else { return nil }
        return output
    }

    // MARK: - /ember/system-prompt (parity check)

    private nonisolated struct SystemPromptRequest: Encodable {
        let app: String
    }

    private nonisolated struct SystemPromptResponse: Decodable {
        let ok: Bool
        let prompt: String?
    }

    /// Returns the exact composed system prompt for an app. Used once to diff
    /// Whisper vs Whisper and confirm Whisper's Jasper is the same brain.
    func systemPrompt(app: String = WhisperEmberBrainService.app) async -> String? {
        guard let url = URL(string: "\(Self.baseURL)/ember/system-prompt") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        guard let httpBody = try? JSONEncoder().encode(SystemPromptRequest(app: app)) else { return nil }
        request.httpBody = httpBody
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(SystemPromptResponse.self, from: data),
              decoded.ok else { return nil }
        return decoded.prompt
    }
}

nonisolated enum EmberBrainError: LocalizedError {
    case badURL
    case server(String)

    nonisolated var errorDescription: String? {
        switch self {
        case .badURL: return "Couldn't reach Knot."
        case .server(let message): return message
        }
    }
}
