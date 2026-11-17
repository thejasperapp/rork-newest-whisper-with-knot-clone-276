import Foundation
import SwiftUI

// MARK: - Action model

/// One executable action Jasper attaches to a reply via a fenced ```actions
/// block. Lenient decoding: numbers may arrive as strings and vice versa —
/// the parser never rejects an action over a formatting quirk.
nonisolated struct WhisperEmberAction: Codable, Sendable, Hashable, Identifiable {
    nonisolated enum Kind: String, Codable, Sendable {
        case open, call, message, schedule, plan, post, follow, bioage, dietplan, groceries,
             clientdashboard, marketplace, recipe, water
    }

    let kind: Kind
    // open
    var route: String?
    var arg: String?
    // call / message
    var username: String?
    var mode: String?
    var text: String?
    // schedule
    var title: String?
    var whenISO: String?
    var invite: String?
    // plan
    var client: String?
    var focus: String?
    var weeks: Int?
    var sessionsPerWeek: Int?
    var summary: String?
    var days: [PlanDay]?
    // post
    var community: String?
    // recipe (title = name, summary = note)
    var emoji: String?
    var servings: Int?
    var prepTime: String?
    var cookTime: String?
    var steps: [String]?
    var ingredients: [RecipeIngredient]?
    // presentation
    var label: String?
    var auto: Bool?

    nonisolated var id: Int { hashValue }

    nonisolated struct PlanDay: Codable, Sendable, Hashable {
        var name: String
        var focus: String?
        var exercises: [PlanExercise]?

        init(name: String, focus: String? = nil, exercises: [PlanExercise]? = nil) {
            self.name = name
            self.focus = focus
            self.exercises = exercises
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.name = c.flexString(.name) ?? "Day"
            self.focus = c.flexString(.focus)
            self.exercises = try? c.decodeIfPresent([PlanExercise].self, forKey: .exercises)
        }

        enum CodingKeys: String, CodingKey { case name, focus, exercises }
    }

    nonisolated struct PlanExercise: Codable, Sendable, Hashable {
        var name: String
        var sets: Int?
        var reps: String?
        var restSeconds: Int?

        init(name: String, sets: Int? = nil, reps: String? = nil, restSeconds: Int? = nil) {
            self.name = name
            self.sets = sets
            self.reps = reps
            self.restSeconds = restSeconds
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.name = c.flexString(.name) ?? "Exercise"
            self.sets = c.flexInt(.sets)
            self.reps = c.flexString(.reps)
            self.restSeconds = c.flexInt(.restSeconds)
        }

        enum CodingKeys: String, CodingKey { case name, sets, reps, restSeconds }
    }

    /// One recipe ingredient — macros describe ONE serving of the ingredient;
    /// numberOfServings is how much the whole recipe uses (POST /v1/recipes).
    nonisolated struct RecipeIngredient: Codable, Sendable, Hashable {
        var name: String
        var calories: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        var servingUnit: String?
        var numberOfServings: Double?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.name = c.flexString(.name) ?? "Ingredient"
            self.calories = c.flexDouble(.calories)
            self.protein = c.flexDouble(.protein)
            self.carbs = c.flexDouble(.carbs)
            self.fat = c.flexDouble(.fat)
            self.servingUnit = c.flexString(.servingUnit)
            self.numberOfServings = c.flexDouble(.numberOfServings)
        }

        enum CodingKeys: String, CodingKey {
            case name, calories, protein, carbs, fat, servingUnit, numberOfServings
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Normalize "diet_plan" / "diet-plan" style kinds before matching.
        let rawKind = (c.flexString(.kind) ?? "open").lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        self.kind = Kind(rawValue: rawKind) ?? .open
        self.route = c.flexString(.route)
        self.arg = c.flexString(.arg)
        self.username = c.flexString(.username)
        self.mode = c.flexString(.mode)
        self.text = c.flexString(.text)
        self.title = c.flexString(.title)
        self.whenISO = c.flexString(.whenISO) ?? c.flexString(.when)
        self.invite = c.flexString(.invite)
        self.client = c.flexString(.client)
        self.focus = c.flexString(.focus)
        self.weeks = c.flexInt(.weeks)
        self.sessionsPerWeek = c.flexInt(.sessionsPerWeek)
        self.summary = c.flexString(.summary)
        self.days = try? c.decodeIfPresent([PlanDay].self, forKey: .days)
        self.community = c.flexString(.community) ?? c.flexString(.topic)
        self.emoji = c.flexString(.emoji)
        self.servings = c.flexInt(.servings)
        self.prepTime = c.flexString(.prepTime)
        self.cookTime = c.flexString(.cookTime)
        self.steps = try? c.decodeIfPresent([String].self, forKey: .steps)
        self.ingredients = try? c.decodeIfPresent([RecipeIngredient].self, forKey: .ingredients)
        self.label = c.flexString(.label)
        self.auto = c.flexBool(.auto)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(route, forKey: .route)
        try c.encodeIfPresent(arg, forKey: .arg)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(whenISO, forKey: .whenISO)
        try c.encodeIfPresent(invite, forKey: .invite)
        try c.encodeIfPresent(client, forKey: .client)
        try c.encodeIfPresent(focus, forKey: .focus)
        try c.encodeIfPresent(weeks, forKey: .weeks)
        try c.encodeIfPresent(sessionsPerWeek, forKey: .sessionsPerWeek)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(days, forKey: .days)
        try c.encodeIfPresent(community, forKey: .community)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encodeIfPresent(servings, forKey: .servings)
        try c.encodeIfPresent(prepTime, forKey: .prepTime)
        try c.encodeIfPresent(cookTime, forKey: .cookTime)
        try c.encodeIfPresent(steps, forKey: .steps)
        try c.encodeIfPresent(ingredients, forKey: .ingredients)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(auto, forKey: .auto)
    }

    enum CodingKeys: String, CodingKey {
        case kind, route, arg, username, mode, text, title, whenISO, when,
             invite, client, focus, weeks, sessionsPerWeek, summary, days,
             community, topic, emoji, servings, prepTime, cookTime, steps,
             ingredients, label, auto
    }

    // MARK: Presentation

    /// Button label — Jasper's own label, or a sensible default per kind.
    var displayLabel: String {
        if let label, !label.isEmpty { return label }
        switch kind {
        case .open:
            let route = route ?? ""
            if let entry = WhisperEmberAtlas.entries.first(where: { $0.route == route }) {
                return "Open \(entry.title)"
            }
            return "Open"
        case .call:
            let name = username.map { "@\(WhisperEmberAction.cleanUsername($0))" } ?? "them"
            return mode == "audio" ? "Call \(name)" : "Video call \(name)"
        case .message:
            let name = username.map { "@\(WhisperEmberAction.cleanUsername($0))" } ?? "them"
            return "Message \(name)"
        case .schedule: return "Schedule meeting"
        case .plan:
            let name = client.map { "@\(WhisperEmberAction.cleanUsername($0))" } ?? "client"
            return "Review \(name)'s plan"
        case .post:
            if let community, !community.isEmpty { return "Draft post in \(community)" }
            return "Open this in the composer"
        case .follow:
            let name = (username ?? client).map { "@\(WhisperEmberAction.cleanUsername($0))" } ?? "them"
            return "Follow \(name)"
        case .bioage:
            if let raw = username ?? client ?? arg, !raw.isEmpty {
                return "@\(WhisperEmberAction.cleanUsername(raw))'s biological age"
            }
            return "View my biological age"
        case .dietplan:
            if let raw = username ?? client ?? arg, !raw.isEmpty {
                return "@\(WhisperEmberAction.cleanUsername(raw))'s diet plan"
            }
            return "View my diet plan"
        case .groceries:
            if let raw = username ?? client ?? arg, !raw.isEmpty {
                return "@\(WhisperEmberAction.cleanUsername(raw))'s grocery list"
            }
            return "My grocery list"
        case .clientdashboard:
            if let raw = username ?? client ?? arg, !raw.isEmpty {
                return "@\(WhisperEmberAction.cleanUsername(raw))'s live dashboard"
            }
            return "Client live dashboard"
        case .marketplace:
            if let query = arg ?? text, !query.isEmpty { return "Marketplace: \(query)" }
            return "Browse the plan marketplace"
        case .recipe:
            if let title, !title.isEmpty { return "Save \"\(title)\" to Jasper" }
            return "Save recipe to Jasper"
        case .water:
            return "Log water — Jasper's cup"
        }
    }

    var iconName: String {
        switch kind {
        case .open: return "arrow.up.right"
        case .call: return mode == "audio" ? "phone.fill" : "video.fill"
        case .message: return "paperplane.fill"
        case .schedule: return "calendar.badge.plus"
        case .plan: return "list.clipboard.fill"
        case .post: return "square.and.pencil"
        case .follow: return "person.crop.circle.badge.plus"
        case .bioage: return "waveform.path.ecg"
        case .dietplan: return "fork.knife"
        case .groceries: return "cart.fill"
        case .clientdashboard: return "square.grid.2x2.fill"
        case .marketplace: return "storefront.fill"
        case .recipe: return "book.closed.fill"
        case .water: return "drop.fill"
        }
    }

    /// Strips @, whitespace, and lowercases — usernames are handles.
    nonisolated static func cleanUsername(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
    }
}

