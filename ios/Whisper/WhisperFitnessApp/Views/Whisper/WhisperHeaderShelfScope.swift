import SwiftUI

struct WhisperHeaderShelfScope<Content: View>: View {
    let content: Content
    let isSelected: Bool
    @State private var shelf: WhisperHeaderShelfState = WhisperHeaderShelfState()

    var body: some View {
        content.environment(\.whisperHeaderShelf, shelf)
            .onChange(of: isSelected) { _, active in if active { shelf.reveal() } }
    }
}

private struct WhisperHeaderShelfKey: EnvironmentKey {
    static let defaultValue: WhisperHeaderShelfState? = nil
}
extension EnvironmentValues {
    var whisperHeaderShelf: WhisperHeaderShelfState? {
        get { self[WhisperHeaderShelfKey.self] }
        set { self[WhisperHeaderShelfKey.self] = newValue }
    }
}

private struct WhisperShelvingHeader<Header: View>: ViewModifier {
    let header: Header
    var backdrop: Color? = nil
    var blurred: Bool = false
    @Environment(\.whisperHeaderShelf) private var shelf
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        if let shelf {
            content.overlay(alignment: .top) {
                header
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if height > 0, abs(shelf.height - height) > 0.5 { shelf.height = height }
                    }
                    .offset(y: shelf.isHidden && !voiceOver ? -shelf.height : 0)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: shelf.isHidden)
                    .clipped()
                    .allowsHitTesting(!shelf.isHidden || voiceOver)
                    .accessibilityHidden(shelf.isHidden && !voiceOver)
            }
            .overlay {
                WhisperStatusBarBackdrop(color: backdrop ?? WhisperTheme.surface(colorScheme), blurred: blurred, blurProgress: shelf.blurProgress)
                    .ignoresSafeArea(edges: .top).allowsHitTesting(false).accessibilityHidden(true)
            }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { header }
        }
    }
}

extension View {
    func whisperShelvingHeader<Header: View>(backdrop: Color? = nil, blurred: Bool = false, @ViewBuilder _ header: () -> Header) -> some View {
        modifier(WhisperShelvingHeader(header: header(), backdrop: backdrop, blurred: blurred))
    }
}
