import Foundation

/// Face-local edits are attached to a source clip, independent of the color look and background.
nonisolated struct WhisperWaveFaceSetting: Codable, Equatable, Sendable {
    var kind: Kind = .none
    var amount: Double = 0.65
    var smoothing: Double = 0
    /// Kept for decoding older drafts; retired accessories normalize to none.
    /// Regular face adjustments, smoothing and source footage remain available.
    var renderingVersion: Int? = nil
    var uses3D: Bool { kind.accessory != nil }
    var accessoryOnly: Self { var copy = self; copy.smoothing = 0; return copy }

    static func current(_ kind: Kind) -> Self {
        .init(kind: kind.accessory == nil ? kind : .none, amount: kind.defaultAmount)
    }

    mutating func select(_ next: Kind) {
        if next != kind { amount = next.defaultAmount }
        kind = next.accessory == nil ? next : .none
        renderingVersion = nil
    }

    var isActive: Bool { kind != .none || smoothing > 0 }
    var clampedAmount: Double { min(1, max(0, amount.isFinite ? amount : 0)) }
    var clampedSmoothing: Double { min(1, max(0, smoothing.isFinite ? smoothing : 0)) }

    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case none, bigEyes, bigMouth, tinyNose, sunnies, halo, puppy, bunny
        static var available: [Self] { [.none, .bigEyes, .bigMouth, .tinyNose] }
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let kind = Self(rawValue: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown face setting"))
            }
            // Normalize only editable recipes; already-baked media stays intact.
            self = kind.accessory == nil ? kind : .none
        }
        var id: String { rawValue }
        var defaultAmount: Double { accessory == nil ? 0.35 : 1.0 }
        var title: String {
            switch self {
            case .none: return "None"
            case .bigEyes: return "Big eyes"
            case .bigMouth: return "Big smile"
            case .tinyNose: return "Tiny nose"
            case .sunnies: return "Sunnies"
            case .halo: return "Halo"
            case .puppy: return "Puppy"
            case .bunny: return "Bunny"
            }
        }
        var symbol: String {
            switch self {
            case .none: return "circle.slash"
            case .bigEyes: return "eyes"
            case .bigMouth: return "mouth"
            case .tinyNose: return "nose"
            case .sunnies: return "eyeglasses"
            case .halo: return "sparkles"
            case .puppy: return "dog"
            case .bunny: return "hare"
            }
        }
        var accessory: WhisperAREffect? {
            switch self {
            case .sunnies: return .sunnies
            case .halo: return .halo
            case .puppy: return .puppy
            case .bunny: return .bunny
            default: return nil
            }
        }
    }
}
