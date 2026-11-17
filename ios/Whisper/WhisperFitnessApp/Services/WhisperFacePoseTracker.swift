import CoreGraphics

/// Owned by one rendering queue. Smooths only unambiguous nearby faces; missing faces disappear immediately.
nonisolated final class WhisperFacePoseTracker {
    private var previous: [WhisperARProcessor.FaceFrame] = []
    private var lastTime: Double? = nil

    func reset() { previous = []; lastTime = nil }

    func update(_ frames: [WhisperARProcessor.FaceFrame], time: Double) -> [WhisperARProcessor.FaceFrame] {
        guard time.isFinite else { reset(); return frames }
        let dt = time - (lastTime ?? time)
        if dt <= 0 || dt > 0.2 { previous = [] }
        lastTime = time
        var candidates = previous
        let result = frames.map { next -> WhisperARProcessor.FaceFrame in
            let ranked = candidates.indices.filter {
                distance(candidates[$0].eyeMid, next.eyeMid) < next.eyeDistance * 0.7 &&
                abs(candidates[$0].eyeDistance - next.eyeDistance) < next.eyeDistance * 0.3
            }.sorted { distance(candidates[$0].eyeMid, next.eyeMid) < distance(candidates[$1].eyeMid, next.eyeMid) }
            guard let index = ranked.first else { return next }
            // Crossing faces must not blend landmarks from two different people.
            if ranked.count > 1,
               distance(candidates[ranked[1]].eyeMid, next.eyeMid) - distance(candidates[index].eyeMid, next.eyeMid) < next.eyeDistance * 0.2 { return next }
            let old = candidates[index]
            let competing = frames.filter { distance(old.eyeMid, $0.eyeMid) < distance(old.eyeMid, next.eyeMid) + next.eyeDistance * 0.2 }
            guard competing.count == 1 else { return next }
            candidates.remove(at: index)
            let delta = atan2(sin(next.angle - old.angle), cos(next.angle - old.angle))
            guard abs(delta) < .pi / 3 else { return next }
            let translation = distance(old.eyeMid, next.eyeMid) / max(1, next.eyeDistance)
            let scaleChange = abs(next.eyeDistance - old.eyeDistance) / max(1, next.eyeDistance)
            let depthRotation = max(abs(next.yaw - old.yaw), abs(next.pitch - old.pitch))
            let motion = max(depthRotation, max(translation, max(abs(delta) * 0.75, scaleChange * 2)))
            let amount = min(1, max(0.5, CGFloat(1 - exp(-max(dt, 0.001) / 0.045)) + motion))
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * amount }
            func point(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: mix(a.x, b.x), y: mix(a.y, b.y)) }
            let angle = old.angle + delta * amount
            let expressionAmount = min(1, max(amount, 0.65 + abs(next.mouthOpening - old.mouthOpening) * 3))
            return .init(eyeMid: point(old.eyeMid, next.eyeMid), eyeDistance: mix(old.eyeDistance, next.eyeDistance),
                         angle: angle, up: CGVector(dx: -sin(angle), dy: cos(angle)),
                         faceWidth: mix(old.faceWidth, next.faceWidth), faceHeight: mix(old.faceHeight, next.faceHeight),
                         noseTip: point(old.noseTip, next.noseTip), mouth: point(old.mouth, next.mouth),
                         mouthOpening: old.mouthOpening + (next.mouthOpening - old.mouthOpening) * expressionAmount,
                         yaw: mix(old.yaw, next.yaw), pitch: mix(old.pitch, next.pitch))
        }
        previous = result
        return result
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
