import Foundation

/// Only removes assistant protocol/analysis envelopes. Ordinary code examples
/// remain readable; never apply this to user messages or attachments.
nonisolated enum WhisperKnotOutput {
    static let instruction = """
    KNOT CHAT PRESENTATION AND APPROVAL RULES (override legacy atlas examples):
    Answer in the active Knot's specialist identity with clean, useful prose. Never print internal reasoning, sandbox output or sandbox:/ links, interpreter traces, execution steps, tool logs or protocol payloads. Do not add health/step charts, native Jasper cards, goalplan or schedule visualization blocks. Numerical claims must come from supplied authorized records; never invent values. All writes and tool openings are proposals for explicit native approval; ignore legacy auto:true directions. Use the client message/actions contract for approval requests. A request is not a completed action. Explain missing capabilities honestly. Available skills: writing/editing; explanations and research (only claim real sources when returned); planning; current authorized profile personalization if supplied; accessible post/community discovery; photo/file understanding; voice; post, meeting, reminder, community and follow proposals; approved recurring public tracking, goal check-ins and own-account creator-performance checks. No arbitrary app-tool navigation contracts are available. Creator metrics require a new exact read-scope approval and account eligibility; no live private metrics tool is available. No extra data access or permissions are granted.
    """

    /// Hide only recognized internal envelopes and a possible partial opener.
    /// Ordinary inline code, code fences, HTML examples and comparisons continue
    /// to stream rather than freezing everything after the first backtick or <.
    static func streaming(_ text: String) -> String {
        var visible = text
        let fences = ["actions", "message", "followups", "chart", "goalplan", "schedule", "postdraft", "profilecard", "jasper", "sandbox", "analysis", "interpret", "interpreter", "tool", "tool_output", "execution", "execution_steps"].map { "```" + $0 }
        let tags = ["analysis", "think", "thinking", "tool_output", "sandbox"].map { "<" + $0 + ">" }
        // These tokens are bounded; inspect only the final line/tail for partials.
        let lineStart = visible.lastIndex(of: "\n").map { visible.index(after: $0) } ?? visible.startIndex
        let line = String(visible[lineStart...]).trimmingCharacters(in: .whitespaces).lowercased()
        if !line.isEmpty, fences.contains(where: { $0.hasPrefix(line) }) {
            visible.removeSubrange(lineStart...)
        }
        if let start = visible.lastIndex(of: "<") {
            let tail = String(visible[start...]).lowercased()
            if tags.contains(where: { $0.hasPrefix(tail) }) { visible.removeSubrange(start...) }
        }
        let token = "sandbox:/"
        for size in stride(from: min(token.count, visible.count), through: 1, by: -1) {
            if visible.lowercased().hasSuffix(String(token.prefix(size))) {
                visible.removeLast(size)
                break
            }
        }
        return clean(visible)
    }

    static func clean(_ text: String) -> String {
        var output = text
        let pattern = #"(?im)^\s*```(?:actions|message|followups|chart|goalplan|schedule|postdraft|profilecard|jasper|sandbox|analysis|interpret(?:er)?|tool(?:_output)?|execution(?:_steps)?)(?=\s|\{|\[|$)[^\n]*\n?"#
        // Strip every known envelope, including malformed unterminated tails.
        while let opening = output.range(of: pattern, options: .regularExpression) {
            let closing = output.range(of: "```", range: opening.upperBound..<output.endIndex)
            output.removeSubrange(opening.lowerBound..<(closing?.upperBound ?? output.endIndex))
        }
        let pairedTags = #"(?is)<(?:analysis|think|thinking|tool_output|sandbox)>.*?(?:</(?:analysis|think|thinking|tool_output|sandbox)>|$)"#
        output = output.replacingOccurrences(of: pairedTags, with: "", options: .regularExpression)
        // A model-authored JSON dispatch is not a real native tool receipt.
        // Remove only recognized complete protocol shapes; retain ordinary JSON
        // and code examples. This never constructs a proposal or authorizes work.
        if let fence = try? NSRegularExpression(pattern: #"(?ims)^\s*```json[^\n]*\n(.*?)^\s*```[^\S\n]*(?:\n|$)"#) {
            for match in fence.matches(in: output, range: NSRange(output.startIndex..., in: output)).reversed() {
                guard let payload = Range(match.range(at: 1), in: output), isMachineDispatch(String(output[payload])), let range = Range(match.range, in: output) else { continue }
                output.removeSubrange(range)
            }
        }
        if isMachineDispatch(output) { output = "" }
        else { output = output.components(separatedBy: "\n").filter { !isMachineDispatch($0) }.joined(separator: "\n") }
        // Hosted analysis sometimes emits local chart-file links that cannot
        // open in Whisper. Do not present them as delivered attachments.
        output = output.replacingOccurrences(of: #"!?\[[^\]\n]*\]\(sandbox:[^\)\n]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
        output = output.replacingOccurrences(of: #"sandbox:/[^\s<>\)]+"#, with: "", options: [.regularExpression, .caseInsensitive])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMachineDispatch(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = (object["tool"] ?? object["name"]) as? String,
              ["session_input", "session_open", "session_status", "session_read", "session_close", "capabilities", "document_script", "document_prepare", "workspace_read", "skill_draft", "skill_draft_read"].contains(tool) else { return false }
        return object["arguments"] is [String: Any] || object["data"] is String
    }
}
