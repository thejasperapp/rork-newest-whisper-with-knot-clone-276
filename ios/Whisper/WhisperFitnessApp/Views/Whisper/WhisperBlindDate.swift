import SwiftUI
import Supabase

/// Blind dating — the SERVICE behind the Dating hub's video circle:
///   • the pairing queue (strangers matched by preferences + private answers)
///   • the in-room date session — a shared clock, the curtain + reveal,
///     mutual extensions, and Jasper's prompt deck
///   • date records + PRIVATE decisions (the partner's answer only comes
///     back once yours is in) + Jasper's recap
/// Mirrors web `lib/blindDate.ts` exactly — same wire names, same payloads,
/// same prompt formats — so a date started on web runs on iOS and vice versa.
enum WhisperBlindDate {
    // ─── The shared clock ────────────────────────────────────────────────
    static let durationSec: Int = 300
    static let revealAtSec: Int = 120
    static let extensionSec: Int = 120
    static let maxExtensions: Int = 2

    enum Decision: String {
        case again, friends, pass

        var label: String {
            switch self {
            case .again: return "See them again"
            case .friends: return "Just friends"
            case .pass: return "Not this time"
            }
        }
        var emoji: String {
            switch self {
            case .again: return "💘"
            case .friends: return "🤝"
            case .pass: return "👋"
            }
        }
    }

    /// Meeting-wire event names (identical on web).
    enum Wire {
        static let ready = "blind-ready"
        static let state = "blind-state"
        static let reveal = "blind-reveal"
        static let extend = "blind-extend"
        static let prompts = "blind-prompts"
        static let promptIndex = "blind-prompt-index"
        static let left = "blind-left"
    }

    /// Rooms where I already said "I'm ready" (the lobby's Enter button) —
    /// the in-room welcome takeover is skipped for these.
    static var readyRooms: Set<String> = []
    /// Queue-paired rooms → the partner's username (the welcome says who).
    static var pairedPartners: [String: String] = [:]

    // ─── Jasper's prompt deck ────────────────────────────────────────────

    enum Stage: String, CaseIterable {
        case warm = "WARM"
        case deeper = "DEEPER"
        case spark = "SPARK"

        var label: String {
            switch self {
            case .warm: return "Warm up"
            case .deeper: return "Go deeper"
            case .spark: return "Spark"
            }
        }
        var emoji: String {
            switch self {
            case .warm: return "☕️"
            case .deeper: return "🌙"
            case .spark: return "✨"
            }
        }
    }

    struct Prompt: Identifiable, Equatable {
        let stage: Stage
        let text: String
        var id: String { "\(stage.rawValue):\(text)" }
    }

    /// Dating-mindset fallback — used when the AI deck doesn't land in time.
    static let fallbackDeck: [Prompt] = [
        Prompt(stage: .warm, text: "What did your week actually look like — the real version, not the highlight reel?"),
        Prompt(stage: .warm, text: "What's something small that made you happy this week?"),
        Prompt(stage: .warm, text: "If you had a free Saturday and zero plans, where would you end up?"),
        Prompt(stage: .deeper, text: "What's something people usually get wrong about you at first?"),
        Prompt(stage: .deeper, text: "What does a good relationship look like to you — day to day, not in theory?"),
        Prompt(stage: .deeper, text: "What's a lesson a past relationship taught you that you're grateful for?"),
        Prompt(stage: .spark, text: "Would you rather a spontaneous road trip or a perfectly planned weekend away — and who's driving?"),
        Prompt(stage: .spark, text: "Give the other person a compliment based only on how they've sounded so far."),
        Prompt(stage: .spark, text: "If this went well, what would the second date be?")
    ]

    /// The strict-format ask both apps send Jasper for the deck.
    static let deckPrompt = """
    You are Knot, Whisper's matchmaker, hosting a BLIND VIDEO DATE between two people who can hear but not yet see each other. Using ONLY their dating cards and icebreaker answers in your context, write 9 conversation prompts they should ask EACH OTHER, in three stages: 3 WARM (easy, playful, specific to what they share), 3 DEEPER (values, what they're looking for — honest but kind), 3 SPARK (flirty, fun, memorable — a would-you-rather, a dare, a compliment prompt). Each prompt is ONE sentence either person can answer, no names, no emojis, never invent facts about them. Reply with EXACTLY nine lines in this format and nothing else:
    WARM: <prompt>
    WARM: <prompt>
    WARM: <prompt>
    DEEPER: <prompt>
    DEEPER: <prompt>
    DEEPER: <prompt>
    SPARK: <prompt>
    SPARK: <prompt>
    SPARK: <prompt>
    """

