import SwiftUI
import AVFoundation
import AudioToolbox

// The native meeting room's Google-Meet-grammar pieces — in-call messages,
// host controls, reactions, raised hands — all riding the SAME wire names
// the web room speaks (`call-chat`, `call-policy`, `call-react`,
// `call-hand`, `call-mute`, `call-mute-all`, `call-end`, `call-host`).

/// One in-call message. Ephemeral by design — gone when the call ends.
struct MeetRoomChatMessage: Identifiable, Equatable {
    let id: String
    let name: String
    let text: String
    let at: Date
    let isSelf: Bool
}

/// What the host lets everyone do. Hosts are always exempt.
struct MeetRoomPolicy: Equatable {
    var chat: Bool = true
    var reactions: Bool = true
    var present: Bool = true
    /// Meet's Quick access: on — signed-in members join without asking;
    /// off — everyone knocks. Guests without an account always knock.
    var quickAccess: Bool = true
}

/// Someone knocking on the room — Meet's "wants to join this call".
/// Same wire as web: meeting-knock {knockId, name, userId, avatarUrl, isGuest, at}.
struct MeetKnock: Identifiable, Equatable {
    let knockId: String
    let name: String
    let avatarURL: String?
    let isGuest: Bool
    let at: Date
    var id: String { knockId }
}

/// A floating emoji drifting up the stage with the sender's name.
struct MeetFloatingReaction: Identifiable, Equatable {
    let id: UUID
    let emoji: String
    let name: String
    /// Horizontal lane (0…1) so a burst of reactions fans out.
    let lane: CGFloat
}

/// Meet's reaction set — identical order to the web strip.
enum MeetReactions {
    static let all: [String] = ["\u{1F496}", "\u{1F44D}", "\u{1F389}", "\u{1F44F}", "\u{1F602}", "\u{1F62E}", "\u{1F622}", "\u{1F914}"]
}

// MARK: - In-call messages

/// Meet's "In-call messages" panel as a sheet: the notice, the thread, the
/// composer. The composer locks when the host turned chat off (hosts exempt).
struct WhisperMeetRoomChatSheet: View {
    let messages: [MeetRoomChatMessage]
    let locked: Bool
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !locked && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                notice
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if messages.isEmpty {
                                WhisperEmptyState(icon: "bubble.left.and.bubble.right", title: "No messages yet", message: "Say hi to everyone in the meeting.", isCard: false, compact: true)
                            }
                            ForEach(messages) { message in
                                row(message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                composer
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("In-call messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var notice: some View {
        Text(
            locked
                ? "The host turned off in-call messages."
                : "Messages are only visible to people in the call and are deleted when the call ends."
        )
        .font(.caption)
        .foregroundStyle(WhisperTheme.muted(colorScheme))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme))
    }

    private func row(_ message: MeetRoomChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(message.isSelf ? "You" : message.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(message.at, style: .time)
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(locked ? "Chat is off" : "Send a message to everyone", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
                .focused($focused)
                .disabled(locked)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 36, height: 36)
                    .background(WhisperTheme.ink(colorScheme).opacity(canSend ? 1 : 0.35), in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WhisperTheme.surface(colorScheme))
        .overlay(alignment: .top) { Divider().overlay(WhisperTheme.hairline(colorScheme)) }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !locked else { return }
        Haptics.tap()
        onSend(text)
        draft = ""
    }
}

// MARK: - Host controls

/// Meet's "Host controls" — what everyone may do, plus Mute everyone.
struct WhisperMeetHostControlsSheet: View {
    @Binding var policy: MeetRoomPolicy
    let participantCount: Int
    let onPolicyChange: (MeetRoomPolicy) -> Void
    let onMuteAll: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Quick access", isOn: binding(\.quickAccess))
                } header: {
                    Text("Meeting access")
                } footer: {
                    Text(policy.quickAccess
                         ? "Signed-in Whisper members join without asking. Guests without an account always ask to join."
                         : "Everyone must ask to join — you'll see each request and choose who gets in.")
                }
                Section {
                    Toggle("Send chat messages", isOn: binding(\.chat))
                    Toggle("Send reactions", isOn: binding(\.reactions))
                    Toggle("Share their screen", isOn: binding(\.present))
                } header: {
                    Text("Let everyone")
                } footer: {
                    Text("Hosts can always do all of these. Changes apply to everyone in the call right away.")
                }
                Section {
                    Button(role: .destructive) {
                        Haptics.warning()
                        onMuteAll()
                        dismiss()
                    } label: {
                        Label("Mute everyone", systemImage: "mic.slash.fill")
                    }
                    .disabled(participantCount < 2)
                } footer: {
                    Text("Everyone except you is muted. They can unmute themselves.")
                }
            }
            .navigationTitle("Host controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(_ key: WritableKeyPath<MeetRoomPolicy, Bool>) -> Binding<Bool> {
        Binding(
            get: { policy[keyPath: key] },
            set: { value in
                var next = policy
                next[keyPath: key] = value
                policy = next
                Haptics.soft()
                onPolicyChange(next)
            }
        )
    }
}

