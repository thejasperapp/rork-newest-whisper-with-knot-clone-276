import SwiftUI

// MARK: - The Jasper pill
//
// Command/status content stays local to the conversation. The shared header
// opens Intelligence without submitting the message draft or sharing a reply.

struct WhisperJasperPeekPill<Content: View>: View {
    /// Corner radius of the pill (24 = capsule-ish for one row of chips).
    var cornerRadius: CGFloat = 24
    var small: Bool = false
    let onOpenIntelligence: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 10) {
            Button { Haptics.tap(); onOpenIntelligence() } label: {
                WhisperJasperIntelligencePill(compact: true, small: small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Knot")
            content()
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background {
                    WhisperJasperIntelligenceShell(shape: RoundedRectangle(cornerRadius: cornerRadius), panel: true)
                }
        }

    }
}

/// Jasper's quiet mark in chat — a small dot wearing the brand gradient with
/// a slow breath. Replaces the app icon everywhere Jasper shows up inside a
/// conversation.
struct WhisperJasperSpark: View {
    var size: CGFloat = 8
    @State private var breathe: Bool = false

    var body: some View {
        Circle()
            .fill(WhisperBrandGradient.diagonal)
            .frame(width: size, height: size)
            .shadow(color: WhisperBrandGradient.accent.opacity(breathe ? 0.45 : 0.15), radius: breathe ? 6 : 2)
            .scaleEffect(breathe ? 1.08 : 0.96)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
            }
            .accessibilityHidden(true)
    }
}

/// One command chip inside the pill — icon + "/name".
struct WhisperJasperCommandChip: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.75))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, subtitle == nil ? 7 : 5)
            .background(WhisperTheme.card(colorScheme), in: Capsule())
            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
        }
        .buttonStyle(WhisperMenuPressStyle())
    }
}

/// The pill's one-line status: a label + optional thinking dots.
struct WhisperJasperPillLine: View {
    let text: String
    var thinking: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                .lineLimit(1)
            if thinking {
                WhisperJasperMiniDots(tint: WhisperTheme.ink(colorScheme).opacity(0.6), dotSize: 4)
            }
        }
        .padding(.vertical, 2)
    }
}
