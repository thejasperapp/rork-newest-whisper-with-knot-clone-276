import SwiftUI

/// Large edge compositions leave a quiet reading field; no repeated clip-art or animation.
struct WhisperChatWallpaper: View {
    let theme: WhisperChatAppearance
    var design: WhisperChatThemeDesign? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = design?.palette(scheme) ?? theme.palette(scheme)
        palette.canvas.overlay {
            if theme != .classic && contrast != .increased {
                Canvas { context, size in
                    context.scaleBy(x: size.width / 390, y: size.height / 780)
                    let pigment = palette.accent.opacity(scheme == .dark ? 0.16 : 0.11)
                    let fine = palette.accent.opacity(scheme == .dark ? 0.25 : 0.18)
                    switch theme {
                    case .rose, .cherry, .forest, .wildflower, .lavender, .mint:
                        for side in 0..<2 {
                            var c = context
                            c.translateBy(x: side == 0 ? -38 : 428, y: side == 0 ? 190 : 740)
                            c.rotate(by: .degrees(side == 0 ? -24 : 156))
                            var stem = Path()
                            stem.move(to: .zero)
                            stem.addQuadCurve(to: CGPoint(x: 64, y: 320), control: CGPoint(x: 120, y: 130))
                            c.stroke(stem, with: .color(fine), lineWidth: 1)
                            for index in 0..<5 {
                                let y = CGFloat(index) * 54 + 12
                                var leaf = Path()
                                leaf.move(to: CGPoint(x: 48, y: y + 34))
                                leaf.addQuadCurve(to: CGPoint(x: -18, y: y - 28), control: CGPoint(x: -38, y: y + 30))
                                leaf.addQuadCurve(to: CGPoint(x: 48, y: y + 34), control: CGPoint(x: 50, y: y - 24))
                                c.fill(leaf, with: .color(pigment))
                            }
                        }
                    case .midnight, .nocturne, .sky:
                        context.fill(Path(ellipseIn: CGRect(x: 280, y: 80, width: 180, height: 180)), with: .color(pigment))
                        for i in 0..<3 {
                            context.stroke(Path(ellipseIn: CGRect(x: -180 + CGFloat(i)*24, y: 460 + CGFloat(i)*24, width: 430, height: 430)), with: .color(fine), lineWidth: 0.8)
                        }
                    case .lantern, .terracotta, .coffee:
                        for i in 0..<4 {
                            let inset = CGFloat(i) * 22
                            let arch = Path(roundedRect: CGRect(x: 270 + inset, y: 80 + inset, width: 210 - inset, height: 390), cornerRadius: 105)
                            context.stroke(arch, with: .color(fine), lineWidth: 1)
                        }
                        context.fill(Path(ellipseIn: CGRect(x: -110, y: 580, width: 210, height: 210)), with: .color(pigment))
                    case .blueprint:
                        for x in stride(from: CGFloat(20), through: 390, by: 32) {
                            for y in stride(from: CGFloat(20), through: 780, by: 32) {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(fine))
                            }
                        }
                    default:
                        for i in 0..<5 {
                            let shift = CGFloat(i) * 24
                            var contour = Path()
                            contour.move(to: CGPoint(x: -90, y: 470 + shift))
                            contour.addCurve(to: CGPoint(x: 470, y: 760 + shift), control1: CGPoint(x: 155, y: 250 + shift), control2: CGPoint(x: 205, y: 900 + shift))
                            context.stroke(contour, with: .color(fine), lineWidth: 1)
                        }
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