// MARK: - Lenient decoding helpers

private extension KeyedDecodingContainer {
    nonisolated func flexString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) {
            return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
        }
        return nil
    }

    nonisolated func flexInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    nonisolated func flexBool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s.lowercased() == "true" }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }

    nonisolated func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

// MARK: - Parser

/// Strips fenced ```actions blocks out of an Jasper reply and decodes them.
/// Tolerates a single object or an array, `actions`/`action` fence names,
/// and never lets malformed JSON leak into the visible prose.
nonisolated enum WhisperEmberActionParser {

    static func parse(_ reply: String) -> (text: String, actions: [WhisperEmberAction]) {
        var working = reply
        var found: [WhisperEmberAction] = []

        for fence in ["```actions", "```action"] {
            while let open = working.range(of: fence, options: .caseInsensitive) {
                guard let close = working.range(of: "```", range: open.upperBound..<working.endIndex) else {
                    // Unterminated fence — drop everything from the fence on.
                    working.removeSubrange(open.lowerBound..<working.endIndex)
                    break
                }
                let inner = String(working[open.upperBound..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                working.removeSubrange(open.lowerBound..<close.upperBound)
                found.append(contentsOf: decode(inner))
            }
        }
        return (
            working.trimmingCharacters(in: .whitespacesAndNewlines),
            Array(found.prefix(4))
        )
    }

    private static func decode(_ json: String) -> [WhisperEmberAction] {
        guard let data = json.data(using: .utf8) else { return [] }
        if let arr = try? JSONDecoder().decode([WhisperEmberAction].self, from: data) { return arr }
        if let one = try? JSONDecoder().decode(WhisperEmberAction.self, from: data) { return [one] }
        return []
    }

    /// Lenient "2026-08-18T17:00" / full-ISO / "2026-08-18 17:00" date parse.
    nonisolated static func parseWhen(_ iso: String?) -> Date? {
        guard let iso = iso?.trimmingCharacters(in: .whitespacesAndNewlines), !iso.isEmpty else { return nil }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: iso) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: iso) { return d }
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = .current
            df.dateFormat = format
            if let d = df.date(from: iso) { return d }
        }
        return nil
    }
}

