import SwiftUI

/// Keeps the room and its private tools in separate, measured layout regions.
struct WhisperMeetingDrawerLayout<Stage: View, Drawer: View>: View {
    let isOpen: Bool
    @ViewBuilder let stage: () -> Stage
    @ViewBuilder let drawer: () -> Drawer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 720
            let gap: CGFloat = isOpen ? 12 : 0
            let drawerWidth: CGFloat = isOpen ? (wide ? min(380, geometry.size.width * 0.44) : geometry.size.width) : 0
            let drawerHeight: CGFloat = isOpen ? (wide ? geometry.size.height : geometry.size.height * 0.68) : 0
            let layout = wide ? AnyLayout(HStackLayout(spacing: gap)) : AnyLayout(VStackLayout(spacing: gap))
            layout {
                stage()
                    .frame(width: wide ? max(0, geometry.size.width - drawerWidth - gap) : geometry.size.width,
                           height: wide ? geometry.size.height : max(0, geometry.size.height - drawerHeight - gap))
                    .clipShape(.rect(cornerRadius: isOpen ? 28 : 0))
                drawer()
                    .frame(width: drawerWidth, height: drawerHeight)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 28))
                    .clipShape(.rect(cornerRadius: 28))
                    .opacity(isOpen ? 1 : 0)
                    .allowsHitTesting(isOpen)
                    .accessibilityHidden(!isOpen)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isOpen)
        }
    }
}
