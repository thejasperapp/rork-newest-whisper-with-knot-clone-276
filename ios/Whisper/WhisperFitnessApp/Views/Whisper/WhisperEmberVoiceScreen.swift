import SwiftUI
import AVFoundation
import UIKit

/// Knot uses the same full-bleed blurred-profile treatment and simple controls
/// as Whisper audio calls. Consented conversation calls relay finalized requests
/// through that chat; welcome and invitation calls keep separate narrow scope.
struct WhisperEmberVoiceScreen: View {
    let knotBot: WhisperKnotBot
    var recentConversation = ""
    var incoming: WhisperKnotIncomingAnswer? = nil
    var welcome: WhisperKnotWelcomeAnswer? = nil
    var directOutgoing = false
    var onExternalClose: (() -> Void)? = nil
    var relay: (@MainActor (String) async -> String)? = nil
    var stopWork: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var voice = WhisperKnotVoiceSession()
    @State private var showTranscript = false

    var body: some View {
        WhisperKnotAudioCallLayout(bot: knotBot, avatarMotion: voice.phase == .active && !(voice.muted && voice.avatarMotion == "call-listening") ? voice.avatarMotion : nil) {
                    if let connected = voice.connectedAt, voice.phase == .active {
                        Text(connected, style: .timer).monospacedDigit().font(.title3).foregroundStyle(.white.opacity(0.8)).padding(.top, 8)
                    }
                    Text(voice.muted && voice.phase == .active ? "Muted" : voice.status)
                        .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 10).padding(.horizontal, 12)
                        .accessibilityAddTraits(.updatesFrequently)
                    if voice.needsSettings {
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                            .buttonStyle(.bordered).tint(.white).padding(.top, 16)
                    }
        } detail: {
                    if directOutgoing {
                        Text("AI call · ElevenLabs handles audio. Answers use chat’s Rork AI Cloud connection via Vercel to OpenAI. Whisper does not save call audio.")
                            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 28).padding(.bottom, 16)
                    }
                    if let call = voice.record {
                        Button { Haptics.tap(); showTranscript = true } label: {
                            Label("Transcript", systemImage: "text.bubble").font(.subheadline.weight(.medium))
                                .padding(.horizontal, 18).frame(minHeight: 44)
                        }.buttonStyle(.plain).padding(.bottom, 24)
                        .sheet(isPresented: $showTranscript) {
                            NavigationStack {
                                WhisperKnotCallTranscriptView(call: voice.record ?? call)
                                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTranscript = false } } }
                            }
                        }
                    }
                    if relay != nil && welcome == nil && incoming == nil {
                        Button("Return to chat for results & approvals") { finish() }
                            .font(.subheadline.weight(.medium)).padding(.bottom, 20)
                    }
                    if voice.history.saveFailed {
                        Text("Couldn’t save the transcript on this device.").font(.caption).padding(.bottom, 16)
                    }
        } controls: {
            controls
        }
        .task(id: scenePhase) {
            // UIKit presentation can initially mount during an inactive scene.
            // Wait for activation; do not dismiss the just-answered call.
            guard scenePhase == .active else { return }
            voice.start(bot: knotBot, recentConversation: recentConversation, incoming: incoming, welcome: welcome, directOutgoing: directOutgoing, relay: relay, stopWork: stopWork)
        }
        .onDisappear { voice.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { finish() } }
        .onChange(of: WhisperCameraCallMonitor.shared.callOwnsAudio) { _, busy in if busy { finish() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in voice.refreshRoute() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue {
                // Permission/presentation transitions are not an active audio
                // interruption. A genuine connected-call interruption still ends.
                if voice.phase == .active { finish() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in finish() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotVoiceConsentChanged"))) { _ in
            if !WhisperKnotVoicePreferences.allowed && welcome == nil || relay != nil && !WhisperKnotVoicePreferences.chatToolsAllowed { finish() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
            voice.stop(); voice.history.clearMemory(); showTranscript = false; close()
        }
        .accessibilityAction(.escape) { finish() }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(spacing: 12) {
                Button { Haptics.tap(); voice.toggleMute() } label: {
                    controlImage(voice.muted ? "mic.slash.fill" : "mic.fill", active: voice.muted)
                }.buttonStyle(.plain).disabled(voice.phase != .active || voice.muteBusy)
                .accessibilityLabel(voice.muted ? "Unmute microphone" : "Mute microphone")
                Text(voice.muted ? "Unmute" : "Mute").font(.caption)
            }.opacity(voice.phase == .active ? 1 : 0.45)
            VStack(spacing: 12) {
                WhisperAudioRouteMenu(current: voice.audioRoute, onSelect: { voice.route(to: $0) }) {
                    controlImage(voice.audioRoute.controlIcon, active: voice.audioRoute == .speaker)
                }.disabled(voice.phase != .active).accessibilityLabel("Audio output")
                Text("Audio").font(.caption)
            }.opacity(voice.phase == .active ? 1 : 0.45)
            VStack(spacing: 12) {
                Button { Haptics.tap(); finish() } label: { controlImage("phone.down.fill", end: true) }
                    .buttonStyle(.plain).accessibilityLabel("End call")
                Text(voice.phase == .ended || voice.phase == .unavailable ? "Done" : "End").font(.caption)
            }
        }
    }

    private func controlImage(_ icon: String, active: Bool = false, end: Bool = false) -> some View {
        Image(systemName: icon).font(.system(size: 24, weight: .medium))
            .foregroundStyle(active && !end ? Color.black : .white)
            .frame(width: 64, height: 64)
            .background(end ? Color.red : (active ? Color.white : .white.opacity(0.14)), in: Circle())
    }

    private func close() { if let onExternalClose { onExternalClose() } else { dismiss() } }
    private func finish() { voice.stop(); showTranscript = false; close() }
}
