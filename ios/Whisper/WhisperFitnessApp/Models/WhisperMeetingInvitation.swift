import Foundation

/// Public invitation identity, never a derived database ID or an authentication handoff.
nonisolated struct WhisperMeetingInvitation: Equatable, Sendable {
    let idOrCode: String
    var speedDate: Bool = false
    var socialCall: Bool = false

    var isSocial: Bool { speedDate || socialCall }
    var webURL: URL? { URL(string: "https://meet.mydailywhisper.com/meet/\(idOrCode)") }
    var appURL: URL? { URL(string: "whisperworkspace://meet/\(idOrCode)") }

    static func isIdentity(_ value: String) -> Bool {
        value.range(of: "^(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[wW][sS][pP]-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4})$", options: .regularExpression) != nil
    }

    static func parse(_ url: URL) -> Self? {
        guard url.user == nil, url.password == nil, url.port == nil else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/").map(String.init)
        let identity: String
        if scheme == "whisper" || scheme == "whisperworkspace" {
            guard host == "meet", parts.count == 1 else { return nil }
            identity = parts[0]
        } else {
            guard ["https", "http"].contains(scheme),
                  ["mydailywhisper.com", "www.mydailywhisper.com", "meet.mydailywhisper.com"].contains(host) else { return nil }
            if parts.count == 2, parts[0] == "meet" { identity = parts[1] }
            else if host == "meet.mydailywhisper.com", parts.count == 1 { identity = parts[0] }
            else { return nil }
        }
        guard isIdentity(identity) else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Self(idOrCode: identity,
                    speedDate: query.contains { $0.name == "sd" && $0.value == "1" },
                    socialCall: query.contains { ["call", "groupCall"].contains($0.name) })
    }

    static func fromText(_ text: String?) -> Self? {
        guard let text else { return nil }
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Structured date/calendar/call payloads must reach their own card decoders.
        guard !raw.contains("::whisper-") else { return nil }
        if isIdentity(raw) { return Self(idOrCode: raw) }
        for word in raw.split(whereSeparator: { $0.isWhitespace }) {
            let candidate = String(word).trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(),.;!"))
            let value = candidate.hasPrefix("www.mydailywhisper.com/") ? "https://" + candidate : candidate
            if let url = URL(string: value), var target = parse(url) {
                if raw.contains("Started a group") { target.socialCall = true }
                return target
            }
        }
        return nil
    }
}
