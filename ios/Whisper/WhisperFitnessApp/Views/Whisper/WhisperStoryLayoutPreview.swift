import SwiftUI

struct WhisperStoryLayoutPreview: View {
    let layout: WhisperStoryPhotoLayout
    var photo: UIImage? = nil
    var modifierLabel: Bool = true
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.12)
                ForEach(Array(layout.cells.enumerated()), id: \.offset) { index, cell in
                    Color(white: 0.25 + Double(index % 3) * 0.08)
                        .frame(width: cell.width * geometry.size.width, height: cell.height * geometry.size.height)
                        .overlay {
                            if let photo { Image(uiImage: photo).resizable().scaledToFill().allowsHitTesting(false) }
                            else { Image(systemName: "plus").font(.caption).foregroundStyle(.white.opacity(0.65)) }
                        }
                        .clipped()
                        .padding(layout == .strip || layout == .frame ? 3 : 0)
                        .padding(.bottom, layout == .strip || layout == .frame ? 8 : 0)
                        .background(layout == .strip || layout == .frame ? Color.white : .clear)
                        .rotationEffect(.degrees(layout == .frame ? -4 : 0))
                        .position(x: cell.midX * geometry.size.width, y: cell.midY * geometry.size.height)
                }
                if modifierLabel {
                    Text("\(layout.cells.count) PHOTOS").font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8)).position(x: geometry.size.width / 2, y: geometry.size.height * 0.94)
                }
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}
