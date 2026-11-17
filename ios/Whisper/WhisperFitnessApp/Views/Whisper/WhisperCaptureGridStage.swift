import SwiftUI

struct WhisperCaptureGridStage<Preview: View>: View {
    let grid: WhisperCaptureGrid?
    let photos: [Int: UIImage]
    let activeCell: Int
    let locked: Bool
    let onRetake: (Int) -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        GeometryReader { geometry in
            let cells = grid?.cells ?? [CGRect(x: 0, y: 0, width: 1, height: 1)]
            ZStack(alignment: .topLeading) {
                Color(white: 0.09)
                // Keep one live renderer mounted while its cell changes.
                let cell = cells[min(max(0, activeCell), cells.count - 1)]
                preview().frame(width: cell.width * geometry.size.width, height: cell.height * geometry.size.height)
                    .clipped().position(x: cell.midX * geometry.size.width, y: cell.midY * geometry.size.height)
                ForEach(Array((grid?.cells ?? []).enumerated()), id: \.offset) { index, rect in
                    Color.clear
                        .frame(width: rect.width * geometry.size.width, height: rect.height * geometry.size.height)
                        .overlay {
                            if let image = photos[index] {
                                Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
                            } else if index != activeCell { Color.black.opacity(0.55) }
                        }
                        .clipped()
                        .overlay {
                            Rectangle().strokeBorder(.white.opacity(index == activeCell ? 0.9 : 0.35), lineWidth: index == activeCell ? 2 : 0.5)
                                .allowsHitTesting(false)
                        }
                        .overlay(alignment: .topTrailing) {
                            if photos[index] != nil {
                                Button { onRetake(index) } label: {
                                    Image(systemName: "arrow.counterclockwise").font(.system(size: 15, weight: .bold))
                                        .frame(width: 44, height: 44).background(.black.opacity(0.35), in: .circle)
                                }.buttonStyle(.plain).foregroundStyle(.white)
                                    .accessibilityLabel("Retake photo \(index + 1)").disabled(locked)
                                    .padding(6)
                            }
                        }
                        .position(x: rect.midX * geometry.size.width, y: rect.midY * geometry.size.height)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}
