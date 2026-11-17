import SwiftUI

/// Speed dating — the saved dating card (what I'm looking for, interests,
/// non-negotiables…), the wire it rides in meetings, the compatibility
/// verdict, and the dating-inbox contact registry. Mirrors web
/// `lib/datingCards.ts` + `lib/datingInbox.ts` exactly (same question ids,
/// same wire shape), so cards and verdicts flow web ↔ iOS.
enum WhisperSpeedDating {
    struct Question: Identifiable {
        let id: String
        let label: String
        let placeholder: String
    }

    /// The five saved prompts — identical ids/labels on web.
    static let questions: [Question] = [
        .init(id: "looking", label: "What are you looking for?", placeholder: "Something real, something casual, new people…"),
        .init(id: "interests", label: "Your interests & passions", placeholder: "Lifting, cooking, live music, trail runs…"),
        .init(id: "dealbreakers", label: "Non-negotiables", placeholder: "Kindness, ambition, no smokers…"),
        .init(id: "firstDate", label: "Your ideal first date", placeholder: "Coffee and a long walk, tacos, climbing…"),
        .init(id: "funFact", label: "A fun fact about you", placeholder: "I've been to 14 countries…")
    ]

    private static var cardKey: String {
        "whisper-dating-card:\(AccountStorage.currentUserID.lowercased())"
    }

    /// My saved answers — device-local; the wire carries them into meetings.
    static func loadCard() -> [String: String] {
        let raw = (UserDefaults.standard.dictionary(forKey: cardKey) as? [String: String]) ?? [:]
        var clean: [String: String] = [:]
        for q in questions {
            if let v = raw[q.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                clean[q.id] = String(v.prefix(240))
            }
        }
        return clean
    }

    static func saveCard(_ answers: [String: String]) {
        var clean: [String: String] = [:]
        for q in questions {
            if let v = answers[q.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                clean[q.id] = String(v.prefix(240))
            }
        }
        UserDefaults.standard.set(clean, forKey: cardKey)
    }

    static var hasCard: Bool { !loadCard().isEmpty }

    /// Room ids primed for speed-date mode by "Start a speed date" — the
    /// meeting room checks this on appear and lights up + broadcasts.
    static var pendingRooms: Set<String> = []

    /// Rooms KNOWN to be blind dates before joining — an ?sd=1 invite link
    /// opened on this device. Drives the rose pre-join lobby (never the
    /// generic meeting lobby); `pendingRooms` is the stricter "I already
    /// said I'm ready" set.
    static var knownRooms: Set<String> = []

    static func markKnownRoom(_ roomID: String) {
        knownRooms.insert(roomID.lowercased())
    }

    /// My card as a wire payload (flat keys — identical to web). Always
    /// non-nil in a dating room: an EMPTY card still announces me so the
    /// other side lights up speed-date mode (answers just read "no card").
    static func myWirePayload(userId: String, username: String) -> [String: Any]? {
        let card = loadCard()
        var payload: [String: Any] = ["userId": userId, "username": username]
        for (key, value) in card { payload[key] = value }
        return payload
    }

    /// One participant's card as it rides the meeting wire.
    struct WireCard: Identifiable {
        let userId: String
        let username: String
        let answers: [String: String]
        var id: String { userId }