    /// Parses the WARM/DEEPER/SPARK lines — nil when fewer than 6 land.
    static func parseDeck(_ text: String) -> [Prompt]? {
        var deck: [Prompt] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            for stage in Stage.allCases {
                let prefix = "\(stage.rawValue):"
                if line.uppercased().hasPrefix(prefix) {
                    let body = String(line.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
                    if body.count > 8 { deck.append(Prompt(stage: stage, text: String(body.prefix(220)))) }
                    break
                }
            }
        }
        guard deck.count >= 6 else { return nil }
        // Stage order: warm → deeper → spark.
        let order: [Stage] = [.warm, .deeper, .spark]
        return order.flatMap { s in deck.filter { $0.stage == s } }
    }

    /// Wire shape — ["WARM: …", …] so both apps decode the same deck.
    static func encodeDeck(_ deck: [Prompt]) -> [String] {
        deck.map { "\($0.stage.rawValue): \($0.text)" }
    }

    static func decodeDeck(_ lines: [String]) -> [Prompt] {
        parseDeck(lines.joined(separator: "\n")) ?? []
    }

    /// ONE quiet AI call for the deck — grounded in both cards + my private
    /// answers; falls back to the static deck on any failure.
    static func generateDeck(
        myName: String,
        myCard: [String: String],
        theirCard: WhisperSpeedDating.WireCard?,
        meetingTitle: String
    ) async -> [Prompt] {
        var blocks: [String] = []
        if !myCard.isEmpty {
            blocks.append(WhisperSpeedDating.contextBlock(label: "@\(myName)'S DATING CARD", answers: myCard))
        }
        if let theirCard {
            blocks.append(WhisperSpeedDating.contextBlock(label: "@\(theirCard.username)'S DATING CARD", answers: theirCard.answers))
        }
        let answers = WhisperDatingAnswers.all().prefix(5)
        if !answers.isEmpty {
            blocks.append("@\(myName)'S ICEBREAKER ANSWERS:\n" + answers.map { "- \($0.prompt) → \($0.answer)" }.joined(separator: "\n"))
        }
        guard !blocks.isEmpty else { return fallbackDeck }
        let reply = await WhisperMeetingCompanion.meetingAnswer(
            question: deckPrompt,
            meetingTitle: meetingTitle,
            participants: [myName, theirCard?.username].compactMap { $0 },
            preferredMode: WhisperEmberCoachMode.load(),
            extraContext: blocks.joined(separator: "\n\n")
        )
        guard let reply, let deck = parseDeck(reply.text) else { return fallbackDeck }
        return deck
    }

    // ─── Jasper's recap ──────────────────────────────────────────────────

    /// The strict-format recap ask — the judge grown up for the leave screen.
    static let recapPrompt = """
    You are Knot, Whisper's matchmaker. A BLIND VIDEO DATE just ended. Using ONLY the dating cards and the call transcript in your context, give the person reading this an honest, warm, specific read of the date. Never invent details; if the transcript is thin, say what you CAN see. Reply in EXACTLY this format with no extra prose:
    SCORE: <0-100 compatibility>
    VERDICT: <one honest line on the match>
    SPARK: <one specific thing that clicked, grounded in what was said>
    SPARK: <another one>
    FLAG: <one honest thing to watch or talk about next time — kind, never harsh>
    OPENER: <the first message to send them after this date, first person, one line, specific to the conversation>
    ASK: <one question they should ask each other next time>
    """

