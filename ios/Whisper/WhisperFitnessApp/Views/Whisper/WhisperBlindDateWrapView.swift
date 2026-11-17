import SwiftUI

/// What a blind date looks like when it ENDS — not a meeting recap. The
/// wrap asks for your private decision (see them again · friends · pass),
/// reveals the partner's answer only once both are in (mutual 💘 → the
/// linking celebration + a DM), offers Jasper's read of the date on tap,
/// and keeps the safety exits one tap away. Mirrors web `BlindDateWrap`.
struct WhisperBlindDateWrapView: View {
    let roomCode: String
    let meetingTitle: String
    let myUserID: String
    let myName: String
    let myAvatarURL: URL?
    let partnerUserID: String
    let partnerName: String
    let partnerAvatarURL: URL?
    let transcript: String
    let theirCard: WhisperSpeedDating.WireCard?
    let revealed: Bool
    let partnerLeft: Bool
    let elapsedSec: Int
    let onClose: () -> Void

    @State private var decision: WhisperBlindDate.Decision? = nil
    @State private var theirDecision: WhisperBlindDate.Decision? = nil
    @State private var waitingForThem: Bool = false
    @State private var waitTimedOut: Bool = false
    @State private var mutual: Bool = false
    @State private var showCelebration: Bool = false
    @State private var recap: WhisperSpeedDating.Verdict? = nil
    @State private var recapBusy: Bool = false
    @State private var recapFailed: Bool = false
    @State private var openDM: Bool = false
    @State private var showReport: Bool = false
    @State private var showSecondDate: Bool = false
    @State private var secondDateSent: Bool = false
    @State private var openerCopied: Bool = false
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var appeared: Bool = false
    @State private var ownerGeneration: UUID = AccountStorage.generation
    @State private var savingDecision: Bool = false
    @State private var decisionError: Bool = false

    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
    private let blush = Color(red: 1.0, green: 0.62, blue: 0.75)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.03, blue: 0.08),
                    Color(red: 0.28, green: 0.06, blue: 0.14),
                    Color(red: 0.12, green: 0.03, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                        .padding(.top, 18)
                    decisionCard
                    recapCard
                    safetyRow
                    Button {
                        Haptics.tap()
                        onClose()
                    } label: {
                        Text("Back to Dating")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 18)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
            }

            if showCelebration {
                WhisperMatchCelebrationView(
                    myName: myName,
                    myAvatarURL: myAvatarURL,
                    otherName: partnerName,
                    otherAvatarURL: partnerAvatarURL,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) { showCelebration = false }
                    }
                )
                .transition(.opacity)
                .zIndex(60)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showReport) {
            WhisperDatingReportSheet(username: partnerName, roomCode: roomCode)
        }
        .sheet(isPresented: $showSecondDate) {
            WhisperSecondDateSheet(partnerUserID: partnerUserID, partnerName: partnerName, onSent: { secondDateSent = true })
        }
        .sheet(isPresented: $openDM) {
            NavigationStack {
                WhisperDMThreadView(otherUserID: partnerUserID, otherUsername: partnerName, conversationKind: .dating)
            }
            .task { WhisperDatingContacts.mark(partnerUserID) }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { appeared = true }
            Task { await WhisperBlindDate.finish(roomCode: roomCode, revealed: revealed, recap: nil) }
        }
        .onDisappear { pollTask?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in pollTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                avatar(url: myAvatarURL, name: myName)
                    .offset(x: -30)
                avatar(url: partnerAvatarURL, name: partnerName)
                    .offset(x: 30)
                Text("💘")
                    .font(.system(size: 22))
                    .padding(6)
                    .background(Circle().fill(Color(red: 0.20, green: 0.05, blue: 0.12)))
                    .offset(y: 28)
            }
            .frame(height: 96)
            Text("DATE OVER")
                .font(.system(size: 10.5, weight: .black))
                .tracking(2.2)
                .foregroundStyle(blush)
            Text(partnerLeft ? "@\(partnerName) left the date" : "Your date with @\(partnerName)")
                .font(.system(size: 24, weight: .black))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("\(max(1, elapsedSec / 60)) min · \(revealed ? "you revealed 👀" : "stayed blind 🙈")")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func avatar(url: URL?, name: String) -> some View {
        ZStack {
            Circle().fill(rose.opacity(0.35))
            if let url {
                WhisperCachedAsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 3))
        .shadow(color: rose.opacity(0.4), radius: 12, y: 4)
    }

    // MARK: - Decision

    private var decisionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let decision {
                decidedState(decision)
            } else {
                Text("Would you see @\(partnerName) again?")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Your answer stays private. They only find out if you BOTH say yes.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    if savingDecision { ProgressView("Saving your answer…").tint(.white) }
                    if decisionError {
                        Text("Your answer couldn't be saved. Tap your choice to try again.")
                            .font(.footnote).foregroundStyle(.white)
                    }
                    decisionButton(.again, primary: true)
                    HStack(spacing: 8) {
                        decisionButton(.friends, primary: false)
                        decisionButton(.pass, primary: false)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(rose.opacity(0.35), lineWidth: 1)
        )
    }

    private func decisionButton(_ d: WhisperBlindDate.Decision, primary: Bool) -> some View {
        Button {
            Haptics.tap()
            decide(d)
        } label: {
            HStack(spacing: 6) {
                Text(d.emoji)
                Text(d.label)
                    .font(.system(size: primary ? 15 : 13, weight: .black))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, primary ? 14 : 11)
            .background(
                Capsule().fill(
                    primary
                        ? AnyShapeStyle(LinearGradient(colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.12))
                )
            )
            .overlay(Capsule().strokeBorder(.white.opacity(primary ? 0 : 0.2), lineWidth: 1))
            .shadow(color: rose.opacity(primary ? 0.35 : 0), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(savingDecision)
    }

    @ViewBuilder
    private func decidedState(_ d: WhisperBlindDate.Decision) -> some View {
        switch d {
        case .again:
            HStack(spacing: 8) {
                Text("💘").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mutual ? "It's a match!" : "You said yes")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(mutualLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if waitingForThem && !mutual && theirDecision == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(blush)
                    Text("Waiting for @\(partnerName)'s answer…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(blush)
                }
            }
            if mutual {
                HStack(spacing: 8) {
                    Button {
                        Haptics.tap()
                        openDM = true
                    } label: {
                        Label("Say hi 💬", systemImage: "bubble.left.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(rose))
                    }
                    .buttonStyle(.plain)
                    Button {
                        Haptics.tap()
                        showSecondDate = true
                    } label: {
                        Label(secondDateSent ? "Invite sent ✓" : "Plan date 2 📅", systemImage: "calendar.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .disabled(secondDateSent)
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showCelebration = true }
                    } label: {
                        Text("Replay 💘")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(blush)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .friends:
            HStack(spacing: 8) {
                Text("🤝").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friends it is")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("@\(partnerName) is in your 💘 inbox — send a friendly note whenever.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                Haptics.tap()
                openDM = true
            } label: {
                Label("Send a friendly note", systemImage: "bubble.left.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        case .pass:
            HStack(spacing: 8) {
                Text("👋").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not this time")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Got it. @\(partnerName) will never know — on to the next one.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var mutualLine: String {
        if mutual { return "You both want to see each other again 💘 — the chat is open." }
        if theirDecision != nil { return "@\(partnerName) chose differently this time — it happens. Your yes stays private." }
        if waitTimedOut { return "Your answer is saved. Check your dating history for their answer later." }
        return "Your answer is saved. Waiting to see if you both chose yes."
    }

    // MARK: - Recap

    private var recapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                WhisperJasperInteractiveMascot(size: 34, dating: true, working: recapBusy,
                    restingExpression: recap != nil ? .delighted : .calm)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Jasper's read of the date")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Both cards + what you actually said")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            if let r = recap {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(r.score)%")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(blush)
                    Text("COMPATIBLE")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.55))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [rose, blush], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(r.score) / 100)
                    }
                }
                .frame(height: 6)
                if !r.verdict.isEmpty {
                    Text(r.verdict)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(r.sparks, id: \.self) { spark in
                    Text("💘 \(spark)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let flag = r.flag, !flag.isEmpty {
                    Text("🚩 \(flag)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let opener = r.opener, !opener.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR OPENER")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(blush)
                        Text("“\(opener)”")
                            .font(.system(size: 13, weight: .semibold))
                            .italic()
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Haptics.tap()
                            UIPasteboard.general.string = opener
                            withAnimation(.easeOut(duration: 0.2)) { openerCopied = true }
                            openDM = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: openerCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10, weight: .bold))
                                Text(openerCopied ? "Copied — paste it in the chat" : "Copy & open the chat")
                                    .font(.system(size: 11.5, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(rose))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07)))
                }
                if !r.askNext.isEmpty {
                    Text("Next time, ask: \(r.askNext)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "No transcript landed from this date, so Jasper will read the two cards."
                     : "One quiet read — score, what clicked, one honest flag, and the first message to send.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                if recapFailed {
                    Text("Jasper couldn't read that — try again in a moment.")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(blush)
                }
                Button {
                    Haptics.tap()
                    Task { await runRecap() }
                } label: {
                    HStack(spacing: 6) {
                        if recapBusy {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                        }
                        Text(recapBusy ? "Jasper is reading…" : "Read the date")
                            .font(.system(size: 12.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(rose))
                }
                .buttonStyle(.plain)
                .disabled(recapBusy)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Safety

    private var safetyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.64, green: 0.98, blue: 0.80))
            Text("Something felt off?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                showReport = true
            } label: {
                Text("Report @\(partnerName)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Actions

    private func decide(_ d: WhisperBlindDate.Decision) {
        guard !savingDecision, ownerGeneration == AccountStorage.generation,
              AccountStorage.currentUserID.lowercased() == myUserID.lowercased() else { return }
        savingDecision = true
        decisionError = false
        pollTask?.cancel()
        pollTask = Task {
            let result = await WhisperBlindDate.decide(roomCode: roomCode, decision: d)
            guard !Task.isCancelled, ownerGeneration == AccountStorage.generation else { return }
            savingDecision = false
            guard let result else { decisionError = true; return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { decision = d }
            if d != .pass { WhisperDatingContacts.mark(partnerUserID) }
            guard d == .again else { return }
            if let raw = result.theirs, let parsed = WhisperBlindDate.Decision(rawValue: raw) {
                landTheirDecision(parsed)
            } else {
                waitingForThem = true
                startPolling()
            }
        }
    }

    /// Reads this date's participant-authorized decision for up to two minutes.
    /// Unscoped DM match tokens cannot establish a decision for this room.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<20 {
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                guard ownerGeneration == AccountStorage.generation else { return }
                // Read the existing participant-scoped history instead of rewriting
                // the decision on every poll or refreshing the entire inbox.
                let history = await WhisperBlindDate.history()
                guard !Task.isCancelled, ownerGeneration == AccountStorage.generation else { return }
                if let raw = history.first(where: { $0.room_code == roomCode })?.their_decision,
                   let parsed = WhisperBlindDate.Decision(rawValue: raw) {
                    landTheirDecision(parsed); return
                }
            }
            await MainActor.run {
                waitingForThem = false
                waitTimedOut = true
            }
        }
    }

    private func landTheirDecision(_ d: WhisperBlindDate.Decision) {
        guard !Task.isCancelled, ownerGeneration == AccountStorage.generation,
              AccountStorage.currentUserID.lowercased() == myUserID.lowercased() else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            theirDecision = d
            waitingForThem = false
            mutual = (d == .again && decision == .again)
        }
        guard mutual else { return }
        Haptics.success()
        // Seal the match on the DM rails exactly like the Match-back button.
        let body = WhisperMatchWire.matchedBody(from: myUserID, name: myName)
        Task {
                guard ownerGeneration == AccountStorage.generation else { return }
                _ = await WhisperBackendService.shared.sendMessage(toUserID: partnerUserID, toUsername: partnerName, body: body, conversationKind: .dating)
            }
        WhisperMatchWire.markCelebrationSeen(threadWith: WhisperConversationKind.dating.localKey(peer: partnerUserID))
        WhisperDatingContacts.mark(partnerUserID)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showCelebration = true }
    }

    private func runRecap() async {
        guard !recapBusy else { return }
        recapBusy = true
        recapFailed = false
        let result = await WhisperBlindDate.generateRecap(
            myName: myName,
            myCard: WhisperSpeedDating.loadCard(),
            theirCard: theirCard,
            transcript: transcript,
            meetingTitle: meetingTitle
        )
        guard !Task.isCancelled, ownerGeneration == AccountStorage.generation else { return }
        recapBusy = false
        guard let result else {
            recapFailed = true
            return
        }
        Haptics.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { recap = result }
        await WhisperBlindDate.finish(roomCode: roomCode, revealed: revealed, recap: result)
    }
}