        static func decode(_ data: [String: Any]) -> WireCard? {
            guard let uid = data["userId"] as? String, !uid.isEmpty else { return nil }
            let name = (data["username"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "someone"
            var answers: [String: String] = [:]
            for q in questions {
                if let v = data[q.id] as? String, !v.isEmpty { answers[q.id] = String(v.prefix(240)) }
            }
            return WireCard(userId: uid, username: name, answers: answers)
        }
    }

    /// Labeled context block for the judge prompt.
    static func contextBlock(label: String, answers: [String: String]) -> String {
        let lines = questions.compactMap { q -> String? in
            guard let v = answers[q.id], !v.isEmpty else { return nil }
            return "- \(q.label) \(v)"
        }
        return lines.isEmpty ? "\(label): (no card shared)" : "\(label):\n\(lines.joined(separator: "\n"))"
    }

    /// The strict-format ask both apps send the judge (context rides along).
    static let judgePrompt = """
    You are judging a SPEED DATE. Using ONLY the dating cards and the call transcript in your context, judge the romantic compatibility of the people on this call. Be warm, honest, specific — never invent details. Reply in EXACTLY this format with no extra prose:
    SCORE: <0-100>
    VERDICT: <one honest line on the match>
    SPARK: <one specific thing that clicks between them>
    SPARK: <another one>
    ASK: <one question they should ask each other next>
    """

    /// The verdict both sides see after Jasper judges the match — grown
    /// into the blind-date RECAP with an honest flag + a ready-to-send opener.
    struct Verdict {
        let score: Int
        let verdict: String
        let sparks: [String]
        let askNext: String
        let byName: String
        var flag: String? = nil
        var opener: String? = nil

        func encode() -> [String: Any] {
            var out: [String: Any] = [
                "score": score,
                "verdict": verdict,
                "sparks": sparks.joined(separator: "\n"),
                "askNext": askNext,
                "byName": byName
            ]
            if let flag { out["flag"] = flag }
            if let opener { out["opener"] = opener }
            return out
        }

        static func decode(_ data: [String: Any]) -> Verdict? {
            let score: Int
            if let v = data["score"] as? Int {
                score = v
            } else if let v = data["score"] as? Double {
                score = Int(v.rounded())
            } else {
                return nil
            }
            let sparksRaw = (data["sparks"] as? String) ?? ""
            return Verdict(
                score: max(0, min(100, score)),
                verdict: (data["verdict"] as? String) ?? "",
                sparks: sparksRaw.components(separatedBy: "\n").filter { !$0.isEmpty },
                askNext: (data["askNext"] as? String) ?? "",
                byName: (data["byName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "someone",
                flag: (data["flag"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                opener: (data["opener"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    /// Parses Jasper's SCORE/VERDICT/SPARK/ASK reply — defensive fallbacks
    /// so a loosely formatted reply still lands. Mirrors web exactly.
    static func parseVerdict(from text: String, byName: String) -> Verdict? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        func firstMatch(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: trimmed) else { return nil }
            return String(trimmed[range]).trimmingCharacters(in: .whitespaces)
        }
        guard let scoreText = firstMatch("SCORE:\\s*(\\d{1,3})") ?? firstMatch("\\b(\\d{1,3})\\s*%"),
              let scoreValue = Int(scoreText) else { return nil }
        var sparks: [String] = []
        if let regex = try? NSRegularExpression(pattern: "SPARK:\\s*(.+)", options: [.caseInsensitive]) {
            let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            for match in matches.prefix(3) {
                if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: trimmed) {
                    let spark = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                    if !spark.isEmpty { sparks.append(spark) }
                }
            }
        }
        return Verdict(
            score: max(0, min(100, scoreValue)),
            verdict: firstMatch("VERDICT:\\s*(.+)") ?? "A promising match — keep talking.",
            sparks: sparks,
            askNext: firstMatch("ASK:\\s*(.+)") ?? "",
            byName: byName,
            flag: firstMatch("FLAG:\\s*(.+)"),
            opener: firstMatch("OPENER:\\s*(.+)")
        )
    }
}

/// Private icebreaker answers — saved when you ANSWER, never posted.
/// They quietly tune the For-you match sort; sharing to the hub is a
/// separate explicit choice. Mirrors web `lib/datingAnswers.ts` exactly
/// (same storage shape) so the answering grammar matches across apps.
enum WhisperDatingAnswers {
    struct Entry: Identifiable {
        let prompt: String
        let answer: String
        let at: Date
        var id: String { prompt }
    }

    private static var key: String {
        "whisper-dating-answers:\(AccountStorage.currentUserID.lowercased())"
    }

    /// Every saved answer, newest first.
    static func all() -> [Entry] {
        let raw = (UserDefaults.standard.array(forKey: key) as? [[String: Any]]) ?? []
        return raw.compactMap { dict -> Entry? in
            guard let prompt = dict["prompt"] as? String, !prompt.isEmpty,
                  let answer = dict["answer"] as? String, !answer.isEmpty else { return nil }
            let at = (dict["at"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            return Entry(prompt: prompt, answer: answer, at: at)
        }
        .sorted { $0.at > $1.at }
    }

    static func answer(for prompt: String) -> String? {
        all().first { $0.prompt.caseInsensitiveCompare(prompt) == .orderedSame }?.answer
    }

    /// Upserts by prompt (newest first), capped at 24 entries.
    static func save(prompt: String, answer: String) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entries = all().filter { $0.prompt.caseInsensitiveCompare(prompt) != .orderedSame }
        entries.insert(Entry(prompt: prompt, answer: String(trimmed.prefix(280)), at: Date()), at: 0)
        let capped: [[String: Any]] = entries.prefix(24).map { entry in
            ["prompt": entry.prompt, "answer": entry.answer, "at": entry.at.timeIntervalSince1970]
        }
        UserDefaults.standard.set(capped, forKey: key)
    }
}

/// The mutual-match wire — 💘 requests and the matched token ride DM
/// bodies, so matches flow web ↔ iOS on the existing message rails
/// (and the push fanout carries the notification for free). Mirrors web
/// `lib/datingMatch.ts` exactly.
enum WhisperMatchWire {
    static let requestPrefix = "::whisper-matchreq-v1::"
    static let matchedPrefix = "::whisper-matched-v1::"

    struct Token {
        let isMatched: Bool
        let fromUserID: String
        let name: String
    }

    static func requestBody(from userID: String, name: String) -> String {
        requestPrefix + encode(["from": userID, "name": name])
    }

    static func matchedBody(from userID: String, name: String) -> String {
        matchedPrefix + encode(["from": userID, "name": name])
    }

    static func decode(_ body: String) -> Token? {
        let isMatched: Bool
        let payload: String
        if body.hasPrefix(requestPrefix) {
            isMatched = false
            payload = String(body.dropFirst(requestPrefix.count))
        } else if body.hasPrefix(matchedPrefix) {
            isMatched = true
            payload = String(body.dropFirst(matchedPrefix.count))
        } else {
            return nil
        }
        guard let data = payload.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let from = dict["from"] as? String, UUID(uuidString: from) != nil else { return nil }
        let name = (dict["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "someone"
        return Token(isMatched: isMatched, fromUserID: from, name: name)
    }

    private static func encode(_ dict: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// One celebration per thread — remembers the match already shown.
    static func celebrationSeen(threadWith otherUserID: String) -> Bool {
        UserDefaults.standard.bool(forKey: seenKey(otherUserID))
    }

    static func markCelebrationSeen(threadWith otherUserID: String) {
        UserDefaults.standard.set(true, forKey: seenKey(otherUserID))
    }

    private static func seenKey(_ otherUserID: String) -> String {
        "whisper-match-seen:\(AccountStorage.currentUserID.lowercased()):\(otherUserID.lowercased())"
    }
}

/// Device-local registry of dating chats — powers the 💘 inbox filter and
/// cupid Jasper's date tools in DM threads. Peers land here automatically
/// when you say hi from the Dating hub. Mirrors web `lib/datingInbox.ts`.
enum WhisperDatingContacts {
    private static var key: String {
        "whisper-dating-peers:\(AccountStorage.currentUserID.lowercased())"
    }

    static func all() -> Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).map { $0.lowercased() })
    }

    static func isDating(_ userID: String) -> Bool {
        all().contains(userID.lowercased())
    }

    static func mark(_ userID: String) {
        let id = userID.lowercased()
        guard !id.isEmpty, id != AccountStorage.currentUserID.lowercased() else { return }
        var set = all()
        guard !set.contains(id) else { return }
        set.insert(id)
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    /// Flips a chat in/out of the dating inbox; returns the NEW state.
    @discardableResult
    static func toggle(_ userID: String) -> Bool {
        let id = userID.lowercased()
        var set = all()
        let next = !set.contains(id)
        if next { set.insert(id) } else { set.remove(id) }
        UserDefaults.standard.set(Array(set), forKey: key)
        return next
    }
}

/// The dating card editor — five rose-labeled prompts saved device-local
/// and broadcast into every speed date. Mirrors web `DatingCardEditor`.
struct WhisperDatingCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var answers: [String: String] = [:]
    @State private var originalAnswers: [String: String] = [:]
    @State private var showsDiscard: Bool = false
    @State private var ownerGeneration: UUID = AccountStorage.generation
    @State private var isClosed: Bool = false
    private var completedCount: Int { WhisperSpeedDating.questions.filter { !(answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }

    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            WhisperJasperInteractiveMascot(size: 48, dating: true)
                            Text("A few things that make you, you. Jasper uses your answers to find conversation starters for your dates.")
                                .font(.subheadline)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(completedCount) of \(WhisperSpeedDating.questions.count) answered")
                                .font(.caption.weight(.semibold)).foregroundStyle(rose)
                            ProgressView(value: Double(completedCount), total: Double(WhisperSpeedDating.questions.count)).tint(rose)
                        }.padding(.vertical, 8)
                        ForEach(WhisperSpeedDating.questions) { q in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(q.label)
                                    .font(.headline)
                                    .foregroundStyle(rose)
                                TextField(q.placeholder, text: Binding(
                                    get: { answers[q.id] ?? "" },
                                    set: { answers[q.id] = $0 }
                                ), axis: .vertical)
                                .lineLimit(2...4)
                                .font(.body)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(rose.opacity(0.16), lineWidth: 1)
                                }
                            }
                        }
                        Button {
                            Haptics.tap()
                            guard !isClosed, ownerGeneration == AccountStorage.generation else { return }
                            WhisperSpeedDating.saveCard(answers)
                            isClosed = true
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Save my card")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(rose))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Your dating card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        if answers != originalAnswers { showsDiscard = true }
                        else { isClosed = true; dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(answers != originalAnswers)
        .confirmationDialog("Discard card changes?", isPresented: $showsDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { isClosed = true; dismiss() }
            Button("Keep editing", role: .cancel) { }
        }
        .onAppear { answers = WhisperSpeedDating.loadCard(); originalAnswers = answers }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            isClosed = true; answers = [:]; dismiss()
        }
    }
}