    static func generateRecap(
        myName: String,
        myCard: [String: String],
        theirCard: WhisperSpeedDating.WireCard?,
        transcript: String,
        meetingTitle: String
    ) async -> WhisperSpeedDating.Verdict? {
        var blocks: [String] = []
        if !myCard.isEmpty {
            blocks.append(WhisperSpeedDating.contextBlock(label: "MY DATING CARD (@\(myName))", answers: myCard))
        }
        if let theirCard {
            blocks.append(WhisperSpeedDating.contextBlock(label: "@\(theirCard.username)'S DATING CARD", answers: theirCard.answers))
        }
        let tail = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            blocks.append("WHAT THEY SAID ON THE DATE:\n\(String(tail.suffix(2400)))")
        }
        guard !blocks.isEmpty else { return nil }
        let reply = await WhisperMeetingCompanion.meetingAnswer(
            question: recapPrompt,
            meetingTitle: meetingTitle,
            participants: [myName, theirCard?.username].compactMap { $0 },
            preferredMode: WhisperEmberCoachMode.load(),
            extraContext: blocks.joined(separator: "\n\n")
        )
        guard let reply else { return nil }
        return WhisperSpeedDating.parseVerdict(from: reply.text, byName: myName)
    }

    // ─── The service (RPCs — degrade honestly until the migration runs) ──

    nonisolated struct QueueResult: Decodable, Sendable {
        let status: String
        let room_code: String?
        let partner_id: String?
        let partner_username: String?
        let role: String?
        let waiting: Int?

        var isPaired: Bool { status == "paired" && !(room_code ?? "").isEmpty }
    }

    nonisolated private struct AnswerParam: Encodable, Sendable {
        let prompt: String
        let answer: String
    }

    nonisolated private struct JoinParams: Encodable, Sendable {
        let p_username: String
        let p_answers: [AnswerParam]
    }

    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Joins (or refreshes) the queue and tries to pair right now.
    static func joinQueue(username: String) async throws -> QueueResult {
        let answers = WhisperDatingAnswers.all().prefix(12).map { AnswerParam(prompt: $0.prompt, answer: $0.answer) }
        return try await client
            .rpc("whisper_blind_date_join", params: JoinParams(p_username: username, p_answers: Array(answers)))
            .execute()
            .value
    }

    /// Heartbeat + re-check (the waiting side also searches).
    static func pollQueue() async throws -> QueueResult {
        try await client.rpc("whisper_blind_date_poll").execute().value
    }

    static func leaveQueue() async {
        _ = try? await client.rpc("whisper_blind_date_leave").execute()
    }

    /// People waiting right now — the header's live dot. 0 until migrated.
    static func queueCount() async -> Int {
        let n: Int? = try? await client.rpc("whisper_blind_queue_count").execute().value
        return n ?? 0
    }

    nonisolated private struct OpenParams: Encodable, Sendable {
        let p_room_code: String
        let p_source: String
    }

    /// Opens/claims the date record for a room (host first, guest second).
    /// `source` is "queue" for paired dates, "invite" for link dates.
    static func openRecord(roomCode: String, source: String = "invite") async {
        _ = try? await client
            .rpc("whisper_blind_date_open", params: OpenParams(p_room_code: roomCode, p_source: source))
            .execute()
    }

    nonisolated struct DecisionResult: Decodable, Sendable {
        let mine: String?
        let theirs: String?
        let mutual: Bool?
    }

    nonisolated private struct DecideParams: Encodable, Sendable {
        let p_room_code: String
        let p_decision: String
    }

    /// Records my decision — the partner's only comes back once both are in.
    /// nil when the table isn't migrated (callers fall back to the DM wire).
    static func decide(roomCode: String, decision: Decision) async -> DecisionResult? {
        try? await client
            .rpc("whisper_blind_date_decide", params: DecideParams(p_room_code: roomCode, p_decision: decision.rawValue))
            .execute()
            .value
    }

    nonisolated private struct RecapParam: Encodable, Sendable {
        let score: Int
        let verdict: String
        let sparks: [String]
        let flag: String?
        let opener: String?
        let askNext: String
        let byName: String
    }

    nonisolated private struct FinishParams: Encodable, Sendable {
        let p_room_code: String
        let p_revealed: Bool
        let p_recap: RecapParam?
    }

    /// Stamps the end + stores Jasper's recap on the record.
    static func finish(roomCode: String, revealed: Bool, recap: WhisperSpeedDating.Verdict?) async {
        let param = recap.map {
            RecapParam(score: $0.score, verdict: $0.verdict, sparks: $0.sparks, flag: $0.flag,
                       opener: $0.opener, askNext: $0.askNext, byName: $0.byName)
        }
        _ = try? await client
            .rpc("whisper_blind_date_finish", params: FinishParams(p_room_code: roomCode, p_revealed: revealed, p_recap: param))
            .execute()
    }

    nonisolated struct HistoryRow: Decodable, Sendable, Identifiable {
        let room_code: String
        let source: String?
        let started_at: String?
        let ended_at: String?
        let revealed: Bool?
        let partner_id: String?
        let partner_username: String?
        let my_decision: String?
        let their_decision: String?
        let mutual: Bool?
        var id: String { room_code }

        var outcomeLabel: String {
            if mutual == true { return "Matched 💘" }
            switch my_decision {
            case "again": return their_decision == nil ? "You said yes 💘" : "Not mutual"
            case "friends": return "Friends 🤝"
            case "pass": return "Passed 👋"
            default: return "Undecided"
            }
        }
    }

    /// My past dates, newest first (empty until migrated).
    static func history() async -> [HistoryRow] {
        let rows: [HistoryRow]? = try? await client.rpc("whisper_blind_date_history").execute().value
        return rows ?? []
    }

    /// Room code → the room id both apps hash to (same as the meeting rails).
    static func roomID(forCode code: String) -> String {
        WhisperMeetingService.meetingID(fromCode: code)
    }

    static func mintCode() -> String {
        let hex = "0123456789abcdef"
        let chunk: () -> String = { String((0..<4).map { _ in hex.randomElement() ?? "0" }) }
        return "wsp-\(chunk())-\(chunk())"
    }
}

