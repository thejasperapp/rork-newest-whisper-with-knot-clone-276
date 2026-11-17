import SwiftUI

struct DismissableScrollView<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var scrollOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("dismissScroll")).minY)
                }
                .frame(height: 0)

                content()
            }
        }
        .coordinateSpace(name: "dismissScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            scrollOffset = value
        }
        .scrollIndicators(.hidden)
        .scrollEdgeBlur()
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if scrollOffset >= -5 && value.translation.height > 0 {
                        isDragging = true
                        dragOffset = value.translation.height * 0.5
                    }
                }
                .onEnded { value in
                    if isDragging && dragOffset > 80 {
                        onDismiss()
                    }
                    withAnimation(.spring(response: 0.3)) {
                        dragOffset = 0
                        isDragging = false
                    }
                }
        )
        .offset(y: dragOffset)
    }
}

nonisolated struct ScrollOffsetKey: PreferenceKey, Sendable {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
