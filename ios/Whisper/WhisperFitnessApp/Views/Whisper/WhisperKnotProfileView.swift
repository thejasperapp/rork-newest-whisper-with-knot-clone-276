import SwiftUI

/// Knot is an app-owned assistant, not a fabricated social account.
struct WhisperKnotProfilePortrait: View {
    var size: CGFloat = 72
    var expression: WhisperEmberMascotExpression = .calm
    var tint: Color? = nil

    var body: some View {
        Group {
            if let tint {
                ZStack {
                    Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
                    WhisperKnotMascot(size: size * 0.82, expression: expression, bodyColor: tint)
                        .shadow(color: .black.opacity(0.18), radius: size * 0.045, x: 0, y: size * 0.045)
                }
                .overlay { Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
            } else {
                // The supplied artwork already has its own background and framing.
                WhisperKnotMascot(size: size, expression: expression)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct WhisperKnotProfileView: View {
    var onChat: (() -> Void)? = nil
    var embedded = false
    var bot: WhisperKnotBot = .main
    @Environment(\.dismiss) private var dismiss
    @Environment(\.whisperMediaActive) private var mediaActive
    @State private var mood: PortraitMood = .calm
    @State private var showChat = false
    @State private var showTuning = false
    @State private var showPortrait = false
    @State private var showDance = false

    private enum PortraitMood: String, CaseIterable, Identifiable {
        case calm = "Calm", curious = "Curious", happy = "Happy"
        var id: String { rawValue }
        var expression: WhisperEmberMascotExpression {
            switch self {
            case .calm: .calm
            case .curious: .curious
            case .happy: .happy
            }
        }
    }

    var body: some View {
        WhisperKnotNavigationContainer(embedded: embedded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 14) {
                        Button { Haptics.tap(); showPortrait = true } label: {
                            WhisperKnotProfilePortrait(size: 128, expression: mood.expression, tint: bot.portraitTint)
                        }.buttonStyle(.plain).accessibilityLabel("Knot’s portrait and expressions")
                        if bot == .main && bot.displayName == "Knot" { WhisperKnotWordmark(width: 86) }
                        else { Text(bot.displayName).font(.title2.bold()) }
                        Text(bot.job).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                        Text("An AI assistant, not a person or a social account. This Knot keeps its own conversation and draft. Knot can make mistakes.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Message \(bot.displayName)") {
                            Haptics.tap()
                            if let onChat { onChat() } else { showChat = true }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
                    }.frame(maxWidth: .infinity).modifier(WhisperKnotPanel())
                    VStack(alignment: .leading, spacing: 12) {
                        Label("\(bot.displayName)’s job", systemImage: "person.3.sequence").font(.headline)
                        Text(bot.about)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.modifier(WhisperKnotPanel())
                    VStack(alignment: .leading, spacing: 12) {
                        Label("You stay in control", systemImage: "checkmark.shield").font(.headline)
                        Text("Knot can help draft posts, propose meetings and reminders, and discover accessible posts and communities. Every action needs its own approval. Existing privacy and account access always apply.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Divider()
                        NavigationLink { WhisperJasperTuningView(embedded: true) } label: {
                            Label("Tune Knot’s replies", systemImage: "slider.horizontal.3").frame(minHeight: 44)
                        }
                        NavigationLink { WhisperKnotVoiceSettingsView(bot: bot) } label: {
                            Label("Voice & calls", systemImage: "waveform").frame(minHeight: 44)
                        }
                        NavigationLink { WhisperKnotPrivacyView() } label: {
                            Label("Privacy & context", systemImage: "hand.raised").frame(minHeight: 44)
                        }
                    }.modifier(WhisperKnotPanel())
                    Text("Use /knot in messages, or @knot in a post to privately shape your feed. Private chats never appear on this page.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6)
                }.frame(maxWidth: 620).padding(20).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("About \(bot.displayName)").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !embedded { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        }
        .sheet(isPresented: $showPortrait) {
            NavigationStack {
                VStack(spacing: 24) {
                    WhisperKnotProfilePortrait(size: 240, expression: mood.expression, tint: bot.portraitTint)
                    Picker("Knot’s expression", selection: $mood) {
                        ForEach(PortraitMood.allCases) { mood in Text(mood.rawValue).tag(mood) }
                    }.pickerStyle(.segmented).padding(.horizontal, 24)
                    if bot == .main && WhisperKnotPersonaStore.shared.snapshot?.masterID == nil {
                        Button("Play supplied dance", systemImage: "play.circle") {
                            Haptics.tap(); showDance = true
                        }.buttonStyle(.bordered).controlSize(.large)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Knot’s portrait").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPortrait = false } } }
            }
            .environment(\.whisperMediaActive, mediaActive && !showDance)
            .fullScreenCover(isPresented: $showDance) { WhisperKnotSuppliedDanceView() }
        }
        .environment(\.whisperMediaActive, mediaActive && !showChat && !showTuning && !showPortrait)
        .fullScreenCover(isPresented: $showChat) { WhisperEmberChatView().environment(\.whisperMediaActive, mediaActive) }
        .fullScreenCover(isPresented: $showTuning) { WhisperJasperTuningView().environment(\.whisperMediaActive, mediaActive) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            showChat = false; showTuning = false; showDance = false; showPortrait = false; dismiss()
        }
    }
}
