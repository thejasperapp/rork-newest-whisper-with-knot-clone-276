import SwiftUI

/// Small paper-cut motifs in the app's illustration palette, simplified for menu rows.
struct WhisperAttachmentIllustration: View {
    let id: String
    let symbol: String
    var jasper: Bool = false
    private var tint: Color {
        if id.contains("photo") || id.contains("media") { return Color(red: 0.65, green: 0.8, blue: 0.73) }
        if id.contains("draw") || id.contains("imagine") { return Color(red: 0.98, green: 0.77, blue: 0.6) }
        if id.contains("location") || id.contains("link") { return Color(red: 0.65, green: 0.79, blue: 0.91) }
        return Color(red: 0.91, green: 0.82, blue: 0.66)
    }
    var body: some View {
        ZStack {
            if jasper {
                WhisperJasperIntelligenceMark().frame(width: 30, height: 30)
            } else if id.contains("sticker") {
                Circle().fill(tint).frame(width: 29, height: 29)
                Image(systemName: "face.smiling").font(.system(size: 22, weight: .regular)).foregroundStyle(Color(white: 0.25))
            } else {
                RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.5)).frame(width: 25, height: 29).rotationEffect(.degrees(-14)).offset(x: -3, y: 1)
                RoundedRectangle(cornerRadius: 5).fill(tint).frame(width: 26, height: 29).rotationEffect(.degrees(6))
                Image(systemName: symbol.isEmpty ? "photo.on.rectangle" : symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Color(white: 0.23)).rotationEffect(.degrees(6))
            }
        }.frame(width: 36, height: 38).accessibilityHidden(true)
    }
}
