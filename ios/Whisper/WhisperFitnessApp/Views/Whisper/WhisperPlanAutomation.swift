import SwiftUI

// MARK: - Plan questionnaire embeds (wire-compatible with web)

/// Coach → client questionnaire riding a DM (`::whisper-plan-quiz-v1::{json}`).
/// Renders as a tappable card in the thread: the client answers each
/// question with one tap per row and sends the answers back as a card.
nonisolated enum WhisperPlanQuizEmbed {
    static let prefix = "::whisper-plan-quiz-v1::"

    nonisolated struct Question: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let q: String
        let opts: [String]
    }

    nonisolated struct Payload: Codable, Sendable, Hashable {
        let id: String
        let coach: String
        let questions: [Question]
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let json = String(trimmed.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }

    /// The standard 8-question intake — everything the automation needs to
    /// build BOTH plans (training via plan_shapes, diet via Jasper's own
    /// generator vocabulary). Option strings map 1:1 onto Jasper's fixed
    /// goal/preference vocabularies.
    nonisolated static func standard(coach: String) -> Payload {
        Payload(
            id: UUID().uuidString.lowercased(),
            coach: coach,
            questions: [
                Question(id: "goal", q: "Main goal right now?",
                         opts: ["Build muscle", "Lose fat", "Get stronger", "Improve endurance", "General fitness"]),
                Question(id: "days", q: "Training days per week?",
                         opts: ["2", "3", "4", "5", "6"]),
                Question(id: "session", q: "Time per session?",
                         opts: ["30 min", "45 min", "60 min", "90 min"]),
                Question(id: "level", q: "Training experience?",
                         opts: ["New", "1-2 years", "3+ years"]),
                Question(id: "limits", q: "Anything to train around?",
                         opts: ["Nothing", "Shoulder", "Knee", "Lower back", "Hip"]),
                Question(id: "diet", q: "Eating style?",
                         opts: ["No Preference", "High Protein", "Vegetarian", "Vegan", "Keto", "Mediterranean"]),
                Question(id: "allergies", q: "Food allergies?",
                         opts: ["None", "Dairy", "Gluten", "Nuts", "Shellfish"]),
                Question(id: "meals", q: "Meals per day?",
                         opts: ["2", "3", "4", "5"]),
            ]
        )
    }
}

/// Client → coach answers card (`::whisper-plan-quiz-answers-v1::{json}`).
nonisolated enum WhisperPlanQuizAnswersEmbed {
    static let prefix = "::whisper-plan-quiz-answers-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable {
        let quizId: String
        let client: String
        let answers: [String: String]
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let json = String(trimmed.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }

    /// Stable display order for answer chips (matches the quiz order).
    nonisolated static let displayOrder = ["goal", "days", "session", "level", "limits", "diet", "allergies", "meals"]

    nonisolated static func label(for id: String) -> String {
        switch id {
        case "goal": return "Goal"
        case "days": return "Days/wk"
        case "session": return "Session"
        case "level": return "Level"
        case "limits": return "Protect"
        case "diet": return "Diet"
        case "allergies": return "Allergies"
        case "meals": return "Meals"
        default: return id.capitalized
        }
    }
}

/// Answer → Jasper vocabulary mapping (plan_shapes program goals + the
/// diet generator's fixed goal list).
nonisolated enum WhisperPlanAutomationMap {
    nonisolated static func dietGoal(from answer: String?) -> String {
        switch answer {
        case "Build muscle": return "Muscle Gain"
        case "Lose fat": return "Fat Loss"
        case "Get stronger": return "Lean Bulk"
        default: return "Maintain Weight"
        }
    }

    nonisolated static func programGoal(from answer: String?) -> String {
        switch answer {
        case "Build muscle": return "Build Muscle"
        case "Lose fat": return "Lose Fat"
        case "Get stronger": return "Get Stronger"
        case "Improve endurance": return "Improve Endurance"
        default: return "General Fitness"
        }
    }

    nonisolated static func mealsPerDay(from answer: String?) -> Int {
        min(5, max(2, Int(answer ?? "") ?? 3))
    }

    nonisolated static func daysPerWeek(from answer: String?) -> Int {
        min(6, max(2, Int(answer ?? "") ?? 3))
    }

    nonisolated static func allergies(from answer: String?) -> [String] {
        guard let a = answer, !a.isEmpty, a != "None" else { return [] }
        return [a]
    }
}

