import Foundation

/// Whole leading command tokens only; transport and legacy aliases stay compatible.
enum WhisperKnotCommand {
    static func prompt(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = trimmed.split(whereSeparator: { $0.isWhitespace }).first,
              ["/knot", "/jasper", "/ember"].contains(token.lowercased()) else { return nil }
        return String(trimmed.dropFirst(token.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