// MARK: - Reactions

/// Meet's reaction strip — floats above the controls while open.
struct WhisperMeetReactionStrip: View {
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MeetReactions.all, id: \.self) { emoji in
                Button {
                    Haptics.soft()
                    onPick(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(width: 42, height: 42)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React \(emoji)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(white: 0.19), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}

/// Emojis drifting up the stage with the sender's name — Meet's floating
/// reactions. Each item runs its own rise and clears itself.
struct WhisperMeetFloatingReactionsLayer: View {
    let items: [MeetFloatingReaction]
    let onExpire: (UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                ForEach(items) { item in
                    FloatingReactionView(item: item, height: geo.size.height) {
                        onExpire(item.id)
                    }
                    .position(
                        x: 40 + item.lane * max(0, geo.size.width - 80),
                        y: geo.size.height - 120
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct FloatingReactionView: View {
        let item: MeetFloatingReaction
        let height: CGFloat
        let onDone: () -> Void
        @State private var risen: Bool = false

        var body: some View {
            VStack(spacing: 4) {
                Text(item.emoji)
                    .font(.system(size: 34))
                Text(item.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: Capsule())
            }
            .offset(y: risen ? -min(height * 0.55, 380) : 0)
            .opacity(risen ? 0 : 1)
            .scaleEffect(risen ? 1.15 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 2.6)) { risen = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) { onDone() }
            }
        }
    }
}

// MARK: - Sounds

/// Whisper Meet's sound kit — the SAME three chimes the web room plays
/// (rising pair on join, falling pair on leave, a resolving descent when the
/// meeting ends), synthesized as PCM at runtime so nothing ships as an asset
/// and the bell math matches web note for note. Plays through the call's
/// shared audio session (it mixes; it never interrupts the WebRTC unit).
@MainActor
enum WhisperMeetChime {
    nonisolated private struct Note: Sendable {
        let hz: Double
        let at: Double
        let decay: Double
        let gain: Double
    }

    private static var cache: [String: Data] = [:]
    private static var players: [AVAudioPlayer] = []

    static func playJoin() {
        play("join", [
            Note(hz: 523.25, at: 0, decay: 0.55, gain: 0.16),
            Note(hz: 783.99, at: 0.13, decay: 0.75, gain: 0.15)
        ])
    }

    static func playLeave() {
        play("leave", [
            Note(hz: 783.99, at: 0, decay: 0.45, gain: 0.11),
            Note(hz: 523.25, at: 0.13, decay: 0.7, gain: 0.11)
        ])
    }

    static func playEnd() {
        play("end", [
            Note(hz: 659.25, at: 0, decay: 0.5, gain: 0.15),
            Note(hz: 523.25, at: 0.16, decay: 0.55, gain: 0.14),
            Note(hz: 392.0, at: 0.34, decay: 1.1, gain: 0.15)
        ])
    }

    /// A tiny tick for hands / chat arrivals — the web kit's B5.
    static func playTick() {
        play("tick", [Note(hz: 987.77, at: 0, decay: 0.22, gain: 0.07)])
    }

    // MARK: UI sounds — the same bell math, played as SYSTEM sounds

    /// A soft two-note pop when you like something — identical math on web.
    static func playLike() {
        playUI("like", [
            Note(hz: 1046.50, at: 0, decay: 0.14, gain: 0.09),
            Note(hz: 1567.98, at: 0.045, decay: 0.18, gain: 0.07)
        ])
    }

    /// A tiny low tick the moment a message lifts under a long press.
    static func playPress() {
        playUI("press", [Note(hz: 440, at: 0, decay: 0.08, gain: 0.05)])
    }

    /// A quick rising pair as a message or comment leaves the device.
    static func playSend() {
        playUI("send", [
            Note(hz: 783.99, at: 0, decay: 0.12, gain: 0.07),
            Note(hz: 1174.66, at: 0.06, decay: 0.16, gain: 0.06)
        ])
    }

    /// A soft falling pair when a message arrives while the app is open.
    static func playReceive() {
        playUI("receive", [
            Note(hz: 1174.66, at: 0, decay: 0.14, gain: 0.06),
            Note(hz: 880, at: 0.07, decay: 0.2, gain: 0.06)
        ])
    }

    /// A resolving triad when a post or wave goes live.
    static func playPublished() {
        playUI("published", [
            Note(hz: 659.25, at: 0, decay: 0.18, gain: 0.07),
            Note(hz: 783.99, at: 0.08, decay: 0.2, gain: 0.07),
            Note(hz: 1046.50, at: 0.16, decay: 0.32, gain: 0.08)
        ])
    }

    /// A low, short double knock for failures — noticeable, never harsh.
    static func playError() {
        playUI("error", [
            Note(hz: 261.63, at: 0, decay: 0.1, gain: 0.07),
            Note(hz: 246.94, at: 0.11, decay: 0.16, gain: 0.07)
        ])
    }

    /// The web kit's B5 tick at a whisper — refresh completion, follows.
    static func playTickQuiet() {
        playUI("tick-quiet", [Note(hz: 987.77, at: 0, decay: 0.12, gain: 0.04)])
    }

    private static var systemSounds: [String: SystemSoundID] = [:]
    private static var preparingSounds: Set<String> = []

    /// UI sounds ride AudioToolbox system sounds so they HONOR THE RINGER
    /// SWITCH (a liked post must never make noise on a silenced phone) and
    /// never touch the call's audio session. Rendered once, cached as a
    /// registered system sound.
    private static func playUI(_ key: String, _ notes: [Note]) {
        if let id = systemSounds[key] {
            AudioServicesPlaySystemSound(id)
            return
        }
        guard preparingSounds.insert(key).inserted else { return }
        let accountGeneration = AccountStorage.generation
        Task {
            defer { preparingSounds.remove(key) }
            let id = await Task.detached(priority: .utility) { () -> SystemSoundID? in
                let data = render(notes)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-ui-\(key).wav")
                guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
                var id: SystemSoundID = 0
                guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
                return id
            }.value
            guard let id else { return }
            systemSounds[key] = id
            if accountGeneration == AccountStorage.generation { AudioServicesPlaySystemSound(id) }
        }
    }

    private static func play(_ key: String, _ notes: [Note]) {
        let data: Data
        if let cached = cache[key] {
            data = cached
        } else {
            data = render(notes)
            cache[key] = data
        }
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = 0.6
        // Pre-buffer so the first note lands on the beat, not a frame late.
        player.prepareToPlay()
        players.removeAll { !$0.isPlaying }
        players.append(player)
        player.play()
    }

    /// A marimba-ish bell — fundamental + quiet 2nd/3rd partials that die
    /// faster, fast attack, exponential decay — rendered to 16-bit mono WAV.
    nonisolated private static func render(_ notes: [Note]) -> Data {
        let rate: Double = 44_100
        let length = (notes.map { $0.at + $0.decay }.max() ?? 1) + 0.1
        let frames = Int(length * rate)
        var samples = [Float](repeating: 0, count: frames)
        let partials: [(ratio: Double, level: Double)] = [(1, 1), (2, 0.28), (3, 0.1)]
        for note in notes {
            let start = Int(note.at * rate)
            let count = Int(note.decay * rate)
            for i in 0..<count where start + i < frames {
                let t = Double(i) / rate
                let attack = min(1, t / 0.012)
                let env = attack * pow(0.0001, t / note.decay) * note.gain
                var value: Double = 0
                for partial in partials {
                    let partialEnv = partial.ratio > 1 ? pow(0.0001, t / (note.decay * 0.45)) : 1
                    value += sin(2 * .pi * note.hz * partial.ratio * t) * partial.level * partialEnv
                }
                samples[start + i] += Float(value * env)
            }
        }
        var pcm = Data(capacity: frames * 2 + 44)
        let byteRate = UInt32(rate) * 2
        pcm.append(contentsOf: Array("RIFF".utf8))
        pcm.append(le32(UInt32(36 + frames * 2)))
        pcm.append(contentsOf: Array("WAVE".utf8))
        pcm.append(contentsOf: Array("fmt ".utf8))
        pcm.append(le32(16))
        pcm.append(le16(1))
        pcm.append(le16(1))
        pcm.append(le32(UInt32(rate)))
        pcm.append(le32(byteRate))
        pcm.append(le16(2))
        pcm.append(le16(16))
        pcm.append(contentsOf: Array("data".utf8))
        pcm.append(le32(UInt32(frames * 2)))
        for sample in samples {
            let clipped = max(-1, min(1, sample))
            let int16 = Int16(clipped * 32_767)
            pcm.append(le16(UInt16(bitPattern: int16)))
        }
        return pcm
    }

    nonisolated private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    nonisolated private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}

/// "name raised a hand" — the chip under the top bar.
/// Meet's "NAME wants to join this call · Deny entry · Admit" — the prompt the
/// doorkeeper sees under the top bar. Several knockers collapse into one
/// card with Admit all.
struct WhisperMeetKnockBanner: View {
    let knocks: [MeetKnock]
    let onAdmit: (MeetKnock) -> Void
    let onDeny: (MeetKnock) -> Void
    let onAdmitAll: () -> Void

    private static let meetBlue = Color(red: 0.66, green: 0.78, blue: 0.98)
    private static let meetBlueInk = Color(red: 0.02, green: 0.18, blue: 0.44)

    var body: some View {
        if let first = knocks.first {
            let many = knocks.count > 1
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if many {
                        HStack(spacing: -8) {
                            ForEach(knocks.prefix(3)) { knock in
                                WhisperAvatar(
                                    username: knock.name,
                                    size: 30,
                                    imageURL: knock.avatarURL.flatMap(URL.init(string:))
                                )
                                .overlay(Circle().stroke(Color(red: 0.19, green: 0.19, blue: 0.20), lineWidth: 2))
                            }
                        }
                    } else {
                        WhisperAvatar(
                            username: first.name,
                            size: 38,
                            imageURL: first.avatarURL.flatMap(URL.init(string:))
                        )
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(many ? "\(knocks.count) people want to join this call" : "\(first.name) wants to join this call")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(many
                             ? knocks.prefix(3).map(\.name).joined(separator: ", ") + (knocks.count > 3 ? " +\(knocks.count - 3)" : "")
                             : (first.isGuest ? "Joining as a guest" : "Whisper member"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if many {
                        Button {
                            Haptics.soft()
                            onAdmitAll()
                        } label: {
                            Text("Admit all")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Self.meetBlueInk)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(Self.meetBlue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Haptics.soft()
                            onDeny(first)
                        } label: {
                            Text("Deny entry")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        Button {
                            Haptics.soft()
                            onAdmit(first)
                        } label: {
                            Label("Admit", systemImage: "person.fill.checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Self.meetBlueInk)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(Self.meetBlue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 352)
            .background(Color(red: 0.19, green: 0.19, blue: 0.20), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        }
    }
}

struct WhisperMeetRaisedHandsChip: View {
    let names: [String]

    var body: some View {
        if names.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.99, green: 0.84, blue: 0.39))
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.6), in: Capsule())
        }
    }

    private var label: String {
        if names.count == 1 { return "\(names[0]) raised a hand" }
        let shown = names.prefix(2).joined(separator: ", ")
        let extra = names.count > 2 ? " +\(names.count - 2)" : ""
        return "\(shown)\(extra) raised their hands"
    }
}