// MARK: - DM inline cards

/// The questionnaire as it lands in the thread. For the CLIENT it's fully
/// interactive — tap one option per question, then send. For the coach
/// (sender) it's a compact "sent" summary.
struct WhisperPlanQuizInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperPlanQuizEmbed.Payload
    let mine: Bool
    /// The thread already contains an answers card for this quiz.
    let answered: Bool
    let onSubmit: ([String: String]) async -> Void

    @State private var picks: [String: String] = [:]
    @State private var sending: Bool = false
    @State private var sentLocally: Bool = false

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .black))
                Text("PLAN QUESTIONNAIRE")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                Spacer(minLength: 6)
                Text("\(payload.questions.count) TAPS")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ink.opacity(0.06), in: Capsule())
            }
            .foregroundStyle(WhisperTheme.coachAccent)

            if mine {
                Text("Answers land here as a card for review. Automatic plan delivery is paused; nutrition requires review in Jasper.")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if answered || sentLocally {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.coachAccent)
                    Text("Answered — @\(payload.coach) got your picks for review. No plan was generated or activated.")
                        .font(.caption)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("@\(payload.coach) wants to review your training and nutrition goals. Answering does not authorize plan changes.")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(payload.questions) { question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.q)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ink)
                        WhisperPlanQuizOptionGrid(
                            options: question.opts,
                            selected: picks[question.id]
                        ) { option in
                            Haptics.tap()
                            picks[question.id] = option
                        }
                    }
                }

                Button {
                    guard !sending else { return }
                    Haptics.success()
                    sending = true
                    Task {
                        await onSubmit(picks)
                        await MainActor.run {
                            sending = false
                            sentLocally = true
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        if sending {
                            ProgressView().controlSize(.small).tint(WhisperTheme.surface(colorScheme))
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.caption.weight(.bold))
                        }
                        Text(sending ? "Sending…" : (allAnswered ? "Send answers" : "Send answers (\(picks.count)/\(payload.questions.count))"))
                            .font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ink, in: Capsule())
                    .opacity(allAnswered && !sending ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!allAnswered || sending)
            }
        }
        .padding(12)
        .frame(maxWidth: 290, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.coachAccent.opacity(0.35), lineWidth: 1)
        }
    }

    private var allAnswered: Bool {
        payload.questions.allSatisfy { picks[$0.id] != nil }
    }
}

/// Wrapping option chips — single select.
struct WhisperPlanQuizOptionGrid: View {
    @Environment(\.colorScheme) private var colorScheme
    let options: [String]
    let selected: String?
    let onPick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isPicked = selected == option
                Button {
                    onPick(option)
                } label: {
                    Text(option)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isPicked ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            isPicked ? WhisperTheme.ink(colorScheme) : WhisperTheme.ink(colorScheme).opacity(0.05),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().strokeBorder(
                                isPicked ? Color.clear : WhisperTheme.hairline(colorScheme),
                                lineWidth: 1
                            )
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The client's answers as a compact card — chips in quiz order. The coach
/// side carries the "automate" hint.
struct WhisperPlanQuizAnswersInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperPlanQuizAnswersEmbed.Payload
    let mine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10, weight: .black))
                Text("QUESTIONNAIRE ANSWERS")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(WhisperTheme.coachAccent)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(orderedAnswers, id: \.0) { key, value in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WhisperPlanQuizAnswersEmbed.label(for: key).uppercased())
                            .font(.system(size: 7.5, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        Text(value)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.ink(colorScheme).opacity(0.05), in: .rect(cornerRadius: 9))
                }
            }

            if !mine {
                Text("Ready for review — Coach Studio → Jasper's read → Plan questionnaire.")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(12)
        .frame(maxWidth: 290, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.coachAccent.opacity(0.35), lineWidth: 1)
        }
    }

    private var orderedAnswers: [(String, String)] {
        var out: [(String, String)] = []
        for key in WhisperPlanQuizAnswersEmbed.displayOrder {
            if let value = payload.answers[key] { out.append((key, value)) }
        }
        for (key, value) in payload.answers where !WhisperPlanQuizAnswersEmbed.displayOrder.contains(key) {
            out.append((key, value))
        }
        return out
    }
}

