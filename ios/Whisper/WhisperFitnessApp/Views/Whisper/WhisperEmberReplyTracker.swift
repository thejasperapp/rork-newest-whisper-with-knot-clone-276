import Foundation
import SwiftUI

/// Tracks Jasper's auto-replies (`@ember` mention answers) per local device.
/// Because Jasper's comments are session-only synthetic rows, we keep a small
/// persistent log so `WhisperEmberProfileView` can show "things Jasper has
/// replied to" across launches.
@MainActor
@Observable
final class WhisperEmberReplyTracker {
    static let shared = WhisperEmberReplyTracker()

    nonisolated struct Entry: Codable, Identifiable, Hashable, Sendable {
        let id: String                 // synthetic comment id
        let postID: String
        let postUsername: String       // who owns the post
        let postCaption: String        // a short snippet for the profile feed
        let parentCommentID: String?
        let body: String               // Jasper's reply
        let askedBy: String?           // who tagged @ember (if known)
        let askedText: String?         // what they asked
        let created_at: Date
    }

    private let key = "whisper.ember.replies.v1"
    private(set) var entries: [Entry] = []

    private init() {
        load()
    }

    func record(_ entry: Entry) {
        // Dedupe by id (synthetic).
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        // Cap to last 200 to keep the log bounded.
        if entries.count > 200 { entries = Array(entries.prefix(200)) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
