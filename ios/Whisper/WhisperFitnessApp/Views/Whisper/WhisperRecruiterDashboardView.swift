import SwiftUI

/// Recruiter HQ — the iOS twin of the web Recruiting OS v4. Six views,
/// same discipline, same tables:
///   TODAY    — the work queue (overdue · due today · coming up · no next step)
///   PIPELINE — Sourced → Contacted → In talks → Evaluating → Offer with
///              aging dots, quick advance, the signed strip and the archive
///   PEOPLE   — the searchable talent pool with #tags and composite scores
///   INBOX    — QR applications + meeting requests
///   INSIGHTS — goal ring, days-to-sign, 8-week bars, sources, funnel
///   GROW     — invite code + QR, territories, pitch decks, reviews
/// Tapping any person opens the full person sheet (stage stepper, next
/// step, scorecard, tags, timeline, sign flow).
struct WhisperRecruiterDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var recruiter = WhisperRecruiterService.shared
    @State private var meetings = WhisperMeetingsService.shared

    /// The six HQ views — web parity.
    private enum HQTab: String, CaseIterable, Identifiable {
        case today, pipeline, people, inbox, insights, grow
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Today"
            case .pipeline: return "Pipeline"
            case .people: return "People"
            case .inbox: return "Inbox"
            case .insights: return "Insights"
            case .grow: return "Grow"
            }
        }
        var icon: String {
            switch self {
            case .today: return "checklist"
            case .pipeline: return "arrow.right.arrow.left"
            case .people: return "person.2.fill"
            case .inbox: return "tray.full.fill"
            case .insights: return "chart.bar.fill"
            case .grow: return "qrcode"
            }
        }
    }

    @State private var tab: HQTab = .today
    @State private var selectedStage: String = "discovered"
    @State private var relationshipFilter: String = "All people"
    @State private var showTeamPipeline: Bool = false
    @State private var selectedProspect: WhisperRecruiterService.ProspectRow?
    @State private var showPassedArchive: Bool = false
    @State private var peopleQuery: String = ""
    @State private var selectedTag: String?
    @State private var appWorking: Set<String> = []

    // Sheets
    @State private var showAddProspect: Bool = false
    @State private var showClaimTerritory: Bool = false
    @State private var copiedReferralLink: Bool = false
    @State private var approveTarget: WhisperMeetingsService.MeetingRow?
    @State private var denyTarget: WhisperMeetingsService.MeetingRow?
    @State private var selectedPitchAudience: WhisperPitchAudience?
    @State private var presentQRApplicant: Bool = false
    @State private var showMap: Bool = false
    @State private var showPitch: Bool = false
    @State private var showTargets: Bool = false
    @State private var showPromote: Bool = false
    @State private var showAllMeetings: Bool = false

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var cardBG: Color { WhisperTheme.card(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }
    /// #7059E8 — the recruiter violet the web portal wears.
    private var hqViolet: Color { Color(red: 0.439, green: 0.349, blue: 0.910) }
    private var good: Color { Color(red: 0.13, green: 0.65, blue: 0.36) }
    private var warn: Color { Color(red: 0.96, green: 0.62, blue: 0.04) }
    private var bad: Color { Color(red: 0.91, green: 0.30, blue: 0.24) }

    /// One canonical invite-link shape everywhere — identical to the
    /// profile's creator link (`/auth?mode=signup&code=CODE`) so a recruiter's
    /// shared link never differs from their profile invite link.
    private func referralLink(for code: String) -> String {
        "\(WhisperBillingBackend.webOrigin)/auth?mode=signup&code=\(code)"
    }

    // MARK: - Derived

    private var activeProspects: [WhisperRecruiterService.ProspectRow] {
        recruiter.prospects.filter { $0.status != "passed" }
    }

    private var passedProspects: [WhisperRecruiterService.ProspectRow] {
        recruiter.prospects.filter { $0.status == "passed" }
    }

    private var signedThisMonth: Int {
        recruiter.monthPromotionCounts().values.reduce(0, +)
    }

    private var goalTotal: Int {
        guard let t = recruiter.target else { return 0 }
        return t.target_coach + t.target_athlete + t.target_creator
    }

    private enum DueState { case overdue, today, upcoming, later, none }

    private func dueState(_ p: WhisperRecruiterService.ProspectRow) -> DueState {
        guard p.next_action?.isEmpty == false else { return .none }
        guard let due = WhisperRecruiterService.parseDueDate(p.next_action_due) else { return .later }
        let cal = Calendar.current
        if cal.isDateInToday(due) { return .today }
        if due < cal.startOfDay(for: Date()) { return .overdue }
        if let horizon = cal.date(byAdding: .day, value: 7, to: Date()), due <= horizon {
            return .upcoming
        }
        return .later
    }

    private var overdueRows: [WhisperRecruiterService.ProspectRow] {
        activeProspects.filter { dueState($0) == .overdue }
    }
    private var dueTodayRows: [WhisperRecruiterService.ProspectRow] {
        activeProspects.filter { dueState($0) == .today }
    }
    private var upcomingRows: [WhisperRecruiterService.ProspectRow] {
        activeProspects.filter { dueState($0) == .upcoming || dueState($0) == .later }
    }
    private var noStepRows: [WhisperRecruiterService.ProspectRow] {
        activeProspects.filter { dueState($0) == .none }
    }

    private var pendingMeetingCount: Int {
        meetings.requests.filter { $0.status == "pending" }.count
    }

    private var newApplicationCount: Int {
        recruiter.applications.filter { !recruiter.isApplicationInPipeline($0) }.count
    }

    private func tabBadge(_ t: HQTab) -> Int {
        switch t {
        case .today: return overdueRows.count + dueTodayRows.count
        case .inbox: return pendingMeetingCount + newApplicationCount
        default: return 0
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 0) {
                    heroPanel
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    tabChips
                        .padding(.top, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch tab {
                            case .today: todayTab
                            case .pipeline: pipelineTab
                            case .people: peopleTab
                            case .inbox: inboxTab
                            case .insights: insightsTab
                            case .grow: growTab
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, tab == .today ? 120 : 40)
                    }
                }
            }
            .navigationTitle("Recruiter HQ")
            .navigationBarTitleDisplayMode(.inline)
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
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showAddProspect = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .accessibilityLabel("Add prospect")
                }
            }
            .overlay(alignment: .bottom) {
                if tab == .today {
                    JasperAnalysisDock(
                        pillLabel: "Knot's read",
                        boxTitle: "Pipeline analysis",
                        focus: """
                        You are analyzing a recruiter's live pipeline. From the numbers and prospects below, give a tight read: who is HOT (ready or in meetings) and the single best next contact, anything going stale, then ONE concrete next move for this week. Use the actual usernames.
                        """,
                        buildContext: { recruiterAnalysisContext() },
                        emptyText: "No prospects yet — add your first prospect and I'll analyze the pipeline here.",
                        actions: [
                            JasperDockAction(
                                id: "rank",
                                label: "Rank pipeline",
                                icon: "list.number",
                                kind: .lens("Stack-rank every prospect below from hottest to coldest — one line each: rank, @handle, why they sit there (status + meetings), and the exact next touch. Use only the listed prospects.")
                            ),
                            JasperDockAction(
                                id: "outreach",
                                label: "Outreach drafts",
                                icon: "text.bubble",
                                kind: .lens("Write 2 short copy-ready outreach DMs for the two prospects most worth contacting right now. Format: @handle — then the message in quotes. Warm, specific to their status, no hard sell, under 40 words each.")
                            ),
                            JasperDockAction(
                                id: "stale",
                                label: "Stale leads",
                                icon: "clock.arrow.circlepath",
                                kind: .lens("From the pipeline below, name the prospects going STALE (no movement, stuck status) — one line each with the revival move. If nothing is stale, say the pipeline is moving and name the freshest lead.")
                            ),
                        ]
                    )
                    .padding(.bottom, 10)
                }
            }
            .task {
                await recruiter.refreshMyStatus()
                await recruiter.refreshAll()
                await meetings.refresh()
                await recruiter.refreshMyReviews()
            }
            .sheet(item: $selectedProspect) { prospect in
                WhisperRecruiterPersonSheet(prospectID: prospect.id)
                    .whisperSheetBorder()
            }
            .sheet(isPresented: $showAddProspect) {
                WhisperRecruiterAddProspectSheet()
                    .whisperSheetBorder()
            }
            .sheet(isPresented: $showClaimTerritory) {
                WhisperRecruiterClaimTerritorySheet()
                    .whisperSheetBorder()
            }
            .sheet(item: $approveTarget) { row in
                WhisperMeetingApproveSheet(row: row)
                    .whisperSheetBorder()
            }
            .sheet(item: $denyTarget) { row in
                WhisperMeetingDenySheet(row: row)
                    .whisperSheetBorder()
            }
            .sheet(isPresented: $presentQRApplicant) {
                WhisperQRApplicantView()
            }
            .sheet(isPresented: $showMap) {
                mapSheet
            }
            .sheet(isPresented: $showPitch) {
                pitchSheet
            }
            .sheet(isPresented: $showTargets) {
                targetsSheet
            }
            .sheet(isPresented: $showPromote) {
                promoteSheet
            }
        }
    }

    // MARK: - Hero (violet panel — web parity)

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECRUITER HQ")
                        .font(.system(size: 10, weight: .black))
                        .tracking(2)
                        .foregroundStyle(hqViolet)
                    Text("Talent desk")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                }
                Spacer()
                goalRing(size: 46, lineWidth: 5)
            }
            HStack(spacing: 8) {
                statTile("\(activeProspects.count)", "Active")
                statTile("\(recruiter.prospects.filter { $0.status == "ready" }.count)", "Offer")
                statTile("\(recruiter.promotions.count)", "Signed")
                statTile("\(recruiter.referralCode?.uses ?? 0)", "Signups")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBG)
                .overlay {
                    LinearGradient(
                        colors: [hqViolet.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(hqViolet.opacity(0.25), lineWidth: 1)
        }
    }

    private func goalRing(size: CGFloat, lineWidth: CGFloat) -> some View {
        let progress: Double = goalTotal > 0
            ? min(1, Double(signedThisMonth) / Double(goalTotal))
            : 0
        return ZStack {
            Circle()
                .stroke(hqViolet.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(hqViolet, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: progress)
            VStack(spacing: 0) {
                Text("\(signedThisMonth)")
                    .font(.system(size: size * 0.32, weight: .black, design: .rounded))
                    .foregroundStyle(ink)
                Text(goalTotal > 0 ? "of \(goalTotal)" : "signed")
                    .font(.system(size: size * 0.17, weight: .bold))
                    .foregroundStyle(muted)
            }
        }
        .frame(width: size, height: size)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(WhisperTheme.surface(colorScheme).opacity(0.6), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(hairline, lineWidth: 0.5)
        }
    }

    // MARK: - Tab chips

    private var tabChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(HQTab.allCases) { t in
                    let active = tab == t
                    let badge = tabBadge(t)
                    Button {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) { tab = t }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(t.label)
                                .font(.system(size: 13, weight: .bold))
                            if badge > 0 {
                                Text("\(badge)")
                                    .font(.system(size: 10, weight: .black).monospacedDigit())
                                    .foregroundStyle(active ? hqViolet : .white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(active ? .white : bad, in: Capsule())
                            }
                        }
                        .foregroundStyle(active ? .white : ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(active ? hqViolet : cardBG, in: Capsule())
                        .overlay {
                            if !active {
                                Capsule().strokeBorder(hairline, lineWidth: 1)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - TODAY

    @ViewBuilder
    private var todayTab: some View {
        let relationshipFollowUps = activeProspects.filter { recruiter.clientProfile($0.id)?.followUp.isEmpty == false }
        if !relationshipFollowUps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Private relationship follow-ups").font(.headline)
                ForEach(relationshipFollowUps) { p in
                    Button { selectedProspect = p } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.prospect_display_name ?? p.prospect_username ?? "Prospect").font(.subheadline.bold())
                            Text(recruiter.clientProfile(p.id)?.followUp ?? "").font(.subheadline)
                            Text((recruiter.clientProfile(p.id)?.followUpDue).flatMap { $0.isEmpty ? nil : $0 } ?? "No due date").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12).background(cardBG, in: .rect(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
        }
        if !recruiter.v4Available {
            v4Banner
        }
        if activeProspects.isEmpty {
            emptyCard(
                icon: "binoculars",
                title: "No prospects yet",
                subtitle: "Add the talented people you find and Today becomes your work queue — who to touch, in order."
            )
        } else {
            let clear = overdueRows.isEmpty && dueTodayRows.isEmpty && upcomingRows.isEmpty && noStepRows.isEmpty
            if clear {
                emptyCard(
                    icon: "checkmark.seal.fill",
                    title: "Queue clear",
                    subtitle: "Every active prospect has a next step and nothing is due. Go find more talent."
                )
            }
            if !overdueRows.isEmpty {
                queueSection("Overdue", tint: bad, rows: overdueRows)
            }
            if !dueTodayRows.isEmpty {
                queueSection("Due today", tint: warn, rows: dueTodayRows)
            }
            if !upcomingRows.isEmpty {
                queueSection("Coming up", tint: hqViolet, rows: upcomingRows)
            }
            if !noStepRows.isEmpty {
                noStepSection
            }
        }
    }

    private var v4Banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(warn)
            Text("Run supabase/recruiting-v4.sql once to unlock next steps, tags, scorecards & timelines.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warn.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(warn.opacity(0.35), lineWidth: 1)
        }
    }

    private func queueSection(
        _ title: String,
        tint: Color,
        rows: [WhisperRecruiterService.ProspectRow]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                sectionTitle(title)
                Text("\(rows.count)")
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(tint)
                Spacer()
            }
            VStack(spacing: 8) {
                ForEach(rows) { p in
                    todayRow(p, tint: tint)
                }
            }
        }
    }

    private func todayRow(_ p: WhisperRecruiterService.ProspectRow, tint: Color) -> some View {
        Button {
            Haptics.tap()
            selectedProspect = p
        } label: {
            HStack(spacing: 10) {
                WhisperAvatar(
                    username: p.prospect_username ?? p.prospect_display_name ?? "?",
                    size: 38,
                    imageURL: p.prospect_image_url.flatMap(URL.init(string:)),
                    ring: false
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.prospect_display_name ?? p.prospect_username ?? "Prospect")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        stageChip(p.status)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                        Text(p.next_action ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink.opacity(0.85))
                            .lineLimit(1)
                        if let due = WhisperRecruiterService.parseDueDate(p.next_action_due) {
                            Text(due.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(tint)
                        }
                    }
                }
                Spacer(minLength: 6)
                Button {
                    Haptics.success()
                    Task {
                        await recruiter.logActivity(
                            prospectID: p.id,
                            kind: "task",
                            body: "Did: \(p.next_action ?? "next step")"
                        )
                        _ = await recruiter.updateNextAction(p, action: nil, due: nil)
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(good)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark done")
                Button {
                    Haptics.tap()
                    let base = WhisperRecruiterService.parseDueDate(p.next_action_due) ?? Date()
                    let snoozed = Calendar.current.date(byAdding: .day, value: 3, to: base) ?? base
                    Task {
                        _ = await recruiter.updateNextAction(p, action: p.next_action, due: snoozed)
                    }
                } label: {
                    Text("+3d")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Snooze 3 days")
            }
            .padding(12)
            .background(cardBG, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var noStepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(muted.opacity(0.5)).frame(width: 7, height: 7)
                sectionTitle("No next step")
                Text("\(noStepRows.count)")
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(muted)
                Spacer()
            }
            Text("The #1 CRM rule: every active person carries a next step.")
                .font(.caption2)
                .foregroundStyle(muted)
            VStack(spacing: 8) {
                ForEach(noStepRows.prefix(8)) { p in
                    Button {
                        Haptics.tap()
                        selectedProspect = p
                    } label: {
                        HStack(spacing: 10) {
                            WhisperAvatar(
                                username: p.prospect_username ?? p.prospect_display_name ?? "?",
                                size: 34,
                                imageURL: p.prospect_image_url.flatMap(URL.init(string:)),
                                ring: false
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.prospect_display_name ?? p.prospect_username ?? "Prospect")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                stageChip(p.status)
                            }
                            Spacer(minLength: 6)
                            Text("Set step")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(hqViolet)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(hqViolet.opacity(0.12), in: Capsule())
                        }
                        .padding(12)
                        .background(cardBG, in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func stageChip(_ status: String) -> some View {
        let color = WhisperRecruiterService.statusColor(status)
        return Text(WhisperRecruiterService.stageLabel(status))
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())
    }

    // MARK: - PIPELINE

    @ViewBuilder
    private var pipelineTab: some View {
        relationshipControls
        stageSelector
        let inStage = activeProspects
            .filter { $0.status == selectedStage && matchesRelationship($0) }
            .sorted { ($0.updated_at ?? "") > ($1.updated_at ?? "") }
        if inStage.isEmpty {
            emptyCard(
                icon: "tray",
                title: "Nobody in \(WhisperRecruiterService.stageLabel(selectedStage))",
                subtitle: selectedStage == "discovered"
                    ? "Add a prospect with + and they start here."
                    : "Advance people into this stage from the earlier ones."
            )
        } else {
            VStack(spacing: 8) {
                ForEach(inStage) { p in
                    pipelineRow(p)
                }
            }
        }
        signedStrip
        if !passedProspects.isEmpty {
            passedArchive
        }
    }

    private var relationshipControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("My private list", systemImage: "lock").font(.subheadline.bold())
                Spacer()
                Button("Team pipeline") { showTeamPipeline = true }.frame(minHeight: 44)
            }
            Picker("Relationship view", selection: $relationshipFilter) {
                ForEach(["All people", "Overdue", "Stalled", "Upcoming meetings", "Recently promoted"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
            Text("Stalled: 8+ days in a recorded stage. Older stage dates are unknown. Promotions are role changes, not contracts.").font(.caption).foregroundStyle(.secondary)
            if let error = recruiter.clientMetadataError { Text(error).font(.caption).foregroundStyle(.red); Button("Retry private details") { Task { await recruiter.refreshClientMetadata() } } }
            RecruiterPromotionRecordsView().id(AccountStorage.generation)
        }
        .sheet(isPresented: $showTeamPipeline) {
            NavigationStack {
                ScrollView { RecruiterTeamPipelineView().padding(16) }
                    .navigationTitle("Team pipeline")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTeamPipeline = false } } }
            }.id(AccountStorage.generation)
        }
    }
    private func matchesRelationship(_ p: WhisperRecruiterService.ProspectRow) -> Bool {
        let profile = recruiter.clientProfile(p.id)
        switch relationshipFilter {
        case "Overdue":
            let due = profile?.followUp.isEmpty == false ? profile?.followUpDue : p.next_action_due
            guard p.status != "passed", let date = WhisperRecruiterService.parseDueDate(due) else { return false }
            return date < Calendar.current.startOfDay(for: Date())
        case "Stalled": return p.status != "passed" && (profile?.stageAge(status: p.status) ?? -1) >= 8
        case "Upcoming meetings": return p.status != "passed" && (WhisperBackendService.parseISO(profile?.nextMeetingAt ?? "") ?? .distantPast) >= Date()
        case "Recently promoted": return recruiter.promotions.contains { row in
            let matches = row.promoted_id == p.prospect_user_id || (p.prospect_username != nil && row.promoted_username.lowercased() == p.prospect_username?.lowercased())
            return matches && (WhisperBackendService.parseISO(row.created_at ?? "") ?? .distantPast) >= Date().addingTimeInterval(-30 * 86400)
        }
        default: return true
        }
    }
    private var stageSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WhisperRecruiterService.stageLabels, id: \.value) { stage in
                    let count = activeProspects.filter { $0.status == stage.value }.count
                    let active = selectedStage == stage.value
                    let color = WhisperRecruiterService.statusColor(stage.value)
                    Button {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) { selectedStage = stage.value }
                    } label: {
                        HStack(spacing: 5) {
                            Text(stage.label)
                                .font(.system(size: 12, weight: .bold))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .black).monospacedDigit())
                                .foregroundStyle(active ? .white.opacity(0.85) : color)
                        }
                        .foregroundStyle(active ? .white : ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(active ? color : color.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    /// Aging dot — green under 4 days, amber under 8, red 8+ (web parity).
    private func agingColor(_ days: Int) -> Color {
        if days < 4 { return good }
        if days < 8 { return warn }
        return bad
    }

    private func pipelineRow(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        let days = recruiter.clientProfile(p.id)?.stageAge(status: p.status)
        let stageIdx = WhisperRecruiterService.stageLabels.firstIndex { $0.value == p.status }
        let nextStage: (value: String, label: String)? = {
            guard let stageIdx, stageIdx + 1 < WhisperRecruiterService.stageLabels.count else { return nil }
            return WhisperRecruiterService.stageLabels[stageIdx + 1]
        }()
        return Button {
            Haptics.tap()
            selectedProspect = p
        } label: {
            HStack(spacing: 10) {
                WhisperAvatar(
                    username: p.prospect_username ?? p.prospect_display_name ?? "?",
                    size: 40,
                    imageURL: p.prospect_image_url.flatMap(URL.init(string:)),
                    ring: false
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.prospect_display_name ?? p.prospect_username ?? "Prospect")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let source = p.source, !source.isEmpty {
                            Text(source)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(muted.opacity(0.10), in: Capsule())
                        }
                        HStack(spacing: 3) {
                            Circle().fill(days.map(agingColor) ?? muted).frame(width: 6, height: 6)
                            Text(days.map { "\($0)d" } ?? "Stage date unknown")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(muted)
                        }
                        if let score = WhisperRecruiterService.compositeScore(p.scorecard) {
                            Text("\(score)")
                                .font(.system(size: 10, weight: .black).monospacedDigit())
                                .foregroundStyle(hqViolet)
                        }
                    }
                }
                Spacer(minLength: 6)
                if p.status == "ready" {
                    Button {
                        Haptics.success()
                        selectedProspect = p
                    } label: {
                        Text("Sign")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(good, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if let nextStage {
                    Button {
                        Haptics.tap()
                        Task { await recruiter.updateProspectStatus(p, status: nextStage.value) }
                    } label: {
                        HStack(spacing: 3) {
                            Text(nextStage.label)
                                .font(.caption2.weight(.bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .black))
                        }
                        .foregroundStyle(hqViolet)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(hqViolet.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Advance to \(nextStage.label)")
                }
                Button {
                    Haptics.warning()
                    Task { await recruiter.updateProspectStatus(p, status: "passed") }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(muted.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(WhisperTheme.surface(colorScheme), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pass")
            }
            .padding(11)
            .background(cardBG, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(hairline, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var signedStrip: some View {
        let recent = recruiter.promotions.prefix(3).map { "@\($0.promoted_username)" }
        return HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.body)
                .foregroundStyle(good)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(recruiter.promotions.count) recorded role promotions")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                if !recent.isEmpty {
                    Text(recent.joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                Haptics.tap()
                showPromote = true
            } label: {
                Text("Promote")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(good)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(good.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(good.opacity(0.07), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(good.opacity(0.3), lineWidth: 1)
        }
    }

    private var passedArchive: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(.whisperSnappy) { showPassedArchive.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(muted)
                    Text("Passed · \(passedProspects.count)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(muted)
                    Spacer()
                    Image(systemName: showPassedArchive ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(cardBG, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(hairline, lineWidth: 1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showPassedArchive {
                VStack(spacing: 6) {
                    ForEach(passedProspects) { p in
                        HStack(spacing: 10) {
                            WhisperAvatar(
                                username: p.prospect_username ?? p.prospect_display_name ?? "?",
                                size: 30,
                                imageURL: p.prospect_image_url.flatMap(URL.init(string:)),
                                ring: false
                            )
                            Text(p.prospect_display_name ?? p.prospect_username ?? "Prospect")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(muted)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                Haptics.tap()
                                Task { await recruiter.updateProspectStatus(p, status: "discovered") }
                            } label: {
                                Text("Bring back")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(hqViolet)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(cardBG.opacity(0.6), in: .rect(cornerRadius: 10))
                    }
                }
            }
        }
    }

    // MARK: - PEOPLE

    private var allTags: [String] {
        var set = Set<String>()
        for p in recruiter.prospects {
            for t in p.tags ?? [] { set.insert(t) }
        }
        return set.sorted()
    }

    private var filteredPeople: [WhisperRecruiterService.ProspectRow] {
        let q = peopleQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return recruiter.prospects.filter { p in
            guard matchesRelationship(p) else { return false }
            if let tag = selectedTag, !(p.tags ?? []).contains(tag) { return false }
            guard !q.isEmpty else { return true }
            let hay = [
                p.prospect_display_name, p.prospect_username, p.niche,
                p.location, p.source, p.instagram
            ].compactMap { $0?.lowercased() }.joined(separator: " ")
                + " " + (p.tags ?? []).joined(separator: " ")
            return hay.contains(q)
        }
    }

    @ViewBuilder
    private var peopleTab: some View {
        relationshipControls
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(muted)
            TextField("Search people, niches, sources…", text: $peopleQuery)
                .font(.subheadline)
                .foregroundStyle(ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !peopleQuery.isEmpty {
                Button {
                    peopleQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(cardBG, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(hairline, lineWidth: 1)
        }

        if !allTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tagChip(nil, label: "All")
                    ForEach(allTags, id: \.self) { tag in
                        tagChip(tag, label: "#\(tag)")
                    }
                }
            }
            .scrollClipDisabled()
        }

        if filteredPeople.isEmpty {
            emptyCard(
                icon: "person.crop.circle.badge.questionmark",
                title: recruiter.prospects.isEmpty ? "Your talent pool is empty" : "No matches",
                subtitle: recruiter.prospects.isEmpty
                    ? "Every prospect you add joins the pool — searchable by name, niche, source, and #tags."
                    : "Try a different search or clear the tag filter."
            )
        } else {
            VStack(spacing: 8) {
                ForEach(filteredPeople) { p in
                    peopleRow(p)
                }
            }
        }
    }

    private func tagChip(_ tag: String?, label: String) -> some View {
        let active = selectedTag == tag
        return Button {
            Haptics.tap()
            withAnimation(.whisperSnappy) { selectedTag = tag }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? .white : ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(active ? hqViolet : cardBG, in: Capsule())
                .overlay {
                    if !active {
                        Capsule().strokeBorder(hairline, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func peopleRow(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        Button {
            Haptics.tap()
            selectedProspect = p
        } label: {
            HStack(spacing: 10) {
                WhisperAvatar(
                    username: p.prospect_username ?? p.prospect_display_name ?? "?",
                    size: 40,
                    imageURL: p.prospect_image_url.flatMap(URL.init(string:)),
                    ring: false
                )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(p.prospect_display_name ?? p.prospect_username ?? "Prospect")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(p.status == "passed" ? muted : ink)
                            .lineLimit(1)
                        stageChip(p.status)
                    }
                    HStack(spacing: 5) {
                        if let niche = p.niche, !niche.isEmpty {
                            Text(niche)
                                .font(.caption2)
                                .foregroundStyle(muted)
                                .lineLimit(1)
                        }
                        ForEach((p.tags ?? []).prefix(2), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(hqViolet)
                        }
                        if (p.tags ?? []).count > 2 {
                            Text("+\((p.tags ?? []).count - 2)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(muted)
                        }
                    }
                }
                Spacer(minLength: 6)
                if let score = WhisperRecruiterService.compositeScore(p.scorecard) {
                    VStack(spacing: 0) {
                        Text("\(score)")
                            .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(hqViolet)
                        Text("SCORE")
                            .font(.system(size: 7, weight: .black))
                            .tracking(0.5)
                            .foregroundStyle(muted)
                    }
                } else if let rating = p.rating, rating > 0 {
                    HStack(spacing: 1) {
                        ForEach(0..<min(rating, 5), id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(warn)
                        }
                    }
                }
            }
            .padding(11)
            .background(cardBG, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(hairline, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - INBOX

    @ViewBuilder
    private var inboxTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Applications")
                Spacer()
                Button {
                    Haptics.tap()
                    presentQRApplicant = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode")
                            .font(.caption.weight(.bold))
                        Text("Your QR")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(hqViolet)
                }
                .buttonStyle(.plain)
            }
            if recruiter.applications.isEmpty {
                emptyCard(
                    icon: "doc.text.magnifyingglass",
                    title: "No applications yet",
                    subtitle: "Share your QR code — every questionnaire lands here, scored and ready to file."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(recruiter.applications) { app in
                        applicationRow(app)
                    }
                }
            }
        }

        if !meetings.requests.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("Meeting requests")
                    Spacer()
                    if meetings.requests.count > visibleMeetingRequests.count || showAllMeetings {
                        Button {
                            Haptics.tap()
                            withAnimation(.whisperSnappy) { showAllMeetings.toggle() }
                        } label: {
                            Text(showAllMeetings ? "Pending only" : "Show all")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(visibleMeetingRequests, id: \.id) { req in
                    WhisperMeetingRequestCard(
                        row: req,
                        onApprove: { approveTarget = req },
                        onDeny: { denyTarget = req }
                    )
                }
                if visibleMeetingRequests.isEmpty {
                    Text("No pending requests — approved and past meetings live under Show all.")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
            }
        }
    }

    private var visibleMeetingRequests: [WhisperMeetingsService.MeetingRow] {
        let pending = meetings.requests.filter { $0.status == "pending" }
        if showAllMeetings { return meetings.requests }
        return pending
    }

    private func applicationRow(_ app: WhisperRecruiterService.ApplicationRow) -> some View {
        let inPipeline = recruiter.isApplicationInPipeline(app)
        let busy = appWorking.contains(app.id)
        return HStack(spacing: 10) {
            WhisperAvatar(username: app.applicant_name ?? "?", size: 38, ring: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.applicant_name ?? "Applicant")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let role = app.best_position, !role.isEmpty {
                        Text(role.capitalized)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(hqViolet)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(hqViolet.opacity(0.12), in: Capsule())
                    }
                    if let score = app.potential_score {
                        Text("potential \(score)/100")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(muted)
                    }
                }
            }
            Spacer(minLength: 6)
            if inPipeline {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                    Text("In pipeline")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(good)
            } else {
                Button {
                    Haptics.tap()
                    appWorking.insert(app.id)
                    Task {
                        _ = await recruiter.addApplicationToPipeline(app)
                        appWorking.remove(app.id)
                    }
                } label: {
                    Group {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Text("Add to pipeline")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(hqViolet, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(11)
        .background(cardBG, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hairline, lineWidth: 1)
        }
    }

    // MARK: - INSIGHTS

    @ViewBuilder
    private var insightsTab: some View {
        goalCard
        HStack(spacing: 8) {
            insightTile(
                value: avgDaysToSign.map { "\($0)d" } ?? "—",
                label: "Avg days to sign"
            )
            insightTile(value: "\(signedThisMonth)", label: "Signed this month")
            insightTile(value: "\(recruiter.promotions.count)", label: "Signed all-time")
        }
        weeklyBarsCard
        sourceCard
        if !recruiter.prospects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Stage funnel")
                funnelCard
            }
        }
    }

    private var goalCard: some View {
        HStack(spacing: 16) {
            goalRing(size: 72, lineWidth: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(goalTotal > 0
                    ? "\(signedThisMonth) of \(goalTotal) signed this month"
                    : "No monthly goal set")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                Text(goalTotal > 0
                    ? "Coach \(recruiter.target?.target_coach ?? 0) · Athlete \(recruiter.target?.target_athlete ?? 0) · Creator \(recruiter.target?.target_creator ?? 0)"
                    : "Set per-role targets and the ring tracks your signs.")
                    .font(.caption)
                    .foregroundStyle(muted)
                Button {
                    Haptics.tap()
                    showTargets = true
                } label: {
                    Text(goalTotal > 0 ? "Edit goal" : "Set goal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(hqViolet)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(hqViolet.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    private func insightTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundStyle(ink)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(cardBG, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    /// Average days from a prospect entering the pipeline to their
    /// promotion — matched by linked account or username.
    private var avgDaysToSign: Int? {
        var spans: [Double] = []
        for promo in recruiter.promotions {
            guard let promoDate = WhisperBackendService.parseISO(promo.created_at ?? "") else { continue }
            let match = recruiter.prospects.first { p in
                if let uid = p.prospect_user_id, uid == promo.promoted_id { return true }
                guard let uname = p.prospect_username else { return false }
                return uname.caseInsensitiveCompare(promo.promoted_username) == .orderedSame
            }
            guard let match,
                  let start = WhisperBackendService.parseISO(match.created_at ?? "") else { continue }
            let days = promoDate.timeIntervalSince(start) / 86_400
            if days >= 0 { spans.append(days) }
        }
        guard !spans.isEmpty else { return nil }
        return Int((spans.reduce(0, +) / Double(spans.count)).rounded())
    }

    /// Promotions per week for the last 8 ISO weeks, oldest first.
    private var weeklySigns: [(label: String, count: Int)] {
        let cal = Calendar.current
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var buckets: [(Date, Int)] = []
        for i in stride(from: 7, through: 0, by: -1) {
            guard let start = cal.date(byAdding: .weekOfYear, value: -i, to: thisWeekStart) else { continue }
            buckets.append((start, 0))
        }
        for promo in recruiter.promotions {
            guard let date = WhisperBackendService.parseISO(promo.created_at ?? "") else { continue }
            for idx in buckets.indices {
                let start = buckets[idx].0
                guard let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
                if date >= start && date < end {
                    buckets[idx].1 += 1
                    break
                }
            }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return buckets.map { (fmt.string(from: $0.0), $0.1) }
    }

    private var weeklyBarsCard: some View {
        let data = weeklySigns
        let maxCount = max(data.map(\.count).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Signings · last 8 weeks")
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 4) {
                        Text(item.count > 0 ? "\(item.count)" : "")
                            .font(.system(size: 9, weight: .black).monospacedDigit())
                            .foregroundStyle(hqViolet)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.count > 0 ? hqViolet : hairline.opacity(0.5))
                            .frame(height: max(6, 52 * CGFloat(item.count) / CGFloat(maxCount)))
                        Text(item.label)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    private func prospectIsSigned(_ p: WhisperRecruiterService.ProspectRow) -> Bool {
        recruiter.promotions.contains { promo in
            if let uid = p.prospect_user_id, uid == promo.promoted_id { return true }
            guard let uname = p.prospect_username else { return false }
            return uname.caseInsensitiveCompare(promo.promoted_username) == .orderedSame
        }
    }

    /// Top sources by volume with added vs signed — web parity.
    private var sourceStats: [(source: String, added: Int, signed: Int)] {
        var map: [String: (added: Int, signed: Int)] = [:]
        for p in recruiter.prospects {
            let key = (p.source?.isEmpty == false ? p.source! : "manual").lowercased()
            var entry = map[key] ?? (0, 0)
            entry.added += 1
            if prospectIsSigned(p) { entry.signed += 1 }
            map[key] = entry
        }
        return map.map { (source: $0.key, added: $0.value.added, signed: $0.value.signed) }
            .sorted { $0.added > $1.added }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder
    private var sourceCard: some View {
        let stats = sourceStats
        if !stats.isEmpty {
            let maxAdded = max(stats.map(\.added).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Source effectiveness")
                ForEach(stats, id: \.source) { stat in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(stat.source.capitalized)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ink)
                            Spacer()
                            Text("\(stat.added) added · \(stat.signed) signed")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(muted)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(hairline.opacity(0.4))
                                Capsule()
                                    .fill(hqViolet.opacity(0.4))
                                    .frame(width: max(4, geo.size.width * CGFloat(stat.added) / CGFloat(maxAdded)))
                                Capsule()
                                    .fill(good)
                                    .frame(width: max(stat.signed > 0 ? 4 : 0, geo.size.width * CGFloat(stat.signed) / CGFloat(maxAdded)))
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
            .padding(14)
            .background(cardBG, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(hairline, lineWidth: 0.75)
            }
        }
    }

    private var funnelCard: some View {
        let stages: [(label: String, count: Int, color: Color)] = {
            var counts: [String: Int] = [:]
            for p in recruiter.prospects where p.status != "passed" {
                counts[p.status, default: 0] += 1
            }
            return [
                ("Sourced", counts["discovered"] ?? 0, WhisperRecruiterService.statusColor("discovered")),
                ("Contacted", counts["contacted"] ?? 0, WhisperRecruiterService.statusColor("contacted")),
                ("In talks", counts["interested"] ?? 0, WhisperRecruiterService.statusColor("interested")),
                ("Evaluating", counts["meeting"] ?? 0, WhisperRecruiterService.statusColor("meeting")),
                ("Offer", counts["ready"] ?? 0, WhisperRecruiterService.statusColor("ready")),
                ("Signed", recruiter.promotions.count, WhisperRecruiterService.statusColor("ready"))
            ]
        }()
        let maxCount = max(stages.map(\.count).max() ?? 1, 1)
        return VStack(spacing: 8) {
            ForEach(stages, id: \.label) { stage in
                HStack(spacing: 10) {
                    Text(stage.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                        .frame(width: 76, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(hairline.opacity(0.4))
                            Capsule()
                                .fill(stage.color)
                                .frame(width: max(6, geo.size.width * CGFloat(stage.count) / CGFloat(maxCount)))
                        }
                    }
                    .frame(height: 8)
                    Text("\(stage.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(muted)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    // MARK: - GROW

    @ViewBuilder
    private var growTab: some View {
        shareCard
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Territories")
                Spacer()
                Button {
                    Haptics.tap()
                    showClaimTerritory = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("Claim")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            regionGrid
            if recruiter.territories.isEmpty {
                emptyCard(
                    icon: "map",
                    title: "No territories claimed",
                    subtitle: "Claim the regions you scout so the team knows who covers what."
                )
            } else {
                ForEach(recruiter.territories, id: \.id) { territory in
                    territoryRow(territory)
                }
            }
        }
        moreToolsCard
        reviewsBlock
    }

    // MARK: - Jasper dock context

    /// Live pipeline context for the dock — real statuses, real handles.
    private func recruiterAnalysisContext() -> String? {
        let prospects = recruiter.prospects
        guard !prospects.isEmpty || !visibleMeetingRequests.isEmpty else { return nil }
        var lines: [String] = ["RECRUITER PIPELINE (live)"]
        let active = prospects.filter { $0.status != "passed" }
        let ready = prospects.filter { $0.status == "ready" }
        lines.append("Prospects: \(active.count) active · \(ready.count) ready · \(recruiter.promotions.count) promoted · referral signups \(recruiter.referralCode?.uses ?? 0)")
        for prospect in prospects.prefix(12) {
            let name = prospect.prospect_username ?? "unnamed"
            let step = prospect.next_action.map { " · next: \($0)" } ?? " · NO NEXT STEP"
            lines.append("- @\(name) · \(prospect.status)\(step)")
        }
        if !visibleMeetingRequests.isEmpty {
            lines.append("Meeting requests waiting on a decision: \(visibleMeetingRequests.count)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Share card (QR + referral, merged)

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("YOUR CODE")
                    .font(.caption2.weight(.black))
                    .tracking(1.6)
                    .foregroundStyle(muted)
                Spacer()
                if let code = recruiter.referralCode {
                    Text("\(code.uses) signup\(code.uses == 1 ? "" : "s")")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(muted)
                }
            }
            if let code = recruiter.referralCode {
                let link = referralLink(for: code.code)
                HStack {
                    Text(code.code)
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(ink)
                    Spacer()
                    Button {
                        Haptics.tap()
                        presentQRApplicant = true
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ink)
                            .frame(width: 40, height: 40)
                            .background(ink.opacity(0.06), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    ShareLink(
                        item: URL(string: link) ?? URL(string: "https://mydailywhisper.com")!,
                        message: Text("Use my code \(code.code) to join Whisper — the fitness social network where talent gets discovered.")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ink)
                            .frame(width: 40, height: 40)
                            .background(ink.opacity(0.06), in: .rect(cornerRadius: 12))
                    }
                }
                Button {
                    UIPasteboard.general.string = link
                    copiedReferralLink = true
                    Haptics.success()
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedReferralLink = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(muted)
                        Text(link.replacingOccurrences(of: "https://", with: ""))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: copiedReferralLink ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(copiedReferralLink ? good : muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                Text("Scan or share — prospects sign up with your code and land in your pipeline automatically.")
                    .font(.caption)
                    .foregroundStyle(muted)
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(muted)
                    Text("Loading your code…")
                        .font(.footnote)
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            }
        }
        .padding(16)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    // MARK: - Reviews

    private var reviewsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Reputation")
            if let summary = recruiter.myReviews {
                reviewsSummaryCard(summary)
                if !summary.reviews.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(summary.reviews) { review in
                            reviewRow(review)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(muted)
                    Text("Loading reviews…")
                        .font(.subheadline)
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .background(cardBG, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(hairline, lineWidth: 0.75)
                }
            }
        }
    }

    private func reviewsSummaryCard(_ summary: WhisperRecruiterService.ReviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.averageRating != nil ? String(format: "%.1f", summary.averageRating!) : "—")
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(ink)
                    Text("\(summary.reviewCount) review\(summary.reviewCount == 1 ? "" : "s")")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(muted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                        let matches = summary.reviews.filter { $0.rating == star }.count
                        let pct = summary.reviewCount > 0 ? CGFloat(matches) / CGFloat(summary.reviewCount) : 0
                        HStack(spacing: 4) {
                            Text("\(star)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(muted)
                                .frame(width: 10)
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(red: 0.96, green: 0.65, blue: 0.14))
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(hairline.opacity(0.4))
                                    Capsule().fill(Color(red: 0.96, green: 0.65, blue: 0.14))
                                        .frame(width: max(2, geo.size.width * pct))
                                }
                            }
                            .frame(width: 80, height: 6)
                        }
                    }
                }
            }
            if summary.positiveCount + summary.negativeCount > 0 {
                HStack(spacing: 8) {
                    sentimentPill(count: summary.positiveCount, label: "Positive", color: good)
                    sentimentPill(count: summary.negativeCount, label: "Needs work", color: bad)
                }
            }
            if summary.reviewCount == 0 {
                Text("People you recruit can rate you after they sign up. Your reputation will show here once reviews come in.")
                    .font(.caption)
                    .foregroundStyle(muted)
            }
        }
        .padding(18)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    private func sentimentPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private func reviewRow(_ review: WhisperRecruiterService.ReviewRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: i < review.rating ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(i < review.rating ? Color(red: 0.96, green: 0.65, blue: 0.14) : muted.opacity(0.3))
                }
                Spacer()
                if let created = review.created_at {
                    Text(WhisperMeetingsService.formatWhen(created))
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
            }
            if let body = review.review, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    // MARK: - More tools

    private var moreToolsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("More tools")
            VStack(spacing: 0) {
                toolRow(
                    icon: "map",
                    title: "Scout map",
                    subtitle: "The globe — territories and team coverage"
                ) { showMap = true }
                Divider().background(hairline).padding(.leading, 62)
                toolRow(
                    icon: "rectangle.on.rectangle.angled",
                    title: "Pitch decks",
                    subtitle: "Walk prospects through live decks"
                ) { showPitch = true }
                Divider().background(hairline).padding(.leading, 62)
                toolRow(
                    icon: "badge.plus.radiowaves.right",
                    title: "Promote a member",
                    subtitle: "Grant coach, athlete or verified status"
                ) { showPromote = true }
            }
            .background(cardBG, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(hairline, lineWidth: 0.75)
            }
        }
    }

    private func toolRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(width: 36, height: 36)
                    .background(ink.opacity(0.06), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
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
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sheets (map / pitch / targets / promote)

    private var mapSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        WhisperRecruiterGlobeView()
                            .background(cardBG, in: .rect(cornerRadius: 18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(hairline, lineWidth: 1)
                            }
                        Text("Territories live on the Grow tab — this globe shows the whole team's coverage.")
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Scout map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { showMap = false }
                        .foregroundStyle(ink)
                }
            }
        }
        .whisperSheetBorder()
    }

    private var pitchSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let audience = selectedPitchAudience {
                            inlinePitchDeck(audience)
                        } else {
                            pitchAudienceList
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Pitch decks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        selectedPitchAudience = nil
                        showPitch = false
                    }
                    .foregroundStyle(ink)
                }
            }
        }
        .whisperSheetBorder()
    }

    private var targetsSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        WhisperRecruiterTargetsSection()
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Monthly targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { showTargets = false }
                        .foregroundStyle(ink)
                }
            }
        }
        .whisperSheetBorder()
    }

    private var promoteSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        WhisperRecruiterPromoteSection()
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Promote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { showPromote = false }
                        .foregroundStyle(ink)
                }
            }
        }
        .whisperSheetBorder()
    }

    // MARK: - Territory pieces

    private var regionGrid: some View {
        let byRegion = Dictionary(grouping: recruiter.territories, by: \.region)
        let rows: [[String]] = [
            ["northwest", "midwest", "northeast"],
            ["west", "southwest", "southeast"],
            ["international", "other"]
        ]
        return VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { region in
                        regionCell(region: region, claimed: byRegion[region] ?? [])
                    }
                }
            }
        }
        .padding(12)
        .background(cardBG, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hairline, lineWidth: 1)
        }
    }

    private func regionCell(region: String, claimed: [WhisperRecruiterService.TerritoryRow]) -> some View {
        let color = WhisperRecruiterService.regionColor(region)
        let active = !claimed.isEmpty
        let prospectTotal = claimed.reduce(0) {
            $0 + WhisperRecruiterService.prospectCount(for: $1, prospects: recruiter.prospects)
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(WhisperRecruiterService.regionLabel(region))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(active ? color : muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if active {
                Text(claimed.first?.name ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.8))
                    .lineLimit(1)
                if claimed.count > 1 {
                    Text("+\(claimed.count - 1) more")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(muted)
                }
                Text("\(prospectTotal) prospect\(prospectTotal == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            } else {
                Text("Unclaimed")
                    .font(.system(size: 9))
                    .foregroundStyle(muted.opacity(0.7))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 74)
        .background(active ? color.opacity(0.1) : Color.clear, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    active ? color.opacity(0.6) : hairline,
                    style: StrokeStyle(lineWidth: 1, dash: active ? [] : [4, 3])
                )
        }
    }

    private func territoryRow(_ territory: WhisperRecruiterService.TerritoryRow) -> some View {
        let color = WhisperRecruiterService.regionColor(territory.region)
        let count = WhisperRecruiterService.prospectCount(for: territory, prospects: recruiter.prospects)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(territory.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                Text("\(WhisperRecruiterService.regionLabel(territory.region))\(territory.cities.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .lineLimit(1)
                Text("\(count) pipeline prospect\(count == 1 ? "" : "s")")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.warning()
                Task { await recruiter.releaseTerritory(territory) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(cardBG, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(hairline, lineWidth: 1)
        }
    }

    // MARK: - Pitch pieces

    /// Inline pitch deck — renders the live web deck inside the sheet with a
    /// back button to return to the audience list.
    private func inlinePitchDeck(_ audience: WhisperPitchAudience) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) { selectedPitchAudience = nil }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                        Text("Decks")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(ink)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(audience.title) deck")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)

                Spacer()

                // Mirror the width of the leading button so the title stays centered.
                Text("Decks")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.clear)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            WhisperNativePitchDeckView(audience: audience)
                .whisperEdgeBack { withAnimation(.whisperSnappy) { selectedPitchAudience = nil } }
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(hairline, lineWidth: 1)
                }
        }
    }

    /// Audience chooser for the pitch sheet.
    private var pitchAudienceList: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Hero — black stage echoing the Pitch Mode hub
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(red: 0.05, green: 0.05, blue: 0.07))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(.caption.weight(.bold))
                        Text("Pitch Mode")
                            .font(.caption.weight(.bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    Text("Walk any prospect through Whisper, live.")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                    Text("Interactive decks for every audience — open one and present from your phone.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(18)
            }
            .clipShape(.rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.10), lineWidth: 1) }

            Text("AUDIENCE DECKS")
                .font(.caption2.weight(.black))
                .tracking(1.6)
                .foregroundStyle(muted)

            VStack(spacing: 10) {
                ForEach(whisperPitchAudiences) { audience in
                    Button {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) { selectedPitchAudience = audience }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(audience.accent.opacity(0.12))
                                Image(systemName: audience.icon)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(audience.accent)
                            }
                            .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(audience.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(ink)
                                Text(audience.tagline)
                                    .font(.caption)
                                    .foregroundStyle(muted)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(muted)
                        }
                        .padding(12)
                        .background(cardBG, in: .rect(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(hairline, lineWidth: 1) }
                        .contentShape(.rect)
                    }
                    .buttonStyle(WhisperMenuPressStyle())
                }
            }
        }
    }

    // MARK: - Building blocks

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.black))
            .tracking(1.6)
            .foregroundStyle(muted)
    }

    private func emptyCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: icon, height: 120)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, style: StrokeStyle(lineWidth: 0.75, dash: [5]))
        }
    }
}

// MARK: - Meeting request card

private struct WhisperMeetingRequestCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let row: WhisperMeetingsService.MeetingRow
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.requester_name.isEmpty ? "Anonymous" : row.requester_name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(row.requester_email)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer(minLength: 0)
                Text(WhisperMeetingsService.statusLabel(row.status))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WhisperMeetingsService.statusColor(row.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WhisperMeetingsService.statusColor(row.status).opacity(0.15), in: Capsule())
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(WhisperMeetingsService.formatWhen(row.requested_time))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if let tz = row.requester_timezone, !tz.isEmpty {
                    Text("· \(tz)")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }

            if let message = row.message, !message.isEmpty {
                Text("\(message)")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.9))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
            }

            if row.status == "approved", let link = row.meeting_link, let url = URL(string: link) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.badge")
                        Text("Meeting link sent")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
            }
            if row.status == "denied", let note = row.recruiter_note, !note.isEmpty {
                Text("You declined: \(note)")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }

            if row.status == "pending" {
                HStack(spacing: 8) {
                    Button {
                        Haptics.tap()
                        onApprove()
                    } label: {
                        Text("Approve")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.tap()
                        onDeny()
                    } label: {
                        Text("Decline")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.clear, in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }
}

// MARK: - Approve sheet

private struct WhisperMeetingApproveSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let row: WhisperMeetingsService.MeetingRow

    @State private var meetingLink: String = ""
    @State private var note: String = ""
    @State private var submitting: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let recipient = row.requester_name.isEmpty ? "them" : row.requester_name
                    Text("Paste the Google Meet link that will be emailed to \(recipient) in a Whisper-branded invite.")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("MEETING LINK")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        TextField("https://meet.google.com/xxx-xxxx-xxx", text: $meetingLink)
                            .textFieldStyle(.plain)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(12)
                            .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTE (OPTIONAL)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        TextEditor(text: $note)
                            .frame(minHeight: 72)
                            .padding(8)
                            .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }

                    Button {
                        guard !meetingLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        Haptics.tap()
                        submitting = true
                        Task {
                            let ok = await WhisperMeetingsService.shared.approve(
                                id: row.id,
                                meetingLink: meetingLink.trimmingCharacters(in: .whitespacesAndNewlines),
                                note: note.isEmpty ? nil : note
                            )
                            submitting = false
                            if ok { dismiss() }
                        }
                    } label: {
                        Group {
                            if submitting {
                                ProgressView().tint(WhisperTheme.surface(colorScheme))
                            } else {
                                Text("Approve & send invite")
                            }
                        }
                        .font(.body.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(submitting || meetingLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
            .navigationTitle("Approve meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }
}

// MARK: - Deny sheet

private struct WhisperMeetingDenySheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let row: WhisperMeetingsService.MeetingRow

    @State private var note: String = ""
    @State private var submitting: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let subject = row.requester_name.isEmpty ? "This person" : row.requester_name
                    Text("\(subject) will be emailed to let them know the meeting won't happen. You can add an optional note.")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTE (OPTIONAL)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        TextEditor(text: $note)
                            .frame(minHeight: 96)
                            .padding(8)
                            .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }

                    Button {
                        Haptics.tap()
                        submitting = true
                        Task {
                            let ok = await WhisperMeetingsService.shared.deny(
                                id: row.id,
                                note: note.isEmpty ? nil : note
                            )
                            submitting = false
                            if ok { dismiss() }
                        }
                    } label: {
                        Group {
                            if submitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Decline & notify")
                            }
                        }
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.91, green: 0.30, blue: 0.24), in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(submitting)
                }
                .padding(16)
            }
            .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
            .navigationTitle("Decline meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }
}
