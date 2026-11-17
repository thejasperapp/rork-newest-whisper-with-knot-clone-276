import SwiftUI

/// Coach Studio hub — one scrollable, monochrome surface matching the rest
/// of Whisper: identity hero, ink stat strip, pending requests, studio
/// shortcuts (programs / marketplace / earnings) and the client roster.
///
/// The roster preview chips are the SAME one-call Jasper dashboard summary
/// the full client panel renders (`GET /v1/dashboard`, 60s cache, change-feed
/// refresh) — so the preview box can never disagree with what opens
/// when you tap the name. No legacy snapshot numbers, ever.
struct WhisperCoachClientsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var requests = WhisperCoachRequestService.shared
    @State private var coach = WhisperCoachService.shared
    @State private var auth = AuthenticationService.shared
    @State private var coachConnect = JasperCoachConnect.shared
    @State private var selectedClient: WhisperCoachRequestRow?
    /// One-call dashboards per client uid — the preview truth.
    @State private var dashboards: [String: JasperClientDashboard] = [:]
    @State private var dashboardTokens: [String: UUID] = [:]
    @State private var dashErrors: [String: String] = [:]
    @State private var loadingDashboards: Bool = false
    @State private var dashboardOperation = UUID()
    @State private var pulseOperations: [String: UUID] = [:]
    @State private var pageVisible = false
    /// Last change-feed pulse handled per client (dedupe for targeted refreshes).
    @State private var pulseHandled: [String: Date] = [:]
    @State private var searchText: String = ""
    @State private var presentPrograms: Bool = false
    @State private var presentEarnings: Bool = false
    @State private var presentMarketplace: Bool = false
    /// Jasper dock quick action — the three-step plan automation wizard
    /// (questionnaire DMs → review answers → generate + assign both plans).
    @State private var presentAutomation: Bool = false

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var cardBG: Color { WhisperTheme.card(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    statStrip
                    if !pendingRequests.isEmpty {
                        VStack(spacing: 10) {
                            sectionHeader("New requests", count: pendingRequests.count)
                            ForEach(pendingRequests) { row in
                                pendingCard(row)
                            }
                        }
                    }
                    studioCard
                    clientsBlock
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 104)
            }
            .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
            .whisperEdgeBack { dismiss() }
            .navigationTitle("Coach Studio")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search clients")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                }
            }
            .whisperRefreshable {
                await requests.refresh()
                await reloadDashboards(force: true)
            }
            .overlay(alignment: .bottom) {
                // The meeting-style Jasper dock — a live roster read plus the
                // coach quick actions: attention lens, check-in drafts, and
                // the flagship "Automate plans" wizard.
                JasperAnalysisDock(
                    pillLabel: "Knot's read",
                    boxTitle: "Roster analysis",
                    focus: """
                    You are analyzing a coach's client roster (live Jasper dashboards). Lead with WHO NEEDS ATTENTION and why (readiness or sleep under 50, or no readable dashboard), then who's cruising, then ONE concrete coaching move for today. Use the actual @handles. The Plan questionnaire collects answers for review only; automated plan delivery is paused pending native Nutrition review in Jasper. Missing or unavailable data is not evidence of inactivity.
                    """,
                    buildContext: { rosterAnalysisContext() },
                    emptyText: "No clients yet — accept a coaching request and I'll read the roster here.",
                    actions: [
                        JasperDockAction(
                            id: "attention",
                            label: "Who needs attention",
                            icon: "exclamationmark.triangle",
                            kind: .lens("From the roster below, list ONLY the clients who need attention this week — one line each: @handle, the exact signal (readiness/sleep number or unreadable dashboard), and the single move to make. If everyone is fine, say so in one sentence.")
                        ),
                        JasperDockAction(
                            id: "checkins",
                            label: "Check-in drafts",
                            icon: "text.bubble",
                            kind: .lens("Write 2 short copy-ready check-in DMs for the clients who most need one right now, grounded in their live numbers. Format: @handle — then the message in quotes. Warm, specific, coach-voiced, no emojis overload.")
                        ),
                        JasperDockAction(
                            id: "automate",
                            label: "Plan questionnaire",
                            icon: "wand.and.stars",
                            kind: .perform { presentAutomation = true }
                        ),
                    ]
                )
                .padding(.bottom, 10)
            }
            .sheet(item: $selectedClient, onDismiss: {
                // The full panel may have force-refreshed the shared cache —
                // fold it back so the preview matches the second it closes.
                Task { await reloadDashboards(force: false) }
            }) { row in
                WhisperClientHealthView(client: row)
            }
            .sheet(isPresented: $presentPrograms) {
                WhisperCoachProgramsView()
            }
            .sheet(isPresented: $presentEarnings) {
                WhisperCoachEarningsView()
            }
            .sheet(isPresented: $presentMarketplace) {
                JasperMarketplaceSheet()
            }
            .fullScreenCover(isPresented: $presentAutomation) {
                WhisperPlanAutomationView()
            }
            .onAppear { pageVisible = true }
            .onDisappear { pageVisible = false; dashboardOperation = UUID(); pulseOperations = [:]; loadingDashboards = false }
            .task(id: "\(AccountStorage.generation)|\(scenePhase)") {
                guard scenePhase == .active else { return }
                await requests.refresh()
                guard !Task.isCancelled else { return }
                await reloadDashboards(force: false)
            }
            .onChange(of: coachConnect.accessByClient.mapValues { $0.tokenID }) { _, current in
                dashboards = dashboards.filter { key, _ in current[key] != nil && dashboardTokens[key] == current[key] }
                dashboardTokens = dashboardTokens.filter { key, _ in dashboards[key] != nil }
            }
            .onChange(of: requests.myClients.map { normalize($0.client_user_id) }.sorted()) { _, ids in
                let roster = Set(ids)
                dashboards = dashboards.filter { roster.contains($0.key) }
                dashboardTokens = dashboardTokens.filter { roster.contains($0.key) }
                dashErrors = dashErrors.filter { roster.contains($0.key) }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                dashboardOperation = UUID(); pulseOperations = [:]; dashboards = [:]; dashboardTokens = [:]; dashErrors = [:]; pulseHandled = [:]
                selectedClient = nil; presentPrograms = false; presentEarnings = false; presentMarketplace = false; presentAutomation = false
                dismiss()
            }
            .onChange(of: JasperEventPush.shared.pulses) { _, pulses in
                // Fresh change-feed events landed for someone on the roster —
                // force-refresh THAT client's dashboard so the preview chips
                // move the moment the panel would.
                guard pageVisible, scenePhase == .active else { return }
                for (uid, stamp) in pulses {
                    guard requests.myClients.contains(where: { normalize($0.client_user_id) == uid }) else { continue }
                    if let handled = pulseHandled[uid], handled >= stamp { continue }
                    pulseHandled[uid] = stamp
                    let generation = AccountStorage.generation, operation = UUID()
                    pulseOperations[uid] = operation
                    Task {
                        let fresh = await coachConnect.dashboard(forClient: uid, force: true)
                        guard !Task.isCancelled, pageVisible, scenePhase == .active,
                              generation == AccountStorage.generation, pulseOperations[uid] == operation,
                              requests.myClients.contains(where: { normalize($0.client_user_id) == uid }) else { return }
                        if let fresh, coachConnect.accessByClient[uid] != nil {
                            dashboardTokens[uid] = coachConnect.accessByClient[uid]?.tokenID
                            withAnimation(.spring(duration: 0.3)) { dashboards[uid] = fresh; dashErrors[uid] = nil }
                        } else if coachConnect.accessByClient[uid] == nil { dashboards[uid] = nil }
                    }
                }
            }
        }
    }

    // MARK: - Hero

    private var coachName: String {
        LeaderboardService.shared.savedUsername
            ?? auth.currentUser.username
            ?? "coach"
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Welcome back"
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                WhisperCoachBadge(size: 15)
                Text("COACH STUDIO")
                    .font(.caption2.weight(.black))
                    .tracking(2.2)
                    .foregroundStyle(WhisperTheme.coachAccent)
                Spacer()
            }
            HStack(spacing: 14) {
                WhisperAvatar(username: coachName, size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.footnote)
                        .foregroundStyle(muted)
                    Text("@\(coachName)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    // MARK: - Stat strip

    private var statStrip: some View {
        HStack(spacing: 10) {
            statTile(value: "\(requests.myClients.count)", label: "Clients", icon: "person.2.fill")
            statTile(value: "\(pendingRequests.count)", label: "Requests", icon: "tray.fill")
            statTile(value: "\(attentionClients.count)", label: "Attention", icon: "exclamationmark.circle.fill")
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(ink)
                .frame(width: 26, height: 26)
                .background(ink.opacity(0.07), in: Circle())
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(ink)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    // MARK: - Pending requests

    private func pendingCard(_ row: WhisperCoachRequestRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WhisperAvatar(username: row.client_username, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(row.client_username)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text("Wants you as their coach")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
            }
            if let msg = row.message, !msg.isEmpty {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(ink)
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                Button {
                    Haptics.success()
                    Task {
                        await requests.accept(row)
                        await reloadDashboards(force: false)
                    }
                } label: {
                    Text("Accept")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(ink, in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.warning()
                    Task { await requests.decline(row) }
                } label: {
                    Text("Decline")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(hairline, lineWidth: 0.75) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    // MARK: - Studio shortcuts

    private var studioCard: some View {
        VStack(spacing: 0) {
            studioRow(
                icon: "rectangle.stack.fill",
                title: "Programs",
                subtitle: "Design and send training programs"
            ) { presentPrograms = true }
            Divider()
                .background(hairline)
                .padding(.leading, 56)
            studioRow(
                icon: "storefront.fill",
                title: "Plan marketplace",
                subtitle: "Browse, publish and import Jasper plan templates"
            ) { presentMarketplace = true }
            Divider()
                .background(hairline)
                .padding(.leading, 56)
            studioRow(
                icon: "banknote.fill",
                title: "Earnings & payouts",
                subtitle: "Coaching income, rate and payouts"
            ) { presentEarnings = true }
        }
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    private func studioRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(width: 32, height: 32)
                    .background(ink.opacity(0.07), in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(muted.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clients

    @ViewBuilder
    private var clientsBlock: some View {
        if requests.myClients.isEmpty {
            emptyState
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("CLIENTS")
                        .font(.caption2.weight(.black))
                        .tracking(1.6)
                        .foregroundStyle(muted)
                    Text("\(requests.myClients.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(ink.opacity(0.08), in: Capsule())
                    Spacer()
                    Text("LIVE · /v1/dashboard")
                        .font(.system(size: 7.5, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(WhisperTheme.coachAccent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(WhisperTheme.coachAccent.opacity(0.1), in: Capsule())
                }
                .padding(.top, 4)
                ForEach(sortedClients, id: \.id) { row in
                    Button {
                        Haptics.tap()
                        selectedClient = row
                    } label: {
                        clientCard(row)
                    }
                    .buttonStyle(.plain)
                }
                if sortedClients.isEmpty {
                    WhisperEmptyState(icon: "magnifyingglass", title: "No matching clients", message: "Try another name or clear your search.", isCard: false, compact: true)
                }
                Text("Preview chips are Jasper's one-call dashboard summary — the exact numbers the full panel shows when you tap a name.")
                    .font(.system(size: 9))
                    .foregroundStyle(muted.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The preview box: headline numbers straight off `dashboard.summary` —
    /// the SAME payload (and the same 60s cache entry) the full client panel
    /// renders, so tapping the name can never show different numbers.
    private func clientCard(_ row: WhisperCoachRequestRow) -> some View {
        let uid = normalize(row.client_user_id)
        let dash = dashboards[uid]
        let fresh = dash.map { Date().timeIntervalSince($0.fetchedAt) < 10 * 60 } ?? false
        let needsAttention = isAttention(row)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    WhisperAvatar(username: row.client_username, size: 44)
                    Circle()
                        .fill(fresh ? Color.green : Color.gray)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(cardBG, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(row.client_username)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(subtitleFor(row, needsAttention: needsAttention))
                        .font(.caption)
                        .foregroundStyle(needsAttention ? WhisperTheme.likeRed : muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(muted.opacity(0.6))
            }

            if let summary = dash?.summary {
                HStack(spacing: 6) {
                    if let readiness = summary.readinessScore {
                        metricChip(icon: "bolt.heart.fill", value: "\(readiness)")
                    }
                    if let kcal = summary.kcalToday {
                        metricChip(icon: "flame.fill", value: "\(grouped(kcal)) kcal")
                    }
                    if let sleep = sleepChipValue(summary) {
                        metricChip(icon: "moon.stars.fill", value: sleep)
                    }
                    if let workouts = summary.workoutsLast7d {
                        metricChip(icon: "dumbbell.fill", value: "\(workouts)×7d")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
        .contentShape(.rect)
    }

    private func sleepChipValue(_ summary: JasperClientDashboard.Summary) -> String? {
        if let secs = summary.sleepDurationSeconds {
            let hours = secs / 3600
            let minutes = (secs % 3600) / 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        }
        if let quality = summary.sleepQualityScore { return "\(quality)" }
        return nil
    }

    private func metricChip(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(value)
                .font(.caption2.weight(.semibold))
                .contentTransition(.numericText())
        }
        .foregroundStyle(ink.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(ink.opacity(0.06), in: Capsule())
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.6)
                .foregroundStyle(muted)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(ink.opacity(0.08), in: Capsule())
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: "person.2", height: 120)
            Text("No active clients yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            Text("Share your @\(coachName) handle. When someone taps “Become my coach,” their request lands here.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(muted)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, style: StrokeStyle(lineWidth: 0.75, dash: [5]))
        }
    }

    // MARK: - Derived

    private var pendingRequests: [WhisperCoachRequestRow] {
        requests.incoming.filter { $0.status == "pending" }
    }

    /// Clients filtered by search, attention first, then freshest dashboard.
    private var sortedClients: [WhisperCoachRequestRow] {
        let base: [WhisperCoachRequestRow]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            base = requests.myClients
        } else {
            let q = searchText.lowercased()
            base = requests.myClients.filter { $0.client_username.lowercased().contains(q) }
        }
        return base.sorted { a, b in
            let aA = isAttention(a) ? 1 : 0
            let bA = isAttention(b) ? 1 : 0
            if aA != bA { return aA > bA }
            let aDate = dashboardStamp(a) ?? .distantPast
            let bDate = dashboardStamp(b) ?? .distantPast
            return aDate > bDate
        }
    }

    /// Live roster context for the Jasper dock — the same one-call
    /// dashboard numbers the preview chips render.
    private func rosterAnalysisContext() -> String? {
        let clients = requests.myClients
        guard !clients.isEmpty else { return nil }
        var lines: [String] = ["COACH ROSTER (live one-call Jasper dashboards)"]
        for row in clients.prefix(14) {
            let uid = normalize(row.client_user_id)
            var bits: [String] = ["@\(row.client_username)"]
            if let summary = dashboards[uid]?.summary {
                if let readiness = summary.readinessScore { bits.append("readiness \(readiness)") }
                if let sleep = summary.sleepQualityScore { bits.append("sleep quality \(sleep)") }
            } else {
                bits.append("no readable dashboard")
            }
            lines.append("- " + bits.joined(separator: " · "))
        }
        if !pendingRequests.isEmpty {
            lines.append("Pending coaching requests: \(pendingRequests.count)")
        }
        return lines.joined(separator: "\n")
    }

    private func dashboardStamp(_ row: WhisperCoachRequestRow) -> Date? {
        let dash = dashboards[normalize(row.client_user_id)]
        return dash?.generatedAt ?? dash?.fetchedAt
    }

    private var attentionClients: [WhisperCoachRequestRow] {
        requests.myClients.filter { isAttention($0) }
    }

    /// Attention comes from the SAME summary the panel shows: low readiness,
    /// rough sleep, or no readable dashboard at all.
    private func isAttention(_ row: WhisperCoachRequestRow) -> Bool {
        guard let summary = dashboards[normalize(row.client_user_id)]?.summary else {
            // Nothing readable yet — surface it instead of hiding it.
            return !loadingDashboards
        }
        if let readiness = summary.readinessScore, readiness < 50 { return true }
        if let quality = summary.sleepQualityScore, quality < 50 { return true }
        return false
    }

    private func subtitleFor(_ row: WhisperCoachRequestRow, needsAttention: Bool) -> String {
        let uid = normalize(row.client_user_id)
        guard let dash = dashboards[uid] else {
            if loadingDashboards { return "Pulling live dashboard…" }
            return dashErrors[uid] ?? "Live dashboard unavailable — tap to retry"
        }
        let summary = dash.summary
        if needsAttention {
            if let readiness = summary.readinessScore, readiness < 50 {
                return "Low readiness · \(readiness)"
            }
            if let quality = summary.sleepQualityScore, quality < 50 {
                return "Rough sleep · quality \(quality)"
            }
            return "Needs a look"
        }
        if let stamp = dash.generatedAt ?? Optional(dash.fetchedAt) {
            return "Live · \(relativeTime(stamp))"
        }
        return "Live via Jasper"
    }

    // MARK: - Dashboard loading (one-call rail, shared with the full panel)

    /// One `GET /v1/dashboard` per client (60s-cached by JasperCoachConnect,
    /// in-flight deduped — the panel and this preview share the same cache
    /// entry). Each read also reconciles that client's change feed, so
    /// journal events keep previews current between polls.
    private func reloadDashboards(force: Bool) async {
        guard pageVisible, scenePhase == .active, !Task.isCancelled else { return }
        let generation = AccountStorage.generation, operation = UUID()
        dashboardOperation = operation
        let clients = Array(Set(requests.myClients.map { normalize($0.client_user_id) })).sorted()
        let roster = Set(clients)
        dashboards = dashboards.filter { roster.contains($0.key) }
        dashboardTokens = dashboardTokens.filter { roster.contains($0.key) }
        dashErrors = dashErrors.filter { roster.contains($0.key) }
        guard !clients.isEmpty else { loadingDashboards = false; return }
        loadingDashboards = true
        defer { if dashboardOperation == operation { loadingDashboards = false } }
        await withTaskGroup(of: (String, JasperClientDashboard?).self) { group in
            var next = 0
            // Bound scheduling; the shared service still owns request coalescing with client details.
            for _ in 0..<min(4, clients.count) {
                let uid = clients[next]; next += 1
                group.addTask { @MainActor in
                    guard !Task.isCancelled else { return (uid, nil) }
                    return (uid, await JasperCoachConnect.shared.dashboard(forClient: uid, force: force))
                }
            }
            for await (uid, dash) in group {
                guard !Task.isCancelled, pageVisible, scenePhase == .active,
                      generation == AccountStorage.generation, dashboardOperation == operation else { group.cancelAll(); break }
                if requests.myClients.contains(where: { normalize($0.client_user_id) == uid }) {
                    if let dash, coachConnect.accessByClient[uid] != nil {
                        dashboardTokens[uid] = coachConnect.accessByClient[uid]?.tokenID
                        dashboards[uid] = dash; dashErrors[uid] = nil
                    } else {
                        if coachConnect.accessByClient[uid] == nil { dashboards[uid] = nil }
                        dashErrors[uid] = "Live dashboard couldn’t load. Try refreshing."
                    }
                }
                while next < clients.count {
                    let uid = clients[next]; next += 1
                    // A client removed while this batch runs must not acquire a new preview read.
                    guard requests.myClients.contains(where: { normalize($0.client_user_id) == uid }) else { continue }
                    group.addTask { @MainActor in
                        guard !Task.isCancelled else { return (uid, nil) }
                        return (uid, await JasperCoachConnect.shared.dashboard(forClient: uid, force: force))
                    }
                    break
                }
            }
        }
    }

    // MARK: - Formatting helpers

    private func normalize(_ uid: String) -> String {
        uid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