// MARK: - Modals

/// A self-produced Jasper modal — the pre-filled editor an action opens.
enum WhisperEmberModal: Identifiable, Hashable {
    case call(username: String, video: Bool)
    case schedule(title: String, when: Date?, invite: String?)
    case reply(username: String, text: String)
    case plan(WhisperEmberPlanDraft)
    case bioAge(username: String?)
    case dietPlan(username: String?)
    case groceries(username: String?)
    case clientDashboard(username: String?)
    case marketplace(query: String?)
    case recipeSave(JasperRecipeDraft)
    case waterTracker

    var id: String {
        switch self {
        case .call(let u, let v): return "call-\(u)-\(v)"
        case .schedule(let t, _, _): return "schedule-\(t)"
        case .reply(let u, let text): return "reply-\(u)-\(text.count)"
        case .plan(let d): return "plan-\(d.title)"
        case .bioAge(let u): return "bioage-\(u ?? "me")"
        case .dietPlan(let u): return "dietplan-\(u ?? "me")"
        case .groceries(let u): return "groceries-\(u ?? "me")"
        case .clientDashboard(let u): return "clientdash-\(u ?? "client")"
        case .marketplace(let q): return "marketplace-\(q ?? "")"
        case .recipeSave(let d): return "recipe-\(d.name)"
        case .waterTracker: return "water"
        }
    }
}

/// Pre-filled training-program draft carried into the plan modal.
struct WhisperEmberPlanDraft: Hashable {
    var client: String?
    var title: String
    var focus: String
    var weeks: Int
    var sessionsPerWeek: Int
    var summary: String
    var days: [WhisperEmberAction.PlanDay]

