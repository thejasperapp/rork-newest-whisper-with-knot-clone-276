import Foundation

/// Strict v1 decoding only. A well-formed embed is NOT a verified delivery or access grant.
nonisolated struct WhisperNotesCardCandidate: Decodable, Hashable, Sendable {
    let kind: String
    let deliveryID: UUID
    let documentID: UUID?
    let invitationID: UUID?
    let requestID: UUID?
    let sourceSequence: Int64?
    let roleAtSend: String?
    let sourceSHA256: String?
    let pageCount: Int?
    let expiresAt: String?
    let title: String
    let excerpt: String?
    let capturedAt: String

    var summary: String { kind == "whisper.notes.invitation" ? "Document invitation" : "Signature request" }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
    private static func invalid(_ decoder: Decoder) -> DecodingError {
        .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Notes card"))
    }
    private static func safeText(_ value: String, limit: Int) -> Bool {
        (1...limit).contains(value.utf16.count) && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !value.contains("<") && !value.contains(">")
        && !value.unicodeScalars.contains { [.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory) }
    }
    private static func utc(_ value: String) -> Bool {
        guard value.utf8.count <= 40, value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$"#, options: .regularExpression) != nil else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = value.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func string(_ name: String) throws -> String { try c.decode(String.self, forKey: Key(name)) }
        func uuid(_ name: String) throws -> UUID {
            guard let id = UUID(uuidString: try string(name)) else { throw Self.invalid(decoder) }
            return id
        }
        kind = try string("kind")
        let invitation = kind == "whisper.notes.invitation"
        guard invitation || kind == "whisper.sign.request", try c.decode(Int.self, forKey: Key("version")) == 1,
              try string("source_app") == "whisper-notes" else { throw Self.invalid(decoder) }
        let common: Set<String> = ["kind", "version", "source_app", "delivery_id", "preview"]
        let variant: Set<String> = invitation ? ["document_id", "invitation_id", "source_seq", "role_at_send"] : ["request_id", "source_sha256", "page_count", "expires_at"]
        guard Set(c.allKeys.map(\.stringValue)) == common.union(variant) else { throw Self.invalid(decoder) }
        deliveryID = try uuid("delivery_id")
        if invitation {
            documentID = try uuid("document_id"); invitationID = try uuid("invitation_id")
            let seq = try c.decode(Int64.self, forKey: Key("source_seq")); let role = try string("role_at_send")
            guard (0...9_007_199_254_740_991).contains(seq), ["viewer", "commenter", "editor"].contains(role) else { throw Self.invalid(decoder) }
            sourceSequence = seq; roleAtSend = role; requestID = nil; sourceSHA256 = nil; pageCount = nil; expiresAt = nil
        } else {
            requestID = try uuid("request_id")
            let hash = try string("source_sha256"); let count = try c.decode(Int.self, forKey: Key("page_count")); let expiry = try string("expires_at")
            guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil, (1...10).contains(count), Self.utc(expiry) else { throw Self.invalid(decoder) }
            sourceSHA256 = hash; pageCount = count; expiresAt = expiry
            documentID = nil; invitationID = nil; sourceSequence = nil; roleAtSend = nil
        }
        let p = try c.nestedContainer(keyedBy: Key.self, forKey: Key("preview"))
        guard Set(p.allKeys.map(\.stringValue)) == ["mode", "title", "excerpt", "captured_at"] else { throw Self.invalid(decoder) }
        title = try p.decode(String.self, forKey: Key("title")); capturedAt = try p.decode(String.self, forKey: Key("captured_at"))
        guard Self.safeText(title, limit: 160), Self.utc(capturedAt) else { throw Self.invalid(decoder) }
        let mode = try p.decode(String.self, forKey: Key("mode"))
        if mode == "title_only" {
            guard try p.decodeNil(forKey: Key("excerpt")) else { throw Self.invalid(decoder) }
            excerpt = nil
        } else if mode == "approved_excerpt" {
            let text = try p.decode(String.self, forKey: Key("excerpt"))
            guard Self.safeText(text, limit: 280) else { throw Self.invalid(decoder) }
            excerpt = text
        } else { throw Self.invalid(decoder) }
    }
}
