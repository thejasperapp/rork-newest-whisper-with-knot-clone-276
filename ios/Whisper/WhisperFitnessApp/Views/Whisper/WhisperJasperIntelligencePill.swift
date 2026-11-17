import SwiftUI

/// Knot's shared native glass entry. The registered knit artwork peeks above
/// the control without becoming a hit target or painting over its name.
struct WhisperJasperIntelligencePill: View {
    // Retained for existing hosts; every entry now uses the reference proportions.
    var compact: Bool = false
    var working: Bool = false
    var showsPeek: Bool = true
    var title: String = "Knot"
    var reservesPeekSpace: Bool = true
    var leadingAsset: String? = nil
    var coachMode: WhisperEmberCoachMode = .regular
    var mascotPalette: WhisperEmberMascotPalette? = nil
    var mascotSmitten: Bool = false
    /// Legacy host hint; no longer changes the shared brand dimensions.
    var small: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let mascotSize: CGFloat = 48
    // The capsule hides the lower body; both eyes stay fully above its rim.
    private var peekHeight: CGFloat { mascotSize * 0.72 }

    var body: some View {
        HStack(spacing: 7) {
            if let leadingAsset {
                Image(leadingAsset)
                    .renderingMode(.template)
                    .resizable().scaledToFit().frame(height: 14)
                    .foregroundStyle(mascotSmitten ? LinearGradient(colors: [.pink, Color(red: 0.91, green: 0.28, blue: 0.49)], startPoint: .topLeading, endPoint: .bottomTrailing) : WhisperBrandGradient.linear)
            }
            if title == "Knot" {
                WhisperKnotWordmark(width: 52)
            } else {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 8)
        .frame(minWidth: 90, minHeight: 36)
        .modifier(WhisperKnotGlassPill())
        .background(alignment: .top) {
            if showsPeek {
                WhisperJasperIntelligenceMark(working: working, coachMode: coachMode,
                    palette: mascotPalette, smitten: mascotSmitten)
                    .frame(width: mascotSize, height: mascotSize)
                    .frame(height: peekHeight, alignment: .top)
                    .clipped()
                    .offset(y: -peekHeight + 1)
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, showsPeek && reservesPeekSpace ? peekHeight : 0)
        // A compact visual capsule still has a full native touch target.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(working ? "Working" : "")
    }
}
