import SwiftUI
import AuthenticationServices

/// Whisper Paid Partners card — the creator's cut of REAL ad revenue.
/// Mirrors the web Creator Studio card exactly: every month, 50% of actual
/// ad spend becomes the creator pool; a creator's month = min(views × tier
/// RPM, their view-share of the pool). Months finalize on the 1st; only
/// closed months cash out (min $10) through the same in-app Stripe rail
/// coaches use.
struct WhisperWppCard: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var billing = WhisperBillingService.shared
    @State private var summary: WhisperWppSummary?
    @State private var isLoading: Bool = true
    @State private var isCashingOut: Bool = false
    @State private var isLinkingBank: Bool = false
    @State private var notice: String?
    @State private var errorMessage: String?

    private let ember = Color(red: 0.976, green: 0.451, blue: 0.086)
    private let amber = Color(red: 0.961, green: 0.62, blue: 0.043)

    private var emberGradient: LinearGradient {
        LinearGradient(colors: [ember, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isLoading && summary == nil {
                HStack {
                    Spacer()
                    ProgressView().tint(WhisperTheme.muted(colorScheme))
                    Spacer()
                }
                .padding(.vertical, 18)
            } else if let s = summary {
                if s.eligible {
                    eligibleBody(s)
                } else {
                    lockedBody(s)
                }
            } else if errorMessage != nil {
                Text("Couldn't load your WPP standing — pull to refresh.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            if let notice {
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.65, blue: 0.36))
            }
            if let errorMessage, summary != nil {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .task { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(emberGradient, in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text("Whisper Paid Partners")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Your share of real ad revenue — 50% of ad spend pays creators")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Text(summary?.eligible == true ? (summary?.tierLabel ?? "Partner").uppercased() : "LOCKED")
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(summary?.eligible == true ? ember : WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    (summary?.eligible == true ? ember.opacity(0.14) : WhisperTheme.muted(colorScheme).opacity(0.12)),
                    in: Capsule()
                )
        }
    }

    // MARK: - Locked

    private func lockedBody(_ s: WhisperWppSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lockedLine(s))
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(WhisperTheme.muted(colorScheme).opacity(0.16))
                    Capsule()
                        .fill(emberGradient)
                        .frame(width: max(6, geo.size.width * min(1, CGFloat(s.followers) / 1000)))
                }
            }
            .frame(height: 8)
        }
    }

    private func lockedLine(_ s: WhisperWppSummary) -> String {
        let toGo = max(0, (s.nextTierFollowers ?? 1000) - s.followers)
        return "WPP unlocks at 1,000 followers — you're at \(s.followers) (\(toGo) to go). Then your qualified views earn a monthly share of the ad-revenue pool — half of every ad dollar goes to creators."
    }

    // MARK: - Eligible

    private func eligibleBody(_ s: WhisperWppSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statTile(label: "Views · month", value: shortNumber(s.monthViews))
                statTile(label: "\(monthName) · est.", value: WhisperBillingService.formatCents(s.monthEstimatedCents))
                statTile(label: "Cashable", value: WhisperBillingService.formatCents(s.availableCents), tint: ember)
            }

            Text("\(monthName)'s creator pool so far: \(WhisperBillingService.formatCents(s.poolMonthCents)) — funded by real ad spend. Your month finalizes on the 1st and becomes cashable.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if !s.payoutsReady {
                Button {
                    Haptics.tap()
                    Task { await linkBank() }
                } label: {
                    HStack(spacing: 8) {
                        if isLinkingBank { ProgressView().tint(colorScheme == .dark ? .black : .white) }
                        Image(systemName: "building.columns.fill")
                        Text("Link bank to get paid")
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                }
                .buttonStyle(.plain)
                .disabled(isLinkingBank)
            } else {
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
                        Text(s.availableCents >= 1000
                             ? "Cash out \(WhisperBillingService.formatCents(s.availableCents))"
                             : "Cash out (unlocks at $10)")
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        s.availableCents >= 1000
                            ? AnyShapeStyle(emberGradient)
                            : AnyShapeStyle(WhisperTheme.muted(colorScheme).opacity(0.35)),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isCashingOut || s.availableCents < 1000)
            }

            Text(footnote(s))
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footnote(_ s: WhisperWppSummary) -> String {
        var line = "Your tier caps at \(WhisperBillingService.formatCents(s.rpmCents))/1k qualified views · one view per person per post per day, never self-views · paid via Stripe"
        if s.cashedOutCents > 0 {
            line += " · \(WhisperBillingService.formatCents(s.cashedOutCents)) paid out so far"
        }
        return line
    }

    private func statTile(label: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(tint ?? WhisperTheme.ink(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            summary = try await billing.fetchWppSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cashOut() async {
        isCashingOut = true
        errorMessage = nil
        notice = nil
        defer { isCashingOut = false }
        do {
            let result = try await billing.wppCashOut()
            notice = result.sentToBank
                ? "\(WhisperBillingService.formatCents(result.amountCents)) is on its way to your bank."
                : "\(WhisperBillingService.formatCents(result.amountCents)) moved to your payout balance."
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func linkBank() async {
        isLinkingBank = true
        defer { isLinkingBank = false }
        do {
            let url = try await billing.startConnectOnboarding()
            await MainActor.run {
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "whisper") { _, _ in
                    Task { await reload() }
                }
                session.presentationContextProvider = WebAuthPresenter.shared
                session.start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shortNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
