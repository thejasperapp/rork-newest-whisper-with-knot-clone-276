import SwiftUI

/// The sheet behind the Dating hub's video circle — the front door of the
/// blind-date service: FIND ME A BLIND DATE (the queue, with a live radar
/// while it searches and a matched moment when someone compatible lands),
/// INVITE SOMEONE (the link lobby), your preferences + dating card at a
/// glance, and your past dates. Mirrors web `BlindDateFinder`.
struct WhisperBlindDateFinderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Hands the invite flow back to the hub (it owns the lobby + room).
    let onInvite: () -> Void

    private enum Mode: Equatable {
        case idle
        case searching(since: Date)
        case paired(name: String, code: String)
        case failed(String)
    }

    @State private var mode: Mode = .idle
    @State private var waiting: Int = 0
    @State private var prefs: WhisperDatingPrefs = WhisperDatingPrefsStore.load()
    @State private var cardCount: Int = 0
    @State private var history: [WhisperBlindDate.HistoryRow] = []
    @State private var showPrefs: Bool = false
    @State private var showCard: Bool = false
    @State private var dmTarget: HistoryPeer? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var radar: Bool = false
    // Round 77 — trust + calendar of dating.
    @State private var showVerify: Bool = false
    @State private var showIntro: Bool = false
    @State private var verification = WhisperDatingVerificationService.shared
    @State private var intros = WhisperDatingIntroService.shared

    private struct HistoryPeer: Identifiable {
        let id: String
        let name: String
    }

    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
    private var ink: Color { WhisperTheme.ink(colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                LinearGradient(colors: [rose.opacity(0.13), .clear], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea().allowsHitTesting(false)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        hero
                        switch mode {
                        case .idle, .failed:
                            findCard
                        case .searching(let since):
                            searchingCard(since: since)
                        case .paired(let name, _):
                            pairedCard(name: name)
                        }
                        setupRow
                        WhisperDatingEventCard(onJoinQueue: { startSearch() })
                        trustCard
                        inviteCard
                        if !history.isEmpty { historyCard }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Blind dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        cancelSearch()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showVerify) {
            WhisperDatingVerifyView()
        }
        .sheet(isPresented: $showIntro) {
            WhisperDatingIntroSheet()
                .presentationDetents([.large])
        }
        .task {
            await verification.refreshMine()
            await intros.refreshMine()
        }
        .sheet(isPresented: $showPrefs) {
            WhisperDatingPrefsSheet(onSaved: { prefs = WhisperDatingPrefsStore.load() })
        }
        .sheet(isPresented: $showCard, onDismiss: { cardCount = WhisperSpeedDating.loadCard().count }) {
            WhisperDatingCardEditorSheet()
        }
        .sheet(item: $dmTarget) { peer in
            NavigationStack {
                WhisperDMThreadView(otherUserID: peer.id, otherUsername: peer.name, conversationKind: .dating)
            }
        }
        .task {
            cardCount = WhisperSpeedDating.loadCard().count
            prefs = await WhisperDatingPrefsStore.syncFromCloud()
            waiting = await WhisperBlindDate.queueCount()
            history = await WhisperBlindDate.history()
        }
        .onDisappear { cancelSearch() }
    }

    // MARK: - Pieces

    private var hero: some View {
        VStack(spacing: 8) {
            WhisperJasperInteractiveMascot(size: 76, dating: true)
                .padding(.top, 8)
            Text("A LITTLE CHEMISTRY")
                .font(.caption.weight(.semibold))
                .tracking(1.8)
                .foregroundStyle(rose)
            Text("Hear them first.\nSee them at the reveal.")
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(ink)
            Text("Five minutes to find a spark. Cameras reveal at two minutes, or earlier if you both choose. Jasper brings prompts from your dating cards.")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
    }

    private var findCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your next hello")
                    .font(.headline)
                    .foregroundStyle(rose)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(waiting > 0 ? Color(red: 0.24, green: 0.78, blue: 0.5) : ink.opacity(0.3)).frame(width: 6, height: 6)
                    Text(waiting > 0 ? "\(waiting) waiting right now" : "Nobody waiting yet")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.55))
                }
            }
            Text("Meet someone based on your preferences, distance and private icebreaker answers.")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            if case .failed(let message) = mode {
                Text(message)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(rose)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Haptics.tap()
                startSearch()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                    Text("Find me a blind date 💘")
                        .font(.system(size: 16, weight: .black))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)], startPoint: .leading, endPoint: .trailing)
                    )
                )
                .shadow(color: rose.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(rose.opacity(0.2), lineWidth: 1) }
    }

    private func searchingCard(since: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(since))
            VStack(spacing: 12) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .strokeBorder(rose.opacity(0.35 - Double(i) * 0.1), lineWidth: 1.5)
                            .frame(width: 90 + CGFloat(i) * 46, height: 90 + CGFloat(i) * 46)
                            .scaleEffect(reduceMotion ? 1 : (radar ? 1.08 : 0.94))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: radar)
                    }
                    WhisperEmberMascot(size: 64, isActive: true, expression: .curious, palette: .cupidPink, smitten: true)
                }
                .frame(height: 190)
                Text("Looking for someone compatible…")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(ink)
                Text("\(String(format: "%d:%02d", elapsed / 60, elapsed % 60)) · \(waiting) waiting · \(prefs.summaryLine)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                Text("Keep this open — the moment someone fits, you both drop into the room.")
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button {
                    Haptics.tap()
                    cancelSearch()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(rose)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(WhisperTheme.card(colorScheme)))
                        .overlay(Capsule().strokeBorder(rose.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WhisperTheme.card(colorScheme)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(rose.opacity(0.25), lineWidth: 1))
        }
        .onAppear { radar = true }
    }

    private func pairedCard(name: String) -> some View {
        VStack(spacing: 10) {
            Text("💘")
                .font(.system(size: 44))
            Text("It's a date!")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(ink)
            Text("You're meeting @\(name). Opening the room…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink.opacity(0.65))
            ProgressView().tint(rose)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WhisperTheme.card(colorScheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(rose.opacity(0.35), lineWidth: 1))
    }

    private var setupRow: some View {
        let layout = typeSize >= .xxLarge ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            setupChip(
                icon: "slider.horizontal.3",
                title: prefs.isConfigured ? prefs.summaryLine : "Set who you want to meet",
                done: prefs.isConfigured
            ) { showPrefs = true }
            setupChip(
                icon: "heart.text.square.fill",
                title: cardCount > 0 ? "Card \(cardCount)/\(WhisperSpeedDating.questions.count)" : "Fill your card",
                done: cardCount > 0
            ) { showCard = true }
        }
    }

    private func setupChip(icon: String, title: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(done ? .white : rose)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Capsule().fill(done ? rose : WhisperTheme.card(colorScheme)))
            .overlay(Capsule().strokeBorder(rose.opacity(done ? 0 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Verified dater + your 15-second intro — the two trust signals a
    /// stranger sees before the curtain lifts.
    private var trustCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: verification.isVerified ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(rose)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(rose.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verification.isVerified ? "You're a verified dater" : "Get verified")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        if verification.isVerified { WhisperVerifiedDaterBadge(compact: true) }
                    }
                    Text(verification.isVerified
                         ? "Your badge shows on the hub, in the queue, and on every date."
                         : (verification.status == "pending" ? "Sent for review — your badge appears once a moderator confirms." : "A 10-second face check. Verified daters pair first and wear the badge."))
                        .font(.footnote)
                        .foregroundStyle(ink.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !verification.isVerified && verification.status != "pending" {
                    Button {
                        Haptics.tap()
                        showVerify = true
                    } label: {
                        Text("Verify")
                            .font(.system(size: 12.5, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(rose))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().overlay(rose.opacity(0.15))
            HStack(spacing: 12) {
                Image(systemName: intros.mine == nil ? "mic" : "waveform")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(rose)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(rose.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(intros.mine == nil ? "Record a 15s intro" : "Your intro is live")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(intros.mine == nil
                         ? "Your voice (or a quick video) plays behind the curtain before the reveal."
                         : "Blind dates hear it first — tap to replace or remove it.")
                        .font(.footnote)
                        .foregroundStyle(ink.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    showIntro = true
                } label: {
                    Text(intros.mine == nil ? "Record" : "Edit")
                        .font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(intros.mine == nil ? .white : rose)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(intros.mine == nil ? rose : rose.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WhisperTheme.card(colorScheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(rose.opacity(0.2), lineWidth: 1))
    }

    private var inviteCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(rose)
                .frame(width: 38, height: 38)
                .background(Circle().fill(rose.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Invite someone instead")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text("Send a link — same blind-date room, your pick of person.")
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.6))
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                cancelSearch()
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(380))
                    onInvite()
                }
            } label: {
                Text("Invite")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(rose))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WhisperTheme.card(colorScheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(rose.opacity(0.2), lineWidth: 1))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR PAST DATES")
                .font(.system(size: 9.5, weight: .black))
                .tracking(1.4)
                .foregroundStyle(rose)
            ForEach(history.prefix(8)) { row in
                Button {
                    guard let pid = row.partner_id else { return }
                    Haptics.tap()
                    dmTarget = HistoryPeer(id: pid, name: row.partner_username ?? "someone")
                } label: {
                    HStack(spacing: 10) {
                        Text(String((row.partner_username ?? "?").prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(rose.opacity(0.8)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(row.partner_username ?? "someone")")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(ink)
                            Text(dateLine(row))
                                .font(.caption)
                                .foregroundStyle(ink.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                        Text(row.outcomeLabel)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(row.mutual == true ? .white : rose)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(row.mutual == true ? rose : rose.opacity(0.12)))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WhisperTheme.card(colorScheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(rose.opacity(0.2), lineWidth: 1))
    }

    private func dateLine(_ row: WhisperBlindDate.HistoryRow) -> String {
        var parts: [String] = []
        if let iso = row.started_at, let date = WhisperBackendService.parseISO(iso) {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        parts.append(row.source == "queue" ? "blind match" : "invited")
        if row.revealed == true { parts.append("revealed") }
        return parts.joined(separator: " · ")
    }

    // MARK: - The queue

    private var myUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "someone"
    }

    private func startSearch() {
        cancelSearch()
        mode = .searching(since: Date())
        searchTask = Task {
            do {
                var result = try await WhisperBlindDate.joinQueue(username: myUsername)
                while !Task.isCancelled, !result.isPaired {
                    await MainActor.run { waiting = result.waiting ?? waiting }
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    result = try await WhisperBlindDate.pollQueue()
                    if result.status == "none" {
                        result = try await WhisperBlindDate.joinQueue(username: myUsername)
                    }
                }
                guard !Task.isCancelled, result.isPaired, let code = result.room_code else { return }
                let partnerName = result.partner_username ?? "someone"
                await MainActor.run {
                    Haptics.success()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        mode = .paired(name: partnerName, code: code)
                    }
                }
                await enterRoom(code: code, partnerName: partnerName)
            } catch {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        mode = .failed("Matchmaking isn't switched on for this account yet — invite someone with a link meanwhile.")
                    }
                }
            }
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        if case .searching = mode {
            mode = .idle
            Task { await WhisperBlindDate.leaveQueue() }
        }
    }

    /// Both people were paired — prime the room for blind-date mode, remember
    /// who we're meeting, and open the real meeting window.
    private func enterRoom(code: String, partnerName: String) async {
        let roomID = WhisperBlindDate.roomID(forCode: code)
        await WhisperMeetingService.shared.ensureRoom(id: roomID, title: "Blind date")
        let row = await WhisperMeetingService.shared.fetch(id: roomID)
        await WhisperBlindDate.leaveQueue()
        await MainActor.run {
            WhisperSpeedDating.pendingRooms.insert(roomID.lowercased())
            WhisperBlindDate.pairedPartners[roomID.lowercased()] = partnerName
            dismiss()
        }
        try? await Task.sleep(for: .milliseconds(420))
        if let row {
            await MainActor.run { WhisperMeetingWindow.shared.present(row) }
        }
    }
}
