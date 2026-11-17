import SwiftUI

// The morphing vitality blob lives in JasperNativeLooks.swift
// (JasperVitalityBlob) — drawn from Jasper's own published `look` spec so
// the card is pixel-true to the partner app and restyles automatically.

// MARK: - Card

/// The biological-age card — Whisper's rendering of the partner Jasper
/// app's hero: blob + glowing numeral, delta pill, confidence, and the
/// factor rows driving the score. `compact` fits coach dashboards.
struct WhisperBioAgeCardView: View {
    let row: WhisperBioAgeRow
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            hero
            deltaPill
            if !compact {
                confidenceRow
            }
            factorList
            bloodRow
            if !compact {
                Text("An estimate from synced health data — not a medical measurement.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Accent per Jasper's look spec — tinted by vitality t, read from the
    /// live `look` at runtime so Jasper-side palette tweaks flow through.
    private var specAccent: Color {
        JasperVitalityPalette.accent(deltaYears: row.deltaYears)
    }

    private var hero: some View {
        ZStack {
            JasperVitalityBlob(deltaYears: row.deltaYears, size: compact ? 122 : 166, compact: compact)
            VStack(spacing: 2) {
                Text(numberText)
                    .font(.system(size: compact ? 44 : 62, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: specAccent.opacity(0.6), radius: compact ? 12 : 18)
                    .contentTransition(.numericText())
                Text("BIOLOGICAL AGE")
                    .font(.system(size: compact ? 8.5 : 10, weight: .heavy))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(height: compact ? 146 : 198)
    }

    private var numberText: String {
        guard let bio = row.biologicalAge else { return "—" }
        return String(format: bio.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", bio)
    }

    private var deltaPill: some View {
        HStack(spacing: 6) {
            Image(systemName: (row.deltaYears ?? 0) <= 0 ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 12, weight: .bold))
            Text(row.deltaHeadline)
                .font(.system(size: 15, weight: .bold))
            if let chrono = row.chronologicalAge {
                Text("· real age \(Int(chrono.rounded()))")
                    .font(.system(size: 14))
                    .opacity(0.6)
            }
        }
        .foregroundStyle(specAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(specAccent.opacity(0.14), in: Capsule())
        .overlay { Capsule().strokeBorder(specAccent.opacity(0.35), lineWidth: 1) }
    }

    private var confidenceRow: some View {
        HStack(spacing: 6) {
            Circle().fill(row.confidenceColor).frame(width: 7, height: 7)
            Text("\(row.confidenceLevel.uppercased()) CONFIDENCE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var factorList: some View {
        let factors = Array(row.sortedFactors.prefix(compact ? 3 : 6))
        if !factors.isEmpty {
            VStack(spacing: 7) {
                ForEach(Array(factors.enumerated()), id: \.offset) { _, factor in
                    factorRow(factor)
                }
            }
        }
    }

    private func factorRow(_ factor: WhisperBioAgeFactor) -> some View {
        let delta = factor.delta ?? 0
        let color: Color = delta < 0
            ? Color(red: 0.16, green: 0.68, blue: 0.42)
            : (delta > 0 ? Color(red: 0.92, green: 0.42, blue: 0.26) : .secondary)
        return HStack(spacing: 10) {
            Image(systemName: factorSymbol(factor.title ?? ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(factor.title ?? "Factor")
                    .font(.system(size: 13.5, weight: .semibold))
                if let detail = factor.detail, !detail.isEmpty, !compact {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Text(String(format: "%@%.1fy", delta < 0 ? "−" : "+", abs(delta)))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 14))
    }

    private func factorSymbol(_ title: String) -> String {
        let t = title.lowercased()
        if t.contains("hrv") || t.contains("recovery") { return "waveform.path.ecg" }
        if t.contains("heart") || t.contains("hr") { return "heart.fill" }
        if t.contains("sleep") { return "moon.zzz.fill" }
        if t.contains("activity") || t.contains("active") || t.contains("step") { return "figure.walk" }
        if t.contains("vo2") || t.contains("vo₂") || t.contains("cardio") { return "lungs.fill" }
        if t.contains("body") || t.contains("bmi") || t.contains("fat") { return "figure.arms.open" }
        if t.contains("blood") || t.contains("pheno") { return "drop.fill" }
        return "chart.line.uptrend.xyaxis"
    }

    @ViewBuilder
    private var bloodRow: some View {
        let status: String = {
            if row.usedBloodBiomarkers == true {
                let f = (row.freshness ?? "").lowercased()
                if f.contains("aging") || f.contains("refresh") { return "Blood panel: refresh suggested" }
                return "Blood panel: up to date"
            }
            return "Blood panel: not included"
        }()
        HStack(spacing: 5) {
            Image(systemName: "drop.fill")
                .font(.system(size: 9, weight: .bold))
            Text(status)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Jasper action modal

/// The card Jasper's `bioage` action opens — fetches the live snapshot for
/// the asker (or a named client) and offers real sharing: a pre-filled feed
/// post or a DM card sent straight to someone.
struct WhisperBioAgeModalCard: View {
    @Environment(\.colorScheme) private var colorScheme
    /// nil = the signed-in user's own biological age.
    let username: String?

    @State private var row: WhisperBioAgeRow?
    @State private var loading: Bool = true
    @State private var dmHandle: String = ""
    @State private var dmSending: Bool = false
    @State private var dmSent: Bool = false
    @State private var dmError: String?
    @State private var showDmField: Bool = false

    private var isSelf: Bool {
        guard let username, !username.isEmpty else { return true }
        let mine = (LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "").lowercased()
        return username.lowercased() == mine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if loading {
                HStack {
                    Spacer()
                    ProgressView().tint(WhisperTheme.ink(colorScheme))
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if let row {
                ScrollView(showsIndicators: false) {
                    WhisperBioAgeCardView(row: row, compact: false)
                }
                .frame(maxHeight: 380)
                if isSelf {
                    shareRow(row)
                }
            } else {
                emptyState
            }
        }
        .padding(16)
        .frame(maxWidth: 440)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            WhisperEmberMascot(
                size: 26,
                expression: .attentive,
                coachMode: WhisperEmberCoachMode.load()
            )
            .frame(width: 26, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("JASPER")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(isSelf ? "Your biological age" : "@\(username ?? "")'s biological age")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                WhisperEmberActionRouter.shared.dismissModal()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 28, height: 28)
                    .background(WhisperTheme.surface(colorScheme), in: Circle())
                    .overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text(isSelf
                 ? "No biological age synced yet"
                 : "No biological age synced for this person")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(isSelf
                 ? "Open the Jasper app and add health data — your score syncs here automatically."
                 : "They haven't synced a Jasper biological-age snapshot with you yet.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    @ViewBuilder
    private func shareRow(_ row: WhisperBioAgeRow) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                shareButton("Post to feed", icon: "square.and.pencil") {
                    WhisperEmberActionRouter.shared.dismissModal()
                    WhisperEmberActionRouter.shared.openComposer(
                        draft: WhisperBioAgeService.feedPostText(row)
                    )
                }
                shareButton(
                    dmSent ? "Sent" : "Send in chat",
                    icon: dmSent ? "checkmark" : "paperplane.fill"
                ) {
                    withAnimation(.spring(response: 0.32)) { showDmField.toggle() }
                }
            }
            if showDmField, !dmSent {
                HStack(spacing: 8) {
                    TextField("@username", text: $dmHandle)
                        .font(.subheadline.weight(.semibold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                    Button {
                        Haptics.tap()
                        sendDm(row)
                    } label: {
                        Group {
                            if dmSending {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(WhisperTheme.surface(colorScheme))
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .frame(width: 40, height: 40)
                        .background(WhisperTheme.ink(colorScheme), in: Circle())
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                    }
                    .buttonStyle(.plain)
                    .disabled(dmSending || dmHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let dmError {
                    Text(dmError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func shareButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(WhisperTheme.ink(colorScheme), in: Capsule())
            .foregroundStyle(WhisperTheme.surface(colorScheme))
        }
        .buttonStyle(.plain)
    }

    private func sendDm(_ row: WhisperBioAgeRow) {
        guard !dmSending else { return }
        dmSending = true
        dmError = nil
        let myName = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "me"
        let payload = WhisperBioAgeService.sharePayload(
            row,
            senderUsername: myName,
            recordedOn: ISO8601DateFormatter().string(from: Date())
        )
        let body = WhisperHealthShareEmbed.encode(payload)
        let target = dmHandle
        Task {
            let error = await WhisperEmberActionRouter.shared.sendDirectMessage(to: target, body: body)
            dmSending = false
            if let error {
                dmError = error
            } else {
                Haptics.success()
                withAnimation(.spring(response: 0.3)) {
                    dmSent = true
                    showDmField = false
                }
            }
        }
    }

    private func load() async {
        loading = true
        if let username, !username.isEmpty, !isSelf {
            row = await WhisperBioAgeService.shared.fetch(forUsername: username)
        } else {
            row = await WhisperBioAgeService.shared.fetchMine(force: true)
        }
        loading = false
    }
}
