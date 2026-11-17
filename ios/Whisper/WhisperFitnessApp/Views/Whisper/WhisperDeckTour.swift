import Foundation
import SwiftUI
import AVFoundation

// MARK: - Script (mirrors web lib/emberDeckTour.ts + the backend narration table)

nonisolated struct WhisperDeckTourSegment: Identifiable, Hashable {
    let id: String
    /// The short line shown (and highlighted) on the slide.
    let text: String
    /// What Jasper says out loud for this line.
    let narration: String
}

nonisolated struct WhisperDeckTourStat: Hashable {
    let value: String
    let label: String
}

nonisolated enum WhisperDeckTourInteractive {
    case wpp
    case brands
}

nonisolated struct WhisperDeckTourSlide: Identifiable {
    let id: String
    let kicker: String
    let title: String
    /// Real interactive pitch component embedded in the slide.
    let interactive: WhisperDeckTourInteractive?
    /// One-liner inviting the room to touch the interactive component.
    let interactiveHint: String?
    /// Hero stat chips rendered on slides without an interactive panel.
    let stats: [WhisperDeckTourStat]
    let segments: [WhisperDeckTourSegment]
}

/// Jasper's narrated deck walkthrough — the same five slides and script the
/// web client uses, so both platforms present the identical tour. Keep in
/// sync with `web-whisperweb/src/lib/emberDeckTour.ts` and the backend's
/// `TOUR_NARRATION` table (which voices these exact lines).
nonisolated enum WhisperDeckTourScript {
    static let slides: [WhisperDeckTourSlide] = [
        WhisperDeckTourSlide(
            id: "welcome",
            kicker: "The platform",
            title: "Whisper in one minute",
            interactive: nil,
            interactiveHint: nil,
            stats: [
                WhisperDeckTourStat(value: "1", label: "platform for the whole creator economy"),
                WhisperDeckTourStat(value: "10%", label: "flat platform fee"),
                WhisperDeckTourStat(value: "100%", label: "real product — no mockups"),
            ],
            segments: [
                WhisperDeckTourSegment(
                    id: "intro",
                    text: "Whisper is a social platform with a real creator economy built in.",
                    narration: "Hey everyone — I'm Jasper, Whisper's built-in AI, and I'll walk you through the deck. Whisper is a social platform with a real creator economy built in. Not promised — built and running."
                ),
                WhisperDeckTourSegment(
                    id: "who",
                    text: "Creators, athletes, coaches, recruiters, and brands all earn in one place.",
                    narration: "Creators, athletes, coaches, recruiters, and brands all earn in one place — posting, sponsorships, coaching, and recruiting share the same profile and the same wallet."
                ),
                WhisperDeckTourSegment(
                    id: "real",
                    text: "Everything in this walkthrough is the live product with sample data.",
                    narration: "And everything I'm about to show you is the live product with clearly marked sample data — the sliders slide and the cards open, so feel free to touch things as we go."
                ),
            ]
        ),
        WhisperDeckTourSlide(
            id: "wpp",
            kicker: "Ad revenue share",
            title: "WPP — Whisper Paid Partners",
            interactive: .wpp,
            interactiveHint: "These sliders are live — drag followers and views and the payout updates in real time.",
            stats: [],
            segments: [
                WhisperDeckTourSegment(
                    id: "what",
                    text: "Post Reels and threads — earn a share of ad revenue, paid monthly via Stripe.",
                    narration: "First, the money most people ask about: W-P-P, Whisper Paid Partners. You post Reels and threads like you already do, and you earn a share of ad revenue, paid out monthly through Stripe."
                ),
                WhisperDeckTourSegment(
                    id: "tiers",
                    text: "Partner $0.90/1k · Partner+ $1.40/1k · Elite $2.20/1k views.",
                    narration: "There are three tiers. Partner opens at 1,000 followers and pays about $0.90 per thousand qualified views. Partner+ pays $1.40, and Elite pays $2.20 per thousand."
                ),
                WhisperDeckTourSegment(
                    id: "math",
                    text: "Example: 250,000 monthly views at Partner+ ≈ $350/mo.",
                    narration: "Quick example — two hundred and fifty thousand monthly views at the Partner+ tier is about $350 every single month, on top of sponsorships and coaching."
                ),
                WhisperDeckTourSegment(
                    id: "try",
                    text: "Drag the sliders — this is the real calculator from our pitch deck.",
                    narration: "The calculator on this slide is the real one from our pitch deck — drag the followers and views sliders and watch the payout move. Go ahead, play with it while we talk."
                ),
            ]
        ),
        WhisperDeckTourSlide(
            id: "brands",
            kicker: "Sponsorships",
            title: "The brand marketplace",
            interactive: .brands,
            interactiveHint: "Tap any brand card — these are the actual modals with escrow terms and the apply flow.",
            stats: [],
            segments: [
                WhisperDeckTourSegment(
                    id: "marketplace",
                    text: "Brands post sponsorships; creators apply, negotiate, and get tracked payouts.",
                    narration: "Next, sponsorships. Brands post real offers in the marketplace, creators apply or get scouted, both sides can counter, and every deal is tracked automatically."
                ),
                WhisperDeckTourSegment(
                    id: "escrow",
                    text: "Funds are escrowed up front and released when the tracked post goes live — Whisper keeps 10%.",
                    narration: "Here's the trust piece: the brand's money goes into escrow up front, and it's released the moment the tracked post goes live. Nobody chases invoices, and Whisper keeps a flat 10 percent."
                ),
                WhisperDeckTourSegment(
                    id: "cards",
                    text: "Apex Nutrition, Stride Athletics, Forge Recovery — $150/post up to $9,000/yr deals.",
                    narration: "On this slide are three sample brands — Apex Nutrition, Stride Athletics, and Forge Recovery Lab — with typical deals from a hundred and fifty dollars a post up to nine thousand a year."
                ),
                WhisperDeckTourSegment(
                    id: "try",
                    text: "Open a card — requirements, typical pay, and the apply flow are all real.",
                    narration: "These are the actual brand card modals from the deck — tap one open and you'll see the requirements, the typical pay range, and the real apply flow, right here in the meeting."
                ),
            ]
        ),
        WhisperDeckTourSlide(
            id: "coaches",
            kicker: "Coach Studio",
            title: "A coaching business, built in",
            interactive: nil,
            interactiveHint: nil,
            stats: [
                WhisperDeckTourStat(value: "$5–$2,000", label: "your monthly rate, your call"),
                WhisperDeckTourStat(value: "10%", label: "flat fee — the rest is yours"),
                WhisperDeckTourStat(value: "$540/mo", label: "12 clients at $50 after fees"),
            ],
            segments: [
                WhisperDeckTourSegment(
                    id: "rate",
                    text: "Set any monthly rate from $5 to $2,000 — clients subscribe right on your profile.",
                    narration: "For coaches, the business side is already wired. You set any monthly rate from 5 to 2,000 dollars, and clients subscribe directly on your profile — no invoices, no spreadsheets."
                ),
                WhisperDeckTourSegment(
                    id: "flow",
                    text: "Stripe pays you out automatically; Whisper keeps just 10%.",
                    narration: "Stripe handles the payouts automatically every month, and Whisper keeps just 10 percent — the rest lands in the coach's account."
                ),
                WhisperDeckTourSegment(
                    id: "example",
                    text: "Twelve clients at $50/month is $540 recurring after fees.",
                    narration: "So a coach with just twelve clients at fifty dollars a month takes home five hundred and forty dollars, recurring, from day one. That's a real business, not a side hustle."
                ),
            ]
        ),
        WhisperDeckTourSlide(
            id: "close",
            kicker: "The close",
            title: "Why people join now",
            interactive: nil,
            interactiveHint: nil,
            stats: [
                WhisperDeckTourStat(value: "Live", label: "recruiting pipeline + meetings"),
                WhisperDeckTourStat(value: "AI", label: "notes after every call — like this one"),
                WhisperDeckTourStat(value: "Now", label: "the best usernames are still open"),
            ],
            segments: [
                WhisperDeckTourSegment(
                    id: "recruit",
                    text: "Recruiters scout talent with a live pipeline, meetings, and AI notes.",
                    narration: "Behind all of this is a recruiting engine — scouts track talent in a live pipeline, run meetings exactly like this one, and every conversation files itself to the right prospect."
                ),
                WhisperDeckTourSegment(
                    id: "notes",
                    text: "Every meeting gets captions and AI notes — this call included.",
                    narration: "And yes — this very call is getting live captions and AI notes. When we hang up, the key points and action items write themselves."
                ),
                WhisperDeckTourSegment(
                    id: "cta",
                    text: "Ask Jasper anything, or open the full interactive deck from the meeting menu.",
                    narration: "That's the tour. I'm here the whole meeting — ask me anything out loud, or open the full interactive deck from the menu. Thanks for listening, everyone."
                ),
            ]
        ),
    ]

    /// Clamp a broadcast position onto valid slide/segment indexes.
    static func clamp(slide: Int, segment: Int) -> (slide: Int, segment: Int) {
        let s = min(max(0, slide), slides.count - 1)
        let g = min(max(0, segment), slides[s].segments.count - 1)
        return (s, g)
    }

    /// The position after the given one, or nil when the tour is finished.
    static func next(slide: Int, segment: Int) -> (slide: Int, segment: Int)? {
        let current = clamp(slide: slide, segment: segment)
        if current.segment + 1 < slides[current.slide].segments.count {
            return (current.slide, current.segment + 1)
        }
        if current.slide + 1 < slides.count {
            return (current.slide + 1, 0)
        }
        return nil
    }
}