    init(from action: WhisperEmberAction) {
        self.client = action.client.map(WhisperEmberAction.cleanUsername)
        self.title = action.title ?? "Training plan"
        self.focus = action.focus ?? ""
        let days = action.days ?? []
        self.weeks = max(1, action.weeks ?? 4)
        self.sessionsPerWeek = max(1, action.sessionsPerWeek ?? max(days.count, 3))
        self.summary = action.summary ?? ""
        self.days = days
    }

    /// Converts the draft into a real Coach Studio program.
    @MainActor
    func toProgram() -> WhisperCoachProgram {
        let coachName = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "coach"
        return WhisperCoachProgram(
            id: UUID(),
            coachUserID: AccountStorage.currentUserID,
            coachUsername: coachName,
            title: title,
            focus: focus,
            weeks: weeks,
            sessionsPerWeek: sessionsPerWeek,
            summary: summary,
            days: days.map { day in
                WhisperProgramDay(
                    name: day.name,
                    focus: day.focus ?? "",
                    exercises: (day.exercises ?? []).map { ex in
                        WhisperProgramExercise(
                            name: ex.name,
                            sets: max(1, ex.sets ?? 3),
                            reps: ex.reps ?? "8-12",
                            restSeconds: max(15, ex.restSeconds ?? 90),
                            note: nil
                        )
                    }
                )
            },
            createdAt: Date()
        )
    }

