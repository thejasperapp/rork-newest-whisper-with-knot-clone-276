import SwiftUI

struct WhisperCaptureGridGlyph: View {
    let grid: WhisperCaptureGrid
    var body: some View {
        Canvas { context, size in
            for cell in grid.cells {
                let rect = CGRect(x: cell.minX * size.width, y: cell.minY * size.height, width: cell.width * size.width, height: cell.height * size.height).insetBy(dx: 1.5, dy: 1.5)
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .foreground, lineWidth: 1.5)
            }
        }.frame(width: 25, height: 30).accessibilityHidden(true)
    }
}
