import SwiftUI

/// Compact workout preview rendered inline on a feed post when the post's
/// caption carries a `WhisperWorkoutEmbed` payload. One quiet row — the
/// author's avatar, kicker, session title, a single stat line, and a
/// trailing photo or icon disc — so the feed stays light.
///
/// Tapping anywhere opens `WhisperWorkoutPostDetailSheet`: a mid-screen
/// popup (expandable to full height) with the complete exercise list and
/// a "Save to your Whisper" button, exactly like saving a coach's plan.
struct WhisperWorkoutPostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperWorkoutEmbed.Payload
    let username: String
    /// Signature accent inherited from the parent post — used only for the
    /// tiny kicker rule so the card stays calm.
    let accent: Color
    /// Optional photo paired with the workout — shown as a compact rounded
    /// thumbnail in the header; the detail sheet renders it full-bleed.
    var photoURL: URL? = nil

    @State private var presentDetail: Bool = false

    private var minutes: Int { max(0, payload.durationSeconds / 60) }
    private var isDark: Bool { colorScheme == .dark }

    /// Yoga / mobility sessions read naturally with a different noun.
    private var isYoga: Bool {
        let f = payload.focus.lowercased()
        return f.contains("yoga") || f.contains("flow") || f.contains("stretch") || f.contains("mobility")
    }

    private var subtitle: String {
        let noun = isYoga ? "yoga session" : "workout"
        if payload.focus.isEmpty || isYoga {
            return "Shared a \(noun)"
        }
        return "Shared a \(noun) · \(payload.focus)"
    }

    private var statLine: String {
        "\(minutes) min · \(payload.calories) kcal · \(payload.totalSets) sets"
    }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }

    var body: some View {
        Button {
            Haptics.tap()
            presentDetail = true
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(username: username, size: 36, ring: false)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 3, height: 11)
                            .clipShape(.capsule)
                        Text(subtitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                    Text(payload.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(statLine)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let url = photoURL {
                    thumbnail(url)
                } else {
                    Image(systemName: isYoga ? "figure.mind.and.body" : "dumbbell.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(width: 30, height: 30)
                        .background(ink.opacity(0.92), in: Circle())
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(hairline, lineWidth: 0.75)
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $presentDetail) {
            WhisperWorkoutPostDetailSheet(
                payload: payload,
                username: username,
                accent: accent,
                photoURL: photoURL
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
    }

    // MARK: - Sections

    /// Compact rounded photo thumbnail — the size anchor is a Color so the
    /// filled image can never overflow the card layout.
    private func thumbnail(_ url: URL) -> some View {
        Color(.secondarySystemBackground)
            .frame(width: 40, height: 40)
            .overlay {
                WhisperCachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    default:
                        Color(.secondarySystemBackground)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hairline, lineWidth: 0.5)
            }
    }

}

// MARK: - Detail sheet (mid-screen popup, expandable)

/// Full detail of a shared workout — photo hero when the post carries one,
/// stat ledger, complete exercise list, and a pinned "Save to your Whisper"
/// bar. Mirrors the save flow used when a coach sends a plan in chat.
struct WhisperWorkoutPostDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let payload: WhisperWorkoutEmbed.Payload
    let username: String
    let accent: Color
    var photoURL: URL? = nil

    @State private var saved: Bool = false

    private var alreadySaved: Bool {
        guard let data = AccountStorage.data(forKey: "workoutSessionHistory"),
              let decoded = try? JSONDecoder().decode([WorkoutSessionRecord].self, from: data),
              let payloadID = UUID(uuidString: payload.id) else { return false }
        return decoded.contains(where: { $0.id == payloadID })
    }

    private var minutes: Int { max(0, payload.durationSeconds / 60) }
    private var isDark: Bool { colorScheme == .dark }
    private var background: Color {
        isDark ? Color(red: 0.05, green: 0.05, blue: 0.06) : Color(red: 0.97, green: 0.97, blue: 0.96)
    }
    private var surface: Color {
        isDark ? Color(red: 0.10, green: 0.10, blue: 0.11) : .white
    }
    private var primaryText: Color {
        isDark ? .white : Color(red: 0.08, green: 0.08, blue: 0.10)
    }
    private var secondaryText: Color {
        isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.50)
    }
    private var hairline: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    private var kickerLine: String {
        payload.focus.isEmpty ? "WORKOUT SESSION" : "WORKOUT SESSION · \(payload.focus.uppercased())"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    sharedByRow
                        .padding(.horizontal, 16)
                    statsLedger
                        .padding(.horizontal, 16)
                    exerciseList
                        .padding(.horizontal, 16)
                    Color.clear.frame(height: 96)
                }
            }
            saveBar
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(photoURL != nil ? .white : primaryText)
                    .frame(width: 30, height: 30)
                    .background(
                        photoURL != nil ? Color.black.opacity(0.35) : primaryText.opacity(0.08),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.trailing, 14)
            .accessibilityLabel("Close")
        }
    }

    // MARK: Hero

    /// Photo posts get a full-bleed hero with the session identity set over
    /// a scrim; text-only sessions get a clean printed header block.
    @ViewBuilder
    private var hero: some View {
        if let url = photoURL {
            Color(.secondarySystemBackground)
                .frame(height: 250)
                .overlay(alignment: .top) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        default:
                            Color(.secondarySystemBackground)
                        }
                    }
                }
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.35),
                            .init(color: .black.opacity(0.30), location: 0.65),
                            .init(color: .black.opacity(0.82), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Rectangle()
                                .fill(accent)
                                .frame(width: 18, height: 2)
                                .clipShape(.capsule)
                            Text(kickerLine)
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1.8)
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                        }
                        Text(payload.displayName)
                            .font(.system(size: 25, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(16)
                    .allowsHitTesting(false)
                }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 18, height: 2)
                        .clipShape(.capsule)
                    Text(kickerLine)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.8)
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
                Text(payload.displayName)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 26)
        }
    }

    private var sharedByRow: some View {
        HStack(spacing: 10) {
            WhisperAvatar(username: username, size: 32, ring: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("@\(username)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(primaryText)
                Text("Shared this session")
                    .font(.caption2)
                    .foregroundStyle(secondaryText)
            }
            Spacer(minLength: 0)
            Text(payload.dateValue.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(surface, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hairline, lineWidth: 0.5)
        }
    }

    private var statsLedger: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(minutes)", unit: "min")
            ledgerDivider
            statColumn(value: "\(payload.calories)", unit: "kcal")
            ledgerDivider
            statColumn(value: "\(payload.totalSets)", unit: "sets")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(surface, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hairline, lineWidth: 0.5)
        }
    }

    private var ledgerDivider: some View {
        Rectangle()
            .fill(hairline)
            .frame(width: 0.5, height: 32)
    }

    private func statColumn(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(unit.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(secondaryText)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var exerciseList: some View {
        if !payload.exerciseNames.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Exercises")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(secondaryText)
                    Spacer()
                    Text("\(payload.exerciseNames.count) · \(payload.totalSets) sets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                }
                .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(payload.exerciseNames.enumerated()), id: \.offset) { idx, name in
                        HStack(spacing: 14) {
                            Text(String(format: "%02d", idx + 1))
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(accent)
                                .frame(width: 26, alignment: .leading)
                            Text(name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(primaryText)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        if idx < payload.exerciseNames.count - 1 {
                            Rectangle()
                                .fill(hairline)
                                .frame(height: 0.5)
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(surface, in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(hairline, lineWidth: 0.5)
                }
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, background],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 36)
            .allowsHitTesting(false)
            Button {
                let result = WhisperWorkoutImport.saveToWhisper(payload)
                if result != .failed {
                    withAnimation(.spring(response: 0.3)) { saved = true }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: (saved || alreadySaved) ? "checkmark" : "arrow.down.to.line")
                        .font(.subheadline.weight(.bold))
                    Text((saved || alreadySaved) ? "Saved to your Whisper" : "Save to your Whisper")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(isDark ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(primaryText, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saved || alreadySaved)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .background(background)
        }
    }
}

// MARK: - Beach / summer banner

/// Banner shown inline on a post when the caption talks about the beach,
/// summer, or vacation — same paper-card aesthetic as the workout banner,
/// with the Whisper beach-ball ghost as the signature graphic. Picks the
/// strongest matching keyword to label the banner ("Beach day", "Summer",
/// "Vacation", etc) so it reads naturally.
struct WhisperBeachBannerCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let caption: String
    let username: String
    let accent: Color

    private var isDark: Bool { colorScheme == .dark }
    private var primaryText: Color {
        isDark ? .white : Color(red: 0.08, green: 0.08, blue: 0.10)
    }
    private var secondaryText: Color {
        isDark ? Color.white.opacity(0.70) : Color.black.opacity(0.62)
    }
    private var mutedText: Color {
        isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.42)
    }
    private var borderColor: Color {
        isDark ? Color.white.opacity(0.18) : Color(red: 0.85, green: 0.85, blue: 0.86)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isDark { Color(red: 0.06, green: 0.06, blue: 0.07) } else { Color.white }
    }

    /// Pick the most specific matching label for the banner kicker.
    private var label: String {
        let c = caption.lowercased()
        if c.contains("vacation") || c.contains("vacay") { return "Vacation" }
        if c.contains("beach") { return "Beach day" }
        if c.contains("pool") { return "Pool day" }
        if c.contains("surf") { return "Surf session" }
        if c.contains("ocean") || c.contains("sea") { return "Ocean day" }
        if c.contains("summer") { return "Summer" }
        return "Summer"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("WhisperGhostBeachBall")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(2.0)
                    .foregroundStyle(mutedText)
                Text("Out there with @\(username)")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Rectangle()
                .fill(accent)
                .frame(width: 3, height: 44)
                .clipShape(.capsule)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(borderColor, lineWidth: isDark ? 1 : 0.75)
        }
        .shadow(color: Color.black.opacity(isDark ? 0.3 : 0.05), radius: 12, x: 0, y: 6)
    }
}

/// Caption-keyword sniff that decides whether a post deserves the beach /
/// summer banner. Returns false if the caption is empty or doesn't match
/// any sun/beach/vacation keyword.
enum WhisperBeachDetector {
    static let keywords: [String] = [
        "beach", "summer", "vacation", "vacay", "tropical",
        "poolside", "pool day", "by the pool", "sunny day",
        "ocean", "seaside", "surf", "surfing", "tan lines",
        "boardwalk", "shoreline", "sandy", "palm trees", "sunshine"
    ]

    static func matches(_ caption: String) -> Bool {
        let c = caption.lowercased()
        guard !c.isEmpty else { return false }
        for k in keywords {
            if c.contains(k) { return true }
        }
        return false
    }
}
