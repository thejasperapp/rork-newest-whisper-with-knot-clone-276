import SwiftUI

/// The one-tap "Connect Jasper" control from `WHISPER_CONNECT.md`, dressed in
/// Whisper's settings-row language (ink text, icon tile, hairline rhythm)
/// instead of the doc's generic glass card. Self-contained — drop into any
/// settings section:
///
///     ConnectJasperButton()
///
/// States: not connected → connecting → connected (with Test / Reconnect /
/// Disconnect menu) → error (with retry). A remote revoke flips it back to
/// "Connect Jasper" automatically on the next validate.
///
/// ONE BUTTON, the original journey: every tap mints the token directly off
/// the linked-or-same Jasper sign-in (the logic that always worked). Only an
/// unlinked result hops to Jasper's Allow screen, whose return deep link —
/// with a foreground poll fallback — finishes the connection automatically.
struct ConnectJasperButton: View {
    @State private var client = JasperConnectClient.shared
    @State private var link = WhisperWhisperLinkService.shared
    @State private var showPermissions: Bool = false
    @State private var showDisconnectError: Bool = false
    @State private var showDisconnectConfirm = false
    @State private var testResult: String?
    @State private var previewPhase: PreviewPhase = .idle
    @State private var showCelebration = false
    @State private var awaitingJasperReturn = false
    @State private var showLinkFallback = false
    @State private var coachTokens: [JasperCoachTokenInfo] = []
    @State private var coachWalkthrough: JasperCoachTokenInfo?
    @State private var showGroceries = false
    @State private var showDietPlan = false
    @State private var showRecipes = false
    @State private var showWater = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private let jasperOrange = Color(red: 0.953, green: 0.565, blue: 0.341)

