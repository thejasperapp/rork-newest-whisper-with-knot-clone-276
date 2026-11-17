import CoreGraphics
import Foundation

/// Actual pixels win over a neighboring sticker's expanded touch target.
nonisolated struct WhisperStoryHitRegion {
    let id: String
    let center: CGPoint
    let size: CGSize
    let scale: CGFloat
    let rotation: CGFloat

    func distance(to point: CGPoint) -> CGFloat {
        let dx = point.x - center.x; let dy = point.y - center.y
        let x = abs(dx * cos(-rotation) - dy * sin(-rotation))
        let y = abs(dx * sin(-rotation) + dy * cos(-rotation))
        return hypot(max(0, x - size.width * scale / 2), max(0, y - size.height * scale / 2))
    }

    static func target(at point: CGPoint, regions: [Self]) -> String? {
        let frontToBack = regions.reversed()
        if let exact = frontToBack.first(where: { $0.distance(to: point) <= 0.001 }) { return exact.id }
        var closest: (String, CGFloat)?
        for region in frontToBack {
            let dx = point.x - region.center.x; let dy = point.y - region.center.y
            let x = abs(dx * cos(-region.rotation) - dy * sin(-region.rotation))
            let y = abs(dx * sin(-region.rotation) + dy * cos(-region.rotation))
            guard x <= max(22, region.size.width * region.scale / 2), y <= max(22, region.size.height * region.scale / 2) else { continue }
            let distance = region.distance(to: point)
            if distance < (closest?.1 ?? .infinity) { closest = (region.id, distance) }
        }
        return closest?.0
    }
}
