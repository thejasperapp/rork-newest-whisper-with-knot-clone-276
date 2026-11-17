import SwiftUI
import AuthenticationServices

// MARK: - Shared money widgets

/// Animated money readout — rolls to the new amount whenever it changes.
/// Mirrors the web earnings page's count-up.
private struct WhisperMoneyText: View {
    let cents: Int
    var font: Font
    var color: Color

    @State private var displayed: Int = 0

    var body: some View {
        Text(WhisperBillingService.formatCents(displayed))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(displayed)))
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) { displayed = cents }
            }
            .onChange(of: cents) { _, newValue in
                withAnimation(.easeOut(duration: 0.9)) { displayed = newValue }
            }
    }
}

/// Small breathing status dot — green when ok, amber while pending.
private struct WhisperPulsingDot: View {
    let color: Color
    @State private var bright: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(bright ? 1 : 0.45)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
    }
}

/// The ember money gradient shared by every payment CTA.
private let whisperEmberGradient = LinearGradient(
    colors: [
        Color(red: 0.976, green: 0.451, blue: 0.086),
        Color(red: 0.961, green: 0.62, blue: 0.043),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private func whisperShortDate(_ iso: String?) -> String {
    guard let iso, let date = WhisperBackendService.parseISO(iso) else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

// MARK: - Coach earnings (the money home)

/// Coach earnings — the money home, matching the web app screen for screen:
/// animated dark wallet hero, snapshot tiles, Banking & payouts with the
/// full in-app Stripe standing, the money-movement timeline, pricing with a
/// live "you keep" preview, the share link, and payment history.
struct WhisperCoachEarningsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var billing = WhisperBillingService.shared
    @State private var earnings: WhisperCoachEarnings?
    @State private var overview: WhisperStripeOverview?
    @State private var isLoading: Bool = false
    @State private var isCashingOut: Bool = false
    @State private var isLinkingBank: Bool = false
    @State private var errorMessage: String?
    @State private var payoutSuccess: String?
    @State private var rateString: String = ""
    @State private var currentRateCents: Int?
    @State private var isSavingRate: Bool = false
    @State private var rateSaved: Bool = false
    @State private var linkCopied: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if isLoading && earnings == nil {
                            loadingSkeleton
                        } else if let earnings {
                            walletHero(earnings)
                            snapshotRow(earnings)
                            bankingCard(earnings)
                            if let overview, overview.connected {
                                moneyMovementCard(overview)
                            }
                            rateCard
                            coachingLinkCard
                            paymentHistory(earnings)
                            footerNote
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }
                        if let success = payoutSuccess {
                            Text(success)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                                .padding(.horizontal, 20)
                        }
                        Color.clear.frame(height: 32)
                    }
                    .padding(.top, 8)
                }
                .whisperRefreshable { await refresh() }
            }
            .navigationTitle("Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            earnings = try await billing.fetchCoachEarnings()
        } catch {
            errorMessage = error.localizedDescription
        }
        // The full Stripe standing renders the banking + movement cards.
        if earnings?.connected == true {
            overview = try? await billing.fetchStripeOverview()
        }
        if let rate = try? await billing.fetchCoachRate(coachUserID: AccountStorage.currentUserID.lowercased()),
           let cents = rate.monthlyPriceCents {
            currentRateCents = cents
            if rateString.isEmpty {
                rateString = cents % 100 == 0
                    ? String(cents / 100)
                    : String(format: "%.2f", Double(cents) / 100)
            }
        }
    }

    // MARK: Wallet hero

    private func walletHero(_ e: WhisperCoachEarnings) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("YOUR BALANCE")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if e.connected {
                    HStack(spacing: 5) {
                        WhisperPulsingDot(color: Color(red: 0.2, green: 0.83, blue: 0.6))
                        Text("LIVE · STRIPE")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                }
            }

            WhisperMoneyText(
                cents: e.availableCents,
                font: .system(size: 44, weight: .black, design: .rounded),
                color: .white
            )
            .padding(.top, 10)

            HStack(spacing: 8) {
                heroChip {
                    Circle()
                        .fill(Color(red: 0.96, green: 0.62, blue: 0.043))
                        .frame(width: 6, height: 6)
                    Text("Pending \(WhisperBillingService.formatCents(e.pendingCents))")
                }
                heroChip {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.83, blue: 0.6))
                    Text("All-time \(WhisperBillingService.formatCents(e.totalEarnedCents))")
                }
            }
            .padding(.top, 14)

            Button {
                Haptics.tap()
                Task { await cashOut() }
            } label: {
                HStack(spacing: 8) {
                    if isCashingOut {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "banknote.fill")
                    }
                    Text("Cash out to bank")
                }
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(whisperEmberGradient, in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.976, green: 0.451, blue: 0.086).opacity(canCashOut(e) ? 0.35 : 0), radius: 12, y: 5)
                .opacity(canCashOut(e) ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canCashOut(e))
            .padding(.top, 18)

            if !e.payoutsEnabled {
                Text("Link your bank below to enable cash outs.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
        }
        .padding(22)
        .background {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.5), .clear],
                            center: .center,
                            startRadius: 6,
                            endRadius: 160
                        )
                    )
                    .frame(width: 320, height: 320)
                    .offset(x: -110, y: -120)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.961, green: 0.62, blue: 0.043).opacity(0.3), .clear],
                            center: .center,
                            startRadius: 6,
                            endRadius: 170
                        )
                    )
                    .frame(width: 340, height: 340)
                    .offset(x: 130, y: 130)
            }
            .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func heroChip(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 6) { content() }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1) }
    }

    private func canCashOut(_ e: WhisperCoachEarnings) -> Bool {
        e.payoutsEnabled && e.availableCents >= 100 && !isCashingOut
    }

    private func cashOut() async {
        isCashingOut = true
        errorMessage = nil
        payoutSuccess = nil
        defer { isCashingOut = false }
        do {
            let amount = try await billing.cashOut()
            payoutSuccess = "Cash out started — \(WhisperBillingService.formatCents(amount)) is on its way to your bank."
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Snapshot row

    private func monthStats(_ e: WhisperCoachEarnings) -> (cents: Int, count: Int) {
        let calendar = Calendar.current
        let now = Date()
        var cents = 0
        var count = 0
        for p in e.payments {
            guard let date = WhisperBackendService.parseISO(p.created_at) else { continue }
            if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                cents += p.net_cents
                count += 1
            }
        }
        return (cents, count)
    }

    private func snapshotRow(_ e: WhisperCoachEarnings) -> some View {
        let stats = monthStats(e)
        return HStack(spacing: 10) {
            snapshotTile(icon: "chart.line.uptrend.xyaxis", value: WhisperBillingService.formatCents(stats.cents), label: "This month")
            snapshotTile(icon: "receipt", value: "\(stats.count)", label: "Payments · mo")
            snapshotTile(icon: "wallet.bifold", value: WhisperBillingService.formatCents(e.totalEarnedCents), label: "Lifetime")
        }
        .padding(.horizontal, 16)
    }

    private func snapshotTile(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WhisperTheme.coachAccent)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: Banking & payouts

    private func bankingCard(_ e: WhisperCoachEarnings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WhisperTheme.coachAccent)
                    .frame(width: 34, height: 34)
                    .background(WhisperTheme.coachAccent.opacity(0.12), in: .rect(cornerRadius: 11))
                Text("Banking & payouts")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                if e.connected && e.payoutsEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("LINKED")
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.6)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.13, green: 0.65, blue: 0.36), in: Capsule())
                } else {
                    Text("NOT LINKED")
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(Color(red: 0.85, green: 0.55, blue: 0.1))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.92, green: 0.63, blue: 0.18).opacity(0.15), in: Capsule())
                }
            }

            if !e.connected {
                Text("Payouts are handled securely by Stripe. Link your bank once — cash outs arrive in 1–2 business days.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Button {
                    Haptics.tap()
                    Task { await linkBank() }
                } label: {
                    HStack(spacing: 8) {
                        if isLinkingBank { ProgressView().tint(.white) }
                        Text("Link bank account — takes ~2 minutes")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(whisperEmberGradient, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isLinkingBank)
            } else {
                statusPillRow

                if let due = overview?.requirementsDue, !due.isEmpty {
                    requirementsBox(due)
                }

                if let balance = overview?.balance {
                    HStack(spacing: 10) {
                        stripeBalanceTile(label: "At Stripe · available", cents: balance.availableCents)
                        stripeBalanceTile(label: "On the way · pending", cents: balance.pendingCents)
                    }
                }

                bankRow

                Button {
                    Haptics.tap()
                    Task { await linkBank() }
                } label: {
                    HStack(spacing: 8) {
                        if isLinkingBank { ProgressView().tint(WhisperTheme.ink(colorScheme)) }
                        Text("Update bank details")
                            .font(.footnote.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                .buttonStyle(.plain)
                .disabled(isLinkingBank)
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var statusPillRow: some View {
        HStack(spacing: 6) {
            statusPill(ok: overview?.chargesEnabled == true, label: "Charges")
            statusPill(ok: overview?.payoutsEnabled == true, label: "Payouts")
            statusPill(ok: overview?.detailsSubmitted == true, label: "Details")
            Spacer(minLength: 0)
        }
    }

    private func statusPill(ok: Bool, label: String) -> some View {
        HStack(spacing: 5) {
            WhisperPulsingDot(color: ok ? Color(red: 0.13, green: 0.65, blue: 0.36) : Color(red: 0.92, green: 0.63, blue: 0.18))
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
        }
        .foregroundStyle(ok ? Color(red: 0.13, green: 0.65, blue: 0.36) : Color(red: 0.85, green: 0.55, blue: 0.1))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            (ok ? Color(red: 0.13, green: 0.65, blue: 0.36) : Color(red: 0.92, green: 0.63, blue: 0.18)).opacity(0.12),
            in: Capsule()
        )
    }

    private func requirementsBox(_ due: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stripe still needs:")
                .font(.footnote.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            ForEach(due.prefix(6), id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(item)
                }
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Button {
                Haptics.tap()
                Task { await linkBank() }
            } label: {
                Text("Finish setup")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(red: 0.92, green: 0.63, blue: 0.18).opacity(0.1), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(red: 0.92, green: 0.63, blue: 0.18).opacity(0.4), lineWidth: 1)
        }
    }

    private func stripeBalanceTile(label: String, cents: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            WhisperMoneyText(
                cents: cents,
                font: .system(size: 17, weight: .heavy, design: .rounded),
                color: WhisperTheme.ink(colorScheme)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 14))
    }

    private var bankRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.columns")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(width: 40, height: 40)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(overview?.bank.map { "\($0.bankName) ····\($0.last4)" } ?? "No bank on file yet")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text("Payouts run \(overview?.payoutSchedule?.interval ?? "daily") · ~\(overview?.payoutSchedule?.delayDays ?? 2)-day rolling")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            if let bank = overview?.bank {
                Text(bank.currency)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func linkBank() async {
        isLinkingBank = true
        defer { isLinkingBank = false }
        do {
            let url = try await billing.startConnectOnboarding()
            await MainActor.run {
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "whisper") { _, _ in
                    Task { await refresh() }
                }
                session.presentationContextProvider = WebAuthPresenter.shared
                session.start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Money movement

    private func moneyMovementCard(_ o: WhisperStripeOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WhisperTheme.coachAccent)
                    .frame(width: 34, height: 34)
                    .background(WhisperTheme.coachAccent.opacity(0.12), in: .rect(cornerRadius: 11))
                Text("Money movement")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
            }

            Text("PAYOUTS TO YOUR BANK")
                .font(.system(size: 9, weight: .black))
                .tracking(1.2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))

            let payouts = o.payouts ?? []
            if payouts.isEmpty {
                Text("No payouts yet — cash out above and it appears here.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(payouts.prefix(8).enumerated()), id: \.element.id) { index, payout in
                        payoutTimelineRow(payout, isLast: index == min(payouts.count, 8) - 1)
                    }
                }
            }

            Text("MONEY IN — RECENT TRANSFERS")
                .font(.system(size: 9, weight: .black))
                .tracking(1.2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.top, 4)

            let transfers = o.transfers ?? []
            if transfers.isEmpty {
                Text("Client payments route here automatically.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transfers.prefix(8).enumerated()), id: \.element.id) { index, transfer in
                        transferRow(transfer)
                        if index < min(transfers.count, 8) - 1 {
                            Divider().background(WhisperTheme.hairline(colorScheme))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func payoutStatusColor(_ status: String) -> Color {
        switch status {
        case "paid": return Color(red: 0.13, green: 0.65, blue: 0.36)
        case "failed", "canceled": return .red
        default: return Color(red: 0.92, green: 0.63, blue: 0.18)
        }
    }

    private func payoutTimelineRow(_ p: WhisperStripeOverview.PayoutRow, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(payoutStatusColor(p.status))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                if !isLast {
                    Rectangle()
                        .fill(WhisperTheme.hairline(colorScheme))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(WhisperBillingService.formatCents(p.amountCents))
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(p.arrivalDate != nil ? "Arrives \(whisperShortDate(p.arrivalDate))" : whisperShortDate(p.createdAt))
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Text(p.status.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.system(size: 8.5, weight: .black))
                .tracking(0.5)
                .foregroundStyle(payoutStatusColor(p.status))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(payoutStatusColor(p.status).opacity(0.12), in: Capsule())
        }
        .padding(.bottom, isLast ? 0 : 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func transferRow(_ t: WhisperStripeOverview.TransferRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                .frame(width: 30, height: 30)
                .background(Color(red: 0.13, green: 0.65, blue: 0.36).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(WhisperCoachEarningsView.cleanDescription(t.description) ?? "Earnings transfer")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text(whisperShortDate(t.createdAt))
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Text("+" + WhisperBillingService.formatCents(t.amountCents))
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
        }
        .padding(.vertical, 9)
    }

    // MARK: Monthly rate

    private var keepPreviewCents: Int {
        let cleaned = rateString
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(cleaned), dollars > 0 else { return 0 }
        return Int((dollars * 100 * 0.9).rounded())
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WhisperTheme.coachAccent)
                    .frame(width: 34, height: 34)
                    .background(WhisperTheme.coachAccent.opacity(0.12), in: .rect(cornerRadius: 11))
                Text("Your monthly rate")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Text("What clients pay per month for coaching. Whisper keeps a 10% platform fee — the rest lands in your balance above.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("$")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    TextField("149.99", text: $rateString)
                        .font(.subheadline.weight(.semibold))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("/month")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
                Button {
                    Haptics.tap()
                    Task { await saveRate() }
                } label: {
                    HStack(spacing: 6) {
                        if isSavingRate { ProgressView().tint(.white) }
                        Text("Save")
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(whisperEmberGradient, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSavingRate || rateString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if keepPreviewCents > 0 {
                Text("You keep \(WhisperBillingService.formatCents(keepPreviewCents))/month per client after the fee.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
            }
            if rateSaved {
                Text("Rate saved — clients see it on your profile and hire page.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func saveRate() async {
        let cleaned = rateString
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(cleaned), dollars >= 5, dollars <= 2000 else {
            errorMessage = "Enter a monthly rate between $5 and $2,000."
            return
        }
        isSavingRate = true
        errorMessage = nil
        rateSaved = false
        defer { isSavingRate = false }
        do {
            let cents = Int((dollars * 100).rounded())
            try await billing.saveCoachRate(monthlyPriceCents: cents)
            currentRateCents = cents
            rateSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Coaching link

    private var hireLink: String {
        "\(WhisperBillingBackend.webOrigin)/hire/\(AccountStorage.currentUserID.lowercased())"
    }

    private var coachingLinkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WhisperTheme.coachAccent)
                    .frame(width: 34, height: 34)
                    .background(WhisperTheme.coachAccent.opacity(0.12), in: .rect(cornerRadius: 11))
                Text("Your coaching link")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                ShareLink(item: hireLink) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            Text("Share this anywhere — clients open it, see your plans, and subscribe in one tap.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Button {
                Haptics.tap()
                UIPasteboard.general.string = hireLink
                linkCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    linkCopied = false
                }
            } label: {
                HStack(spacing: 8) {
                    Text(hireLink)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(linkCopied ? Color(red: 0.13, green: 0.65, blue: 0.36) : WhisperTheme.muted(colorScheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            linkCopied ? Color(red: 0.13, green: 0.65, blue: 0.36).opacity(0.5) : WhisperTheme.hairline(colorScheme),
                            lineWidth: 1
                        )
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Payment history

    private func paymentHistory(_ e: WhisperCoachEarnings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "receipt")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WhisperTheme.coachAccent)
                    .frame(width: 34, height: 34)
                    .background(WhisperTheme.coachAccent.opacity(0.12), in: .rect(cornerRadius: 11))
                Text("Payments")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            if e.payments.isEmpty {
                VStack(spacing: 8) {
                    WhisperMeetDoodle(symbol: "banknote", height: 120)
                    Text("No payments yet")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Share your coaching link to get your first client — payments land here the moment they subscribe.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(e.payments) { payment in
                        paymentRow(payment)
                        if payment.id != e.payments.last?.id {
                            Divider().background(WhisperTheme.hairline(colorScheme)).padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func paymentRow(_ p: WhisperCoachPaymentRow) -> some View {
        let isProgramSale = (p.description ?? "").contains("[program:")
        return HStack(spacing: 11) {
            Text(String((p.client_email ?? "C").prefix(1)).uppercased())
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(whisperEmberGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Self.cleanDescription(p.description) ?? "Coaching payment")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    if isProgramSale {
                        Text("PROGRAM")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(WhisperTheme.coachAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(WhisperTheme.coachAccent.opacity(0.14), in: Capsule())
                    }
                }
                Text(Self.formatDate(p.created_at) + ((p.client_email?.isEmpty == false) ? " · \(p.client_email!)" : ""))
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("+" + WhisperBillingService.formatCents(p.net_cents))
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                Text("\(WhisperBillingService.formatCents(p.gross_cents)) − fee")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(.vertical, 10)
    }

    private var footerNote: some View {
        Text("Payments and payouts are processed by Stripe. Whisper keeps a 10% platform fee on client payments; payouts to your bank are free.")
            .font(.caption2)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.9))
                .frame(height: 230)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(WhisperTheme.card(colorScheme))
                        .frame(height: 84)
                }
            }
            RoundedRectangle(cornerRadius: 20)
                .fill(WhisperTheme.card(colorScheme))
                .frame(height: 150)
            RoundedRectangle(cornerRadius: 20)
                .fill(WhisperTheme.card(colorScheme).opacity(0.7))
                .frame(height: 120)
        }
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
        .opacity(0.75)
    }

    /// Drops internal `[program:id]` fulfillment markers from Stripe
    /// checkout descriptions before display.
    nonisolated static func cleanDescription(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        let cleaned = raw.replacingOccurrences(
            of: #"\s*\[program:[^\]]*\]"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    nonisolated static func formatDate(_ iso: String) -> String {
        guard let date = WhisperBackendService.parseISO(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Coach rate setting sheet

/// Lets a coach set their monthly coaching rate. Mirrors the web's
/// Coach Studio pricing panel.
struct WhisperCoachRateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var billing = WhisperBillingService.shared
    @State private var rateString: String = ""
    @State private var currentRate: Int?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showSaved: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "tag.fill")
                            .font(.largeTitle)
                            .foregroundStyle(WhisperTheme.coachAccent)
                        Text("Set your monthly rate")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("Clients pay this every month to be coached by you. You can change it anytime — existing clients keep their current rate until they renew.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 20)

                    HStack(spacing: 6) {
                        Text("$")
                            .font(.title.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        TextField("50", text: $rateString)
                            .font(.system(size: 34, weight: .black))
                            .keyboardType(.numberPad)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .multilineTextAlignment(.leading)
                        Text("/ month")
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        Spacer()
                    }
                    .padding(16)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                    .padding(.horizontal, 20)

                    Text("Range: $5 – $2,000 / month")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))

                    Button {
                        Haptics.tap()
                        Task { await saveRate() }
                    } label: {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView().tint(.white)
                            }
                            Text(currentRate != nil ? "Update rate" : "Set rate")
                                .font(.body.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(WhisperTheme.coachAccent, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || rateString.isEmpty)
                    .padding(.horizontal, 20)

                    if showSaved {
                        Text("Rate saved! Clients can now hire you from your profile.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
                            .padding(.horizontal, 20)
                    }
                    if let err = errorMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
            }
            .navigationTitle("Monthly Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await loadCurrentRate() }
    }

    private func loadCurrentRate() async {
        do {
            let rate = try await billing.fetchCoachRate(coachUserID: AccountStorage.currentUserID.lowercased())
            if let cents = rate.monthlyPriceCents {
                currentRate = cents
                rateString = cents % 100 == 0
                    ? String(cents / 100)
                    : String(format: "%.2f", Double(cents) / 100)
            }
        } catch {
            // No rate set yet — that's fine.
        }
    }

    private func saveRate() async {
        let cleaned = rateString
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(cleaned), dollars >= 5, dollars <= 2000 else {
            errorMessage = "Enter a monthly rate between $5 and $2,000."
            return
        }
        isLoading = true
        errorMessage = nil
        showSaved = false
        defer { isLoading = false }
        do {
            let cents = Int((dollars * 100).rounded())
            try await billing.saveCoachRate(monthlyPriceCents: cents)
            currentRate = cents
            showSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - My coach subscriptions (client side)

/// Shows the signed-in client's active coaching subscriptions and lets them
/// cancel at the end of the current paid month.
struct WhisperMyCoachSubscriptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var billing = WhisperBillingService.shared
    @State private var subscriptions: [WhisperCoachSubscription] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if isLoading && subscriptions.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .padding(.top, 60)
                        } else if subscriptions.isEmpty && errorMessage == nil {
                            VStack(spacing: 8) {
                                WhisperMeetDoodle(symbol: "person.crop.circle.badge.checkmark", height: 144)
                                Text("No active coaching subscriptions")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text("When you hire a coach, your subscription shows here.")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            .padding(.top, 40)
                        } else {
                            ForEach(subscriptions) { sub in
                                subscriptionCard(sub)
                            }
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }
                        Color.clear.frame(height: 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("My Coaches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await loadSubscriptions() }
    }

    private func loadSubscriptions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            subscriptions = try await billing.fetchMyCoachSubscriptions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func subscriptionCard(_ sub: WhisperCoachSubscription) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(WhisperTheme.coachAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.coachUsername.map { "@\($0)" } ?? "Your coach")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    if let price = sub.priceCents {
                        Text("\(WhisperBillingService.formatCents(price)) / month")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                Spacer()
                statusPill(sub)
            }
            if let periodEnd = sub.currentPeriodEnd,
               let date = WhisperBackendService.parseISO(periodEnd) {
                Text("\(sub.cancelAtPeriodEnd ? "Access ends" : "Renews") \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            if !sub.cancelAtPeriodEnd {
                Button(role: .destructive) {
                    Haptics.warning()
                    Task { await cancelSubscription(sub) }
                } label: {
                    Text("Cancel at end of billing period")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("Access continues until the end of your current billing period.")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.92, green: 0.63, blue: 0.18))
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func statusPill(_ sub: WhisperCoachSubscription) -> some View {
        let (color, label): (Color, String) = {
            if sub.cancelAtPeriodEnd {
                return (Color(red: 0.92, green: 0.63, blue: 0.18), "Cancelling")
            }
            switch sub.status {
            case "active", "trialing": return (Color(red: 0.13, green: 0.65, blue: 0.36), "Active")
            case "past_due": return (Color.red, "Past due")
            default: return (WhisperTheme.muted(colorScheme), sub.status.capitalized)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func cancelSubscription(_ sub: WhisperCoachSubscription) async {
        do {
            try await billing.cancelCoachSubscription(subscriptionID: sub.id)
            await loadSubscriptions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Coach hire sheet (client initiates checkout)

/// Sheet shown when a client taps "Hire @coach" on a coach's profile.
/// Mirrors the web hire page: published plan tiers as selectable cards
/// (single-rate fallback), what-you-get rows, and a Stripe checkout via
/// ASWebAuthenticationSession.
struct WhisperCoachHireSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let coachUsername: String
    let coachUserID: String
    let monthlyPriceCents: Int?

    @State private var billing = WhisperBillingService.shared
    @State private var rateCard: WhisperCoachRate?
    @State private var checkoutSession: ASWebAuthenticationSession?
    @State private var checkoutOpen: Bool = false
    @State private var checkoutNotice: String?
    @State private var pendingCheckoutURL: URL?
    @State private var isCheckingHire: Bool = false
    @State private var hirePaid: Bool = false
    @State private var hirePresentationActive: Bool = true
    @State private var ownerGeneration: UUID = AccountStorage.generation
    @State private var selectedTierID: String?
    @State private var isLoading: Bool = false
    @State private var isFetchingPlans: Bool = true
    @State private var errorMessage: String?

    private var tiers: [WhisperCoachTier] { rateCard?.tiers ?? [] }

    private var selectedTier: WhisperCoachTier? {
        tiers.first { $0.id == selectedTierID } ?? tiers.first
    }

    private var priceCents: Int? {
        selectedTier?.monthlyPriceCents ?? rateCard?.monthlyPriceCents ?? monthlyPriceCents
    }

    private let defaultPerks: [String] = [
        "Direct line to your coach in DMs",
        "Personalized programming & check-ins",
        "Cancel anytime — no lock-in",
        "Your coach keeps 90% of every payment",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header

                        if isFetchingPlans && tiers.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.muted(colorScheme))
                                .padding(.vertical, 12)
                        } else if !tiers.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(tiers) { tier in
                                    tierCard(tier).disabled(isLoading || checkoutOpen || pendingCheckoutURL != nil || hirePaid)
                                }
                            }
                            .padding(.horizontal, 20)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(defaultPerks, id: \.self) { perk in
                                    perkRow(perk)
                                }
                            }
                            .padding(.horizontal, 28)
                        }

                        if let notice = checkoutNotice {
                            Text(notice).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24)
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        VStack(spacing: 6) {
                            Text("Billed monthly through Stripe · cancel anytime · 7-day refund window")
                                .font(.caption2.weight(.semibold))
                            Text("Payments are processed securely by Stripe. Whisper never sees your card details.")
                                .font(.caption2)
                        }
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 28)
                        .padding(.bottom, 8)
                        WhisperPaymentLegalFooter()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    subscribeButton
                    Button("Refresh coaching access") { Task { await reconcileHire() } }
                        .font(.caption).frame(minHeight: 44).disabled(isLoading || checkoutOpen || isCheckingHire)
                    Text("USD · billed monthly · cancel in Coaching subscriptions")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .background(WhisperTheme.surface(colorScheme))
            }
            .navigationTitle("Your coaching plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { hirePresentationActive = false; checkoutSession?.cancel(); dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(WhisperMenuGeometry.sheetRadius)
        .task { await loadPlans(); await reconcileHire() }
        .onDisappear { if !checkoutOpen { hirePresentationActive = false } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            hirePresentationActive = false
            checkoutSession?.cancel(); checkoutSession = nil; dismiss()
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            WhisperMembershipIllustration(kind: .coach)
            Text("VERIFIED COACH")
                .font(.system(size: 9.5, weight: .black))
                .tracking(2)
                .foregroundStyle(WhisperTheme.coachAccent)
            Text("Train with @\(coachUsername)")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .multilineTextAlignment(.center)
            Text("A plan for your progress. Choose the support that feels right for you, directly with your coach on Whisper.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 24)
        }
    }

    private func tierCard(_ tier: WhisperCoachTier) -> some View {
        let isActive = tier.id == (selectedTier?.id ?? "")
        return Button {
            Haptics.tap()
            selectedTierID = tier.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                isActive ? WhisperTheme.coachAccent : WhisperTheme.hairline(colorScheme),
                                lineWidth: isActive ? 6 : 1.5
                            )
                            .frame(width: 20, height: 20)
                    }
                    .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        if let tagline = tier.tagline, !tagline.isEmpty {
                            Text(tagline)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(WhisperBillingService.formatCents(tier.monthlyPriceCents))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(WhisperTheme.coachAccent)
                        Text("/month")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                if !tier.perks.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(tier.perks, id: \.self) { perk in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(WhisperTheme.coachAccent)
                                    .padding(.top, 2.5)
                                Text(perk)
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 30)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive ? WhisperTheme.coachAccent.opacity(0.06) : WhisperTheme.card(colorScheme),
                in: .rect(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        isActive ? WhisperTheme.coachAccent : WhisperTheme.hairline(colorScheme),
                        lineWidth: isActive ? 1.5 : 1
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func perkRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(WhisperTheme.coachAccent)
                .frame(width: 24)
            Text(text)
                .font(.footnote)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }

    private var subscribeButton: some View {
        Button {
            Haptics.tap()
            Task { await startHire() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                }
                Text(hirePaid ? "Your coaching is active" : pendingCheckoutURL != nil ? "Resume secure checkout" : priceCents == nil
                     ? "Rate not set"
                     : "Subscribe — \(WhisperBillingService.formatCents(priceCents ?? 0))/month")
                    .font(.body.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                priceCents == nil
                    ? AnyShapeStyle(WhisperTheme.muted(colorScheme).opacity(0.4))
                    : AnyShapeStyle(whisperEmberGradient),
                in: Capsule()
            )
            .foregroundStyle(.white)
            .shadow(color: WhisperTheme.coachAccent.opacity(priceCents == nil ? 0 : 0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        // A nil rate means Stripe checkout has nothing to charge —
        // the server call would fail cryptically. Disable instead.
        .disabled(isLoading || checkoutOpen || isCheckingHire || hirePaid || isFetchingPlans || rateCard == nil || priceCents == nil)
        .padding(.horizontal, 20)
    }

    private func loadPlans() async {
        isFetchingPlans = true
        defer { isFetchingPlans = false }
        do {
            let card = try await billing.fetchCoachRate(coachUserID: coachUserID)
            guard ownerGeneration == AccountStorage.generation, !Task.isCancelled else { return }
            rateCard = card
            errorMessage = nil
            if selectedTierID == nil { selectedTierID = card.tiers?.first?.id }
        } catch {
            guard ownerGeneration == AccountStorage.generation else { return }
            errorMessage = "Current plans couldn’t be loaded. Please close and try again."
        }
    }

    private func reconcileHire() async {
        guard !isCheckingHire, hirePresentationActive, ownerGeneration == AccountStorage.generation else { return }
        isCheckingHire = true
        defer { isCheckingHire = false }
        do {
            let status = try await billing.fetchHireStatus(coachUserID: coachUserID)
            guard hirePresentationActive, ownerGeneration == AccountStorage.generation, !Task.isCancelled else { return }
            hirePaid = status.paid
            if hirePaid {
                pendingCheckoutURL = nil
                checkoutNotice = "Your coaching subscription is active. Manage it in Settings → Coaching subscriptions."
            } else if pendingCheckoutURL != nil {
                checkoutNotice = "Payment hasn’t been confirmed yet. Refresh access, or resume the same checkout if you haven’t paid."
            }
        } catch {
            guard hirePresentationActive, ownerGeneration == AccountStorage.generation else { return }
            errorMessage = "Coaching access couldn’t be checked. Refresh before purchasing again."
        }
    }

    private func startHire() async {
        guard hirePresentationActive, !hirePaid, !isLoading, !checkoutOpen, !isCheckingHire, rateCard != nil, ownerGeneration == AccountStorage.generation else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let tierID = selectedTier?.id
            let status = try await billing.fetchHireStatus(coachUserID: coachUserID)
            guard hirePresentationActive, ownerGeneration == AccountStorage.generation, !Task.isCancelled else { return }
            if status.paid {
                hirePaid = true
                checkoutNotice = "You already have active coaching with this coach."
                return
            }
            let url: URL
            if let pendingCheckoutURL { url = pendingCheckoutURL }
            else { url = try await billing.startHireCheckout(coachUserID: coachUserID, tierId: tierID) }
            guard hirePresentationActive, ownerGeneration == AccountStorage.generation, !Task.isCancelled else { return }
            pendingCheckoutURL = url
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "whisper") { _, _ in
                Task { @MainActor in
                    guard hirePresentationActive, ownerGeneration == AccountStorage.generation else { return }
                    checkoutOpen = false
                    checkoutSession = nil
                    await reconcileHire()
                }
            }
            session.presentationContextProvider = WebAuthPresenter.shared
            checkoutSession = session
            checkoutOpen = session.start()
            if !checkoutOpen { errorMessage = "Checkout couldn’t open. Please try again." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
