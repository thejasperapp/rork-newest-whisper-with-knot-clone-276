import Foundation

/// Identity-only links supplied by Whisper Notes. They never establish access.
nonisolated enum WhisperNotesLink: Equatable, Sendable {
    case shared(UUID?)
    case document(id: UUID, owner: UUID, tab: String)

    static func isNotesURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "whispernotes" || url.host?.lowercased() == "notes.mydailywhisper.com"
    }

    static func parse(_ url: URL) -> Self? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.user == nil, c.password == nil, c.port == nil, c.fragment == nil else { return nil }
        let native = c.scheme?.lowercased() == "whispernotes"
        guard native || (c.scheme?.lowercased() == "https" && c.host?.lowercased() == "notes.mydailywhisper.com") else { return nil }
        let route = native ? "/\(c.host ?? "")\(c.path)" : c.path
        let parts = route.split(separator: "/", omittingEmptySubsequences: false)
        let query = c.queryItems ?? []
        if route == "/shared", query.isEmpty { return .shared(nil) }
        guard parts.count == 3, parts[0].isEmpty, let id = UUID(uuidString: String(parts[2])) else { return nil }
        if parts[1] == "shared", query.isEmpty { return .shared(id) }
        guard parts[1] == (native ? "document" : "d"),
              query.allSatisfy({ ["owner", "tab"].contains($0.name) }),
              query.filter({ $0.name == "owner" }).count == 1,
              query.filter({ $0.name == "tab" }).count <= 1,
              let rawOwner = query.first(where: { $0.name == "owner" })?.value,
              let owner = UUID(uuidString: rawOwner) else { return nil }
        let tabItems = query.filter { $0.name == "tab" }
        let tab = tabItems.isEmpty ? "full" : (tabItems.first?.value ?? "")
        guard ["quick", "full", "transcript"].contains(tab) else { return nil }
        return .document(id: id, owner: owner, tab: tab)
    }

    var appURL: URL? { makeURL(native: true) }
    var webURL: URL? { makeURL(native: false) }

    private func makeURL(native: Bool) -> URL? {
        var c = URLComponents()
        c.scheme = native ? "whispernotes" : "https"
        switch self {
        case .shared(let id):
            c.host = native ? "shared" : "notes.mydailywhisper.com"
            c.path = (native ? "" : "/shared") + (id.map { "/" + $0.uuidString.lowercased() } ?? "")
        case .document(let id, let owner, let tab):
            c.host = native ? "document" : "notes.mydailywhisper.com"
            c.path = (native ? "/" : "/d/") + id.uuidString.lowercased()
            c.queryItems = [URLQueryItem(name: "owner", value: owner.uuidString.lowercased()), URLQueryItem(name: "tab", value: tab)]
        }
        return c.url
    }
}
