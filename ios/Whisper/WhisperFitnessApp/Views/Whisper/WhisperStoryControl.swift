import SwiftUI

/// Quiet, readable media controls with one consistent 44-point hit target.
struct WhisperStoryControl: View {
    let symbol: String
    let label: String
    var selected: Bool = false
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button {
            Haptics.tap(); action()
        } label: {
            Group {
                if symbol == "face.smiling.inverse" {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 1.8).frame(width: 24, height: 25)
                        VStack(spacing: 4) {
                            HStack(spacing: 7) { Circle().frame(width: 2.5, height: 2.5); Circle().frame(width: 2.5, height: 2.5) }
                            Path { path in path.move(to: CGPoint(x: 0, y: 0)); path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 6)) }.stroke(style: StrokeStyle(lineWidth: 1.7, lineCap: .round)).frame(width: 10, height: 5)
                        }
                    }
                } else { Image(systemName: symbol) }
            }
                .font(.system(size: symbol == "xmark" ? 23 : 22, weight: .regular))
                .foregroundStyle(selected ? .black : .white)
                .frame(width: 44, height: 44)
                .background(selected ? Color.white : Color(white: 0.12).opacity(reduceTransparency ? 1 : 0.62), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
