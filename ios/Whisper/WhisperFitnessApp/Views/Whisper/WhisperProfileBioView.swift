import SwiftUI

struct WhisperProfileBioView: View {
    let text: String
    let category: String
    var interests: [String] = []
    @Environment(\.colorScheme) private var colorScheme

    /// Display-only cleanup keeps authored text and URL fragments intact in storage.
    nonisolated static func displayBio(_ text: String) -> String {
        text.replacingOccurrences(of: #"(^|\s)#+(?=[\p{L}\p{N}_])"#, with: "$1", options: .regularExpression)
    }

    var body: some View {
        let range = text.range(of: #"https?://\S+|www\.\S+"#, options: .regularExpression)
        let rawLink = range.map { String(text[$0]) }
        let bio = range.map { text.replacingCharacters(in: $0, with: "").trimmingCharacters(in: .whitespacesAndNewlines) } ?? text
        VStack(spacing: 8) {
            if !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(category.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !bio.isEmpty {
                Text(Self.displayBio(bio)).font(.subheadline).foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let rawLink, let url = URL(string: rawLink.lowercased().hasPrefix("www.") ? "https://" + rawLink : rawLink) {
                Link(destination: url) {
                    Label(rawLink.replacingOccurrences(of: #"^https?://(www\.)?|^www\."#, with: "", options: .regularExpression), systemImage: "link")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