// MARK: - Shared view state

/// One participant's view of the live walkthrough — mirrors the web client's
/// `DeckTourView` and rides the same `deck-tour` app events.
struct WhisperDeckTourViewState: Equatable {
    var slide: Int
    var segment: Int
    var playing: Bool
    var driverPeerId: String
    var driverName: String
    /// True when narration plays locally on every device (iOS drivers, which
    /// can't mix Jasper's voice into their outgoing call audio). Web drivers
    /// carry the narration on their own audio track instead.
    var deviceVoice: Bool
}

// MARK: - Engine

/// Drives (or follows) Jasper's synced deck walkthrough inside a meeting.
///
/// Driver side: broadcasts `deck-tour` app events (open/slide/segment/playing
/// + a 4s heartbeat), plays each fixed narration line through the device
/// speaker, and advances when the line finishes — every participant's device
/// plays the same line locally (`voice: "device"` on the wire).
///
/// Viewer side: applies remote broadcasts, plays the narration locally when
/// the tour is device-voiced, and drops the overlay when the driver's
/// heartbeat stops or they leave the call.
@MainActor
@Observable
final class WhisperDeckTourEngine {
    enum NarrationPhase: Equatable {
        case off
        case connecting
        case live
    }

    private(set) var view: WhisperDeckTourViewState?
    private(set) var isDriver: Bool = false
    /// Driver-side narration status for the overlay header.
    private(set) var narration: NarrationPhase = .off

