import SwiftUI

/// The supplied artwork, with native light/dark variants and one shared scale.
/// Keep prose, mentions and navigation labels as real text; this is branding only.
struct WhisperKnotWordmark: View {
    var width: CGFloat = 48
    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1

    var body: some View {
        Image("KnotWordmark")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: width * min(scale, 1.6), height: width * min(scale, 1.6) * 588 / 1600)
            .accessibilityLabel("Knot")
    }
}
