import SwiftUI

/// Coach-facing dashboard for a single accepted client — THE Jasper API
/// dashboard, nothing else.
///
/// One rule (Aug 17 2026): every health number on this screen comes from
/// `GET /v1/dashboard` through this client's own Connect token — the exact
/// payload Jasper's own coach view renders. There is no legacy snapshot
/// path, no local recomputation, and no mixing: when the API can't be
/// reached the screen says so honestly and offers a retry, it never quietly
/// swaps in stale local numbers. Whisper-native coach features (proposals,
/// DMs, marketplace imports, end coaching) live BELOW the dashboard.
struct WhisperClientHealthView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let client: WhisperCoachRequestRow

    @State private var requests = WhisperCoachRequestService.shared
    @State private var proposals = WhisperCoachProposalService()
    @State private var coachConnect = JasperCoachConnect.shared

    @State private var connectPhase: ClientConnectPhase = .loading
    @State private var showReconnectConfirm: Bool = false
    @State private var reconnectBusy: Bool = false
    @State private var connectBusy = false
    @State private var connectDashboard: JasperClientDashboard?
    @State private var displayedTokenID: UUID?
    /// `?period=week` payload (digest block included) — fetched on first
    /// switch, cached by the same 60s rail as the daily payload.
    @State private var connectWeekDashboard: JasperClientDashboard?
    @State private var showWeekDigest = false
    @State private var weekBusy = false
    /// Change-feed→refresh throttle so a burst of journal events can't
    /// hammer the dashboard endpoint.
    @State private var lastPushRefresh = Date.distantPast
    @State private var skeletonPulse = false

    // Diet plan + groceries ride the SAME dashboard payload
    // (sections.diet_plans.data — byte-identical to the /v1/diet_plans read).
    @State private var connectGroceries: JasperGroceryList?
    @State private var showClientGroceries = false
    @State private var connectDietPlan: JasperDietPlan?
    @State private var showClientDietPlan = false
    /// Today's water off the same payload — drawn as Jasper's own water_cup
    /// look (display-only here; it's the client's glass).
    @State private var connectWaterTodayML: Int?

    @State private var showCoachWalkthrough = false
    @State private var showCoachTools = false
    @State private var showMarketplace = false
    @State private var openThread = false
    @State private var showEndConfirm = false
    @State private var activeProposalKind: ProposalKind?
    @State private var refreshTimer: Timer?

    private let jasperOrange = Color(red: 0.953, green: 0.565, blue: 0.341)

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        dashboardCard
                        coachActionsCard
                        proposalsCard
                        actionsCard
                    }
                    .padding(.bottom, 108)
                    .whisperPadContent()
                }
                .whisperRefreshable { await refreshAll() }
                // Locked in place — the dashboard never rubber-bands when the
                // content already fits; scrolling stays purposeful.
                .scrollBounceBehavior(.basedOnSize)
            }
            .overlay(alignment: .bottom) {
                JasperAnalysisDock(
                    pillLabel: "Quick analysis",
                    boxTitle: "@\(client.client_username) — Knot's read",
                    focus: """
                    You are Knot, the coach's assistant, analyzing ONE client's LIVE Jasper dashboard (the block below is fresh off the one-call API this moment). Give the coach a quick read in 3 tight parts: **Win** — the strongest number right now; **Watch** — the risk or slipping metric; **Next move** — one concrete action for this week. Ground every claim in the numbers below; if a section is missing, say it isn't shared instead of inventing it.
                    """,
                    buildContext: {
                        guard let dash = connectDashboard else { return nil }
                        return WhisperEmberClientContext.dashboardBlock(dash, username: client.client_username)
                    },
                    emptyText: "The live dashboard hasn't loaded yet — pull to refresh, then ask again."
                )
                .padding(.bottom, 6)
            }
            .whisperNavigationBack()
            .navigationTitle("@\(client.client_username)")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                async let dash: Void = loadConnect(force: false)
                async let props: Void = proposals.refresh(forClient: client.client_user_id)
                _ = await (dash, props)
            }
            .onAppear { startAutoRefresh() }
            .onDisappear { stopAutoRefresh() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                stopAutoRefresh(); clearJasperDisplay(); dismiss()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await loadConnect(force: false) }
                    startAutoRefresh()
                } else {
                    stopAutoRefresh()
                }
            }
            .fullScreenCover(isPresented: $openThread) {
                WhisperDMThreadView(otherUserID: client.client_user_id, otherUsername: client.client_username)
            }
            .sheet(item: $activeProposalKind) { kind in
                WhisperCoachProposalSheet(
                    client: client,
                    kind: kind,
                    activePlan: nil
                ) { newProposal in
                    proposals.proposals.insert(newProposal, at: 0)
                }
            }
            .fullScreenCover(isPresented: $showCoachWalkthrough) {
                if case .ready(let access, let snap) = connectPhase {
                    JasperCoachAccessWalkthrough(clientUsername: client.client_username,
                                                 access: access,
                                                 snapshot: snap)
                }
            }
            .fullScreenCover(isPresented: $showCoachTools, onDismiss: {
                Task { await loadConnect(force: true) }
            }) {
                JasperCoachToolsSheet(clientUID: client.client_user_id,
                                      clientUsername: client.client_username)
            }
            .sheet(isPresented: $showMarketplace, onDismiss: {
                Task { await loadConnect(force: true) }
            }) {
                JasperMarketplaceSheet(importClientUID: client.client_user_id,
                                       importClientUsername: client.client_username)
            }
            .confirmationDialog(
                "End coaching @\(client.client_username)?",
                isPresented: $showEndConfirm,
                titleVisibility: .visible
            ) {
                Button("End coaching", role: .destructive) {
                    Task {
                        await requests.end(client)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their Jasper Connect token is revoked and they stop sharing their data with you.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            WhisperAvatar(username: client.client_username, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(client.client_username)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                HStack(spacing: 6) {
                    Text("Active client")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.coachAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(WhisperTheme.coachAccent.opacity(0.12), in: Capsule())
                    if connectDashboard != nil {
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(1)
                        }
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.green.opacity(0.1), in: Capsule())
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - The Jasper dashboard (one call, API-only)

    private enum ClientConnectPhase: Equatable {
        case loading
        case ready(JasperCoachAccess, JasperLiveSnapshot)
        case unavailable(String)
    }

    private var dashboardCard: some View {
        sectionCard(title: "Jasper dashboard", icon: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 10) {
                switch connectPhase {
                case .loading:
                    loadingSkeleton
                case .unavailable(let reason):
                    unavailableBlock(reason)
                case .ready(let access, _):
                    connectReadyContent(access)
                }
            }
        }
        .onChange(of: coachConnect.accessByClient[pushUID]) { _, access in
            guard access == nil || (displayedTokenID != nil && displayedTokenID != access?.tokenID) else { return }
            clearJasperDisplay()
        }
        .confirmationDialog("Reconnect Jasper access?", isPresented: $showReconnectConfirm, titleVisibility: .visible) {
            Button("Reconnect after client review") {
                let generation = AccountStorage.generation
                reconnectBusy = true
                Task {
                    defer { reconnectBusy = false }
                    do {
                        try await coachConnect.reconnect(forClient: client.client_user_id)
                        guard generation == AccountStorage.generation else { return }
                        await loadConnect(force: true)
                    } catch {
                        guard generation == AccountStorage.generation else { return }
                        connectPhase = .unavailable(JasperCoachConnect.friendlyMintMessage(error))
                    }
                }
            }
        } message: { Text("Ask the client to review their standing grant in Jasper first. This requests a new token with the existing coach permissions; Jasper still decides what is shared.") }
        .onChange(of: JasperEventPush.shared.pulses[pushUID]) { _, stamp in
            // Fresh change-feed events landed — the graph changed, so refresh
            // the one-call dashboard (throttled; force bypasses the 60s cache
            // exactly because the hint IS the change signal). The reconcile
            // runs ahead of each dashboard read, so a pulse raised there joins
            // the read already in flight instead of starting another.
            guard stamp != nil, !connectBusy else { return }
            guard Date().timeIntervalSince(lastPushRefresh) > 8 else { return }
            lastPushRefresh = Date()
            Task {
                await loadConnect(force: true)
                if connectWeekDashboard != nil { await loadWeek(force: true) }
            }
        }
    }

    /// Structured shimmer in the panel's own shape — never a lone spinner.
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Loading @\(client.client_username)'s shared dashboard…")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(WhisperTheme.surface(colorScheme))
                        .frame(height: 52)
                        .opacity(skeletonPulse ? 0.45 : 0.95)
                }
            }
            RoundedRectangle(cornerRadius: 12)
                .fill(WhisperTheme.surface(colorScheme))
                .frame(height: 88)
                .opacity(skeletonPulse ? 0.45 : 0.95)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                skeletonPulse = true
            }
        }
    }

    /// The API said no — say so and offer a retry. NEVER a stale local
    /// substitute: this screen is the API or it's honest.
    private func unavailableBlock(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(jasperOrange)
                Text("Live dashboard unavailable")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Text(reason)
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            Text("Only permitted cloud records are shown. Missing data is not a zero or a missed activity.")
                .font(.system(size: 9))
                .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                connectPhase = .loading
                Task { await loadConnect(force: true) }
            } label: {
                Text("Retry read")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            Button("Reconnect Jasper access") { showReconnectConfirm = true }
                .disabled(reconnectBusy)
                .frame(minHeight: 44)
        }
    }

    private func clearJasperDisplay() {
        displayedTokenID = nil
        connectDashboard = nil
        connectWeekDashboard = nil
        connectGroceries = nil
        connectDietPlan = nil
        connectWaterTodayML = nil
        showClientGroceries = false
        showClientDietPlan = false
        showCoachTools = false
        connectPhase = .unavailable("Jasper access changed. Review permissions before reconnecting.")
    }

    @ViewBuilder
    private func connectReadyContent(_ access: JasperCoachAccess) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(access.username.map { "@\($0)" } ?? "Client graph")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
            Text("· \(access.scopeSummary.lowercased()) · revocable")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Button {
                Haptics.tap()
                Task { await loadConnect(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 28, height: 28)
                    .background(WhisperTheme.surface(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh live Jasper data")
        }
        if !access.hasJasperProfile {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text("No Jasper profile on this account yet — the dashboard may be empty.")
                    .font(.caption2)
            }
            .foregroundStyle(jasperOrange)
        }
        if let dash = connectDashboard {
            // One call (Aug 2026): GET /v1/dashboard — the exact payload
            // Jasper's own coach view renders. WEEK flips to ?period=week:
            // 7-day windows + the server-computed digest.
            periodSwitcher
            livePushStrip
            if showWeekDigest {
                if let week = connectWeekDashboard {
                    JasperClientDashboardPanel(dashboard: week, clientUsername: client.client_username)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini)
                        Text("Computing the week-over-week digest…")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .padding(.vertical, 8)
                }
            } else {
                JasperClientDashboardPanel(dashboard: dash, clientUsername: client.client_username)
            }
            planRows
            coachActionButtons(access)
            footnote(dash)
        }
    }

    /// TODAY ⇄ WEEK — week mode is `?period=week`: 7-day windows plus the
    /// server-computed digest (this-week vs last-week + paste-ready highlights).
    private var periodSwitcher: some View {
        HStack(spacing: 6) {
            periodChip("TODAY", active: !showWeekDigest) {
                withAnimation(.spring(duration: 0.3)) { showWeekDigest = false }
            }
            periodChip("WEEK DIGEST", active: showWeekDigest) {
                withAnimation(.spring(duration: 0.3)) { showWeekDigest = true }
                if connectWeekDashboard == nil { Task { await loadWeek(force: false) } }
            }
            Spacer()
        }
    }

    private func periodChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(active ? WhisperTheme.surface(colorScheme) : WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Change-feed events light this strip — every dashboard refresh also
    /// reads `GET /v1/events/page` through the coach token (Jasper has paused
    /// webhook push), so events that landed since the last pass show here.
    /// Quiet-but-armed means the cursor sits at the journal tail; a note
    /// explains when the grant doesn't share `read:events`.
    @ViewBuilder
    private var livePushStrip: some View {
        if let latest = JasperEventPush.shared.recent[pushUID]?.first {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("LIVE")
                    .font(.system(size: 8, weight: .heavy)).tracking(1)
                    .foregroundStyle(.green)
                Text(latest.title + (latest.occurredAt.map { " · \(relativeShort($0))" } ?? ""))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if let count = JasperEventPush.shared.recent[pushUID]?.count, count > 1 {
                    Text("+\(count - 1)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 10))
        } else if JasperEventPush.shared.armed.contains(pushUID) {
            HStack(spacing: 5) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                Text("Change feed positioned — new events show here on the next refresh"
                     + (JasperEventPush.shared.dispatcherLine.map { " · \($0)" } ?? ""))
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.9))
        } else if let note = JasperEventPush.shared.lastNotes[pushUID] {
            HStack(spacing: 5) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 9, weight: .semibold))
                Text(note)
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.9))
        }
    }

    /// Diet plan + groceries — read off the SAME dashboard payload
    /// (`sections.diet_plans.data`), rendered by the verbatim decoders.
    @ViewBuilder
    private var planRows: some View {
        if connectDietPlan != nil || connectGroceries != nil || connectWaterTodayML != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let plan = connectDietPlan {
                    Button {
                        Haptics.tap()
                        showClientDietPlan = true
                    } label: {
                        planRow(icon: "fork.knife",
                                kicker: "DIET PLAN · " + plan.name.uppercased(),
                                line: dietPlanSummary(plan))
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showClientDietPlan) {
                        JasperDietPlanSheet(source: .preloaded(
                            plan,
                            note: "Off the same one-call dashboard payload — their plan exactly as Jasper stores it."))
                    }
                }
                if let groceries = connectGroceries {
                    Button {
                        Haptics.tap()
                        showClientGroceries = true
                    } label: {
                        planRow(icon: "cart.fill",
                                kicker: "GROCERIES · " + groceries.planName.uppercased(),
                                line: "\(groceries.itemCount) items · shared state — checks sync with their Jasper live")
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showClientGroceries) {
                        // Aug 17 grocery sync: the sheet loads /v1/grocery_list
                        // through the coach token — the SAME rows the client's
                        // Jasper checks off (write grants can check for them).
                        JasperGroceryListSheet(source: .coachClient(
                            uid: client.client_user_id,
                            username: client.client_username))
                    }
                }
                if let waterML = connectWaterTodayML {
                    let cups = Int((Double(waterML) / 250.0).rounded())
                    HStack(spacing: 10) {
                        JasperWaterCupGlass(level: min(1, Double(cups) / 8.0), width: 30, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WATER TODAY · JASPER'S OWN CUP")
                                .font(.system(size: 8.5, weight: .heavy))
                                .tracking(1.0)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("\(cups) of 8 cups · \(waterML) ml — the water_cup render spec, live")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        JasperWaterRing(count: cups, goal: 8, size: 34)
                    }
                }
            }
            .padding(10)
            .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func planRow(icon: String, kicker: String, line: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(jasperOrange)
                .frame(width: 30, height: 30)
                .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1),
                            in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(.system(size: 8.5, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(line)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .contentShape(.rect)
    }

    private func dietPlanSummary(_ plan: JasperDietPlan) -> String {
        var parts: [String] = []
        if let kcal = plan.targetCalories { parts.append("\(kcal) kcal/day") }
        if !plan.days.isEmpty { parts.append("\(plan.days.count) days of meals") }
        if plan.isActive { parts.append("active") }
        return parts.isEmpty ? "Their Jasper plan — tap to read" : parts.joined(separator: " · ")
    }

    /// Coach tools (writes), the marketplace (imports for THIS client), and
    /// the reopenable access walkthrough.
    private func coachActionButtons(_ access: JasperCoachAccess) -> some View {
        HStack(spacing: 8) {
            if access.canWrite == true {
                Button {
                    Haptics.tap()
                    showCoachTools = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10, weight: .bold))
                        Text("Coach tools")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(colors: [jasperOrange,
                                                Color(red: 0.906, green: 0.435, blue: 0.227)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Read-only · client's choice")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(WhisperTheme.surface(colorScheme), in: .capsule)
            }
            Button {
                Haptics.tap()
                showMarketplace = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "storefront")
                        .font(.system(size: 10, weight: .bold))
                    Text("Marketplace")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(WhisperTheme.surface(colorScheme), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                showCoachWalkthrough = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 10, weight: .bold))
                    Text("What I can see")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(WhisperTheme.surface(colorScheme), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func footnote(_ dash: JasperClientDashboard) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 8))
            Text("Updated \(relativeShort(dash.generatedAt ?? dash.fetchedAt)) · Shared from Jasper")
                .font(.system(size: 9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.85))
    }

    // MARK: - Loading (API-only — no legacy fallback, ever)

    private var pushUID: String {
        client.client_user_id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Mints/reuses the client token, then pulls the ONE-CALL dashboard.
    /// The only outcomes are the real payload or an honest unavailable
    /// state — a failed refresh keeps the last REAL payload on screen
    /// (with its timestamp) instead of swapping in anything local.
    private func loadConnect(force: Bool) async {
        if connectBusy { return }
        connectBusy = true
        let generation = AccountStorage.generation
        defer { if generation == AccountStorage.generation { connectBusy = false } }
        do {
            let access = try await coachConnect.access(forClient: client.client_user_id)
            let dash = await coachConnect.dashboard(forClient: client.client_user_id, force: force)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            if let dash {
                guard
                      coachConnect.accessByClient[pushUID]?.tokenID == access.tokenID else { return }
                displayedTokenID = access.tokenID
                withAnimation(.spring(duration: 0.35)) {
                    connectDashboard = dash
                    connectPhase = .ready(access, dash.legacySnapshot())
                }
                applyDashboardPlanRows(dash)
                maybeShowWalkthrough()
            } else if coachConnect.accessByClient[pushUID] == nil {
                clearJasperDisplay()
            } else if connectDashboard == nil {
                let uid = pushUID
                withAnimation(.spring(duration: 0.3)) {
                    connectPhase = .unavailable(coachConnect.lastErrors[uid]
                                                ?? "The shared dashboard couldn’t load. Please try again.")
                }
            }
            // else: keep the last REAL payload; the footnote shows its age.
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            if coachConnect.accessByClient[pushUID] == nil { clearJasperDisplay() }
            if connectDashboard == nil {
                withAnimation(.spring(duration: 0.3)) {
                    connectPhase = .unavailable(JasperCoachConnect.friendlyMintMessage(error))
                }
            }
        }
    }

    private func refreshAll() async {
        async let dash: Void = loadConnect(force: true)
        async let props: Void = proposals.refresh(forClient: client.client_user_id)
        _ = await (dash, props)
        if connectWeekDashboard != nil { await loadWeek(force: true) }
    }

    /// `?period=week` — 7-day windows + the digest block, on the same
    /// 60s-cached rail (separate cache key) so the switch can't break the
    /// ≤1/min polling cap.
    private func loadWeek(force: Bool) async {
        if weekBusy { return }
        weekBusy = true
        let generation = AccountStorage.generation
        defer { if generation == AccountStorage.generation { weekBusy = false } }
        do {
            let access = try await coachConnect.access(forClient: client.client_user_id)
            let week = await coachConnect.dashboard(forClient: client.client_user_id, period: "week", force: force)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            guard coachConnect.accessByClient[pushUID]?.tokenID == access.tokenID else {
                clearJasperDisplay(); return
            }
            guard displayedTokenID == access.tokenID else { return }
            if let week { withAnimation(.spring(duration: 0.35)) { connectWeekDashboard = week } }
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            if coachConnect.accessByClient[pushUID] == nil { clearJasperDisplay() }
        }
    }

    /// Diet plan + groceries ride the SAME dashboard call —
    /// `sections.diet_plans.data` rows are byte-identical to the
    /// /v1/diet_plans read, so the verbatim decoders (groceryList included,
    /// never re-derived) drop straight in.
    private func applyDashboardPlanRows(_ dash: JasperClientDashboard) {
        let planRows = dash.rows("diet_plans")
        let waterRows = dash.rows("water")
        withAnimation(.spring(duration: 0.35)) {
            // An authoritative empty/locked section must remove its previous display.
            connectGroceries = planRows.isEmpty ? nil : JasperGroceryList.fromRows(planRows)
            connectDietPlan = planRows.isEmpty ? nil : JasperDietPlan.fromRows(planRows)
            if planRows.isEmpty { showClientGroceries = false; showClientDietPlan = false }
            connectWaterTodayML = Self.todayWaterML(waterRows)
        }
    }

    /// Sum of today's water rows (ml) — nil when the section is locked or
    /// absent, so the cup hides instead of faking an empty glass.
    nonisolated private static func todayWaterML(_ rows: [[String: Any]]) -> Int? {
        guard !rows.isEmpty else { return nil }
        let calendar = Calendar.current
        return rows.reduce(0) { sum, row in
            guard let ml = (row["amount_ml"] as? NSNumber)?.intValue,
                  let at = jasperConnectDate(row["logged_at"]),
                  calendar.isDateInToday(at) else { return sum }
            return sum + ml
        }
    }

    /// First time this client's live pipe opens for this coach — play the
    /// glow walkthrough once (reopenable from the panel).
    private func maybeShowWalkthrough() {
        let seenKey = "jasper_coach_walkthrough_seen_" + pushUID
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        UserDefaults.standard.set(true, forKey: seenKey)
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            showCoachWalkthrough = true
        }
    }

    /// Gentle poll while on-screen — the 60s cache inside `dashboard()`
    /// keeps this well under the published ≤1/min cap; change-feed hints
    /// force-refresh ahead of it.
    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                await loadConnect(force: false)
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func relativeShort(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Coach proposal actions (Whisper-native — not health data)

    private var coachActionsCard: some View {
        sectionCard(title: "Suggest changes", icon: "sparkles") {
            VStack(spacing: 8) {
                Text("Send a proposal — your client reviews it in Whisper and accepts, modifies or declines.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                proposalButton(.macros)
                    .frame(maxWidth: .infinity)
                proposalButton(.dietPlan)
                    .frame(maxWidth: .infinity)
                proposalButton(.note)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func proposalButton(_ kind: ProposalKind) -> some View {
        Button {
            Haptics.tap()
            activeProposalKind = kind
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.icon)
                    .font(.footnote.weight(.bold))
                Text(kind.title)
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(WhisperTheme.coachAccent)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WhisperTheme.coachAccent.opacity(0.12), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(WhisperTheme.coachAccent.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var proposalsCard: some View {
        if !proposals.proposals.isEmpty {
            sectionCard(title: "Your suggestions", icon: "paperplane.fill") {
                VStack(spacing: 8) {
                    ForEach(proposals.proposals.prefix(6)) { p in
                        proposalRow(p)
                    }
                    if proposals.pendingCount > 0 {
                        Text("\(proposals.pendingCount) awaiting response in Whisper")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func proposalRow(_ p: WhisperCoachProposalRow) -> some View {
        let kind = ProposalKind(rawValue: p.kind) ?? .note
        let showResend = p.status == "expired" || p.status == "declined" || isStaleNoop(p)
        return HStack(spacing: 10) {
            Button {
                Haptics.tap()
                WhisperCoachProposalService.openWhisperLink(for: p.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: kind.icon)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.coachAccent)
                        .frame(width: 24, height: 24)
                        .background(WhisperTheme.coachAccent.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text(proposalSummary(p))
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                    Spacer()
                    statusPill(p.status)
                }
            }
            .buttonStyle(.plain)

            if showResend {
                Button {
                    Haptics.tap()
                    Task { await resendProposal(p) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.coachAccent)
                        .frame(width: 28, height: 28)
                        .background(WhisperTheme.coachAccent.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resend suggestion")
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                Task { await resendProposal(p) }
            } label: {
                Label("Resend suggestion", systemImage: "arrow.clockwise")
            }
            Button {
                WhisperCoachProposalService.openWhisperLink(for: p.id)
            } label: {
                Label("Open in Whisper", systemImage: "arrow.up.right.square")
            }
        }
    }

    /// A proposal counts as a no-op if it's still pending more than 24h
    /// after creation (the client either ignored it or, for very old rows,
    /// it was sent with the pre-fix key names and silently failed to apply).
    private func isStaleNoop(_ p: WhisperCoachProposalRow) -> Bool {
        guard p.status == "pending",
              let iso = p.created_at,
              let created = ISO8601DateFormatter().date(from: iso) else { return false }
        return Date().timeIntervalSince(created) > 24 * 60 * 60
    }

    private func resendProposal(_ p: WhisperCoachProposalRow) async {
        if let fresh = await proposals.resend(p) {
            Haptics.success()
            WhisperCoachProposalService.openWhisperLink(for: fresh.id)
        } else {
            Haptics.warning()
        }
    }

    private func proposalSummary(_ p: WhisperCoachProposalRow) -> String {
        if let note = p.note, !note.isEmpty { return note }
        if let patch = p.patch {
            if let msg = patch["message"]?.stringValue { return msg }
            var parts: [String] = []
            if let v = (patch["calories"]  ?? patch["target_calories"])?.doubleValue  { parts.append("\(Int(v)) kcal") }
            if let v = (patch["protein_g"] ?? patch["target_protein_g"])?.doubleValue { parts.append("P \(Int(v))g") }
            if let v = (patch["carbs_g"]   ?? patch["target_carbs_g"])?.doubleValue   { parts.append("C \(Int(v))g") }
            if let v = (patch["fat_g"]     ?? patch["target_fat_g"])?.doubleValue     { parts.append("F \(Int(v))g") }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        return "Sent \(formatDateShort(p.created_at))"
    }

    private func formatDateShort(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func statusPill(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "accepted": return ("Accepted", .green)
            case "declined": return ("Declined", .red)
            case "modified": return ("Modified", .orange)
            case "expired":  return ("Expired", .gray)
            default:         return ("Pending", WhisperTheme.coachAccent)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                openThread = true
            } label: {
                Label("Message client", systemImage: "bubble.left.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.coachAccent, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.warning()
                showEndConfirm = true
            } label: {
                Text("End coaching")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.red.opacity(0.4), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Building blocks

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(WhisperTheme.coachAccent)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }
}