    private let audio = WhisperDeckTourAudio()
    private var heartbeatTask: Task<Void, Never>?
    private var beatWatchTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var speakEpoch: Int = 0
    private var lastBeat: Date = .distantPast
    private var viewerAudioKey: String = ""

    // MARK: Driver

    /// Starts driving the walkthrough from slide one. Returns false when
    /// somebody else is already presenting (callers show a toast).
    @discardableResult
    func startDriving(selfName: String) -> Bool {
        if view != nil && !isDriver { return false }
        guard !isDriver else { return true }
        isDriver = true
        viewerAudioKey = ""
        view = WhisperDeckTourViewState(
            slide: 0,
            segment: 0,
            playing: true,
            driverPeerId: WhisperLiveRTCService.shared.localPeerId,
            driverName: selfName,
            deviceVoice: true
        )
        broadcast(open: true)
        startHeartbeat()
        speak(slide: 0, segment: 0)
        return true
    }

    /// Ends the walkthrough for everyone (driver only).
    func stopDriving() {
        guard isDriver else { return }
        let name = view?.driverName ?? "someone"
        cancelDriverTasks()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        audio.stop()
        isDriver = false
        view = nil
        narration = .off
        WhisperLiveRTCService.shared.sendAppEvent("deck-tour", data: [
            "open": false,
            "slide": 0,
            "segment": 0,
            "playing": false,
            "driverName": name,
            "rev": Date().timeIntervalSince1970 * 1000,
            "voice": "device",
        ])
    }

    func nextSlide() {
        guard isDriver, let current = view,
              current.slide + 1 < WhisperDeckTourScript.slides.count else { return }
        speak(slide: current.slide + 1, segment: 0)
    }

    func previousSlide() {
        guard isDriver, let current = view, current.slide > 0 else { return }
        speak(slide: current.slide - 1, segment: 0)
    }

    /// Pause stops the narration mid-line; resume re-reads the current line
    /// for context (same behavior as the web driver).
    func togglePlay() {
        guard isDriver, var current = view else { return }
        if current.playing {
            current.playing = false
            view = current
            cancelDriverTasks()
            audio.stop()
            narration = .off
            broadcast(open: true)
        } else {
            current.playing = true
            view = current
            broadcast(open: true)
            speak(slide: current.slide, segment: current.segment)
        }
    }

    /// Late joiners broadcast `present-sync-request` — the driver answers
    /// instantly instead of making them wait for the next heartbeat.
    func answerSyncRequest() {
        guard isDriver, view != nil else { return }
        broadcast(open: true)
    }

