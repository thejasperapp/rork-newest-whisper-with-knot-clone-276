import Foundation
import SwiftUI

/// "How are you today" mood highlights — Whisper's take on Instagram story
/// highlights. A horizontal strip of circles that lets the user broadcast
/// their current vibe with one tap. Selected mood doubles as the active
/// thought (so it shows in the avatar bubble + story strip).
nonisolated struct WhisperHighlight: Identifiable, Sendable, Hashable {
    let id: String
    let label: String
    let emoji: String
    let symbol: String
    let phrase: String
    let tint: WhisperHighlightTint

    nonisolated var asMoodTag: String { "\(emoji) \(label)" }
}

/// Light/dark-aware tint pair for a highlight bubble.
nonisolated struct WhisperHighlightTint: Sendable, Hashable {
    let light: UInt32  // 0xRRGGBB
    let dark: UInt32

    func color(_ scheme: ColorScheme) -> Color {
        let v = scheme == .dark ? dark : light
        return Color(
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0
        )
    }
}

@MainActor
@Observable
final class WhisperHighlightsService {
    static let shared = WhisperHighlightsService()

    private let key = "whisper.highlight.id"

    /// The currently-selected highlight, if any.
    var selectedID: String?

    /// Catalog — kept stable across the app so the IG-style highlight reel
    /// looks identical wherever it's rendered.
    let catalog: [WhisperHighlight] = [
        WhisperHighlight(id: "locked",   label: "Locked in", emoji: "🔒", symbol: "lock.fill",
                         phrase: "Locked in. No noise today.",
                         tint: .init(light: 0x111111, dark: 0xF5F5F5)),
        WhisperHighlight(id: "pr",       label: "PR day",    emoji: "💪", symbol: "flame.fill",
                         phrase: "PR loading… 💪",
                         tint: .init(light: 0xFF6A3D, dark: 0xFF7A4A)),
        WhisperHighlight(id: "rest",     label: "Rest",      emoji: "😌", symbol: "moon.zzz.fill",
                         phrase: "Rest day energy.",
                         tint: .init(light: 0x6E7CFF, dark: 0x8E9BFF)),
        WhisperHighlight(id: "recover",  label: "Recovery",  emoji: "🧘", symbol: "leaf.fill",
                         phrase: "Recovering. Listening to the body.",
                         tint: .init(light: 0x4FB17A, dark: 0x6EC793)),
        WhisperHighlight(id: "hyped",    label: "Hyped",     emoji: "🔥", symbol: "bolt.fill",
                         phrase: "Hyped. Let's go.",
                         tint: .init(light: 0xE83C5C, dark: 0xFF5A78)),
        WhisperHighlight(id: "quiet",    label: "Quiet",     emoji: "🌙", symbol: "sparkles",
                         phrase: "Quiet grind.",
                         tint: .init(light: 0x4A4458, dark: 0x9A93AC)),
        WhisperHighlight(id: "fueled",   label: "Fueled",    emoji: "🥗", symbol: "fork.knife",
                         phrase: "Fueled & focused.",
                         tint: .init(light: 0x59A86B, dark: 0x7BC58D)),
        WhisperHighlight(id: "running",  label: "Running",   emoji: "🏃", symbol: "figure.run",
                         phrase: "Out for a run.",
                         tint: .init(light: 0x2E78D2, dark: 0x4F95EF)),
        WhisperHighlight(id: "lifting",  label: "Lifting",   emoji: "🏋️", symbol: "dumbbell.fill",
                         phrase: "Bar in hand.",
                         tint: .init(light: 0x8B5CF6, dark: 0xA784FF)),
        WhisperHighlight(id: "yoga",     label: "Stretch",   emoji: "🧘‍♀️", symbol: "figure.yoga",
                         phrase: "Stretching it out.",
                         tint: .init(light: 0x14B8A6, dark: 0x2DD4BF))
    ]

    private init() {
        selectedID = UserDefaults.standard.string(forKey: key)
    }

    var selected: WhisperHighlight? {
        guard let id = selectedID else { return nil }
        return catalog.first(where: { $0.id == id })
    }

    /// Toggles a highlight on/off. When activating, the matching phrase is
    /// also pushed into `WhisperThoughtService` so the existing avatar /
    /// story bubble surfaces it everywhere.
    func toggle(_ h: WhisperHighlight) {
        if selectedID == h.id {
            selectedID = nil
            UserDefaults.standard.removeObject(forKey: key)
            WhisperThoughtService.shared.clear()
        } else {
            selectedID = h.id
            UserDefaults.standard.set(h.id, forKey: key)
            WhisperThoughtService.shared.post(h.phrase)
        }
    }
}

/// Instagram story-highlight style row. Used in two sizes:
///  - `.full` on the Profile (90pt circles + label below)
///  - `.mini` on the Feed/Inbox (54pt circles + caption)
struct WhisperHighlightsRow: View {
    enum Size { case full, mini }

    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperHighlightsService.shared

    var size: Size = .full
    var title: String? = "How are you today?"

    private var circleSize: CGFloat { size == .full ? 78 : 54 }
    private var ringSize: CGFloat { size == .full ? 88 : 62 }
    private var labelFont: Font { size == .full ? .caption.weight(.semibold) : .caption2.weight(.semibold) }

    var body: some View {
        VStack(alignment: .leading, spacing: size == .full ? 10 : 8) {
            if let title, size == .full {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: size == .full ? 14 : 10) {
                    ForEach(service.catalog) { h in
                        bubble(for: h)
                    }
                }
                .padding(.vertical, 4)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    private func bubble(for h: WhisperHighlight) -> some View {
        let isSelected = service.selectedID == h.id
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                service.toggle(h)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Outer selection ring (Instagram-style gradient → ink-only here)
                    Circle()
                        .strokeBorder(
                            isSelected ? WhisperTheme.ink(colorScheme) : WhisperTheme.hairline(colorScheme),
                            lineWidth: isSelected ? 2 : 1
                        )
                        .frame(width: ringSize, height: ringSize)

                    // Inner tinted disc
                    Circle()
                        .fill(h.tint.color(colorScheme).opacity(isSelected ? 1 : 0.18))
                        .frame(width: circleSize, height: circleSize)
                        .overlay {
                            Text(h.emoji)
                                .font(.system(size: size == .full ? 30 : 22))
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                                    .frame(width: size == .full ? 22 : 16, height: size == .full ? 22 : 16)
                                    .background(
                                        Circle()
                                            .fill(WhisperTheme.ink(colorScheme))
                                            .overlay(Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2))
                                    )
                                    .offset(x: 4, y: 4)
                            }
                        }
                }
                Text(h.label)
                    .font(labelFont)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .frame(maxWidth: ringSize + 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(h.label) mood\(isSelected ? ", selected" : "")")
    }
}
