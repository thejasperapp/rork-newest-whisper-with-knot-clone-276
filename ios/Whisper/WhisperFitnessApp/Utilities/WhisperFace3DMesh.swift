import Foundation
import simd

/// Original parametric accessory meshes. Units are neutral inter-eye distances;
/// anchors and expression groups are evaluated by the same shader on every surface.
nonisolated struct WhisperFace3DMesh {
    struct Vertex {
        var position: SIMD4<Float> // xyz, anchor (eyes / nose / mouth)
        var normal: SIMD4<Float> // xyz, expression group
        var color: SIMD4<Float>
        var surface: SIMD4<Float> // roughness, metallic, emission, velvet
    }
    var vertices: [Vertex] = []
    var indices: [UInt32] = []
    var occlusionIndexCount: Int = 0

    static func make(_ effect: WhisperAREffect, includesPortrait: Bool = false) -> Self {
        var mesh = Self()
        // A conservative head proxy, not a measured face scan. Writes depth only.
        mesh.ellipsoid(center: [0, -0.30, -0.72], radius: [0.94, 1.30, 0.73], color: [0, 0, 0, 1])
        mesh.occlusionIndexCount = mesh.indices.count
        if includesPortrait { mesh.portrait() }
        switch effect {
        case .puppy, .bunny: mesh.animal(isBunny: effect == .bunny)
        case .sunnies: mesh.sunglasses()
        case .halo: mesh.halo()
        default: break
        }
        return mesh
    }

    /// A neutral porcelain display bust only used by the catalog, never on camera.
    private mutating func portrait() {
        let porcelain: SIMD4<Float> = [0.82, 0.84, 0.82, 1]
        let satin: SIMD4<Float> = [0.38, 0.12, 0, 0]
        ellipsoid(center: [0, -0.30, -0.72], radius: [0.943, 1.303, 0.733], color: porcelain, material: satin)
        ellipsoid(center: [0, -1.64, -0.65], radius: [0.34, 0.56, 0.33], color: porcelain, material: satin)
        ellipsoid(center: [0, -2.37, -0.75], radius: [1.48, 0.71, 0.64], color: porcelain, material: satin)
        ellipsoid(center: [0, -0.48, 0.01], radius: [0.105, 0.18, 0.13], color: porcelain, material: satin)
        for side in [Float(-1), Float(1)] {
            ellipsoid(center: [side * 0.48, 0, -0.07], radius: [0.105, 0.064, 0.045], color: [0.15, 0.18, 0.18, 1], material: [0.18, 0.1, 0, 0])
        }
        ellipsoid(center: [0, -1.0, -0.08], radius: [0.18, 0.10, 0.03], color: [0.26, 0.20, 0.19, 1], material: satin)
    }

    private mutating func animal(isBunny: Bool) {
        let fur: SIMD4<Float> = isBunny ? [0.97, 0.94, 0.89, 1] : [0.57, 0.31, 0.15, 1]
        let inner: SIMD4<Float> = isBunny ? [0.93, 0.53, 0.62, 1] : [0.79, 0.49, 0.32, 1]
        for side in [Float(-1), Float(1)] {
            let group: Float = side < 0 ? 1 : 2
            surface(rows: 44, columns: 36, color: fur, material: [0.87, 0, 0, 1], motion: group) { t, v in
                Self.earPoint(t, v * .pi * 2, side: side, isBunny: isBunny)
            }
            // Separate padded inner-ear surface, inset from the rolled outer edge.
            surface(rows: 32, columns: 18, color: inner, material: [0.72, 0, 0, 0.35], motion: group, tint: { t, v in
                let edge = pow(abs(v * 2 - 1), 4) * 0.18 + pow(abs(t * 2 - 1), 6) * 0.12
                return inner * (1 - edge) + fur * edge
            }) { t, v in
                let height = 0.13 + t * 0.73
                let arc = (v * 2 - 1) * 0.86 * pow(max(0, sin(t * .pi)), 0.35)
                var point = Self.earPoint(height, arc, side: side, isBunny: isBunny)
                point.z += 0.006 + 0.018 * sin(t * .pi) * cos(arc)
                return point
            }
            if !isBunny {
                ellipsoid(center: [side * 0.85, 1.03, 0.05], radius: [0.25, 0.19, 0.18], color: fur, material: [0.92, 0, 0, 1], motion: group)
            }
            let muzzle: SIMD4<Float> = isBunny ? [0.98, 0.96, 0.92, 1] : [0.91, 0.76, 0.56, 1]
            ellipsoid(center: [side * 0.23, -0.13, 0.04], radius: [0.32, 0.22, 0.20], color: muzzle, material: [0.8, 0, 0, 1], anchor: 1)
            for i in 0..<3 {
                let y = Float(i - 1) * 0.075 - 0.10
                ellipsoid(center: [side * (0.24 + Float(i % 2) * 0.07), y, 0.225], radius: [0.018, 0.018, 0.012], color: [0.22, 0.13, 0.10, 1], anchor: 1)
                if isBunny {
                    tube(steps: 16, sides: 6, radius: 0.009, color: [0.95, 0.92, 0.88, 1], material: [0.48, 0, 0, 0], anchor: 1) { t in
                        [side * (0.27 + t * 0.77), y + Float(i - 1) * t * 0.14 + 0.04 * sin(.pi * t), 0.15 - 0.10 * t]
                    }
                }
            }
        }
        let nose: SIMD4<Float> = isBunny ? [0.95, 0.48, 0.59, 1] : [0.065, 0.043, 0.043, 1]
        // Rounded triangular nose, with a real convex surface and wet highlight.
        surface(rows: 24, columns: 36, color: nose, material: [0.18, 0.08, 0, 0], anchor: 1) { u, v in
            let latitude = u * .pi
            let longitude = v * .pi * 2
            let ny = cos(latitude)
            let width: Float = (isBunny ? 0.22 : 0.28) * (0.72 + 0.28 * ny)
            return [width * sin(latitude) * cos(longitude), 0.015 + ny * 0.16, 0.17 + 0.18 * sin(latitude) * sin(longitude)]
        }
        if !isBunny {
            ellipsoid(center: [0, -0.34, 0.10], radius: [0.22, 0.39, 0.075], color: [0.98, 0.37, 0.48, 1], material: [0.26, 0, 0, 0], anchor: 2, motion: 3)
            tube(steps: 18, sides: 6, radius: 0.011, color: [0.66, 0.16, 0.25, 1], anchor: 2, motion: 3) { t in
                [0, -0.06 - t * 0.52, 0.18 - 0.03 * t * t]
            }
        }
    }

    private mutating func sunglasses() {
        let acetate: SIMD4<Float> = [0.19, 0.10, 0.065, 1]
        let gold: SIMD4<Float> = [0.87, 0.66, 0.31, 1]
        for side in [Float(-1), Float(1)] {
            let center: Float = side * 0.56
            tube(steps: 72, sides: 12, radius: 0.066, color: acetate, material: [0.17, 0.18, 0, -1]) { t in
                let a = t * .pi * 2
                return [center + 0.47 * Self.signedPower(cos(a), 0.52), 0.02 + 0.32 * Self.signedPower(sin(a), 0.60), 0.29 - 0.05 * abs(cos(a))]
            }
            // Closed, subtly curved smoked lenses rather than flat image decals.
            surface(rows: 20, columns: 48, color: [0.095, 0.22, 0.23, 1], material: [0.12, 0.72, 0, -2]) { u, v in
                let a = v * .pi * 2
                let r = sin(u * .pi)
                return [center + 0.421 * r * Self.signedPower(cos(a), 0.52), 0.02 + 0.278 * r * Self.signedPower(sin(a), 0.60), 0.25 + 0.045 * cos(u * .pi)]
            }
            tube(steps: 24, sides: 10, radius: 0.042, color: acetate, material: [0.22, 0.1, 0, -1]) { t in
                [side * (1.03 + 0.07 * sin(t * .pi)), 0.13 - 0.10 * t * t, 0.24 - 1.18 * t]
            }
            ellipsoid(center: [side * 0.98, 0.16, 0.30], radius: [0.075, 0.023, 0.03], color: gold, material: [0.2, 0.9, 0, 0])
        }
        tube(steps: 16, sides: 10, radius: 0.032, color: gold, material: [0.22, 0.85, 0, 0]) { t in
            [-0.12 + 0.24 * t, 0.02 + 0.08 * sin(t * .pi), 0.30 + 0.02 * sin(t * .pi)]
        }
    }

    private mutating func halo() {
        tube(steps: 112, sides: 16, radius: 0.078, color: [1, 0.77, 0.26, 1], material: [0.2, 0.82, 0.3, 0]) { t in
            let a = t * .pi * 2
            return [1.18 * cos(a), 1.65 + 0.20 * sin(a), -0.28 + 0.73 * sin(a)]
        }
        tube(steps: 80, sides: 8, radius: 0.016, color: [1, 0.94, 0.62, 1], material: [0.18, 0.6, 0.55, 0]) { t in
            let a = t * .pi * 2
            return [1.18 * cos(a), 1.69 + 0.20 * sin(a), -0.28 + 0.73 * sin(a)]
        }
        for i in 0..<12 {
            let angle = Float(i) * .pi / 6
            ellipsoid(center: [1.18 * cos(angle), 1.65 + 0.20 * sin(angle), -0.28 + 0.73 * sin(angle)], radius: [0.038, 0.095, 0.038], color: [1, 0.94, 0.70, 1], material: [0.16, 0.75, 0.35, 0])
        }
        for i in 0..<5 {
            // Each star is a beveled volume, animated around the head in the shader.
            surface(rows: 12, columns: 40, color: [1, 0.86, 0.43, 1], material: [0.22, 0.65, 0.55, 0], motion: Float(4 + i)) { u, v in
                let a = v * .pi * 2
                let radius = (0.075 + 0.045 * pow(0.5 + 0.5 * cos(5 * a), 2)) * sin(u * .pi)
                return [radius * cos(a), radius * sin(a), 0.035 * cos(u * .pi)]
            }
        }
    }

    private static func earPoint(_ t: Float, _ angle: Float, side: Float, isBunny: Bool) -> SIMD3<Float> {
        let fullness = pow(max(0.001, sin(.pi * t)), isBunny ? 0.68 : 0.48)
        let width = (isBunny ? 0.28 : 0.39) * fullness + 0.004
        let thickness = (isBunny ? 0.13 : 0.18) * fullness + 0.004
        let fold = pow(max(0, (t - 0.62) / 0.38), 2)
        let x = side * (isBunny ? 0.65 + 0.29 * t + 0.11 * fold : 0.93 + 0.36 * sin(t * .pi * 0.83))
        let y: Float = isBunny ? 1.02 + 1.64 * t - (side > 0 ? 0.28 : 0.05) * fold : 1.18 - 1.37 * t
        let z: Float = isBunny ? -0.13 + 0.12 * sin(.pi * t) + (side > 0 ? 0.42 : 0.05) * fold : -0.26 + 0.40 * sin(.pi * t) + 0.23 * t
        return [x + width * sin(angle), y, z + thickness * cos(angle)]
    }

    private static func signedPower(_ value: Float, _ power: Float) -> Float {
        (value < 0 ? -1 : 1) * pow(abs(value), power)
    }

    private mutating func ellipsoid(center: SIMD3<Float>, radius: SIMD3<Float>, color: SIMD4<Float>, material: SIMD4<Float> = [0.5, 0, 0, 0], anchor: Float = 0, motion: Float = 0) {
        surface(rows: 20, columns: 32, color: color, material: material, anchor: anchor, motion: motion) { u, v in
            let a = u * .pi, b = v * .pi * 2
            return center + radius * SIMD3<Float>(sin(a) * cos(b), cos(a), sin(a) * sin(b))
        }
    }

    private mutating func tube(steps: Int, sides: Int, radius: Float, color: SIMD4<Float>, material: SIMD4<Float> = [0.5, 0, 0, 0], anchor: Float = 0, motion: Float = 0, path: (Float) -> SIMD3<Float>) {
        surface(rows: steps, columns: sides, color: color, material: material, anchor: anchor, motion: motion) { u, v in
            let tangent = simd_normalize(path(min(1, u + 0.001)) - path(max(0, u - 0.001)))
            let reference: SIMD3<Float> = abs(tangent.z) > 0.9 ? [0, 1, 0] : [0, 0, 1]
            let normal = simd_normalize(simd_cross(tangent, reference))
            let binormal = simd_cross(tangent, normal)
            let angle = v * .pi * 2
            return path(u) + radius * (normal * cos(angle) + binormal * sin(angle))
        }
    }

    private mutating func surface(rows: Int, columns: Int, color: SIMD4<Float>, material: SIMD4<Float>, anchor: Float = 0, motion: Float = 0, tint: ((Float, Float) -> SIMD4<Float>)? = nil, position: (Float, Float) -> SIMD3<Float>) {
        let start = UInt32(vertices.count)
        for row in 0...rows {
            for column in 0...columns {
                let u = Float(row) / Float(rows), v = Float(column) / Float(columns)
                let p = position(u, v)
                // Evaluate just inside collapsed poles so their normals remain finite.
                let normalU = min(0.999, max(0.001, u))
                let du = position(min(1, normalU + 0.0005), v) - position(max(0, normalU - 0.0005), v)
                let dv = position(normalU, v + 0.0005) - position(normalU, v - 0.0005)
                let cross = simd_cross(du, dv)
                let n: SIMD3<Float> = simd_length_squared(cross) > 1e-16 ? simd_normalize(cross) : [0, 0, 1]
                vertices.append(Vertex(position: SIMD4(p, anchor), normal: SIMD4(n, motion), color: tint?(u, v) ?? color, surface: material))
            }
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let a = start + UInt32(row * (columns + 1) + column)
                let b = a + UInt32(columns + 1)
                indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
            }
        }
    }
}
