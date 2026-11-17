import SwiftUI

struct ScrollEdgeBlur: ViewModifier {
    func body(content: Content) -> some View {
        content
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)

                    Color.black

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)
                }
            }
    }
}

extension View {
    func scrollEdgeBlur() -> some View {
        modifier(ScrollEdgeBlur())
    }
}
