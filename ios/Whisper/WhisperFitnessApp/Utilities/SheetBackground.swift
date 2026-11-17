import SwiftUI

/// Background used for popup/sheet screens.
/// Light mode: soft cream so sheets feel calmer than the warm orange app background.
/// Dark mode: same deep-black gradient as AppBackground for consistency.
struct SheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(white: 0.13)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.984, green: 0.956, blue: 0.894), // cream top
                        Color(red: 0.965, green: 0.925, blue: 0.843)  // cream bottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}
