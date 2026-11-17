import SwiftUI
import AVFoundation
import UIKit

/// Main identity: exact supplied films, never a reconstructed puppet.
/// Specialists retain their existing palette and expression APIs.
struct WhisperKnotMascot: View {
    typealias Motion = WhisperKnotSpecialistMascot.Motion
    var size: CGFloat = 120
    var isActive = false
    var showsEyes = true
    var expression: WhisperEmberMascotExpression = .calm
    var showsOrb = false
    var voiceLevel: CGFloat = 0
    var bodyColor: Color? = nil
    var motion: Motion? = nil
    var milestoneDate: Date? = nil
    var callMotion: String? = nil
    var usesCallPortrait = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.whisperMediaActive) private var mediaActive
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var persona = WhisperKnotPersonaStore.shared
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var waking = false
    @State private var milestoneFinished = false

    private var requested: Motion {
        if let motion { return motion }
        if showsOrb { return .making }
        if expression == .happy || expression == .delighted { return .milestone }
        if isActive || expression == .thinking || expression == .focused || expression == .skeptical { return .working }
        return .idle
    }
    private var state: String {
        if let callMotion, ["call-listening", "call-speaking"].contains(callMotion) { return callMotion }
        if requested == .working { return "working" }
        if requested == .making { return "making-something" }
        if requested == .milestone && !milestoneFinished { return "milestone" }
        return waking ? "waking" : "idle"
    }
    private var plays: Bool { visible && size >= 28 && !reduceMotion && !lowPower && mediaActive && scenePhase == .active }
    // Supplied replacement kit uses its original white background in both modes.
    private var master: String { "KnotLightV5-master" }
    private var personalPoster: UIImage? { usesCallPortrait ? (persona.callPortrait ?? persona.masterImage) : persona.masterImage }

    var body: some View {
        Group {
            if bodyColor != nil || !showsEyes {
                WhisperKnotSpecialistMascot(size: size, isActive: isActive, showsEyes: showsEyes, expression: expression, showsOrb: showsOrb, voiceLevel: voiceLevel, bodyColor: bodyColor, motion: motion, milestoneDate: milestoneDate)
            } else if persona.snapshot == nil {
                // Resolve the current account’s identity before showing any avatar.
                // A disk cache is display media, never snapshot authorization.
                ProgressView().controlSize(.small).frame(width: size, height: size)
            } else if persona.snapshot?.masterID != nil {
                ZStack {
                    if let image = personalPoster { Image(uiImage: image).resizable().scaledToFit() }
                    else { ProgressView().controlSize(.small).frame(width: size, height: size) }
                    if plays, let url = persona.film(kind: state) {
                        KnotAvatarFilm(state: state, url: url, completed: {
                            if state == "waking" { waking = false }
                            if state == "milestone" { milestoneFinished = true }
                        }).id("\(url):\(state)")
                    }
                }.background(.white).clipShape(Circle())
            } else {
                ZStack {
                    Image(master)
                        .resizable().scaledToFit()
                    if plays && callMotion == nil {
                        KnotAvatarFilm(state: state) {
                            if state == "waking" { waking = false }
                            if state == "milestone" { milestoneFinished = true }
                        }
                        .id(state)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state)
                .animation(.easeInOut(duration: 0.2), value: plays)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false).accessibilityHidden(true)
        .task { if bodyColor == nil && showsEyes { try? await persona.refresh() } }
        .task(id: "\(persona.snapshot?.masterID ?? "original"):\(persona.snapshot?.version ?? 0):\(state):\(plays)") {
            if bodyColor == nil && showsEyes && plays { await persona.loadFilm(kind: state) }
        }
        .onAppear {
            visible = true
            if plays && bodyColor == nil && showsEyes && requested == .idle {
                waking = KnotAvatarGreeting.claim()
            }
        }
        .onDisappear { visible = false }
        .onChange(of: plays) { _, playing in
            if playing && bodyColor == nil && showsEyes && requested == .idle && !waking {
                waking = KnotAvatarGreeting.claim()
            }
        }
        .onChange(of: requested) { _, value in
            if value == .working || value == .making { waking = false }
            if value == .milestone { milestoneFinished = false }
        }
        .onChange(of: milestoneDate) { _, _ in milestoneFinished = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

enum KnotAvatarResources {
    static let states = ["waking", "idle", "working", "making-something", "milestone"]
    static func film(_ state: String, theme: String = "dark") -> URL? {
        guard states.contains(state) || state == "dance-6" else { return nil }
        guard ["light", "dark"].contains(theme) else { return nil }
        // Keep the existing dance's light treatment, including in dark mode.
        let name = state == "dance-6" ? "clean-light-dance-6" : "anim-light-" + (state == "waking" ? "idle" : state)
        let directory = state == "dance-6" ? "KnotAvatarV4" : "KnotAvatarLightV5"
        return Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: directory)
            ?? Bundle.main.url(forResource: name, withExtension: "mp4")
    }
}

/// The kit includes one dance, not six; never imply a generated complete set.
struct WhisperKnotSuppliedDanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @State private var replay = UUID()
    @State private var finished = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    Image("KnotLightV5-master").resizable().scaledToFit()
                    if phase == .active {
                        KnotAvatarFilm(state: "dance-6") { finished = true }.id("\(scheme):\(replay)")
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                Text("Dance 6").font(.headline)
                Text("This supplied clip is silent.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(finished ? "Play again" : "Restart dance", systemImage: "arrow.counterclockwise") {
                    finished = false; replay = UUID()
                }.buttonStyle(.bordered).controlSize(.large)
            }
            .padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .preferredColorScheme(.light)
            .navigationTitle("Knot’s dance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

@MainActor private enum KnotAvatarGreeting {
    private static var shown = false
    static func claim() -> Bool {
        guard !shown else { return false }
        shown = true
        return true
    }
}

/// Poster remains beneath the layer until an actual video frame is ready.
/// Each mounted visible surface owns its player; no audio-session mutation.
struct KnotAvatarFilm: UIViewRepresentable {
    let state: String
    var url: URL? = nil
    var loops: Bool? = nil
    var theme: String = "dark"
    let completed: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIView(context: Context) -> FilmView {
        let view = FilmView()
        context.coordinator.configure(view, state: state, url: url, loops: loops, theme: theme)
        return view
    }
    func updateUIView(_ uiView: FilmView, context: Context) {
        context.coordinator.completed = completed
        context.coordinator.configure(uiView, state: state, url: url, loops: loops, theme: theme)
    }
    static func dismantleUIView(_ uiView: FilmView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.playerLayer.player = nil
    }

    final class FilmView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    final class Coordinator {
        var completed: () -> Void
        private var configuration: String?
        private var revision = UUID()
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var ready: NSKeyValueObservation?
        var ended: NSObjectProtocol?
        weak var view: FilmView?
        init(completed: @escaping () -> Void) { self.completed = completed }
        func configure(_ view: FilmView, state: String, url: URL?, loops: Bool?, theme: String) {
            let key = "\(state):\(url?.absoluteString ?? "bundled"):\(String(describing: loops)):\(theme)"
            guard configuration != key else { return }
            stop()
            configuration = key
            mount(view, state: state, url: url, loops: loops, theme: theme)
        }
        func mount(_ view: FilmView, state: String, url: URL?, loops: Bool?, theme: String) {
            let token = revision
            self.view = view
            view.backgroundColor = .clear
            view.playerLayer.opacity = 0
            view.playerLayer.videoGravity = .resizeAspect
            guard let url = url ?? KnotAvatarResources.film(state, theme: theme) else { return }
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            player.volume = 0
            player.preventsDisplaySleepDuringVideoPlayback = false
            self.player = player
            if loops ?? ["idle", "working", "waiting_for_subagents", "making-something", "making_something", "call-listening", "call-speaking"].contains(state) {
                looper = AVPlayerLooper(player: player, templateItem: item)
            } else {
                player.insert(item, after: nil)
                ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.revision == token else { return }
                        self.completed()
                    }
                }
            }
            view.playerLayer.player = player
            ready = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                Task { @MainActor [weak self, weak layer] in
                    guard let self, self.revision == token, let layer, let view = self.view, view.playerLayer === layer else { return }
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.2)
                    layer.opacity = layer.isReadyForDisplay ? 1 : 0
                    CATransaction.commit()
                }
            }
            player.play()
        }
        func stop() {
            revision = UUID(); configuration = nil
            player?.pause()
            looper?.disableLooping()
            if let ended { NotificationCenter.default.removeObserver(ended) }
            ended = nil
            ready = nil
            view = nil
            looper = nil
            player?.removeAllItems()
            player = nil
        }
    }
}