    /// Formats the plan as a DM-ready message for the client.
    func asMessageText() -> String {
        var lines: [String] = ["Your new plan: \(title)"]
        if !focus.isEmpty { lines.append("Focus: \(focus)") }
        lines.append("\(weeks) weeks · \(sessionsPerWeek)x per week")
        if !summary.isEmpty { lines.append(summary) }
        for day in days.prefix(7) {
            var d = "\n\(day.name)"
            if let f = day.focus, !f.isEmpty { d += " — \(f)" }
            lines.append(d)
            for ex in (day.exercises ?? []).prefix(8) {
                var e = "• \(ex.name)"
                if let sets = ex.sets { e += " \(sets)x\(ex.reps ?? "8-12")" }
                lines.append(e)
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Router

/// Executes Jasper actions against real Whisper services and owns the
/// self-produced modal state. One shared instance drives every Jasper surface
/// (full chat, meeting box) so modals and navigation behave identically.
@MainActor
@Observable
final class WhisperEmberActionRouter {
    static let shared = WhisperEmberActionRouter()
    private init() {}

    /// The currently presented Jasper modal (overlay-based, works inside any
    /// presented sheet or cover).
    var modal: WhisperEmberModal?

    /// Draft text the composer picks up on its next appearance.
    var pendingComposerDraft: String?
    /// Community/topic the composer assigns the drafted post to.
    var pendingComposerTopic: String?
    /// Question handed to full-screen Jasper Intelligence (for example from the
    /// Meeting Sidekick). It only prefills the composer; the user still sends it.
    var pendingJasperPrompt: String?
    /// Question handed to the Meeting Sidekick (for example from Jasper
    /// Intelligence's meeting_sidekick route). Prefill only; scope approval still applies.
    var pendingSidekickQuestion: String?

    // MARK: Perform

    func perform(_ action: WhisperEmberAction) {
        switch action.kind {
        case .open:
            navigate(route: action.route, arg: action.arg ?? action.username)
        case .call:
            guard let raw = action.username else { return }
            modal = .call(
                username: WhisperEmberAction.cleanUsername(raw),
                video: action.mode?.lowercased() != "audio"
            )
        case .message:
            guard let raw = action.username ?? action.client else { return }
            modal = .reply(
                username: WhisperEmberAction.cleanUsername(raw),
                text: action.text ?? ""
            )
        case .schedule:
            modal = .schedule(
                title: action.title ?? "Meeting",
                when: WhisperEmberActionParser.parseWhen(action.whenISO),
                invite: action.invite.map(WhisperEmberAction.cleanUsername)
            )
        case .plan:
            modal = .plan(WhisperEmberPlanDraft(from: action))
        case .post:
            // The REAL composer, pre-filled — a 1:1 of the actual post box
            // (attachments, thread parts, ghost toggle, community topic).
            openComposer(draft: action.text ?? "", community: action.community)
        case .follow:
            guard let raw = action.username ?? action.client else { return }
            Task { _ = await followUser(raw) }
        case .bioage:
            let target = (action.username ?? action.client ?? action.arg)
                .map(WhisperEmberAction.cleanUsername)
                .flatMap { $0.isEmpty ? nil : $0 }
            modal = .bioAge(username: target)
        case .dietplan:
            let target = (action.username ?? action.client ?? action.arg)
                .map(WhisperEmberAction.cleanUsername)
                .flatMap { $0.isEmpty ? nil : $0 }
            modal = .dietPlan(username: target)
        case .groceries:
            let target = (action.username ?? action.client ?? action.arg)
                .map(WhisperEmberAction.cleanUsername)
                .flatMap { $0.isEmpty ? nil : $0 }
            modal = .groceries(username: target)
        case .clientdashboard:
            let target = (action.username ?? action.client ?? action.arg)
                .map(WhisperEmberAction.cleanUsername)
                .flatMap { $0.isEmpty ? nil : $0 }
            modal = .clientDashboard(username: target)
        case .marketplace:
            let query = (action.arg ?? action.text)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            modal = .marketplace(query: (query?.isEmpty ?? true) ? nil : query)
        case .recipe:
            // Jasper drafts the complete recipe in the action — open the
            // save-ready composer (one POST lands it in Jasper's Recipes).
            func text(_ value: Double?) -> String {
                guard let value else { return "" }
                return value == value.rounded() ? String(Int(value)) : String(value)
            }
            var draft = JasperRecipeDraft()
            draft.name = action.title ?? "Recipe"
            draft.emoji = action.emoji ?? ""
            draft.servings = max(1, action.servings ?? 2)
            draft.prepTime = action.prepTime ?? ""
            draft.cookTime = action.cookTime ?? ""
            draft.note = action.summary ?? ""
            draft.steps = action.steps ?? []
            let mapped = (action.ingredients ?? []).map { ing in
                JasperRecipeDraft.Ingredient(
                    name: ing.name,
                    calories: text(ing.calories),
                    protein: text(ing.protein),
                    carbs: text(ing.carbs),
                    fat: text(ing.fat),
                    servingUnit: ing.servingUnit ?? "serving",
                    numberOfServings: text(ing.numberOfServings ?? 1))
            }
            draft.ingredients = mapped.isEmpty ? [JasperRecipeDraft.Ingredient()] : mapped
            modal = .recipeSave(draft)
        case .water:
            modal = .waterTracker
        }
    }

    /// Jasper self-produces a modal when it marked an action `auto` — only
    /// editor-style actions qualify (never calls or navigation).
    func autoPresent(from actions: [WhisperEmberAction]) {
        guard modal == nil else { return }
        guard let auto = actions.first(where: {
            ($0.auto ?? false) && $0.kind != .call && $0.kind != .open && $0.kind != .follow
        }) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard modal == nil else { return }
            Haptics.tap()
            perform(auto)
        }
    }

    func dismissModal() {
        modal = nil
    }

    /// Resolves an optional handle to an accepted coaching client (uid +
    /// username). Nil means "the user's own Jasper" — either no handle was
    /// given or the handle isn't on the coach roster.
    static func jasperClient(for username: String?) -> (uid: String, username: String)? {
        guard let username, !username.isEmpty else { return nil }
        let clean = WhisperEmberAction.cleanUsername(username)
        guard !clean.isEmpty,
              let row = WhisperCoachRequestService.shared.myClients.first(where: {
                  $0.client_username.lowercased() == clean
              }) else { return nil }
        return (row.client_user_id, row.client_username)
    }

    // MARK: Navigation

    /// Routes anywhere in the app: dismisses any Jasper chat sheet first, then
    /// hands the route to `WhisperRootView`.
    func navigate(route: String?, arg: String? = nil) {
        guard let route = route?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !route.isEmpty else { return }
        NotificationCenter.default.post(name: .whisperEmberDismissChat, object: nil)
        let cleanArg = arg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            NotificationCenter.default.post(
                name: .whisperEmberNavigate,
                object: nil,
                userInfo: ["route": route, "arg": cleanArg]
            )
        }
    }

    /// Opens the REAL composer pre-filled with Jasper's draft (and community).
    func openComposer(draft: String, community: String? = nil) {
        pendingComposerDraft = draft
        pendingComposerTopic = community?.trimmingCharacters(in: .whitespacesAndNewlines)
        navigate(route: "composer")
    }

    /// One-shot read of the pending composer draft.
    func consumeComposerDraft() -> String? {
        defer { pendingComposerDraft = nil }
        return pendingComposerDraft
    }

    /// One-shot read of the pending community/topic assignment.
    func consumeComposerTopic() -> String? {
        defer { pendingComposerTopic = nil }
        return pendingComposerTopic
    }

    /// One-shot read of the question handed to Jasper Intelligence.
    func consumeJasperPrompt() -> String? {
        defer { pendingJasperPrompt = nil }
        return pendingJasperPrompt
    }

    /// One-shot read of the question handed to the Meeting Sidekick.
    func consumeSidekickQuestion() -> String? {
        defer { pendingSidekickQuestion = nil }
        return pendingSidekickQuestion
    }

    // MARK: Executors

    /// Resolves a handle to a real user — checks the coach's client roster
    /// first (they may not be publicly searchable), then the user directory.
    func resolveUser(_ username: String) async -> WhisperUserRow? {
        let clean = WhisperEmberAction.cleanUsername(username)
        guard !clean.isEmpty else { return nil }
        if let row = await WhisperUserService.shared.fetchByUsername(clean) {
            return row
        }
        if let client = WhisperCoachRequestService.shared.myClients.first(where: {
            $0.client_username.lowercased() == clean
        }) {
            return WhisperUserRow(
                user_id: client.client_user_id,
                username: client.client_username,
                display_name: nil,
                bio: nil,
                interests: nil,
                profile_image_url: nil,
                onboarded_at: nil,
                is_private: nil
            )
        }
        return nil
    }

    /// Places a real call. Returns a user-facing error string, or nil on
    /// success (the call UI takes over).
    func startCall(username: String, video: Bool) async -> String? {
        guard WhisperCallService.shared.active == nil else {
            return "You're already in a call — hang up first."
        }
        guard let user = await resolveUser(username) else {
            return "Couldn't find @\(WhisperEmberAction.cleanUsername(username))."
        }
        dismissModal()
        NotificationCenter.default.post(name: .whisperEmberDismissChat, object: nil)
        try? await Task.sleep(for: .milliseconds(450))
        await WhisperCallService.shared.startOutgoing(
            otherUserID: user.user_id,
            otherUsername: user.username,
            avatarURL: user.profile_image_url.flatMap(URL.init(string:)),
            mode: video ? .video : .audio
        )
        return nil
    }

    /// Sends a DM. Returns a user-facing error string, or nil on success.
    func sendDirectMessage(to username: String, body: String) async -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Message is empty." }
        guard let user = await resolveUser(username) else {
            return "Couldn't find @\(WhisperEmberAction.cleanUsername(username))."
        }
        let ok = await WhisperBackendService.shared.sendMessage(
            toUserID: user.user_id,
            toUsername: user.username,
            body: trimmed
        )
        return ok ? nil : "Message didn't send — try again."
    }

    /// Creates a real meeting. Returns (row, errorMessage).
    func scheduleMeeting(title: String, at date: Date?) async -> (WhisperMeetingRow?, String?) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let row = try await WhisperMeetingService.shared.create(
                title: cleanTitle.isEmpty ? "Meeting" : cleanTitle,
                scheduledAt: date
            )
            return (row, nil)
        } catch {
            return (nil, "Couldn't create the meeting — \(error.localizedDescription)")
        }
    }

    /// Saves a drafted plan into Coach Studio programs.
    func savePlan(_ draft: WhisperEmberPlanDraft) async -> Bool {
        await WhisperCoachProgramService.shared.saveProgram(draft.toProgram())
    }

    /// Follows a user for the asker (private accounts get a follow request).
    /// Returns a user-facing error string, or nil on success.
    @discardableResult
    func followUser(_ username: String) async -> String? {
        guard let user = await resolveUser(username) else {
            Haptics.warning()
            return "Couldn't find @\(WhisperEmberAction.cleanUsername(username))."
        }
        let outcome = await WhisperFollowService.shared.attemptFollow(
            userID: user.user_id,
            username: user.username
        )
        switch outcome {
        case .followed, .requested, .alreadyFollowing:
            Haptics.success()
            return nil
        default:
            Haptics.warning()
            return "Couldn't follow @\(user.username) — try again."
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Root-level navigation request: userInfo ["route": String, "arg": String].
    static let whisperEmberNavigate = Notification.Name("whisperEmberNavigate")
    /// Any presented Jasper chat sheet should dismiss (navigation is coming).
    static let whisperEmberDismissChat = Notification.Name("whisperEmberDismissChat")
}