    private func speak(slide: Int, segment: Int) {
        guard isDriver, var current = view else { return }
        let pos = WhisperDeckTourScript.clamp(slide: slide, segment: segment)
        speakEpoch += 1
        let epoch = speakEpoch
        cancelDriverTasks()
        audio.stop()
        current.slide = pos.slide
        current.segment = pos.segment
        view = current
        broadcast(open: true)
        guard current.playing else { return }
        narration = .connecting
        // Watchdog — one stuck line must never stall the whole walkthrough.
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.speakEpoch == epoch else { return }
            self.advanceSoon(after: 0)
        }
        Task { [weak self] in
            guard let self else { return }
            let data = await self.audio.narrationData(slide: pos.slide, segment: pos.segment)
            guard self.speakEpoch == epoch, self.isDriver, self.view?.playing == true else { return }
            guard let data, self.audio.play(data, onFinish: { [weak self] in
                guard let self, self.speakEpoch == epoch else { return }
                self.advanceSoon(after: 0.85)
            }) else {
                // Couldn't fetch or start the line — skip ahead, never stall.
                self.narration = .off
                self.advanceSoon(after: 1.4)
                return
            }
            self.narration = .live
            // Prefetch the next line while this one plays.
            if let next = WhisperDeckTourScript.next(slide: pos.slide, segment: pos.segment) {
                Task { [weak self] in
                    _ = await self?.audio.narrationData(slide: next.slide, segment: next.segment)
                }
            }
        }
    }

    private func advanceSoon(after delay: TimeInterval) {
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self, self.isDriver,
                  let current = self.view, current.playing else { return }
            if let next = WhisperDeckTourScript.next(slide: current.slide, segment: current.segment) {
                self.speak(slide: next.slide, segment: next.segment)
            } else {
                var ended = current
                ended.playing = false
                self.view = ended
                self.narration = .off
                self.broadcast(open: true)
            }
        }
    }

    private func cancelDriverTasks() {
        advanceTask?.cancel()
        advanceTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self, self.isDriver, self.view != nil else { return }
                self.broadcast(open: true)
            }
        }
    }

    private func broadcast(open: Bool) {
        guard let current = view else { return }
        WhisperLiveRTCService.shared.sendAppEvent("deck-tour", data: [
            "open": open,
            "slide": current.slide,
            "segment": current.segment,
            "playing": current.playing,
            "driverName": current.driverName,
            "rev": Date().timeIntervalSince1970 * 1000,
            "voice": "device",
        ])
    }

    // MARK: Viewer

    /// Applies a remote `deck-tour` broadcast from a web or iOS driver.
    func handleRemote(_ data: [String: Any], fromPeerId: String) {
        guard !isDriver else { return } // my own echoes
        lastBeat = Date()
        guard (data["open"] as? Bool) == true else {
            if let current = view,
               fromPeerId.isEmpty || current.driverPeerId.isEmpty || current.driverPeerId == fromPeerId {
                clearViewer()
            }
            return
        }
        let pos = WhisperDeckTourScript.clamp(
            slide: Self.intValue(data["slide"]),
            segment: Self.intValue(data["segment"])
        )
        let name = (data["driverName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "someone"
        view = WhisperDeckTourViewState(
            slide: pos.slide,
            segment: pos.segment,
            playing: (data["playing"] as? Bool) == true,
            driverPeerId: fromPeerId,
            driverName: name,
            deviceVoice: (data["voice"] as? String) == "device"
        )
        startBeatWatch()
        syncViewerNarration()
    }

    /// Viewer hygiene — drop the overlay when the driver leaves the call.
    func noteParticipants(_ peerIds: [String]) {
        guard !isDriver, let current = view, !peerIds.isEmpty,
              !current.driverPeerId.isEmpty else { return }
        if !peerIds.contains(current.driverPeerId) {
            clearViewer()
        }
    }

    /// Full teardown when leaving the meeting.
    func shutdown() {
        if isDriver { stopDriving() }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        beatWatchTask?.cancel()
        beatWatchTask = nil
        cancelDriverTasks()
        audio.stop()
        view = nil
        viewerAudioKey = ""
        narration = .off
    }

    private func startBeatWatch() {
        guard beatWatchTask == nil else { return }
        beatWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self else { return }
                if !self.isDriver, self.view != nil,
                   Date().timeIntervalSince(self.lastBeat) > 15 {
                    self.clearViewer()
                }
            }
        }
    }

    private func clearViewer() {
        view = nil
        viewerAudioKey = ""
        audio.stop()
    }

    /// Device-voiced tours (iOS drivers): this device plays the fixed line
    /// locally, synced to the broadcast position. Driver-voiced tours (web)
    /// arrive through the driver's call audio — nothing to play here.
    private func syncViewerNarration() {
        guard let current = view, !isDriver, current.deviceVoice else { return }
        guard current.playing else {
            if !viewerAudioKey.isEmpty {
                viewerAudioKey = ""
                audio.stop()
            }
            return
        }
        let key = "\(current.slide):\(current.segment)"
        guard viewerAudioKey != key else { return }
        viewerAudioKey = key
        Task { [weak self] in
            guard let self else { return }
            guard let data = await self.audio.narrationData(slide: current.slide, segment: current.segment) else { return }
            // Only start if we're still on this exact line.
            guard let now = self.view, !self.isDriver, now.playing,
                  "\(now.slide):\(now.segment)" == key else { return }
            _ = self.audio.play(data, onFinish: nil)
            if let next = WhisperDeckTourScript.next(slide: now.slide, segment: now.segment) {
                Task { [weak self] in
                    _ = await self?.audio.narrationData(slide: next.slide, segment: next.segment)
                }
            }
        }
    }

    nonisolated private static func intValue(_ any: Any?) -> Int {
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let value = any as? String, let parsed = Int(value) { return parsed }
        return 0
    }
}

