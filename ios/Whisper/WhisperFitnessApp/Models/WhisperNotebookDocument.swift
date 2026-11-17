import Foundation

/// Private account writing with device recovery, separate from shared meeting rows.
nonisolated struct WhisperNotebookDocument: Codable, Identifiable, Equatable, Sendable {
    let version: Int
    let id: String
    let ownerId: String
    var title: String
    var folder: String
    var people: String
    var meetingId: String?
    var templateId: String
    var instructions: String
    var notes: String
    var transcript: String
    var revision: Int
    var storageRevision: Int
    let createdAt: String
    var updatedAt: String
    var enhancement: Result?
    var commitments: [Commitment]
    var syncEnabled: Bool?
    var cloudRevision: Int?
    var syncedStorageRevision: Int?
    var syncOperationId: String?
    var deletedAt: String?
    var recapCopiedAt: String?
    var recordingIds: [String]?
    var highlights: [WhisperNotebookHighlight]?
    var isMeetingWriting: Bool?

    nonisolated struct Source: Codable, Identifiable, Equatable, Sendable {
        let id: String
        let kind: String
        let text: String
        var provenance: String? = nil
    }
    nonisolated struct Item: Codable, Equatable, Sendable {
        let text: String
        let sourceIds: [String]
    }
    nonisolated struct Section: Codable, Equatable, Sendable {
        let title: String
        let items: [Item]
    }
    nonisolated struct Proposal: Codable, Equatable, Sendable {
        var title: String
        var owner: String
        var when: String
        let sourceIds: [String]
    }
    nonisolated struct Result: Codable, Equatable, Sendable {
        let insufficient: Bool
        let sections: [Section]
        let actions: [Proposal]
        let revision: Int
        let generatedAt: String
        let sources: [Source]
    }
    nonisolated struct Commitment: Codable, Identifiable, Equatable, Sendable {
        let id: String
        var title: String
        var owner: String
        var when: String
        var done: Bool
        let sources: [Source]
    }

    static func blank(ownerID: String, meetingID: String? = nil, title: String = "", id: String = UUID().uuidString.lowercased()) -> Self {
        let now = Date().ISO8601Format()
        return Self(version: 1, id: id, ownerId: ownerID, title: String(title.prefix(160)), folder: "", people: "", meetingId: meetingID, templateId: "general", instructions: "", notes: "", transcript: "", revision: 0, storageRevision: 0, createdAt: now, updatedAt: now, enhancement: nil, commitments: [], syncEnabled: true)
    }

    func newCopy(prefix: String) -> Self {
        Self(version: version, id: UUID().uuidString.lowercased(), ownerId: ownerId, title: String("\(prefix)\(displayTitle)".prefix(160)), folder: folder, people: people, meetingId: meetingId, templateId: templateId, instructions: instructions, notes: notes, transcript: transcript, revision: revision, storageRevision: 0, createdAt: Date().ISO8601Format(), updatedAt: Date().ISO8601Format(), enhancement: enhancement, commitments: commitments, syncEnabled: true, recapCopiedAt: recapCopiedAt, recordingIds: recordingIds, highlights: highlights)
    }

    nonisolated struct Recovery: Identifiable, Sendable {
        let id: String
        let document: WhisperNotebookDocument
    }

    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled note" : title }
    var hasStaleEnhancement: Bool { enhancement.map { $0.revision != revision } ?? false }

    func sources() throws -> [Source] {
        guard notes.utf16.count + transcript.utf16.count <= 24000 else { throw WhisperNotebookError.tooLong }
        var result: [Source] = []
        for (kind, body, prefix) in [("notes", notes, "N"), ("transcript", transcript, "T")] {
            var count = 0
            for raw in body.components(separatedBy: .newlines) {
                var remaining = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                while !remaining.isEmpty {
                    count += 1
                    var chunk = "", units = 0
                    for character in remaining {
                        let size = String(character).utf16.count
                        if units + size > 1200 { break }
                        chunk.append(character); units += size
                    }
                    guard !chunk.isEmpty else { throw WhisperNotebookError.tooLong }
                    result.append(Source(id: "\(prefix)\(count)", kind: kind, text: chunk))
                    remaining.removeFirst(chunk.count)
                }
            }
        }
        guard !result.isEmpty else { throw WhisperNotebookError.empty }
        guard result.count <= 160 else { throw WhisperNotebookError.tooManySources }
        return result
    }

    var exportText: String {
        var lines = ["# \(displayTitle)", "People: \(people.isEmpty ? "Not set" : people)", "Folder: \(folder.isEmpty ? "Unfiled" : folder)", "", "## My notes", notes]
        if !transcript.isEmpty { lines += ["", "## Pasted transcript", transcript] }
        if let enhancement {
            lines += ["", "## Jasper draft\(hasStaleEnhancement ? " (sources have since changed)" : "")"]
            for section in enhancement.sections {
                lines.append("### \(section.title)")
                lines += section.items.map { "- \($0.text) [\($0.sourceIds.joined(separator: ", "))]" }
            }
            lines += ["", "### Source snapshot"] + enhancement.sources.map { "[\($0.id)] \($0.provenance ?? $0.kind): \($0.text)" }
        }
        if let highlights, !highlights.isEmpty {
            lines += ["", "## Retained highlights"]
            lines += highlights.map { "- \($0.text)\n  \($0.kind) · \($0.origin)\($0.stale ? " · original quote; writing changed" : "")" }
        }
        lines += ["", "## Tracked follow-ups"]
        for item in commitments {
            lines.append("- [\(item.done ? "x" : " ")] \(item.title) — \(item.owner.isEmpty ? "Unassigned" : item.owner) · \(item.when.isEmpty ? "No due date" : item.when)")
            lines += item.sources.map { "  Original evidence [\($0.id)] \($0.provenance ?? $0.kind): \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }
}