// MARK: - The automation wizard

/// Explicitly send questionnaires and review answers without generating or assigning plans.
struct WhisperPlanAutomationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var requests = WhisperCoachRequestService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var mode: WhisperEmberCoachMode = WhisperEmberCoachMode.load()

    private enum Step: Int, CaseIterable {
        case ask = 0, review, execute
        var title: String {
            switch self {
            case .ask: return "Ask"
            case .review: return "Review"
            case .execute: return "Next steps"
            }
        }
        var icon: String {
            switch self {
            case .ask: return "paperplane.fill"
            case .review: return "checklist"
            case .execute: return "wand.and.stars"
            }
        }
    }

    @State private var step: Step = .ask
    @State private var selected: Set<String> = []
    @State private var sentTo: Set<String> = []
    @State private var sendingQuiz: Bool = false
    @State private var nudged: Set<String> = []
    @State private var refreshingAnswers: Bool = false
    @State private var answerRows: [String: WhisperMessageRow] = [:]
    @State private var answersChecked: Set<String> = []
    @State private var answersRequestID = UUID()
    @State private var viewGeneration: UUID = AccountStorage.generation
    @State private var isVisible: Bool = false
    @State private var sendNotice: String?

    private func check(_ context: JasperAccountSession) throws {
        try context.check()
        guard isVisible, viewGeneration == context.generation else { throw CancellationError() }
    }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var cardBG: Color { WhisperTheme.card(colorScheme) }

    private var clients: [WhisperCoachRequestRow] { requests.myClients }

    private var myUsername: String {
        WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "coach"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperEmberSheetTheme.Backdrop(mode: mode)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    stepHeader
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let sendNotice {
                                Text(sendNotice)
                                    .font(.callout)
                                    .foregroundStyle(muted)
                                    .accessibilityAddTraits(.updatesFrequently)
                            }
                            switch step {
                            case .ask: askStep
                            case .review: reviewStep
                            case .execute: executeStep
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // New identity per step so the content slides in
                        // instead of snapping — the wizard used to jump-cut.
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    .animation(.whisperSnappy, value: step)
                    .scrollBounceBehavior(.basedOnSize)
                }
                // ONE pinned action bar shared by all three steps — same
                // size, same spot, always reachable (the CTA used to sit at
                // the bottom of each step's scroll, making every screen feel
                // oversized and the button easy to lose).
                .safeAreaInset(edge: .bottom) { primaryBar }
            }
            .navigationTitle("Plan questionnaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        isVisible = false
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onChange(of: AuthenticationService.shared.currentUser.userID) { _, _ in
                isVisible = false
                selected.removeAll()
                sentTo.removeAll()
                nudged.removeAll()
                sendNotice = nil
                answersRequestID = UUID(); answerRows = [:]; answersChecked = []
                dismiss()
            }
            .onChange(of: AuthenticationService.shared.isSignedIn) { _, signedIn in
                if !signedIn { isVisible = false; dismiss() }
            }
            .task {
                guard let context = try? await JasperAccountSession.current(),
                      (try? check(context)) != nil else { return }
                mode = WhisperEmberCoachMode.load()
                await requests.refresh()
                guard (try? check(context)) != nil else { return }
                await refreshPlanAnswers(context: context)
                guard (try? check(context)) != nil else { return }
            }
            .task(id: step) {
                // Review polls quietly so answers stream in on their own —
                // plain DB fetch, no AI spend, cancelled the moment the step
                // changes or the sheet closes.
                guard step == .review else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled, step == .review,
                          let context = try? await JasperAccountSession.current(),
                          (try? check(context)) != nil else { break }
                    await refreshPlanAnswers(context: context)
                    guard (try? check(context)) != nil else { break }
                }
            }
        }
    }

    // MARK: Step header

    private var stepHeader: some View {
        HStack(spacing: 0) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                let isActive = s == step
                let isDone = s.rawValue < step.rawValue
                Button {
                    // Free navigation backward; forward only via the CTAs.
                    // Locked while sending/building so state can't shear.
                    guard s.rawValue < step.rawValue, !sendingQuiz else { return }
                    Haptics.tap()
                    withAnimation(.whisperSnappy) { step = s }
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(isActive || isDone ? mode.deepAccent : ink.opacity(0.07))
                                .frame(width: 28, height: 28)
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: s.icon)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(isActive ? .white : muted)
                            }
                        }
                        Text(s.title.uppercased())
                            .font(.system(size: 8.5, weight: .black))
                            .tracking(1)
                            .foregroundStyle(isActive ? ink : muted)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                if s != .execute {
                    Rectangle()
                        .fill(isDone ? mode.deepAccent.opacity(0.6) : ink.opacity(0.1))
                        .frame(height: 2)
                        .frame(maxWidth: 40)
                        .offset(y: -8)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: Step 1 — Ask

    @ViewBuilder
    private var askStep: some View {
        explainerCard

        if clients.isEmpty {
            WhisperStudioEmptyState(
                icon: "person.2",
                title: "No clients yet",
                subtitle: "Accept a coaching request first — then Jasper can run the questionnaire."
            )
            .padding(14)
            .background(cardBG, in: .rect(cornerRadius: 18))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Send to")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ink)
                    Spacer()
                    Button {
                        Haptics.tap()
                        if selected.count == clients.count {
                            selected.removeAll()
                        } else {
                            selected = Set(clients.map { normalize($0.client_user_id) })
                        }
                    } label: {
                        Text(selected.count == clients.count ? "Deselect all" : "Select all")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(mode.deepAccent)
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 6) {
                    ForEach(clients) { row in
                        clientPickRow(row)
                    }
                }
            }
            .padding(14)
            .background(cardBG, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }

            questionnairePreview
        }
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                WhisperEmberBadge(size: 20)
                Text("Plan questionnaire")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
            }
            explainerRow(n: 1, text: "Each client gets a tappable questionnaire in your DM thread — 8 quick taps.")
            explainerRow(n: 2, text: "Answers come back as cards. You review exactly what they picked.")
            explainerRow(n: 3, text: "Automatic plan delivery is paused. Review nutrition in Jasper; answering this questionnaire does not authorize generation, activation or sharing.")
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(mode.accent.opacity(0.3), lineWidth: 1)
        }
    }

    private func explainerRow(n: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(n)")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(mode.deepAccent, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func clientPickRow(_ row: WhisperCoachRequestRow) -> some View {
        let uid = normalize(row.client_user_id)
        let isOn = selected.contains(uid)
        let alreadySent = sentTo.contains(uid)
        return Button {
            Haptics.tap()
            if isOn { selected.remove(uid) } else { selected.insert(uid) }
        } label: {
            HStack(spacing: 10) {
                WhisperAvatar(username: row.client_username, size: 34, ring: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(row.client_username)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    if alreadySent {
                        Text("Questionnaire sent ✓")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WhisperTheme.coachAccent)
                    } else if latestAnswers(forUID: uid) != nil {
                        Text("Already answered — ready to review")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WhisperTheme.coachAccent)
                    }
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? mode.deepAccent : muted.opacity(0.5))
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var questionnairePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT THEY'LL BE ASKED")
                .font(.system(size: 9, weight: .black))
                .tracking(1.4)
                .foregroundStyle(mode.deepAccent)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(WhisperPlanQuizEmbed.standard(coach: myUsername).questions) { question in
                    Text(question.q)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(ink.opacity(0.05), in: .rect(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func sendQuizzes() async {
        guard !selected.isEmpty, !sendingQuiz else { return }
        sendingQuiz = true
        sendNotice = nil
        defer { sendingQuiz = false }
        do {
            let context = try await JasperAccountSession.current()
            try check(context)
            let recipients = clients.filter {
                selected.contains(normalize($0.client_user_id)) && !sentTo.contains(normalize($0.client_user_id))
            }
            let coach = myUsername
            for row in recipients {
                try check(context)
                let quiz = WhisperPlanQuizEmbed.standard(coach: coach)
                let ok = await backend.sendMessage(
                    toUserID: row.client_user_id,
                    toUsername: row.client_username,
                    body: WhisperPlanQuizEmbed.encode(quiz)
                )
                try check(context)
                guard ok else {
                    sendNotice = "Sending stopped. Check Messages before retrying; some questionnaires may already have arrived."
                    return
                }
                sentTo.insert(normalize(row.client_user_id))
            }
            Haptics.success()
            withAnimation(.whisperSnappy) { step = .review }
        } catch {
            if isVisible { sendNotice = "Sending stopped. Reopen this questionnaire for your current account and check Messages before retrying." }
        }
    }

    // MARK: Step 2 — Review

    @ViewBuilder
    private var reviewStep: some View {
        HStack(spacing: 8) {
            Text("Answers")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ink)
            HStack(spacing: 4) {
                Circle().fill(WhisperTheme.coachAccent).frame(width: 5, height: 5)
                Text("auto-checking")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(muted)
            }
            Spacer()
            Button {
                Task {
                    guard let context = try? await JasperAccountSession.current(),
                          (try? check(context)) != nil else { return }
                    refreshingAnswers = true
                    defer { refreshingAnswers = false }
                    await refreshPlanAnswers(context: context)
                    guard (try? check(context)) != nil else { return }
                }
            } label: {
                HStack(spacing: 5) {
                    if refreshingAnswers {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                    }
                    Text("Check again")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(mode.deepAccent)
            }
            .buttonStyle(.plain)
        }

        ForEach(reviewRows) { row in
            reviewCard(row)
        }

        if reviewRows.isEmpty {
            WhisperStudioEmptyState(
                icon: "checklist",
                title: "Nobody selected",
                subtitle: "Go back to Ask and pick at least one client."
            )
            .padding(14)
            .background(cardBG, in: .rect(cornerRadius: 18))
        }

    }

    /// Clients in this run — selected in step 1 (or already answered).
    private var reviewRows: [WhisperCoachRequestRow] {
        clients.filter { selected.contains(normalize($0.client_user_id)) }
    }

    private func reviewCard(_ row: WhisperCoachRequestRow) -> some View {
        let uid = normalize(row.client_user_id)
        let answers = latestAnswers(forUID: uid)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                WhisperAvatar(username: row.client_username, size: 32, ring: false)
                Text("@\(row.client_username)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                Spacer()
                if answers != nil {
                    Label("Answered", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(mode.deepAccent)
                } else {
                    Text("WAITING")
                        .font(.system(size: 8.5, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ink.opacity(0.06), in: Capsule())
                }
            }
            if let answers {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(orderedAnswerPairs(answers.answers), id: \.0) { key, value in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(WhisperPlanQuizAnswersEmbed.label(for: key).uppercased())
                                .font(.system(size: 7.5, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(muted)
                            Text(value)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(ink.opacity(0.05), in: .rect(cornerRadius: 9))
                    }
                }
            } else {
                Button {
                    Haptics.tap()
                    Task {
                        guard !sendingQuiz, let context = try? await JasperAccountSession.current(),
                              (try? check(context)) != nil else { return }
                        sendingQuiz = true
                        defer { sendingQuiz = false }
                        let ok = await backend.sendMessage(
                            toUserID: row.client_user_id,
                            toUsername: row.client_username,
                            body: "When you have time, please answer the questionnaire above so we can review your goals together."
                        )
                        guard (try? check(context)) != nil else { return }
                        if ok { nudged.insert(uid) }
                        else { sendNotice = "The reminder could not be confirmed. Check Messages before retrying." }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: nudged.contains(uid) ? "checkmark" : "hand.wave.fill")
                            .font(.caption2.weight(.bold))
                        Text(nudged.contains(uid) ? "Nudged" : "Nudge")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(nudged.contains(uid) ? muted : mode.deepAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(mode.accent.opacity(nudged.contains(uid) ? 0.06 : 0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(nudged.contains(uid) || sendingQuiz)
            }
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    answers != nil ? WhisperTheme.coachAccent.opacity(0.3) : WhisperTheme.hairline(colorScheme),
                    lineWidth: 1
                )
        }
    }

    // MARK: Step 3 — Execute

    private var executeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            JasperNativeNutritionNotice()
            Text("This questionnaire does not generate, save or activate either plan. No plans-are-live message is sent.")
                .font(.callout)
                .foregroundStyle(muted)
        }
        .padding(16)
        .background(cardBG, in: .rect(cornerRadius: 18))
    }

    // MARK: Pinned primary action — one consistent bar on every step

    /// Any selected client already has answers waiting (skip-ahead path).
    private var anyAnswered: Bool {
        clients.contains {
            let uid = normalize($0.client_user_id)
            return selected.contains(uid) && latestAnswers(forUID: uid) != nil
        }
    }

    private var barTitle: String {
        switch step {
        case .ask: return sendingQuiz ? "Sending…" : "Send questionnaire (\(selected.count))"
        case .review: return "Next steps"
        case .execute: return "Done"
        }
    }

    private var barIcon: String {
        switch step {
        case .ask: return "paperplane.fill"
        case .review: return "wand.and.stars"
        case .execute: return "checkmark"
        }
    }

    private var barDisabled: Bool {
        switch step {
        case .ask: return selected.isEmpty || sendingQuiz
        case .review: return sendingQuiz
        case .execute: return false
        }
    }

    /// One pinned action keeps review and sending controls reachable.
    private var primaryBar: some View {
        VStack(spacing: 8) {
            if step == .ask, anyAnswered, !sendingQuiz {
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) { step = .review }
                } label: {
                    Text("Some already answered — skip to review")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(mode.deepAccent)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Button {
                Haptics.tap()
                switch step {
                case .ask:
                    Task { await sendQuizzes() }
                case .review:
                    Haptics.success()
                    withAnimation(.whisperSnappy) { step = .execute }
                case .execute:
                    isVisible = false
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if sendingQuiz {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: barIcon)
                    }
                    Text(barTitle)
                        .font(.body.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(mode.deepAccent, in: Capsule())
                .shadow(color: mode.deepAccent.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(WhisperMenuPressStyle())
            .disabled(barDisabled)
            .opacity(barDisabled ? 0.55 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WhisperTheme.hairline(colorScheme))
                .frame(height: 0.5)
        }
    }

    // MARK: Execution

    // Connected generation is intentionally unavailable; no execution task is launched.

    // MARK: Helpers

    private func normalize(_ uid: String) -> String {
        uid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Independent answer reads, bounded to four concurrent requests. A failed
    /// read retains its last good answer; an authorized empty response clears it.
    private func refreshPlanAnswers(context: JasperAccountSession) async {
        guard (try? check(context)) != nil else { return }
        let request = UUID(); answersRequestID = request
        let ids = Array(Set(clients.map { normalize($0.client_user_id) }))
            .filter { step != .review || selected.contains($0) }.sorted()
        for start in stride(from: 0, to: ids.count, by: 4) {
            guard answersRequestID == request, (try? check(context)) != nil else { return }
            let batch = Array(ids[start..<min(start + 4, ids.count)])
            await withTaskGroup(of: (String, WhisperMessageRow?, Bool).self) { group in
                for uid in batch {
                    group.addTask { @MainActor in
                        do { return (uid, try await backend.fetchLatestPlanAnswer(from: uid), true) }
                        catch { return (uid, nil, false) }
                    }
                }
                for await (uid, row, succeeded) in group {
                    guard answersRequestID == request, (try? check(context)) != nil else {
                        group.cancelAll(); continue
                    }
                    if succeeded { answerRows[uid] = row; answersChecked.insert(uid) }
                }
            }
        }
    }

    /// Prefer the targeted, authorized answer read over any older local window.
    private func latestAnswers(forUID uid: String) -> WhisperPlanQuizAnswersEmbed.Payload? {
        if let row = answerRows[normalize(uid)] { return WhisperPlanQuizAnswersEmbed.decode(row.body) }
        if answersChecked.contains(normalize(uid)) { return nil }
        let rows = backend.directMessages(with: uid, kind: .direct)
        for msg in rows.reversed() {
            if let payload = WhisperPlanQuizAnswersEmbed.decode(msg.body) {
                return payload
            }
        }
        return nil
    }

    private func orderedAnswerPairs(_ answers: [String: String]) -> [(String, String)] {
        var out: [(String, String)] = []
        for key in WhisperPlanQuizAnswersEmbed.displayOrder {
            if let value = answers[key] { out.append((key, value)) }
        }
        for (key, value) in answers where !WhisperPlanQuizAnswersEmbed.displayOrder.contains(key) {
            out.append((key, value))
        }
        return out
    }

}
