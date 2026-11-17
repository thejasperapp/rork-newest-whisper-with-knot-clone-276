import Foundation

/// The wave EFFECTS catalog — CapCut's "Effects" tab, Whisper's way. These are
/// not color looks (those are `SnapFilter`); they are the fun, animated
/// treatments: shakes, glitches, VHS, mirrors, kaleidoscopes, comic ink,
/// light leaks, sparkles — plus an AI family that reads the person in the
/// frame with on-device Vision and paints around them. One effect at a time,
/// with a strength dial, a speed dial for the animated ones, and a choice of
/// whole wave or a single clip. Rendered identically in the live preview, the
/// cover picker and the final encode by `WhisperWaveFXRenderer`.
nonisolated enum WhisperWaveFX: String, CaseIterable, Codable, Sendable, Identifiable {
    // Camera / lens treatments, independent of color grading.
    case slowPush, handheld, zoomRush, tiltFocus
    // Motion
    case shake, zoomPulse, wobble
    // Retro
    case vhs, oldFilm, glitch, chromatic
    // Distort
    case fisheye, mirror, kaleido, pixelate, triple, quad
    // Art
    case comic, halftone, duotone, popArt, sketch, negative, thermal, xray
    // Light
    case flash, lightLeak, dreamy, softFocus, neon, sparkles, bokeh, rainbow
    // AI — person segmentation
    case neonOutline, aura, spotlight, echo, popOut

    var id: String { rawValue }

    var category: WhisperWaveFXCategory {
        switch self {
        case .slowPush, .handheld, .zoomRush, .tiltFocus: return .camera
        case .shake, .zoomPulse, .wobble: return .motion
        case .vhs, .oldFilm, .glitch, .chromatic: return .retro
        case .fisheye, .mirror, .kaleido, .pixelate, .triple, .quad: return .distort
        case .comic, .halftone, .duotone, .popArt, .sketch, .negative, .thermal, .xray: return .art
        case .flash, .lightLeak, .dreamy, .softFocus, .neon, .sparkles, .bokeh, .rainbow: return .light
        case .neonOutline, .aura, .spotlight, .echo, .popOut: return .ai
        }
    }

    var name: String {
        switch self {
        case .slowPush: return "Slow push"
        case .handheld: return "Handheld"
        case .zoomRush: return "Zoom rush"
        case .tiltFocus: return "Tilt focus"
        case .shake: return "Shake"
        case .zoomPulse: return "Pulse"
        case .wobble: return "Wobble"
        case .vhs: return "VHS"
        case .oldFilm: return "Old film"
        case .glitch: return "Glitch"
        case .chromatic: return "Chroma"
        case .fisheye: return "Fisheye"
        case .mirror: return "Mirror"
        case .kaleido: return "Kaleido"
        case .pixelate: return "Pixels"
        case .triple: return "Triple"
        case .quad: return "Quad"
        case .comic: return "Comic"
        case .halftone: return "Halftone"
        case .duotone: return "Duotone"
        case .popArt: return "Pop art"
        case .sketch: return "Sketch"
        case .negative: return "Negative"
        case .thermal: return "Thermal"
        case .xray: return "X-ray"
        case .flash: return "Flash"
        case .lightLeak: return "Light leak"
        case .dreamy: return "Dreamy"
        case .softFocus: return "Soft focus"
        case .neon: return "Neon"
        case .sparkles: return "Sparkles"
        case .bokeh: return "Bokeh"
        case .rainbow: return "Rainbow"
        case .neonOutline: return "Outline"
        case .aura: return "Aura"
        case .spotlight: return "Spotlight"
        case .echo: return "Echo"
        case .popOut: return "Pop out"
        }
    }

    /// SF Symbol for the tile badge.
    var systemImage: String {
        switch self {
        case .slowPush: return "plus.magnifyingglass"
        case .handheld: return "camera"
        case .zoomRush: return "arrow.up.left.and.arrow.down.right"
        case .tiltFocus: return "camera.aperture"
        case .shake: return "waveform.path"
        case .zoomPulse: return "heart.circle"
        case .wobble: return "water.waves"
        case .vhs: return "tv"
        case .oldFilm: return "film"
        case .glitch: return "bolt.horizontal"
        case .chromatic: return "circle.hexagongrid"
        case .fisheye: return "circle.dashed"
        case .mirror: return "rectangle.split.2x1"
        case .kaleido: return "hexagon"
        case .pixelate: return "square.grid.3x3"
        case .triple: return "rectangle.split.1x2"
        case .quad: return "square.grid.2x2"
        case .comic: return "pencil.and.outline"
        case .halftone: return "circle.grid.3x3"
        case .duotone: return "circle.lefthalf.filled"
        case .popArt: return "paintpalette"
        case .sketch: return "scribble"
        case .negative: return "circle.righthalf.filled"
        case .thermal: return "thermometer.medium"
        case .xray: return "xmark.circle"
        case .flash: return "bolt.fill"
        case .lightLeak: return "sun.haze"
        case .dreamy: return "cloud.fill"
        case .softFocus: return "camera.aperture"
        case .neon: return "lightbulb.max"
        case .sparkles: return "sparkles"
        case .bokeh: return "circle.circle"
        case .rainbow: return "rainbow"
        case .neonOutline: return "person.crop.rectangle"
        case .aura: return "person.and.background.dotted"
        case .spotlight: return "lamp.desk"
        case .echo: return "person.2"
        case .popOut: return "person.fill.viewfinder"
        }
    }

    /// True when the look changes over time and a speed dial makes sense.
    var isAnimated: Bool {
        switch self {
        case .slowPush, .handheld, .zoomRush, .shake, .zoomPulse, .wobble, .vhs, .oldFilm, .glitch, .kaleido, .flash, .lightLeak, .sparkles, .bokeh, .rainbow, .echo, .neonOutline: return true
        default: return false
        }
    }

    /// Effects that read the person in the frame with on-device Vision.
    var usesPersonSegmentation: Bool { category == .ai }

    /// Layout effects (mirror, triple, quad) have no strength to dial.
    var usesIntensity: Bool {
        switch self {
        case .mirror, .triple, .quad: return false
        default: return true
        }
    }

    /// What the strength dial changes, in one word, for the panel caption.
    var intensityLabel: String {
        switch self {
        case .kaleido: return "Segments"
        case .pixelate: return "Pixel size"
        case .halftone: return "Dot size"
        case .shake, .zoomPulse, .wobble: return "Amount"
        default: return "Strength"
        }
    }

    /// Brief flashes are a photosensitivity concern; the picker labels them.
    var flashes: Bool { self == .flash || self == .glitch }
}