// MARK: - Narration audio

/// Fetches Jasper's fixed narration lines (MP3, cached per segment) from the
/// backend and plays them through the meeting's existing audio session — the
/// WebRTC engine owns the session, so this never reconfigures it.
@MainActor
final class WhisperDeckTourAudio: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?
    private var cache: [String: Data] = [:]
    // Boosted engine path — WebRTC's voice-processing unit attenuates plain
    // AVAudioPlayer output during calls (Jasper sounded quiet), so narration
    // plays through an engine with a +12 dB gain stage. AVAudioPlayer stays
    // as the fallback when the engine can't start.
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let boost = AVAudioUnitEQ(numberOfBands: 0)
    private var engineWired = false
    private var playToken = UUID()

    /// Downloads (or returns the cached) narration line for a position.
    /// Walks every backend candidate so a stale configured URL can't
    /// silently mute the walkthrough — the tour must always have a voice.
    func narrationData(slide: Int, segment: Int) async -> Data? {
        let key = "\(slide):\(segment)"
        if let hit = cache[key] { return hit }
        for host in WhisperBillingBackend.hosts {
            guard let url = URL(string: "\(host)/meetings/tour-audio?slide=\(slide)&segment=\(segment)") else {
                continue
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { continue }
            guard http.statusCode == 200, data.count > 500 else {
                print("[DeckTour] narration fetch failed at \(host): HTTP \(http.statusCode)")
                continue
            }
            cache[key] = data
            return data
        }
        return nil
    }

    /// Plays one narration line. Returns false when playback couldn't start.
    @discardableResult
    func play(_ data: Data, onFinish: (() -> Void)?) -> Bool {
        stop()
        self.onFinish = onFinish
        if playBoosted(data) { return true }
        guard let newPlayer = try? AVAudioPlayer(data: data) else {
            self.onFinish = nil
            return false
        }
        player = newPlayer
        newPlayer.delegate = self
        newPlayer.volume = 1
        guard newPlayer.play() else {
            player = nil
            self.onFinish = nil
            return false
        }
        return true
    }

    /// Engine playback with a gain stage so narration stays loud next to
    /// live call audio. Returns false when anything in the chain fails.
    private func playBoosted(_ data: Data) -> Bool {
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ember-tour-\(UUID().uuidString).mp3")
            try data.write(to: url)
            let file = try AVAudioFile(forReading: url)
            if !engineWired {
                engine.attach(playerNode)
                engine.attach(boost)
                engineWired = true
            }
            let format = file.processingFormat
            engine.connect(playerNode, to: boost, format: format)
            engine.connect(boost, to: engine.mainMixerNode, format: format)
            boost.globalGain = 12
            engine.prepare()
            try engine.start()
            let token = UUID()
            playToken = token
            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.playToken == token else {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    try? FileManager.default.removeItem(at: url)
                    let callback = self.onFinish
                    self.onFinish = nil
                    self.playerNode.stop()
                    self.engine.stop()
                    callback?()
                }
            }
            playerNode.play()
            return true
        } catch {
            return false
        }
    }

    func stop() {
        onFinish = nil
        playToken = UUID()
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let callback = self.onFinish
            self.onFinish = nil
            self.player = nil
            callback?()
        }
    }
}
