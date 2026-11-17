import SwiftUI

struct WhisperProfileTabsView: View {
    @Binding var selection: WhisperProfileTab
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if typeSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) { tabs }
                .contentMargins(.horizontal, 16)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(WhisperProfileTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.tap()
                    withAnimation(reduceMotion ? nil : .whisperSnappy) { selection = tab }
                } label: {
                    Text(tab.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == tab ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, typeSize.isAccessibilitySize ? 14 : 3)
                        .overlay(alignment: .bottom) {
                            if selection == tab {
                                Rectangle().fill(WhisperTheme.ink(colorScheme)).frame(height: 2)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5).allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
