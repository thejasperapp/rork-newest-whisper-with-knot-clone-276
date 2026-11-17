import Foundation

/// A navigation identity, never an implicit AI context or access grant.
nonisolated struct WorkspaceSearchResult: Identifiable, Hashable {
    let objectID: String
    let kind: String
    let title: String
    let text: String
    let date: String
    var id: String { "\(kind):\(objectID)" }
    var icon: String {
        switch kind { case "Meetings": "video"; case "Notes": "doc.text"; case "Recordings": "waveform"; case "People": "person"; default: "briefcase" }
    }
    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return terms.allSatisfy { (title + " " + text).localizedStandardContains(String($0)) }
    }
}