/// Picker families — one tab each in the Effects tool.
nonisolated enum WhisperWaveFXCategory: String, CaseIterable, Sendable, Identifiable {
    case camera, motion, retro, distort, art, light, ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .motion: return "Motion"
        case .retro: return "Retro"
        case .distort: return "Distort"
        case .art: return "Art"
        case .light: return "Light"
        case .ai: return "AI"
        }
    }

    var effects: [WhisperWaveFX] { WhisperWaveFX.allCases.filter { $0.category == self } }
}

/// The chosen effect and its dials. `clipID` nil applies to the whole wave;
/// a clip ID limits it to that clip's stretch of the timeline (resolved when
/// the composition is built, so trims and speed changes keep it aligned).
nonisolated struct WhisperWaveFXSetting: Codable, Equatable, Sendable {
    var kind: WhisperWaveFX
    /// 0 … 1 strength.
    var intensity: Double = 0.7
    /// 0.5 … 2 animation rate for `isAnimated` effects.
    var speed: Double = 1
    var clipID: UUID? = nil

    init(kind: WhisperWaveFX, intensity: Double = 0.7, speed: Double = 1, clipID: UUID? = nil) {
        self.kind = kind
        self.intensity = intensity
        self.speed = speed
        self.clipID = clipID
    }

    var clampedIntensity: Double { min(1, max(0, intensity.isFinite ? intensity : 0.7)) }
    var clampedSpeed: Double { min(2, max(0.5, speed.isFinite ? speed : 1)) }
}

/// Preview renders trade a little blur radius and segmentation accuracy for
/// a smooth 30 fps; the final encode and cover use full quality.
nonisolated enum WhisperWaveRenderQuality: Sendable {
    case preview, final
}
