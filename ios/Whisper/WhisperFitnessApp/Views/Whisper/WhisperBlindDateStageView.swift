import SwiftUI

/// The blind-date STAGE — what a dating room looks like instead of a
/// meeting. Before the reveal, a rose curtain covers the video: two blurred
/// silhouettes, the shared timer ring counting down to the reveal, and
/// Jasper's prompt card. After the reveal the curtain parts into a slim HUD
/// (timer + stage + prompt) floating over the live video. The local
/// self-view and call controls render ABOVE this layer in the room.
struct WhisperBlindDateStageView: View {
    let session: WhisperBlindDateSession
    let myName: String
    let myAvatarURL: URL?
    let partnerName: String
    let partnerAvatarURL: URL?
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onReveal: () -> Void
    let onExtend: () -> Void
    let onPrompt: (Int) -> Void

    @State private var drift: Bool = false
    @State private var pulse: Bool = false
    @State private var revealFlash: Bool = false
    /// Round 77 — the partner's 15-second intro, playable behind the curtain.
    @State private var partnerIntro: WhisperDatingIntroService.Intro? = nil

    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
    private let blush = Color(red: 1.0, green: 0.62, blue: 0.75)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ZStack {
                if session.revealed {
                    revealedHUD
                        .transition(.opacity)
                } else {
                    curtain
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 1.12).combined(with: .opacity)
                        ))
                }
                if revealFlash {
                    revealFlashView
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: session.revealed)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: session.revealed) { _, revealed in
            guard revealed else { return }
            Haptics.success()
            withAnimation(.easeOut(duration: 0.25)) { revealFlash = true }
            Task {
                try? await Task.sleep(for: .milliseconds(1700))
                withAnimation(.easeOut(duration: 0.5)) { revealFlash = false }
            }
        }
    }

    // MARK: - The curtain (blind phase)

    private var curtain: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.03, blue: 0.09),
                    Color(red: 0.30, green: 0.06, blue: 0.15),
                    Color(red: 0.13, green: 0.03, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            ZStack {
                Circle()
                    .fill(rose.opacity(0.35))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .offset(x: drift ? -120 : 90, y: drift ? -220 : -140)
                Circle()
                    .fill(blush.opacity(0.22))
                    .frame(width: 260, height: 260)
                    .blur(radius: 66)
                    .offset(x: drift ? 130 : -80, y: drift ? 220 : 160)
            }
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                Spacer().frame(height: topInset + 58)

                HStack(alignment: .top, spacing: 22) {
                    silhouette(name: myName, url: myAvatarURL, ready: session.myRevealTapped, isMe: true)
                    Text("💘")
                        .font(.system(size: 26))
                        .scaleEffect(pulse ? 1.12 : 0.92)
                        .padding(.top, 26)
                    silhouette(name: partnerName, url: partnerAvatarURL, ready: session.theirRevealTapped, isMe: false)
                }

                timerRing(size: 150)

                if let partnerIntro {
                    WhisperDatingIntroPlayButton(intro: partnerIntro, name: partnerName)
                        .transition(.scale.combined(with: .opacity))
                }

                promptCard(compact: false)
                    .padding(.horizontal, 18)

                Spacer(minLength: 8)

                actionRow
                    .padding(.horizontal, 18)

                Spacer().frame(height: bottomInset + 104)
            }
            .frame(maxWidth: .infinity)
            .task(id: partnerName) {
                let intro = await WhisperDatingIntroService.shared.fetch(username: partnerName)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { partnerIntro = intro }
            }
        }
    }

    private func silhouette(name: String, url: URL?, ready: Bool, isMe: Bool) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 92, height: 92)
                if let url {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                    .frame(width: 92, height: 92)
                    .clipShape(Circle())
                    .blur(radius: isMe ? 0 : 16)
                    .clipShape(Circle())
                    .overlay(Circle().fill(Color.black.opacity(isMe ? 0 : 0.35)))
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(.white.opacity(isMe ? 0.9 : 0.25))
                        .frame(width: 92, height: 92)
                        .background(Circle().fill(rose.opacity(0.35)))
                        .blur(radius: isMe ? 0 : 6)
                        .clipShape(Circle())
                }
                Circle()
                    .strokeBorder(ready ? blush : Color.white.opacity(0.25), lineWidth: 2)
                    .frame(width: 92, height: 92)
                if !isMe {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if ready {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white, Color(red: 0.24, green: 0.78, blue: 0.5))
                        .offset(x: 34, y: -34)
                }
            }
            Text(isMe ? "You" : "@\(name)")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Text(ready ? "Ready to reveal" : (isMe ? "Blind" : "Hidden until the reveal"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ready ? blush : .white.opacity(0.5))
        }
        .frame(width: 124)
    }

    private func timerRing(size: CGFloat) -> some View {
        let total = Double(max(1, session.durationSec))
        let progress = session.startedAt == nil ? 0 : min(1, session.elapsed / total)
        let lastCall = session.isLastCall
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    AngularGradient(colors: [rose, blush, rose], center: .center),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
            VStack(spacing: 2) {
                if session.startedAt == nil {
                    Text("Waiting")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.white)
                    Text(session.theirReady ? "starting…" : "for @\(partnerName)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text(WhisperBlindDateSession.format(session.remaining))
                        .font(.system(size: 34, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(lastCall ? blush : .white)
                        .contentTransition(.numericText())
                    Text(lastCall ? "Last call 💘" : "Reveal in \(WhisperBlindDateSession.format(session.untilReveal))")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(lastCall ? blush : .white.opacity(0.65))
                    if !lastCall && session.untilReveal > 60 {
                        // The first minute is voice only — cameras stay dark
                        // until the reveal; only your voices meet.
                        Text("🎙 voice only")
                            .font(.system(size: 9.5, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.12)))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(lastCall && pulse ? 1.03 : 1.0)
    }

    // MARK: - Prompt card

    private func promptCard(compact: Bool) -> some View {
        let prompt = session.currentPrompt
        let stage = prompt?.stage ?? session.clockStage
        return VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 6) {
                Text("\(stage.emoji) \(stage.label.uppercased())")
                    .font(.system(size: 9.5, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(blush)
                if !session.deck.isEmpty {
                    Text("· \(min(session.promptIndex + 1, session.deck.count))/\(session.deck.count)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    WhisperEmberMascot(size: 18, expression: .happy, palette: .cupidPink, smitten: true)
                    Text("Jasper's prompt")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            if let prompt {
                Text(prompt.text)
                    .font(.system(size: compact ? 14 : 17, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(prompt.id)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Text("Jasper is writing prompts from both of your cards…")
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !session.deck.isEmpty {
                HStack(spacing: 8) {
                    promptStep(icon: "chevron.left", enabled: session.promptIndex > 0) { onPrompt(-1) }
                    promptStep(icon: "chevron.right", enabled: session.promptIndex < session.deck.count - 1) { onPrompt(1) }
                    Spacer()
                    Text(nudgeLine)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
        }
        .padding(compact ? 11 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.20, green: 0.05, blue: 0.12).opacity(compact ? 0.92 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(rose.opacity(0.4), lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: session.promptIndex)
    }

    private var nudgeLine: String {
        guard let prompt = session.currentPrompt else { return "" }
        let clock = session.clockStage
        if prompt.stage == .warm, clock != .warm { return "Ready to go deeper →" }
        if prompt.stage == .deeper, clock == .spark { return "Time for a spark →" }
        return "Ask each other"
    }

    private func promptStep(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(enabled ? 0.16 : 0.06)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                onReveal()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: session.myRevealTapped ? "hourglass" : "eye.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(revealLabel)
                        .font(.system(size: 14, weight: .black))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(
                        session.myRevealTapped
                            ? AnyShapeStyle(Color.white.opacity(0.14))
                            : AnyShapeStyle(LinearGradient(colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)], startPoint: .leading, endPoint: .trailing))
                    )
                )
                .overlay(Capsule().strokeBorder(.white.opacity(session.myRevealTapped ? 0.25 : 0), lineWidth: 1))
                .shadow(color: rose.opacity(session.myRevealTapped ? 0 : 0.35), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(session.myRevealTapped || session.startedAt == nil)
            .scaleEffect(session.theirRevealTapped && !session.myRevealTapped && pulse ? 1.03 : 1.0)

            if session.canExtend {
                extendButton
            }
        }
    }

    private var revealLabel: String {
        if session.myRevealTapped { return "Waiting for @\(partnerName)…" }
        if session.theirRevealTapped { return "@\(partnerName) is ready — reveal 💘" }
        return "Reveal now 💘"
    }

    private var extendButton: some View {
        let theyAsked = session.theirExtendRound > session.myExtendRound
        let iAsked = session.myExtendRound > session.theirExtendRound
        return Button {
            Haptics.tap()
            onExtend()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .black))
                Text(iAsked ? "Asked" : "2 min")
                    .font(.system(size: 13, weight: .black))
            }
            .foregroundStyle(theyAsked ? .white : blush)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Capsule().fill(theyAsked ? rose : Color.white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(blush.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(iAsked)
        .scaleEffect(theyAsked && pulse ? 1.05 : 1.0)
    }

    // MARK: - Revealed HUD

    private var revealedHUD: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: topInset + 54)
            HStack(spacing: 10) {
                timerRing(size: 44)
                    .overlay {
                        Text(WhisperBlindDateSession.format(session.remaining))
                            .font(.system(size: 9, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .opacity(0)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.isLastCall ? "Last call 💘" : "Revealed 💘")
                        .font(.system(size: 12.5, weight: .black))
                        .foregroundStyle(session.isLastCall ? blush : .white)
                    Text("\(session.clockStage.emoji) \(session.clockStage.label) · \(WhisperBlindDateSession.format(session.remaining)) left")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .monospacedDigit()
                }
                if session.canExtend {
                    extendButton
                        .scaleEffect(0.85)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Color(red: 0.16, green: 0.05, blue: 0.10).opacity(0.85))
            )
            .overlay(Capsule().strokeBorder(rose.opacity(0.4), lineWidth: 1))

            Spacer()

            promptCard(compact: true)
                .padding(.horizontal, 14)

            Spacer().frame(height: bottomInset + 100)
        }
        .frame(maxWidth: .infinity)
    }

    private var revealFlashView: some View {
        ZStack {
            Color.white.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 8) {
                Text("💘")
                    .font(.system(size: 64))
                Text("Reveal!")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: rose.opacity(0.6), radius: 12)
            }
        }
    }
}