/// The in-room date session — one shared clock both sides converge on
/// (earliest start wins, longest duration wins), the curtain/reveal state,
/// mutual extensions, and Jasper's prompt deck. Owned by the meeting room;
/// the stage view renders it.
@Observable
final class WhisperBlindDateSession {
    var myReady: Bool = false
    var theirReady: Bool = false
    var startedAt: Date? = nil
    var durationSec: Int = WhisperBlindDate.durationSec
    var revealAtSec: Int = WhisperBlindDate.revealAtSec
    var extensions: Int = 0
    var revealed: Bool = false
    var myRevealTapped: Bool = false
    var theirRevealTapped: Bool = false
    /// Extension rounds requested (1-based); a round completes when both hit it.
    var myExtendRound: Int = 0
    var theirExtendRound: Int = 0
    var deck: [WhisperBlindDate.Prompt] = []
    /// ms stamp of the adopted deck — the earliest deck on the wire wins.
    var deckAt: Double = 0
    var promptIndex: Int = 0
    var partnerLeft: Bool = false
    var timeUp: Bool = false
    var partnerUserID: String = ""
    var partnerName: String = ""
    var roomCode: String = ""

    var isRunning: Bool { startedAt != nil && !timeUp }
    var elapsed: TimeInterval { startedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0 }
    var remaining: TimeInterval { max(0, Double(durationSec) - elapsed) }
    var untilReveal: TimeInterval { max(0, Double(revealAtSec) - elapsed) }
    var isLastCall: Bool { startedAt != nil && remaining > 0 && remaining <= 45 }
    var canExtend: Bool {
        startedAt != nil && !timeUp && remaining <= 90 && extensions < WhisperBlindDate.maxExtensions
    }
    var currentPrompt: WhisperBlindDate.Prompt? {
        guard !deck.isEmpty else { return nil }
        return deck[min(max(0, promptIndex), deck.count - 1)]
    }
    /// The stage the clock is in — nudges the deck forward.
    var clockStage: WhisperBlindDate.Stage {
        let third = Double(durationSec) / 3.0
        if elapsed < third { return .warm }
        if elapsed < third * 2 { return .deeper }
        return .spark
    }

    func start() {
        guard startedAt == nil else { return }
        startedAt = Date()
    }

    func statePayload() -> [String: Any] {
        [
            "startedAt": (startedAt ?? Date()).timeIntervalSince1970 * 1000,
            "durationSec": durationSec,
            "revealAtSec": revealAtSec,
            "extensions": extensions,
            "revealed": revealed
        ]
    }

    /// Converges on the shared clock — the EARLIEST start wins, the longest
    /// duration/most extensions win, a reveal anywhere reveals everywhere.
    func adoptState(_ data: [String: Any]) {
        if let ms = data["startedAt"] as? Double, ms > 0 {
            let incoming = Date(timeIntervalSince1970: ms / 1000)
            if let mine = startedAt {
                if incoming < mine { startedAt = incoming }
            } else {
                startedAt = incoming
            }
        }
        if let d = data["durationSec"] as? Int { durationSec = max(durationSec, d) }
        else if let d = data["durationSec"] as? Double { durationSec = max(durationSec, Int(d)) }
        if let r = data["revealAtSec"] as? Int { revealAtSec = r }
        else if let r = data["revealAtSec"] as? Double { revealAtSec = Int(r) }
        if let e = data["extensions"] as? Int { extensions = max(extensions, e) }
        else if let e = data["extensions"] as? Double { extensions = max(extensions, Int(e)) }
        if (data["revealed"] as? Bool) == true { revealed = true }
    }

    /// Applies one completed extension round.
    func applyExtension() {
        guard extensions < WhisperBlindDate.maxExtensions else { return }
        extensions += 1
        durationSec += WhisperBlindDate.extensionSec
    }

    /// Adopts a deck off the wire — the earliest-stamped deck wins so both
    /// sides read the same prompts even if both generated.
    func adoptDeck(lines: [String], at stamp: Double) {
        let incoming = WhisperBlindDate.decodeDeck(lines)
        guard !incoming.isEmpty else { return }
        if deck.isEmpty || (stamp > 0 && (deckAt == 0 || stamp < deckAt)) {
            deck = incoming
            deckAt = stamp
            promptIndex = min(promptIndex, deck.count - 1)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
