import Foundation

/// Original on-device camera presets; stable IDs travel with each take into drafts and export.
nonisolated enum WhisperWaveCameraEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, cloneWall, fisheye, sunnies, halftone, glow, stardust, vintage, mono
    case bigEyes, bigSmile, tinyNose, halo, puppy, bunny, kaleido, prism, pop, mirror, quad

    // Retain legacy IDs for stored recipes, but never offer accessory effects.
    static var available: [Self] { allCases.filter { !$0.isRetiredAccessory } }
    var isRetiredAccessory: Bool { self == .puppy || self == .bunny || self == .sunnies || self == .halo }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let effect = Self(rawValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown camera effect"))
        }
        self = effect.isRetiredAccessory ? .none : effect
    }

    var id: String { rawValue }
    var name: String {
        switch self {
        case .none: "No effect"
        case .cloneWall: "Clone crowd"
        case .fisheye: "Fisheye"
        case .sunnies: "Sunnies"
        case .halftone: "Dot matrix"
        case .glow: "Glow"
        case .stardust: "Stardust"
        case .vintage: "Vintage film"
        case .mono: "Silver"
        case .bigEyes: "Big eyes"
        case .bigSmile: "Big smile"
        case .tinyNose: "Tiny nose"
        case .halo: "Halo"
        case .puppy: "Puppy"
        case .bunny: "Bunny"
        case .kaleido: "Kaleidoscope"
        case .prism: "Prism"
        case .pop: "Pop art"
        case .mirror: "Mirror"
        case .quad: "Four of me"
        }
    }
    var interactionHint: String? {
        switch self {
        case .puppy: "3D · open your mouth to bring Puppy to life"
        case .bunny: "3D · tilt your head gently"
        case .sunnies: "3D · turn your head to catch the light"
        case .halo: "3D · a golden orbit that follows you"
        default: nil
        }
    }
    var category: String {
        if faceKind != .none { return "Face" }
        switch self {
        case .glow, .stardust, .vintage, .mono: return "Looks"
        default: return "Creative"
        }
    }
    var symbol: String {
        if faceKind != .none { return faceKind.symbol }
        switch self {
        case .none: return "circle.slash"
        case .cloneWall: return "person.3.sequence.fill"
        case .glow: return "sun.haze.fill"
        case .stardust: return "sparkles"
        case .mono: return "circle.lefthalf.filled"
        default: return fx?.kind.systemImage ?? "camera.filters"
        }
    }
    var faceKind: WhisperWaveFaceSetting.Kind {
        switch self {
        case .sunnies: .none
        case .bigEyes: .bigEyes
        case .bigSmile: .bigMouth
        case .tinyNose: .tinyNose
        case .halo, .puppy, .bunny: .none
        default: .none
        }
    }
    var fx: WhisperWaveFXSetting? {
        switch self {
        case .fisheye: .init(kind: .fisheye, intensity: 0.85)
        case .halftone: .init(kind: .halftone, intensity: 0.4)
        case .glow: .init(kind: .dreamy, intensity: 0.6)
        case .stardust: .init(kind: .sparkles, intensity: 0.8)
        case .vintage: .init(kind: .oldFilm, intensity: 0.55)
        case .kaleido: .init(kind: .kaleido, intensity: 0.35)
        case .prism: .init(kind: .chromatic, intensity: 0.8)
        case .pop: .init(kind: .popArt, intensity: 0.9)
        case .mirror: .init(kind: .mirror)
        case .quad: .init(kind: .quad)
        default: nil
        }
    }
}
