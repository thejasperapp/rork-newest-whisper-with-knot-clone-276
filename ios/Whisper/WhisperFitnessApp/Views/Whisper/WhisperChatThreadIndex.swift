import SwiftUI

// MARK: - Cached chat formatters
//
// `DateFormatter()` costs on the order of a millisecond to create, and the
// thread used to build one per timestamp chip, per revealed stamp, and per
// card header — on EVERY render (every keystroke). These are built once.

enum WhisperChatFormatters {
    private static func make(_ format: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = format
        return df
    }

    private static let clock: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.timeStyle = .short
        df.dateStyle = .none
        return df
    }()
    private static let hourMinute: DateFormatter = make("h:mm a")
    private static let weekdayAt: DateFormatter = make("EEEE 'at' h:mm a")
    private static let fullAt: DateFormatter = make("MMM d, yyyy 'at' h:mm a")
    private static let monthDayTime: DateFormatter = make("MMM d  h:mm a")

    /// "5:33 PM" — the press card's header.
    static func clockStamp(_ date: Date) -> String {
        clock.string(from: date)
    }

    /// Instagram-style exact-time label shown when you tap a bubble.
    static func exactStamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return hourMinute.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday at " + hourMinute.string(from: date) }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return weekdayAt.string(from: date) }
        return fullAt.string(from: date)
    }

    /// The quiet session-divider chip between runs 15+ minutes apart.
    static func relativeStamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return hourMinute.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday  " + hourMinute.string(from: date) }
        return monthDayTime.string(from: date)
    }
}

// MARK: - The per-thread render index
//
// Everything a chat thread derives from its rows to draw — the filtered
// message list, the runs with their timestamp chips, the "Seen" marker — is
// built ONCE per data change and served from memory. The thread body used to
// regroup every message (parsing every date, creating formatters) on every
// render; with a few hundred rows that alone was tens of milliseconds per
// keystroke.

@MainActor
final class WhisperChatThreadIndex {
    static let shared = WhisperChatThreadIndex()

    /// One run of bubbles — same sender, close in time. `isSystem` marks a
    /// roster/system line in groups that renders as a quiet capsule.
    struct Group: Identifiable {
        let id: String
        /// The divider chip above this run, when 15+ minutes passed.
        let timestamp: String?
        let messages: [WhisperMessageRow]
        let isSystem: Bool
    }

    struct Index {
        let signature: String
        let messages: [WhisperMessageRow]
        let groups: [Group]
        /// The newest message of mine that the other side has read.
        let lastSeenMineID: String?

        static let empty = Index(signature: "", messages: [], groups: [], lastSeenMineID: nil)
    }

    private var cache: [String: Index] = [:]

    private init() {}

    func clear() { cache.removeAll() }

    /// The index for `key` (a thread id) built from `rows`. Returns the cached
    /// index when the rows haven't changed (cheap signature: count · first/last
    /// id · read count · the day, so "Yesterday" chips roll over at midnight).
    ///
    /// - `runWindow`: how close two messages from one sender must be to share
    ///   a run (`.infinity` = only the sender matters, the DM grammar).
    /// - `systemLine`: rows for which this returns true render alone as a
    ///   system capsule (group roster events).
    /// - `dropThoughtReplies`: hide historical thought-reply embeds (DMs).
    func index(
        key: String,
        rows: [WhisperMessageRow],
        currentUIDLower: String,
        runWindow: TimeInterval = .infinity,
        systemLine: ((String) -> Bool)? = nil,
        dropThoughtReplies: Bool = true,
        revision: UInt64? = nil
    ) -> Index {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let contentKey = revision.map(String.init) ?? String(rows.hashValue)
        let signature = "\(AccountStorage.generation)|\(contentKey)|\(day)|\(currentUIDLower)|\(runWindow)|\(dropThoughtReplies)|\(TimeZone.current.identifier)|\(Locale.current.identifier)"
        if let cached = cache[key], cached.signature == signature { return cached }

        let messages: [WhisperMessageRow] = dropThoughtReplies
            ? rows.filter { !$0.body.hasPrefix(WhisperThoughtReplyEmbed.prefix) }
            : rows

        var groups: [Group] = []
        var currentSender: String? = nil
        var currentMsgs: [WhisperMessageRow] = []
        var lastDate: Date? = nil
        var lastRunDate: Date? = nil
        var pendingTimestamp: String? = nil

        func flush() {
            guard let first = currentMsgs.first else { return }
            groups.append(Group(id: first.id + "-grp", timestamp: pendingTimestamp, messages: currentMsgs, isSystem: false))
            pendingTimestamp = nil
            currentMsgs.removeAll()
        }

        for msg in messages {
            let date = WhisperBackendService.parseISO(msg.created_at)
            if let date, let last = lastDate {
                if date.timeIntervalSince(last) > 15 * 60 {
                    flush()
                    pendingTimestamp = WhisperChatFormatters.relativeStamp(date)
                    currentSender = nil
                }
            } else if pendingTimestamp == nil, let date {
                pendingTimestamp = WhisperChatFormatters.relativeStamp(date)
            }
            if let systemLine, systemLine(msg.body) {
                flush()
                groups.append(Group(id: msg.id + "-sys", timestamp: pendingTimestamp, messages: [msg], isSystem: true))
                pendingTimestamp = nil
                currentSender = nil
                lastRunDate = nil
                if let date { lastDate = date }
                continue
            }
            let sender = msg.from_user_id.lowercased()
            var breaksRun = sender != currentSender
            if !breaksRun, runWindow.isFinite, let date, let lastRun = lastRunDate,
               date.timeIntervalSince(lastRun) > runWindow {
                breaksRun = true
            }
            if breaksRun {
                flush()
                currentSender = sender
            }
            currentMsgs.append(msg)
            if let date {
                lastDate = date
                lastRunDate = date
            }
        }
        flush()

        let lastSeen = messages.last(where: {
            $0.from_user_id.lowercased() == currentUIDLower && $0.read_at != nil
        })?.id

        let built = Index(signature: signature, messages: messages, groups: groups, lastSeenMineID: lastSeen)
        if cache.count >= 24, cache[key] == nil { cache.removeAll() }
        cache[key] = built
        return built
    }
}
