import SwiftUI

/// The visible sticker is smaller than its nonoverlapping 44-point touch area.
struct WhisperStoryTrayToolButton: View {
    let tool: WhisperStoryTrayTool
    let photo: UIImage?
    var scale: CGFloat = 1
    var usesReferenceWidth: Bool = true
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var accessibleFontSize: CGFloat = 18

    private var fontSize: CGFloat { usesReferenceWidth ? 18 * scale : accessibleFontSize }
    private var faceHeight: CGFloat { usesReferenceWidth ? 32 * scale : max(36, accessibleFontSize + 14) }

    var body: some View {
        Button(action: action) {
            face
                .rotationEffect(.degrees(usesReferenceWidth ? tool.tilt : 0))
                .frame(width: usesReferenceWidth ? max(44, tool.referenceWidth * scale) : nil)
                .frame(minWidth: 44, minHeight: max(44, 44 * scale))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.rawValue)
        .accessibilityValue(tool.unavailableMessage == nil ? "" : "Not available yet")
        .accessibilityHint(tool.unavailableMessage == nil ? "Opens the \(tool.rawValue) editor" : "Explains this unavailable feature")
        .accessibilityIdentifier("story.attachment.\(tool.id)")
    }

    @ViewBuilder private var face: some View {
        if tool == .reaction {
            Text("😍").font(.system(size: 20 * scale))
                .frame(width: faceHeight, height: faceHeight)
                .background(.white, in: .circle)
        } else if tool == .slider {
            HStack(spacing: 0) {
                Text("😍").font(.system(size: 20 * scale)).zIndex(1)
                Capsule().fill(Color(white: 0.90)).frame(width: 46 * scale, height: 5 * scale).padding(.leading, -2 * scale)
            }
            .frame(width: usesReferenceWidth ? tool.referenceWidth * scale : 108, height: faceHeight)
            .background(.white, in: .rect(cornerRadius: 10 * scale))
        } else {
            HStack(spacing: (tool == .mention || tool == .hashtag ? 1 : 5) * scale) {
                icon
                Text(tool.title)
                    .font(.system(size: fontSize, weight: .regular))
                    .tracking(-0.35 * scale)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Color(white: 0.035))
            .padding(.horizontal, (tool == .frames || tool == .photostrip || tool == .avatar ? 7 : 9) * scale)
            .frame(width: usesReferenceWidth ? tool.referenceWidth * scale : nil, height: faceHeight)
            .background(.white, in: .rect(cornerRadius: 10 * scale))
        }
    }

    @ViewBuilder private var icon: some View {
        switch tool {
        case .frames:
            ZStack {
                photoCard(width: 22 * scale, height: 28 * scale)
                    .rotationEffect(.degrees(-13)).offset(x: -3 * scale)
                photoCard(width: 25 * scale, height: 29 * scale)
                    .rotationEffect(.degrees(10)).offset(x: 3 * scale)
            }.frame(width: 32 * scale, height: faceHeight)
        case .photostrip:
            ZStack {
                strip.rotationEffect(.degrees(-11)).offset(x: -4 * scale)
                strip.rotationEffect(.degrees(5)).offset(x: 3 * scale, y: -1 * scale)
            }.frame(width: 23 * scale, height: faceHeight)
        case .avatar:
            Image("cartoon_boy_heart_eyes").resizable().scaledToFit()
                .frame(width: 37 * scale, height: 40 * scale)
                .offset(y: -3 * scale).allowsHitTesting(false)
        case .music:
            HStack(alignment: .center, spacing: 2 * scale) {
                ForEach(Array([9.0, 18.0, 13.0, 21.0].enumerated()), id: \.offset) { _, height in
                    Capsule().fill(tool.tint).frame(width: 2.5 * scale, height: height * scale)
                }
            }.frame(width: 17 * scale)
        case .poll:
            VStack(alignment: .leading, spacing: 3 * scale) {
                Capsule().fill(tool.tint).frame(width: 17 * scale, height: 4 * scale)
                Capsule().fill(tool.tint.opacity(0.6)).frame(width: 12 * scale, height: 4 * scale)
                Capsule().fill(tool.tint.opacity(0.3)).frame(width: 15 * scale, height: 4 * scale)
            }.frame(width: 17 * scale)
        case .questions:
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 18 * scale, weight: .medium)).foregroundStyle(tool.tint)
        case .countdown:
            Image(systemName: "timer").font(.system(size: 19 * scale, weight: .medium))
                .foregroundStyle(tool.tint)
        default:
            Image(systemName: tool.symbol)
                .font(.system(size: (tool == .hashtag ? 21 : 17) * scale, weight: .medium))
                .foregroundStyle(tool.tint)
        }
    }

    private var strip: some View {
        VStack(spacing: scale) {
            photoCard(width: 10 * scale, height: 9 * scale)
            photoCard(width: 10 * scale, height: 9 * scale)
            photoCard(width: 10 * scale, height: 9 * scale)
        }.padding(1.5 * scale).background(.white)
    }

    private func photoCard(width: CGFloat, height: CGFloat) -> some View {
        Color(white: 0.75)
            .frame(width: width, height: height)
            .overlay {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill().allowsHitTesting(false)
                } else {
                    Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(.gray)
                }
            }
            .clipped()
            .overlay { Rectangle().strokeBorder(.white, lineWidth: 1.5 * scale) }
    }
}
