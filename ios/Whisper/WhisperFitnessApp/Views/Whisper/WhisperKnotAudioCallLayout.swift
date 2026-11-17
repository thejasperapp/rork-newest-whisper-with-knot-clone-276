import SwiftUI
import UIKit

/// Shared presentation only. Rendering this shell never requests audio, a token,
/// or a provider connection. Both invitations and connected calls use it.
struct WhisperKnotAudioCallLayout<Status: View, Detail: View, Controls: View>: View {
    let bot: WhisperKnotBot
    var avatarMotion: String? = nil
    @ViewBuilder var status: () -> Status
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var controls: () -> Controls
    @State private var portrait: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.overlay {
                    if let portrait {
                        Image(uiImage: portrait).resizable().scaledToFill()
                            .blur(radius: 58, opaque: true).saturation(0.95)
                            .overlay(Color.black.opacity(0.55))
                    }
                }.clipped().ignoresSafeArea().allowsHitTesting(false)
                ViewThatFits(in: .vertical) {
                    content.frame(height: geometry.size.height)
                    ScrollView { content }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }.foregroundStyle(.white)
        }
        .environment(\.colorScheme, .dark)
        .task {
            let renderer = ImageRenderer(content: WhisperKnotProfilePortrait(size: 640, expression: .calm, tint: bot.portraitTint)
                .environment(\.whisperMediaActive, false))
            renderer.scale = 1
            portrait = renderer.uiImage
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Label("Whisper Audio · AI", systemImage: "phone.fill")
                .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                .padding(.top, 24)
            Spacer(minLength: 24)
            Group {
                if bot == .main {
                    WhisperKnotMascot(size: 128, callMotion: avatarMotion, usesCallPortrait: true)
                        .environment(\.whisperMediaActive, avatarMotion != nil)
                } else {
                    WhisperKnotProfilePortrait(size: 128, expression: .calm, tint: bot.portraitTint)
                        .environment(\.whisperMediaActive, false)
                }
            }.shadow(color: .black.opacity(0.2), radius: 18, y: 8)
            Text(bot.displayName).font(.system(size: 32, weight: .semibold))
                .multilineTextAlignment(.center).padding(.top, 24)
            status()
            Spacer(minLength: 24)
            detail()
            controls()
        }
        .frame(maxWidth: 520).padding(.horizontal, 24).padding(.bottom, 28)
        .frame(maxWidth: .infinity)
    }
}
