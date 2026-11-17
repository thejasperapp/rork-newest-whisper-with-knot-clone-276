import SwiftUI

/// A standalone, accessible hello. Never place this inside another Button.
struct WhisperJasperInteractiveMascot: View {
    var size: CGFloat = 72
    var dating: Bool = false
    var working: Bool = false
    var restingExpression: WhisperEmberMascotExpression = .calm
    @Environment(\.whisperMediaActive) private var mediaActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var reaction: WhisperEmberMascotExpression? = nil
    @State private var greeting: Int = 0

    var body: some View {
        Button {
            Haptics.tap()
            greeting &+= 1
        } label: {
            WhisperJasperIntelligenceMark(working: working,
                palette: dating ? .cupidPink : nil, smitten: dating,
                expression: reaction ?? (dating ? .happy : restingExpression))
                .frame(width: size, height: size)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(WhisperJasperReactionButtonStyle())
        .accessibilityLabel(dating ? "Say hello to Knot, your matchmaker" : "Say hello to Knot")
        .accessibilityHint("Knot responds with a playful expression")
        .disabled(working || !mediaActive || scenePhase != .active)
        .task(id: greeting) {
            guard greeting > 0, mediaActive, scenePhase == .active else { return }
            reaction = .curious
            do {
                try await Task.sleep(for: .milliseconds(650))
                guard mediaActive, scenePhase == .active else { reaction = nil; return }
                reaction = .delighted
                try await Task.sleep(for: .milliseconds(1100))
                reaction = nil
            } catch { reaction = nil }
        }
        .onChange(of: mediaActive) { _, active in if !active { greeting = 0; reaction = nil } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { greeting = 0; reaction = nil } }
    }
}
