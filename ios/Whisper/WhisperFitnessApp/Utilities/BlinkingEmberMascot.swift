import SwiftUI

struct BlinkingEmberMascot: View {
    var size: CGFloat = 56

    var body: some View {
        Image("EmberMascot")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
