import SwiftUI

/// Public teal-seal chip awarded to users whose safety reports moderators have
/// confirmed as helpful. Auto-derived from `profiles.helpful_report_count` once
/// a user crosses the threshold — no manual handout.
///
/// Goal: reward the people quietly protecting the community so other users
/// have a visible signal that "this person reports stuff that turns out to be
/// real," and so trolls think twice before targeting them.
struct WhisperGuardianBadge: View {
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: [
                Color(red: 0.32, green: 0.80, blue: 0.78),
                Color(red: 0.14, green: 0.55, blue: 0.62)
            ],
            shadowColor: Color(red: 0.14, green: 0.55, blue: 0.62),
            size: size,
            accessibilityLabel: "Community Guardian — verified helpful reports"
        ) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: size * 0.5, weight: .black))
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperGuardianBadge(size: 12)
        WhisperGuardianBadge(size: 16)
        WhisperGuardianBadge(size: 22)
    }
    .padding()
}