    var body: some View {
        // The connection card wears the ember glow box — the same WHISPER_PLANS
        // language every API surface uses now (warm cream/charcoal, gradient
        // hairline, layered aura at stacked-glow strength).
        JasperGlowBox(cornerRadius: 18, glow: 0.5) {
            Group {
                if awaitingJasperReturn {
                    finishInJasperRow.transition(.blurReplace)
                } else {
                    switch client.state {
                    case .notConnected:
                        connectRow.transition(.blurReplace)
                    case .connecting:
                        connectingRow.transition(.blurReplace)
                    case .connected(let info):
                        connectedRow(info).transition(.blurReplace)
                    case .error(let message):
                        errorRow(message).transition(.blurReplace)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .animation(.whisperSmooth, value: client.state)
        .animation(.whisperSmooth, value: awaitingJasperReturn)
        .confirmationDialog("Disconnect Jasper?", isPresented: $showDisconnectConfirm,
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                previewPhase = .idle
                Task {
                    if !(await client.disconnect()) { showDisconnectError = true }
                }
            }
        } message: {
            Text("Revoke this iPhone’s Whisper token on Jasper. Your records and account link stay intact; separate web and coach connections are unchanged.")
        }
        .disabled(client.isDisconnecting)
        .alert("Couldn't disconnect Jasper", isPresented: $showDisconnectError) {
            Button("OK", role: .cancel) {}
        } message: { Text(client.disconnectError ?? "Try again, or revoke Whisper in Jasper’s settings.") }
        .sheet(isPresented: $showPermissions) { JasperPermissionsView(onAllow: performConnect) }
        .fullScreenCover(isPresented: $showCelebration, onDismiss: {
            Task { await loadSnapshot(force: false) }
        }) {
            JasperConnectionCelebration()
        }
        .fullScreenCover(item: $coachWalkthrough) { token in
            JasperClientCoachVisibilityWalkthrough(coachUsername: token.holderUsername,
                                                   appName: token.appName,
                                                   scopes: token.scopes)
        }
        .sheet(isPresented: $showLinkFallback) {
            WhisperConnectWhisperView(startWithCode: true)
                .whisperSheetBorder()
        }
        .onChange(of: link.lastLinkedAt) { _, stamp in
            guard stamp != nil, awaitingJasperReturn || showLinkFallback else { return }
            awaitingJasperReturn = false
            showLinkFallback = false
            Task {
                // Let the fallback sheet fully dismiss before the celebration
                // cover presents, then mint/rotate the token so it resolves
                // the fresh account link.
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                showPermissions = true
            }
        }
        .onChange(of: link.lastDeniedAt) { _, denied in
            guard denied != nil, awaitingJasperReturn else { return }
            // "Don't allow" in Jasper — no token was minted yet, so just
            // settle the row back to "Connect Jasper".
            withAnimation(.whisperSmooth) { awaitingJasperReturn = false }
            Haptics.warning()
        }
        .onChange(of: scenePhase) { _, phase in
            // Foreground fallback: if Jasper's return link never arrived (or
            // landed in a previous process), poll once — a landed link then
            // completes through the same lastLinkedAt path above.
            guard phase == .active, awaitingJasperReturn else { return }
            Task {
                // Give the real return deep link a beat to win the race first.
                try? await Task.sleep(for: .milliseconds(700))
                await link.checkPendingReturn()
            }
        }
        .task { await client.validate() }
    }

    // MARK: The one-button journey

    /// The ORIGINAL working journey, one button: mint the Connect token
    /// directly off the linked-or-same Jasper sign-in (`client.connect()` —
    /// the exact logic the old "Connect Jasper" row used) and celebrate.
    /// Only when the minted token resolves to an EMPTY graph (different
    /// sign-ins, never linked) do we hop to Jasper's Allow screen — and the
    /// return deep link / foreground poll finish that leg automatically.
    private func startConnect() { showPermissions = true }

    private func performConnect(scopes: [String]) {
        let generation = AccountStorage.generation
        Task {
            await client.connect(scopes: scopes)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            switch client.state {
            case .connected(let info):
                if resolution(info) == .unlinked {
                    // Token minted but it points at an empty graph — the
                    // account link is the missing piece. Get permission in
                    // Jasper (or paste a code when it isn't installed).
                    if link.beginDeepLink() {
                        withAnimation(.whisperSmooth) { awaitingJasperReturn = true }
                    } else {
                        showLinkFallback = true
                    }
                } else {
                    Haptics.success()
                    showCelebration = true
                }
            case .error:
                Haptics.warning()
            default:
                break
            }
        }
    }

    // MARK: Not connected — the one-tap moment

    private var connectRow: some View {
        Button {
            Haptics.tap()
            startConnect()
        } label: {
            HStack(spacing: 12) {
                jasperMark
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Jasper")
                        .font(.body)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(link.isLinked
                         ? "Choose permissions before connecting"
                         : "Your linked or same Jasper sign-in · choose access")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(jasperOrange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Connecting

    private var connectingRow: some View {
        HStack(spacing: 12) {
            jasperMark
            Text("Connecting to Jasper…")
                .font(.body)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            ProgressView().controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Connected

    private func connectedRow(_ info: JasperConnection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    showCelebration = true
                } label: {
                    HStack(spacing: 12) {
                        jasperMark
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Jasper connected")
                                    .font(.body)
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                linkPill(resolution(info))
                            }
                            Text(testResult ?? subtitle(for: info))
                                .font(.caption)
                                .foregroundStyle(testResult == nil
                                                 ? WhisperTheme.muted(colorScheme)
                                                 : .green)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Menu {
                    Button {
                        showCelebration = true
                    } label: {
                        Label("View connection", systemImage: "sparkles.rectangle.stack")
                    }
                    Button {
                        Task { await runConnectionTest() }
                    } label: {
                        Label("Test connection", systemImage: "bolt.badge.checkmark")
                    }
                    Button {
                        previewPhase = .idle
                        startConnect()                    // re-approve in Jasper, token rotates on return
                    } label: {
                        Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 32, height: 32)
                        .background(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.13 : 0.06), in: .circle)
                        .contentShape(.circle)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // §8.4 rule: username missing AND linked:false ⇒ the token points
            // at an empty graph. Warn instead of letting reads look broken;
            // otherwise show the live "what Whisper sees" panel.
            if resolution(info) == .unlinked {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One more step — approve Whisper inside Jasper so your real data flows in.")
                        .font(.caption2)
                        .foregroundStyle(jasperOrange)
                    Button {
                        Haptics.tap()
                        if link.beginDeepLink() {
                            withAnimation(.whisperSmooth) { awaitingJasperReturn = true }
                        } else {
                            showLinkFallback = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Finish in Jasper")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(jasperOrange, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else {
                livePreview
                dietPlanRow
                groceryRow
                recipesRow
                waterRow
            }
            coachAccessSection
        }
        .task(id: info.tokenPrefix) { await loadSnapshot(force: false) }
        .task(id: info.tokenPrefix) { await loadCoachTokens() }
    }

    // MARK: Error

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(jasperOrange)
                .frame(width: 32, height: 32)
                .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1), in: .rect(cornerRadius: 10))
            Text(message)
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .lineLimit(3)
            Spacer()
            Button {
                Haptics.tap()
                startConnect()
            } label: {
                Text("Try again")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(jasperOrange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(jasperOrange.opacity(0.14), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Waiting on Jasper's Allow screen

    /// Shown right after the deep-link hop: Jasper is open on its consent
    /// screen. The moment the user taps Allow there, the return link redeems
    /// and `onChange(of: link.isLinked)` completes the flow automatically.
    private var finishInJasperRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                jasperMark
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish in Jasper")
                        .font(.body)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Tap Allow in Jasper — this completes by itself.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer()
                ProgressView().controlSize(.small)
            }
            HStack(spacing: 8) {
                pendingPill("Open Jasper again") {
                    _ = link.beginDeepLink()
                }
                pendingPill("Enter code") {
                    awaitingJasperReturn = false
                    showLinkFallback = true
                }
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSmooth) { awaitingJasperReturn = false }
                } label: {
                    Text("Cancel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func pendingPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(jasperOrange)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(jasperOrange.opacity(0.14), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: Bits

    /// Jasper's brand mark — the REAL App Store icon (iTunes lookup, cached),
    /// sized to match the settings icon tiles.
    private var jasperMark: some View {
        JasperAppIcon(size: 32, cornerScale: 0.3)
    }

    private func subtitle(for info: JasperConnection) -> String {
        var parts: [String] = []
        if let username = info.username { parts.append("@\(username)") }
        parts.append(info.scopeSummary)
        parts.append(info.tokenPrefix + "…")
        return parts.joined(separator: " · ")
    }

    // MARK: Account resolution (§8.4)

    private enum AccountResolution { case linkedAccounts, sameAccount, unlinked }

    /// `linked:true` = an account link/coach grant resolved a different owner;
    /// a username with `linked:false` = the same sign-in owns a Jasper profile;
    /// neither = unlinked (empty graph). `linked == nil` means the metadata
    /// predates the field — fall back to Whisper's account-link service.
    private func resolution(_ info: JasperConnection) -> AccountResolution {
        if info.linked == true { return .linkedAccounts }
        if info.username != nil { return .sameAccount }
        if info.linked == false { return .unlinked }
        return link.isLinked ? .linkedAccounts : .unlinked
    }

    private func linkPill(_ status: AccountResolution) -> some View {
        let label: String
        let icon: String
        let tint: Color
        switch status {
        case .linkedAccounts:
            label = "Linked"; icon = "link"; tint = .green
        case .sameAccount:
            label = "Same account"; icon = "person.fill.checkmark"
            tint = Color(red: 0.13, green: 0.55, blue: 0.96)
        case .unlinked:
            label = "Not linked"; icon = "exclamationmark.triangle.fill"; tint = jasperOrange
        }
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(label).font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(colorScheme == .dark ? 0.18 : 0.12), in: .capsule)
    }

    // MARK: Live preview — what Whisper sees from Jasper

    private enum PreviewPhase: Equatable {
        case idle
        case loading
        case loaded(JasperLiveSnapshot)
        case failed
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("LIVE FROM JASPER")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer()
                if case .loaded(let snap) = previewPhase {
                    Text("Last \(snap.windowDays) days")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Button {
                    Haptics.tap()
                    Task { await loadSnapshot(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(jasperOrange)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(previewPhase == .loading)
            }

            switch previewPhase {
            case .idle, .loading:
                LazyVGrid(columns: previewColumns, spacing: 8) {
                    ForEach(0..<6, id: \.self) { _ in placeholderTile }
                }
            case .failed:
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(jasperOrange)
                        Text("Couldn't reach Jasper — tap refresh to retry.")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    if let reason = client.lastLiveError {
                        Text(reason)
                            .font(.system(size: 9))
                            .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            case .loaded(let snap):
                LazyVGrid(columns: previewColumns, spacing: 8) {
                    ForEach(snap.resources) { item in
                        statTile(item)
                    }
                }
                if snap.totalRows == 0, snap.failedResources.isEmpty {
                    Text("No shared cloud records in this window. Missing records do not mean missed workouts or zero intake.")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                if !snap.failedResources.isEmpty {
                    Text("Couldn't read \(snap.failedResources.joined(separator: ", ")) — refresh to retry.")
                        .font(.system(size: 9))
                        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var previewColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8),
         GridItem(.flexible(), spacing: 8),
         GridItem(.flexible(), spacing: 8)]
    }

    /// Shimmering stand-in tile while the live numbers load.
    private var placeholderTile: some View {
        VStack(spacing: 5) {
            Capsule()
                .fill(WhisperTheme.muted(colorScheme).opacity(0.35))
                .frame(width: 36, height: 13)
            Capsule()
                .fill(WhisperTheme.muted(colorScheme).opacity(0.22))
                .frame(width: 46, height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.045),
                    in: .rect(cornerRadius: 10))
        .phaseAnimator([0.95, 0.45]) { view, phase in
            view.opacity(phase)
        } animation: { _ in .easeInOut(duration: 0.7) }
    }

    private func statTile(_ item: JasperResourceSnapshot) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(jasperOrange)
                Text("\(item.count)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Text(item.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text(item.latest.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
                .font(.system(size: 8))
                .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.045),
                    in: .rect(cornerRadius: 10))
    }

    /// Loads through the client's shared snapshot cache (the celebration
    /// screen and this card always show the same numbers); `force` bypasses.
    private func loadSnapshot(force: Bool) async {
        guard let info = client.connection, resolution(info) != .unlinked else { return }
        if previewPhase == .loading { return }
        if !force, case .loaded(let shown) = previewPhase,
           shown == client.cachedSnapshot,
           Date().timeIntervalSince(shown.fetchedAt) < 300 { return }
        previewPhase = .loading
        if let snap = await client.liveSnapshot(force: force) {
            previewPhase = .loaded(snap)
        } else {
            previewPhase = client.connection == nil ? .idle : .failed
        }
    }

    // MARK: Diet plan — the live plan read off the Connect API

    /// Opens the full diet plan exactly as Jasper stores it — macro targets,
    /// each day's meals, and the grocery checklist — read live through the
    /// user's own token and drawn in Jasper's glow language.
    private var dietPlanRow: some View {
        Button {
            Haptics.tap()
            showDietPlan = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(jasperOrange)
                    .frame(width: 30, height: 30)
                    .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1),
                                in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diet plan")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Your Jasper plan, live — targets, daily meals, and macros")
                        .font(.system(size: 10))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(8)
            .background(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.045),
                        in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .sheet(isPresented: $showDietPlan) {
            JasperDietPlanSheet(source: .ownConnect)
        }
    }

    // MARK: Grocery list — the canonical checklist off the active diet plan

    /// Aug 2026 grocery protocol: every `diet_plans` read carries
    /// `payload.groceryList` — the exact categorized checklist Jasper
    /// renders in-app. This row opens it checkable, in Jasper's glow
    /// language, never re-derived from ingredients.
    private var groceryRow: some View {
        Button {
            Haptics.tap()
            showGroceries = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(jasperOrange)
                    .frame(width: 30, height: 30)
                    .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1),
                                in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grocery list")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("From your active Jasper diet plan — the exact checklist Jasper renders")
                        .font(.system(size: 10))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(8)
            .background(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.045),
                        in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .sheet(isPresented: $showGroceries) {
            JasperGroceryListSheet(source: .ownConnect)
        }
    }

    // MARK: Recipes — one shared library with Jasper (Aug 17 2026)

    /// GET/POST/DELETE /v1/recipes: a recipe saved here appears inside
    /// Jasper under Nutrition → Recipes instantly, and Jasper's own recipes
    /// read back — per-serving macros always derived, never stored.
    private var recipesRow: some View {
        Button {
            Haptics.tap()
            showRecipes = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(jasperOrange)
                    .frame(width: 30, height: 30)
                    .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1),
                                in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipes")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Save here → it's in Jasper's Nutrition → Recipes instantly, and back")
                        .font(.system(size: 10))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(8)
            .background(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.045),
                        in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .sheet(isPresented: $showRecipes) {
            JasperRecipesSheet()
        }
    }

    // MARK: Water — Jasper's own animated cup, tap-to-log

    /// The water_cup look rendered live: tap cups straight into the user's
    /// own Jasper water log (write:nutrition), minus removes the last one.
    private var waterRow: some View {
        Button {
            Haptics.tap()
            showWater = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(jasperOrange)
                    .frame(width: 30, height: 30)
                    .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1),
                                in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Water")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Jasper's animated cup — tap cups straight into your log")
                        .font(.system(size: 10))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(8)
            .background(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.045),
                        in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .sheet(isPresented: $showWater) {
            JasperWaterTrackerSheet()
        }
    }

    // MARK: Coach access — who else reads YOUR Jasper

    /// Coach-held tokens on this account, from Jasper's own
    /// `jasper_connect_connections()` — the client-side mirror of coach
    /// access. Tapping a row (or the first sighting of a new coach token)
    /// opens the "what your coach sees" walkthrough.
    @ViewBuilder
    private var coachAccessSection: some View {
        if !coachTokens.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("COACH ACCESS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                ForEach(coachTokens) { token in
                    Button {
                        Haptics.tap()
                        coachWalkthrough = token
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill.viewfinder")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(jasperOrange)
                                .frame(width: 30, height: 30)
                                .background(jasperOrange.opacity(colorScheme == .dark ? 0.16 : 0.1),
                                            in: .rect(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(token.holderUsername.map { "Coach @\($0)" } ?? "Your coach")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text(token.canWrite
                                     ? "Reads your Jasper + coach tools · tap to see exactly what"
                                     : "Reads your Jasper through Whisper · tap to see exactly what")
                                    .font(.system(size: 10))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        .padding(8)
                        .background(WhisperTheme.ink(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.045),
                                    in: .rect(cornerRadius: 10))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Text("Manage or revoke coach access in Jasper → Settings → Connect. Ending coaching in Whisper removes it automatically.")
                    .font(.system(size: 9))
                    .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    /// Loads coach-held tokens; the FIRST sighting of a coach token
    /// auto-presents the client walkthrough once per token.
    private func loadCoachTokens() async {
        guard client.connection != nil else {
            coachTokens = []
            return
        }
        let generation = AccountStorage.generation
        let connectionID = client.connection?.tokenID
        let tokens = await client.coachConnections()
        guard generation == AccountStorage.generation, client.connection?.tokenID == connectionID, !Task.isCancelled else { return }
        withAnimation(.whisperSmooth) { coachTokens = tokens }
        if let first = tokens.first {
            let key = "jasper_client_coach_walkthrough_seen_\(first.id)"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                try? await Task.sleep(for: .milliseconds(450))
                guard generation == AccountStorage.generation, client.connection?.tokenID == connectionID, !Task.isCancelled else { return }
                coachWalkthrough = first
            }
        }
    }

    /// Pings /v1/me and flashes the result in the subtitle for a moment.
    private func runConnectionTest() async {
        let generation = AccountStorage.generation
        let connectionID = client.connection?.tokenID
        let healthy = await client.validate()
        guard generation == AccountStorage.generation, client.connection?.tokenID == connectionID,
              !Task.isCancelled, client.connection != nil else { return }   // revoked → row already flipped
        if healthy {
            Haptics.success()
            testResult = "Connection verified · granted permissions only"
        } else {
            Haptics.warning()
            testResult = "Couldn't verify — you may be offline"
        }
        try? await Task.sleep(for: .seconds(2.4))
        guard generation == AccountStorage.generation, client.connection?.tokenID == connectionID, !Task.isCancelled else { return }
        testResult = nil
    }
}
