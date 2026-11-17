import WidgetKit
import SwiftUI
import AppIntents
import UIKit

// MARK: - Shared App Group access

private enum AppGroup {
    static let suite = "group.com.mydailywhisper.whisper"
    static var defaults: WhisperWidgetSnapshotDefaults? { WhisperWidgetSnapshotDefaults(suiteName: suite) }

    /// True only when the App Group entitlement is actually granted by iOS.
    /// `UserDefaults(suiteName:)` returns a non-nil instance even WITHOUT
    /// the entitlement (it silently creates a private store), so we must
    /// check the shared container URL — that's the only signal that the
    /// extension can actually see data the app wrote.
    static var isEntitled: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) != nil
    }
}

struct CompactThread: Codable, Hashable {
    let user: String
    let preview: String
    let when: Double
    let fromMe: Bool
    let unread: Bool
    var userID: String? = nil
    /// File name (leaf only) of the cached avatar inside the App Group's
    /// `widget-avatars/` directory.
    var avatar: String? = nil
    var owner: String? = nil
    var threadID: String? = nil
}

struct StoryAuthor: Codable, Hashable {
    let name: String
    var userID: String? = nil
    var avatar: String? = nil
}

/// One upcoming shared-calendar event, mirrored by the app AND refreshed
/// directly from Supabase by the widget itself.
struct CompactEvent: Codable, Hashable {
    let title: String
    /// Unix timestamp of the start time.
    let when: Double
    let type: String
    var host: String? = nil
    var link: Bool = false
}

/// One active coaching client (accepted relationship), for coach accounts.
struct CompactClient: Codable, Hashable {
    let name: String
    var userID: String? = nil
    var avatar: String? = nil
    /// Unix timestamp of when the relationship was accepted.
    var since: Double? = nil
}

/// Whisper's AI identity used to ride the legacy @ember DM account —
/// anywhere that username surfaces, the widget shows Jasper instead.
func jasperDisplayName(_ raw: String) -> String {
    raw.lowercased() == "ember" ? "jasper" : raw
}

private enum WidgetSnapshot {
    static func unreadDMCount() -> Int {
        AppGroup.defaults?.integer(forKey: "whisper_unread_dm_count") ?? 0
    }

    static func lastSender() -> String? {
        let s = AppGroup.defaults?.string(forKey: "whisper_last_sender")
        return (s?.isEmpty == false) ? s : nil
    }

    static func lastPreview() -> String? {
        let s = AppGroup.defaults?.string(forKey: "whisper_last_preview")
        return (s?.isEmpty == false) ? s : nil
    }

    static func lastDate() -> Date? {
        let t = AppGroup.defaults?.double(forKey: "whisper_last_date") ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func myThought() -> String? {
        let s = AppGroup.defaults?.string(forKey: "whisper_my_thought")
        return (s?.isEmpty == false) ? s : nil
    }

    static func followers() -> Int { AppGroup.defaults?.integer(forKey: "whisper_followers") ?? 0 }
    static func following() -> Int { AppGroup.defaults?.integer(forKey: "whisper_following") ?? 0 }
    static func activeStoryCount() -> Int { AppGroup.defaults?.integer(forKey: "whisper_active_story_count") ?? 0 }

    static func storyAuthorRows() -> [StoryAuthor] {
        guard let data = AppGroup.defaults?.data(forKey: "whisper_story_authors"),
              let decoded = try? JSONDecoder().decode([StoryAuthor].self, from: data) else { return [] }
        return decoded
    }

    static func topThreads() -> [CompactThread] {
        guard let data = AppGroup.defaults?.data(forKey: "whisper_top_threads"),
              let decoded = try? JSONDecoder().decode([CompactThread].self, from: data) else { return [] }
        return decoded
    }

    static func activityCount() -> Int { AppGroup.defaults?.integer(forKey: "whisper_activity_count") ?? 0 }
    static func activityPreview() -> String? {
        let s = AppGroup.defaults?.string(forKey: "whisper_activity_preview")
        return (s?.isEmpty == false) ? s : nil
    }

    static func calendarEvents() -> [CompactEvent] {
        guard let data = AppGroup.defaults?.data(forKey: "whisper_calendar_events"),
              let decoded = try? JSONDecoder().decode([CompactEvent].self, from: data) else { return [] }
        // Only future (or just-started) events, soonest first.
        let cutoff = Date().timeIntervalSince1970 - 30 * 60
        return decoded.filter { $0.when > cutoff }.sorted { $0.when < $1.when }
    }

    static func coachClients() -> [CompactClient] {
        guard let data = AppGroup.defaults?.data(forKey: "whisper_coach_clients"),
              let decoded = try? JSONDecoder().decode([CompactClient].self, from: data) else { return [] }
        return decoded
    }

    static func isCoach() -> Bool { AppGroup.defaults?.bool(forKey: "whisper_is_coach") ?? false }

    /// Diagnostic state used by the empty-state UI so TestFlight users
    /// can see *why* the widget is empty (App Group blocked vs. signed
    /// out vs. just no data yet).
    enum EmptyReason {
        case appGroupUnavailable
        case notSignedIn
        case noData
    }

    static func emptyReason() -> EmptyReason {
        // Authoritative entitlement check — `UserDefaults(suiteName:)` lies
        // when the entitlement is missing, so trust the container URL.
        guard AppGroup.isEntitled, let d = AppGroup.defaults else {
            return .appGroupUnavailable
        }
        let hasSession = (d.string(forKey: "whisper_session_access_token")?.isEmpty == false) &&
                         (d.string(forKey: "whisper_session_user_id")?.isEmpty == false)
        return hasSession ? .noData : .notSignedIn
    }
}

// MARK: - Theme — the Whisper brand system (ink · cream · ghost mint · heat)

private enum WidgetTheme {
    /// Brand ink — near-black warm brown.
    static let ink = Color(red: 0.129, green: 0.110, blue: 0.102)
    /// Brand cream paper.
    static let cream = Color(red: 0.984, green: 0.957, blue: 0.894)
    /// Ghost mint — Jasper's pale shell.
    static let mint = Color(red: 0.725, green: 0.953, blue: 0.863)
    /// Deep mint — the money/actions accent.
    static let deepMint = Color(red: 0.055, green: 0.624, blue: 0.463)
    /// Warm heat orange — the activity accent.
    static let heat = Color(red: 0.953, green: 0.565, blue: 0.341)

    /// Adaptive canvas: cream paper in light, warm ink in dark.
    static let bg = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.094, green: 0.082, blue: 0.075, alpha: 1)
            : UIColor(red: 0.984, green: 0.957, blue: 0.894, alpha: 1)
    })
    /// Adaptive ink: ink on cream, cream on ink.
    static let fg = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.984, green: 0.957, blue: 0.894, alpha: 1)
            : UIColor(red: 0.129, green: 0.110, blue: 0.102, alpha: 1)
    })
    static var dim: Color { fg.opacity(0.55) }
    static var stroke: Color { fg.opacity(0.14) }
    static var chip: Color { fg.opacity(0.08) }
}

/// The shared widget canvas — brand paper with a soft mint bloom in the
/// top-right corner and a whisper of deep mint rising from the bottom-left.
private struct WidgetCanvas: View {
    var body: some View {
        ZStack {
            WidgetTheme.bg
            RadialGradient(
                colors: [WidgetTheme.mint.opacity(0.5), .clear],
                center: .topTrailing,
                startRadius: 2,
                endRadius: 210
            )
            RadialGradient(
                colors: [WidgetTheme.deepMint.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 2,
                endRadius: 190
            )
        }
    }
}

// MARK: - The REAL Jasper Intelligence ghost

/// Jasper's expression vocabulary — the same moods the living in-app mascot
/// cycles through. Widgets render static snapshots, so each timeline entry
/// freezes ONE expression — and the timeline flips expressions through the
/// day (see `JasperMood`), so he never sits frozen in one face.
enum JasperExpression {
    case wide, happy, wink, sleepy, curious
}

/// Time-of-day mood — expression + prompt + head tilt. The Jasper widget's
/// timeline aligns entries to these boundaries so the ghost wakes up sleepy,
/// grins through the morning, winks at golden hour, and dozes off late.
enum JasperMood {
    static func of(_ date: Date) -> (expression: JasperExpression, prompt: String, tilt: Double) {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return (.sleepy, "Early one. What's first?", -2)
        case 9..<12: return (.happy, "Morning. What are we making?", -3)
        case 12..<17: return (.wide, "Ask anything.", 2)
        case 17..<21: return (.wink, "Golden hour. Post the thing.", -4)
        case 21..<24: return (.curious, "Night ideas hit different.", 3)
        default: return (.sleepy, "Whisper quietly — it's late.", -2)
        }
    }
    /// Hours where the mood flips — timeline entries align to these.
    static let boundaries: [Int] = [0, 5, 9, 12, 17, 21]
}

/// The canonical Jasper Intelligence mascot, exactly as the app renders him:
/// the production template silhouette (`WhisperEmberGhostBody`, 846×839)
/// tinted with the Original personality's mint gradient (#EDFFF5 → #C2FCE6 →
/// #94D1B8, the jasper-plan.md definitive values), the soft top-left sheen,
/// and the true eye rig placed at the template's exact eye rectangles —
/// now with the living mascot's expression vocabulary.
private struct JasperGhost: View {
    var size: CGFloat
    var tilt: Double = 0
    var expression: JasperExpression = .wide

    private static let srcW: CGFloat = 846
    private static let srcH: CGFloat = 839
    private static let leftEye = CGRect(x: 273, y: 192, width: 101, height: 159)
    private static let rightEye = CGRect(x: 463, y: 192, width: 100, height: 159)

    private static let soft = Color(red: 0.93, green: 1.00, blue: 0.96)
    private static let mid = Color(red: 0.76, green: 0.99, blue: 0.90)
    private static let deep = Color(red: 0.58, green: 0.82, blue: 0.72)

    private var height: CGFloat { size * Self.srcH / Self.srcW }
    private var scale: CGFloat { size / Self.srcW }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("WhisperEmberGhostBody")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [Self.soft, Self.mid, Self.deep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: height)
                .shadow(color: Self.deep.opacity(0.5), radius: size * 0.09, y: size * 0.03)
                .overlay {
                    Image("WhisperEmberGhostBody")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(
                            RadialGradient(
                                colors: [Color.white.opacity(0.32), .clear],
                                center: UnitPoint(x: 0.38, y: 0.20),
                                startRadius: 1,
                                endRadius: size * 0.62
                            )
                        )
                }

            eye(Self.leftEye)
            eye(Self.rightEye)
        }
        .frame(width: size, height: height)
        .rotationEffect(.degrees(tilt))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func eye(_ rect: CGRect) -> some View {
        eye(rect, isLeft: rect.minX < Self.srcW / 2)
    }

    @ViewBuilder
    private func eye(_ rect: CGRect, isLeft: Bool) -> some View {
        let w = rect.width * scale
        let h = rect.height * scale
        Group {
            switch expression {
            case .wide:
                Ellipse().fill(Color.black)
                    .frame(width: w, height: h)
            case .happy:
                JasperHappyEyeShape().fill(Color.black)
                    .frame(width: w, height: h)
            case .wink:
                if isLeft {
                    JasperHappyEyeShape().fill(Color.black)
                        .frame(width: w, height: h)
                } else {
                    // The closed eye — a soft lid line where the eye sits.
                    Capsule().fill(Color.black)
                        .frame(width: w * 1.05, height: max(2, h * 0.14))
                        .offset(y: h * 0.1)
                }
            case .sleepy:
                // Half-lidded — squashed low in the socket.
                Ellipse().fill(Color.black)
                    .frame(width: w, height: h * 0.42)
                    .offset(y: h * 0.2)
            case .curious:
                // Both eyes drift toward the content he's "reading".
                Ellipse().fill(Color.black)
                    .frame(width: w * 0.92, height: h * 0.9)
                    .offset(x: -w * 0.16, y: -h * 0.04)
            }
        }
        .position(x: rect.midX * scale, y: rect.midY * scale)
    }
}

/// The production happy-eye path — same curves as the app's living mascot.
private struct JasperHappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let kappa: CGFloat = 0.5522847498
        let bottomY = rect.minY + h * 0.86
        let smileApexY = rect.minY + h * 0.60
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                      control1: CGPoint(x: rect.midX + w * 0.5 * kappa, y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.midY - h * 0.5 * kappa))
        path.addCurve(to: CGPoint(x: rect.maxX, y: bottomY),
                      control1: CGPoint(x: rect.maxX, y: rect.midY + h * 0.16),
                      control2: CGPoint(x: rect.maxX, y: bottomY - h * 0.10))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: bottomY), control: CGPoint(x: rect.midX, y: smileApexY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                      control1: CGPoint(x: rect.minX, y: bottomY - h * 0.10),
                      control2: CGPoint(x: rect.minX, y: rect.midY + h * 0.16))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.midY - h * 0.5 * kappa),
                      control2: CGPoint(x: rect.midX - w * 0.5 * kappa, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Lock-screen–safe ghost glyph: the real template silhouette, tint-friendly.
private struct GhostGlyph: View {
    var size: CGFloat
    var body: some View {
        Image("WhisperEmberGhostBody")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size * 839 / 846)
            .foregroundStyle(.white)
    }
}

private extension Date {
    var shortRelative: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Shared little pieces

/// Brand kicker — a deep-mint dot + tracked label, the widget's "header".
private func kicker(_ text: String) -> some View {
    HStack(spacing: 6) {
        Circle().fill(WidgetTheme.deepMint).frame(width: 7, height: 7)
        Text(text)
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .tracking(2.2)
            .foregroundStyle(WidgetTheme.fg)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Mint count capsule — ink text on ghost mint, the brand's badge.
private func mintBadge(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(WidgetTheme.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(WidgetTheme.mint, in: Capsule())
}

// MARK: - Avatar disc (shared by DM rows + story rings + client rows)

@ViewBuilder
private func avatarDisc(userID: String?, fallbackLetter: String) -> some View {
    if let img = WhisperWidgetBackend.cachedAvatar(userID: userID) {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipShape(Circle())
    } else {
        ZStack {
            Circle().fill(WidgetTheme.mint.opacity(0.6))
            Text(fallbackLetter)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
        }
    }
}

// MARK: - App Intent for interactive refresh

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Whisper"
    static var description = IntentDescription("Pull the latest Whisper snapshot.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Deep link URLs

private enum WhisperLink {
    /// Opens the full-screen Jasper Intelligence chat (NOT the legacy DM).
    static let jasper = URL(string: "whisper://jasper")!
    static let imagine = URL(string: "whisper://imagine")!
    static let stories = URL(string: "whisper://stories")!
    static let activity = URL(string: "whisper://activity")!
    static let inbox = URL(string: "whisper://inbox")!
    static let thought = URL(string: "whisper://thought")!
    static let calendar = URL(string: "whisper://calendar")!
    static let coach = URL(string: "whisper://coach")!
    static func story(userID: String?, owner: String?) -> URL {
        var c = URLComponents()
        c.scheme = "whisper"; c.host = "stories"
        c.queryItems = [URLQueryItem(name: "uid", value: userID), URLQueryItem(name: "owner", value: owner)]
        return c.url ?? stories
    }
    static func dm(_ user: String, userID: String? = nil, owner: String? = nil, threadID: String? = nil) -> URL {
        if ["ember", "jasper"].contains((userID ?? user).lowercased()) { return jasper }
        var c = URLComponents()
        c.scheme = "whisper"
        c.host = "dm"
        c.path = "/" + user
        c.queryItems = [URLQueryItem(name: "uid", value: userID), URLQueryItem(name: "owner", value: owner ?? AppGroup.defaults?.string(forKey: "whisper_session_user_id"))]
        c.queryItems?.append(URLQueryItem(name: "thread", value: threadID))
        return c.url ?? inbox
    }
}

// =====================================================================
// MARK: - 1. Jasper Intelligence Widget
// =====================================================================

struct JasperEntry: TimelineEntry {
    let date: Date
    let unread: Int
    let activeStories: Int
    let relevance: TimelineEntryRelevance?
}

nonisolated struct JasperProvider: TimelineProvider {
    func placeholder(in _: Context) -> JasperEntry {
        JasperEntry(date: .now, unread: 0, activeStories: 0, relevance: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (JasperEntry) -> Void) {
        let snap = JasperEntry(date: .now, unread: 3, activeStories: 4, relevance: nil)
        completion(snap)
    }
    func getTimeline(in _: Context, completion: @escaping (Timeline<JasperEntry>) -> Void) {
        let unread = WidgetSnapshot.unreadDMCount()
        let stories = WidgetSnapshot.activeStoryCount()
        let score: Float = min(100, Float(unread * 10) + Float(stories * 3))
        // One entry NOW plus one at every upcoming mood boundary in the next
        // ~26h — widgets can't animate, but they CAN change: the ghost wakes
        // sleepy, grins through the morning, winks at golden hour.
        var dates: [Date] = [.now]
        let cal = Calendar.current
        for dayOffset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: .now) else { continue }
            for hour in JasperMood.boundaries {
                guard let moment = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                      moment > Date(),
                      moment < Date().addingTimeInterval(26 * 3600) else { continue }
                dates.append(moment)
            }
        }
        let entries = dates.sorted().map {
            JasperEntry(date: $0, unread: unread, activeStories: stories, relevance: .init(score: score))
        }
        let next = Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

struct JasperIntelligenceView: View {
    @Environment(\.widgetFamily) var family
    var entry: JasperEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                GhostGlyph(size: 26)
            }
            .widgetURL(WhisperLink.jasper)

        case .accessoryRectangular:
            HStack(spacing: 8) {
                GhostGlyph(size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jasper Intelligence").font(.headline)
                    Text("Tap to ask anything")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .widgetURL(WhisperLink.jasper)

        case .accessoryInline:
            Text("Jasper · ready")
                .widgetURL(WhisperLink.jasper)

        case .systemMedium:
            // The EXPANDED dock — prompt + lens capsules on the left, the
            // mascot peeking over his dark-glass analysis box on the right,
            // exactly the state the in-app pill morphs into.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    kicker("JASPER INTELLIGENCE")
                    Spacer(minLength: 0)
                    Text(mood.prompt)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(WidgetTheme.fg)
                    Spacer(minLength: 6)
                    HStack(spacing: 7) {
                        Link(destination: WhisperLink.jasper) {
                            capsuleTag("Chat", systemImage: "bubble.left.fill", filled: true)
                        }
                        Link(destination: WhisperLink.imagine) {
                            capsuleTag("Imagine", systemImage: "wand.and.stars", filled: false)
                        }
                        Spacer(minLength: 0)
                    }
                }
                analysisDock
                    .frame(width: 122)
            }
            .widgetURL(WhisperLink.jasper)

        default:
            // The COLLAPSED dock — the mint "Jasper's read" pill with the
            // mascot peeking over its top edge, pixel language identical to
            // the in-app auto-analysis capsule.
            VStack(spacing: 0) {
                HStack {
                    kicker("JASPER")
                    Spacer(minLength: 0)
                    if entry.unread > 0 {
                        mintBadge("\(entry.unread)")
                    }
                }
                Spacer(minLength: 0)
                Text(mood.prompt)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(WidgetTheme.fg)
                Spacer(minLength: 0)
                dockPill
            }
            .widgetURL(WhisperLink.jasper)
        }
    }

    private var mood: (expression: JasperExpression, prompt: String, tilt: Double) {
        JasperMood.of(entry.date)
    }

    /// The collapsed auto-analysis pill — mascot peeking over the mint
    /// capsule, chevron and all.
    private var dockPill: some View {
        VStack(spacing: 0) {
            JasperGhost(size: 54, tilt: mood.tilt, expression: mood.expression)
                .offset(y: 15)
                .zIndex(0)
            HStack(spacing: 5) {
                Text("Jasper's read")
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(WidgetTheme.ink.opacity(0.6))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(WidgetTheme.mint, in: Capsule())
            .overlay(Capsule().strokeBorder(WidgetTheme.deepMint.opacity(0.35), lineWidth: 1))
            .shadow(color: WidgetTheme.deepMint.opacity(0.3), radius: 7, y: 3)
            .zIndex(1)
        }
    }

    /// The expanded dock — the mascot peeking over the dark-glass analysis
    /// box (charcoal, mint hairline, inner mint bloom) with the pill label
    /// and a scripted thinking line inside.
    private var analysisDock: some View {
        VStack(spacing: 0) {
            JasperGhost(size: 62, tilt: mood.tilt, expression: mood.expression)
                .offset(y: 17)
                .zIndex(0)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.096, blue: 0.088))
                RadialGradient(
                    colors: [WidgetTheme.mint.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 1,
                    endRadius: 92
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text("JASPER'S READ")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.62))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    Text("Thinking with you.")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .italic()
                        .foregroundStyle(WidgetTheme.mint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 9)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(WidgetTheme.mint.opacity(0.32), lineWidth: 1)
            )
            .frame(height: 52)
            .zIndex(1)
        }
    }

    private func capsuleTag(_ text: String, systemImage: String, filled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption2.weight(.bold))
            Text(text).font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(filled ? WidgetTheme.bg : WidgetTheme.fg)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if filled {
                Capsule().fill(WidgetTheme.fg)
            } else {
                Capsule().strokeBorder(WidgetTheme.stroke, lineWidth: 1.5)
            }
        }
    }
}

struct JasperIntelligenceWidget: Widget {
    /// Legacy stable identifier — changing a widget's kind silently removes
    /// it from users' Home Screens, so the registry key stays put while the
    /// identity is fully Jasper Intelligence.
    let kind = "EmberPocketWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JasperProvider()) { entry in
            JasperIntelligenceView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Jasper Intelligence")
        .description("One tap to Jasper's screen — ask anything.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// =====================================================================
// MARK: - 2. DM Inbox Widget
// =====================================================================

struct DMEntry: TimelineEntry {
    let date: Date
    let unread: Int
    let threads: [CompactThread]
    let relevance: TimelineEntryRelevance?
}

nonisolated struct DMProvider: TimelineProvider {
    func placeholder(in _: Context) -> DMEntry {
        DMEntry(date: .now, unread: 0, threads: [], relevance: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (DMEntry) -> Void) {
        let sample = [
            CompactThread(user: "alex", preview: "yo are you down for tonight?", when: Date().timeIntervalSince1970 - 120, fromMe: false, unread: true),
            CompactThread(user: "maya", preview: "sent you a sticker", when: Date().timeIntervalSince1970 - 600, fromMe: false, unread: true),
            CompactThread(user: "kai", preview: "haha that's wild", when: Date().timeIntervalSince1970 - 3600, fromMe: true, unread: false)
        ]
        completion(DMEntry(date: .now, unread: 2, threads: sample, relevance: nil))
    }
    func getTimeline(in _: Context, completion: @escaping (Timeline<DMEntry>) -> Void) {
        Task {
            await WhisperWidgetBackend.refreshSnapshot()
            buildAndDeliver(completion: completion)
        }
    }

    private func buildAndDeliver(completion: @escaping (Timeline<DMEntry>) -> Void) {
        let unread = WidgetSnapshot.unreadDMCount()
        var threads = WidgetSnapshot.topThreads()
        // Fallback: the per-thread JSON list can lag behind the scalar
        // keys after a partial write or stale extension cache. If we have
        // a last sender/preview but no decoded threads, synthesize a
        // single row so the widget never falsely says "all caught up".
        if threads.isEmpty,
           let sender = WidgetSnapshot.lastSender(),
           let preview = WidgetSnapshot.lastPreview() {
            let when = WidgetSnapshot.lastDate()?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
            threads = [CompactThread(
                user: sender,
                preview: preview,
                when: when,
                fromMe: false,
                unread: unread > 0
            )]
        }
        // Smart Stack score: heavier when there's unread, decays with age of latest message.
        let latestAge = threads.first.map { abs(Date(timeIntervalSince1970: $0.when).timeIntervalSinceNow) } ?? .infinity
        let freshness = max(0, 1 - Float(min(latestAge, 3600)) / 3600) // 1.0 fresh → 0 after 1h
        let score = Float(unread) * 20 + freshness * 30
        let entry = DMEntry(
            date: .now,
            unread: unread,
            threads: threads,
            relevance: .init(score: score)
        )
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(10 * 60))))
    }
}

struct DMInboxView: View {
    @Environment(\.widgetFamily) var family
    var entry: DMEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.unread > 0 ? "\(entry.unread) new" : "Inbox")
                    .font(.headline)
                if let t = entry.threads.first {
                    Text("@\(jasperDisplayName(t.user))").font(.caption2.weight(.bold))
                    Text(t.preview).font(.caption2).lineLimit(1)
                } else {
                    Text("All caught up").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .widgetURL(WhisperLink.inbox)

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if entry.unread > 0 {
                    Text("\(min(entry.unread, 99))").font(.title2.bold())
                } else {
                    Image(systemName: "paperplane.fill").font(.title3)
                }
            }
            .widgetURL(WhisperLink.inbox)

        default:
            VStack(alignment: .leading, spacing: 0) {
                header
                rows
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .widgetURL(WhisperLink.inbox)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            JasperGhost(size: 20, expression: JasperMood.of(Date()).expression)
            Text("INBOX")
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(WidgetTheme.fg)
            Spacer()
            if entry.unread > 0 {
                mintBadge("\(entry.unread) new")
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let count = family == .systemLarge ? 5 : 3
        let list = Array(entry.threads.prefix(count))
        if list.isEmpty {
            let reason = WidgetSnapshot.emptyReason()
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: emptyIcon(for: reason)).font(.title2).foregroundStyle(WidgetTheme.dim)
                Text(emptyTitle(for: reason, unread: entry.unread))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WidgetTheme.dim)
                if let sub = emptySubtitle(for: reason) {
                    Text(sub)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WidgetTheme.dim)
                        .padding(.horizontal, 8)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 7) {
                ForEach(list, id: \.self) { t in
                    Link(destination: WhisperLink.dm(t.user, userID: t.userID, owner: t.owner, threadID: t.threadID)) {
                        threadRow(t)
                    }
                }
            }
        }
    }

    private func emptyIcon(for reason: WidgetSnapshot.EmptyReason) -> String {
        switch reason {
        case .appGroupUnavailable: return "exclamationmark.triangle"
        case .notSignedIn: return "person.crop.circle.badge.questionmark"
        case .noData: return "tray"
        }
    }

    private func emptyTitle(for reason: WidgetSnapshot.EmptyReason, unread: Int) -> String {
        switch reason {
        case .appGroupUnavailable: return "Widget needs setup"
        case .notSignedIn: return "Sign in to Whisper"
        case .noData: return unread > 0 ? "\(unread) unread" : "No messages yet"
        }
    }

    private func emptySubtitle(for reason: WidgetSnapshot.EmptyReason) -> String? {
        switch reason {
        case .appGroupUnavailable: return "App Group not provisioned. Needs a fresh TestFlight build after enabling App Groups on the developer portal."
        case .notSignedIn: return "Open the app to load DMs."
        case .noData: return nil
        }
    }

    private func threadRow(_ t: CompactThread) -> some View {
        HStack(spacing: 9) {
            avatarDisc(userID: t.userID, fallbackLetter: jasperDisplayName(t.user).first.map(String.init)?.uppercased() ?? "?")
            .frame(width: 27, height: 27)
            .overlay(alignment: .topTrailing) {
                if t.unread {
                    Circle().fill(WidgetTheme.deepMint).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(WidgetTheme.bg, lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("@\(jasperDisplayName(t.user))")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.fg)
                    Spacer(minLength: 0)
                    Text(Date(timeIntervalSince1970: t.when).shortRelative)
                        .font(.caption2)
                        .foregroundStyle(WidgetTheme.dim)
                }
                Text(t.fromMe ? "You: \(t.preview)" : t.preview)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(t.unread ? WidgetTheme.fg : WidgetTheme.dim)
            }
        }
    }
}

struct DMInboxWidget: Widget {
    let kind = "DMInboxWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DMProvider()) { entry in
            DMInboxView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("DMs")
        .description("Your latest Whisper conversations at a glance.")
        .supportedFamilies([
            .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular
        ])
    }
}

// =====================================================================
// MARK: - 3. Stories Ring Widget
// =====================================================================

struct StoryEntry: TimelineEntry {
    let date: Date
    let count: Int
    let authors: [StoryAuthor]
    let relevance: TimelineEntryRelevance?
    var owner: String? = AppGroup.defaults?.string(forKey: "whisper_session_user_id")
}

nonisolated struct StoryProvider: TimelineProvider {
    func placeholder(in _: Context) -> StoryEntry {
        StoryEntry(date: .now, count: 0, authors: [], relevance: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (StoryEntry) -> Void) {
        let sample = ["alex", "maya", "kai", "ren", "sky"].map { StoryAuthor(name: $0) }
        completion(StoryEntry(date: .now, count: 5, authors: sample, relevance: nil))
    }
    func getTimeline(in _: Context, completion: @escaping (Timeline<StoryEntry>) -> Void) {
        Task {
            await WhisperWidgetBackend.refreshSnapshot()
            let authors = WidgetSnapshot.storyAuthorRows()
            let count = max(WidgetSnapshot.activeStoryCount(), authors.count)
            let score = Float(min(count, 10) * 8)
            let entry = StoryEntry(
                date: .now,
                count: count,
                authors: authors,
                relevance: .init(score: score)
            )
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

struct StoriesRingView: View {
    @Environment(\.widgetFamily) var family
    var entry: StoryEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "circle.dashed").font(.caption)
                    Text("\(entry.count)").font(.headline.bold())
                }
            }
            .widgetURL(WhisperLink.stories)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Stories").font(.headline)
                Text(entry.count > 0 ? "\(entry.count) friends posted" : "Nothing new")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .widgetURL(WhisperLink.stories)

        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    kicker("STORIES")
                    Spacer()
                    if entry.count > 0 {
                        mintBadge("\(entry.count) new")
                    }
                }

                Spacer(minLength: 0)

                if entry.authors.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 5) {
                            JasperGhost(size: 36, tilt: 6, expression: .happy)
                                .opacity(0.85)
                            Text("All caught up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(WidgetTheme.dim)
                        }
                        Spacer()
                    }
                } else {
                    HStack(spacing: -9) {
                        ForEach(entry.authors.prefix(family == .systemMedium ? 6 : 4), id: \.self) { author in
                            Link(destination: WhisperLink.story(userID: author.userID, owner: entry.owner)) {
                                ringAvatar(author)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Text(entry.authors.prefix(3).map { "@\(jasperDisplayName($0.name))" }.joined(separator: ", "))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.deepMint)
                        .lineLimit(1)
                }
            }
            .widgetURL(WhisperLink.stories)
        }
    }

    /// The brand story ring — a mint→deep-mint gradient stroke, exactly the
    /// unseen-story language the app uses.
    private func ringAvatar(_ author: StoryAuthor) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [WidgetTheme.deepMint, WidgetTheme.mint, WidgetTheme.deepMint],
                        center: .center
                    ),
                    lineWidth: 2.5
                )
                .frame(width: 40, height: 40)
            avatarDisc(userID: author.userID, fallbackLetter: jasperDisplayName(author.name).first.map(String.init)?.uppercased() ?? "?")
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(WidgetTheme.bg, lineWidth: 1.5))
        }
    }
}

struct StoriesRingWidget: Widget {
    let kind = "StoriesRingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StoryProvider()) { entry in
            StoriesRingView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Stories")
        .description("See who's posted a new story.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular
        ])
    }
}

// =====================================================================
// MARK: - 4. Thought Widget
// =====================================================================

struct ThoughtEntry: TimelineEntry {
    let date: Date
    let thought: String?
    let followers: Int
    let following: Int
    let relevance: TimelineEntryRelevance?
}

nonisolated struct ThoughtProvider: TimelineProvider {
    func placeholder(in _: Context) -> ThoughtEntry {
        ThoughtEntry(date: .now, thought: nil, followers: 0, following: 0, relevance: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (ThoughtEntry) -> Void) {
        completion(ThoughtEntry(
            date: .now,
            thought: "shipping the new widgets today",
            followers: 128,
            following: 76,
            relevance: nil
        ))
    }
    func getTimeline(in _: Context, completion: @escaping (Timeline<ThoughtEntry>) -> Void) {
        let entry = ThoughtEntry(
            date: .now,
            thought: WidgetSnapshot.myThought(),
            followers: WidgetSnapshot.followers(),
            following: WidgetSnapshot.following(),
            relevance: .init(score: WidgetSnapshot.myThought() == nil ? 15 : 5)
        )
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct ThoughtView: View {
    @Environment(\.widgetFamily) var family
    var entry: ThoughtEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Top of mind").font(.caption2.weight(.bold))
                Text(entry.thought ?? "Tap to share").font(.caption).lineLimit(2)
            }
            .widgetURL(WhisperLink.thought)

        case .accessoryInline:
            Text(entry.thought ?? "Share a thought")
                .widgetURL(WhisperLink.thought)

        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    kicker("TOP OF MIND")
                    Spacer()
                    Image(systemName: "pencil.line")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(WidgetTheme.ink)
                        .padding(6)
                        .background(WidgetTheme.mint, in: Circle())
                }

                Spacer(minLength: 0)

                if let t = entry.thought {
                    // The note bubble — a big decorative mint quote mark with
                    // the thought in warm serif, like the in-app note style.
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{201C}")
                            .font(.system(size: family == .systemMedium ? 40 : 34, weight: .black, design: .serif))
                            .foregroundStyle(WidgetTheme.deepMint)
                            .offset(y: -2)
                        Text(t)
                            .font(.system(size: family == .systemMedium ? 17 : 15, weight: .semibold, design: .serif))
                            .italic()
                            .foregroundStyle(WidgetTheme.fg)
                            .lineLimit(family == .systemSmall ? 3 : 4)
                            .minimumScaleFactor(0.7)
                            .padding(.top, 6)
                    }
                } else {
                    Text("Share what's on your mind.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WidgetTheme.dim)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    stat(label: "Followers", value: entry.followers)
                    if family != .systemSmall {
                        stat(label: "Following", value: entry.following)
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(WhisperLink.thought)
        }
    }

    private func stat(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text("\(value)").font(.system(size: 12, weight: .heavy, design: .rounded))
            Text(label).font(.caption2).foregroundStyle(WidgetTheme.dim)
        }
        .foregroundStyle(WidgetTheme.fg)
    }
}

struct ThoughtWidget: Widget {
    let kind = "ThoughtWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ThoughtProvider()) { entry in
            ThoughtView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Top of Mind")
        .description("Your current thought, always one tap away.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryInline
        ])
    }
}

// =====================================================================
// MARK: - 5. Activity Pulse Widget
// =====================================================================

struct ActivityEntry: TimelineEntry {
    let date: Date
    let count: Int
    let preview: String?
    let relevance: TimelineEntryRelevance?
}

nonisolated struct ActivityProvider: TimelineProvider {
    func placeholder(in _: Context) -> ActivityEntry {
        ActivityEntry(date: .now, count: 0, preview: nil, relevance: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (ActivityEntry) -> Void) {
        completion(ActivityEntry(
            date: .now, count: 7,
            preview: "@maya liked your post",
            relevance: nil
        ))
    }
    func getTimeline(in _: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        let count = WidgetSnapshot.activityCount()
        let entry = ActivityEntry(
            date: .now,
            count: count,
            preview: WidgetSnapshot.activityPreview(),
            relevance: .init(score: Float(min(count, 99)) * 1.5)
        )
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(10 * 60))))
    }
}

struct ActivityPulseView: View {
    @Environment(\.widgetFamily) var family
    var entry: ActivityEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if entry.count > 0 {
                    Text("\(min(entry.count, 99))").font(.title3.bold())
                } else {
                    Image(systemName: "heart").font(.title3)
                }
            }
            .widgetURL(WhisperLink.activity)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.count > 0 ? "\(entry.count) new" : "Activity")
                    .font(.headline)
                Text(entry.preview ?? "Nothing yet")
                    .font(.caption2).lineLimit(2)
            }
            .widgetURL(WhisperLink.activity)

        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(5.5)
                        .background(WidgetTheme.heat, in: Circle())
                    Text("ACTIVITY")
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(WidgetTheme.fg)
                    Spacer()
                }

                Spacer(minLength: 0)

                // The pulse number wears the warm heat gradient.
                Text("\(entry.count)")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        entry.count > 0
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [WidgetTheme.heat, WidgetTheme.deepMint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(WidgetTheme.fg)
                    )
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text(entry.preview ?? (entry.count == 0 ? "Nothing yet" : "new pings"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetTheme.dim)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .widgetURL(WhisperLink.activity)
        }
    }
}

struct ActivityPulseWidget: Widget {
    let kind = "ActivityPulseWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActivityProvider()) { entry in
            ActivityPulseView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Activity Pulse")
        .description("New likes, comments, and follows at a glance.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular, .accessoryRectangular
        ])
    }
}

// =====================================================================
// MARK: - 6. Shared Calendar Widget
// =====================================================================

struct CalendarEntry: TimelineEntry {
    let date: Date
    let events: [CompactEvent]
    let relevance: TimelineEntryRelevance?
}

nonisolated struct CalendarProvider: TimelineProvider {
    func placeholder(in _: Context) -> CalendarEntry {
        CalendarEntry(date: .now, events: [], relevance: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (CalendarEntry) -> Void) {
        let sample = [
            CompactEvent(title: "Team check-in", when: Date().addingTimeInterval(3600).timeIntervalSince1970, type: "meeting", host: "dyl", link: true),
            CompactEvent(title: "Content review", when: Date().addingTimeInterval(26 * 3600).timeIntervalSince1970, type: "review", host: "maya", link: false)
        ]
        completion(CalendarEntry(date: .now, events: sample, relevance: nil))
    }
    func getTimeline(in _: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        Task {
            await WhisperWidgetBackend.refreshExtras()
            let events = WidgetSnapshot.calendarEvents()
            // Score climbs as the next event approaches (2h window).
            let score: Float
            if let next = events.first {
                let secondsAway = max(0, next.when - Date().timeIntervalSince1970)
                score = secondsAway < 2 * 3600 ? Float(80 - secondsAway / 120) : 20
            } else {
                score = 0
            }
            let entry = CalendarEntry(date: .now, events: events, relevance: .init(score: max(0, score)))
            // Refresh at the next event start (so "in 2h" flips to "now")
            // or in 20 minutes, whichever comes first.
            var next = Date().addingTimeInterval(20 * 60)
            if let soonest = events.first {
                let start = Date(timeIntervalSince1970: soonest.when)
                if start > Date(), start < next { next = start }
            }
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct SharedCalendarView: View {
    @Environment(\.widgetFamily) var family
    var entry: CalendarEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Team calendar").font(.caption2.weight(.bold))
                if let next = entry.events.first {
                    Text(next.title).font(.headline).lineLimit(1)
                    Text(timeLine(for: next)).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Nothing scheduled").font(.caption)
                }
            }
            .widgetURL(WhisperLink.calendar)

        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    kicker(family == .systemSmall ? "CALENDAR" : "SHARED CALENDAR")
                    Spacer()
                    if entry.events.count > 0 {
                        mintBadge("\(entry.events.count) up next")
                    }
                }

                Spacer(minLength: 0)

                if entry.events.isEmpty {
                    emptyState
                } else if family == .systemSmall {
                    nextEventHero(entry.events[0])
                } else {
                    VStack(spacing: 7) {
                        ForEach(Array(entry.events.prefix(2)), id: \.self) { event in
                            eventRow(event)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .widgetURL(WhisperLink.calendar)
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 5) {
                JasperGhost(size: 34, tilt: 5, expression: .happy).opacity(0.85)
                Text("Nothing scheduled")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WidgetTheme.dim)
                if family != .systemSmall {
                    Text("Events your team creates show up here.")
                        .font(.caption2)
                        .foregroundStyle(WidgetTheme.dim)
                }
            }
            Spacer()
        }
    }

    /// Small family: the single next event, big.
    private func nextEventHero(_ event: CompactEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dayChipText(for: event))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(WidgetTheme.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(WidgetTheme.mint, in: Capsule())
            Text(event.title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetTheme.fg)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                if event.link {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(WidgetTheme.deepMint)
                }
                Text(clockText(for: event))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetTheme.dim)
            }
        }
    }

    private func eventRow(_ event: CompactEvent) -> some View {
        HStack(spacing: 9) {
            VStack(spacing: 0) {
                Text(weekdayText(for: event))
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.deepMint)
                Text(dayNumberText(for: event))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.ink)
            }
            .frame(width: 34, height: 34)
            .background(WidgetTheme.mint.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.fg)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if event.link {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(WidgetTheme.deepMint)
                    }
                    Text(clockText(for: event) + (event.host.map { " · @\(jasperDisplayName($0))" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(WidgetTheme.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func startDate(for event: CompactEvent) -> Date { Date(timeIntervalSince1970: event.when) }

    private func weekdayText(for event: CompactEvent) -> String {
        startDate(for: event).formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private func dayNumberText(for event: CompactEvent) -> String {
        startDate(for: event).formatted(.dateTime.day())
    }

    private func dayChipText(for event: CompactEvent) -> String {
        let d = startDate(for: event)
        if Calendar.current.isDateInToday(d) { return "TODAY" }
        if Calendar.current.isDateInTomorrow(d) { return "TOMORROW" }
        return d.formatted(.dateTime.weekday(.wide)).uppercased()
    }

    private func clockText(for event: CompactEvent) -> String {
        startDate(for: event).formatted(date: .omitted, time: .shortened)
    }

    private func timeLine(for event: CompactEvent) -> String {
        let d = startDate(for: event)
        if Calendar.current.isDateInToday(d) {
            return "Today · " + clockText(for: event)
        }
        return d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

struct SharedCalendarWidget: Widget {
    let kind = "SharedCalendarWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarProvider()) { entry in
            SharedCalendarView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Shared Calendar")
        .description("Your team's next events — meetings open with one tap.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular
        ])
    }
}

// =====================================================================
// MARK: - 7. Coach Clients Widget
// =====================================================================

struct ClientsEntry: TimelineEntry {
    let date: Date
    let clients: [CompactClient]
    let isCoach: Bool
    let relevance: TimelineEntryRelevance?
}

nonisolated struct ClientsProvider: TimelineProvider {
    func placeholder(in _: Context) -> ClientsEntry {
        ClientsEntry(date: .now, clients: [], isCoach: false, relevance: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (ClientsEntry) -> Void) {
        let sample = [
            CompactClient(name: "alex", since: Date().addingTimeInterval(-86_400 * 40).timeIntervalSince1970),
            CompactClient(name: "maya", since: Date().addingTimeInterval(-86_400 * 12).timeIntervalSince1970),
            CompactClient(name: "kai", since: Date().addingTimeInterval(-86_400 * 3).timeIntervalSince1970)
        ]
        completion(ClientsEntry(date: .now, clients: sample, isCoach: true, relevance: nil))
    }
    func getTimeline(in _: Context, completion: @escaping (Timeline<ClientsEntry>) -> Void) {
        Task {
            await WhisperWidgetBackend.refreshExtras()
            let clients = WidgetSnapshot.coachClients()
            let entry = ClientsEntry(
                date: .now,
                clients: clients,
                isCoach: WidgetSnapshot.isCoach() || !clients.isEmpty,
                relevance: .init(score: Float(min(clients.count, 10)) * 4)
            )
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

struct CoachClientsView: View {
    @Environment(\.widgetFamily) var family
    var entry: ClientsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                kicker("YOUR CLIENTS")
                Spacer()
                if !entry.clients.isEmpty {
                    mintBadge("\(entry.clients.count)")
                }
            }

            if entry.clients.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(entry.clients.prefix(family == .systemLarge ? 6 : 3)), id: \.self) { client in
                        Link(destination: WhisperLink.dm(client.name, userID: client.userID)) {
                            clientRow(client)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(WhisperLink.coach)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 5) {
                JasperGhost(size: 36, tilt: -5, expression: .happy).opacity(0.85)
                Text(entry.isCoach ? "No clients yet" : "Coach Studio")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WidgetTheme.dim)
                Text(entry.isCoach
                     ? "Share your coaching link to get hired."
                     : "Your client roster lives here when you coach on Whisper.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WidgetTheme.dim)
                    .padding(.horizontal, 10)
            }
            Spacer()
        }
    }

    private func clientRow(_ client: CompactClient) -> some View {
        HStack(spacing: 9) {
            avatarDisc(userID: client.userID, fallbackLetter: client.name.first.map(String.init)?.uppercased() ?? "?")
                .frame(width: 27, height: 27)

            VStack(alignment: .leading, spacing: 1) {
                Text("@\(client.name)")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.fg)
                    .lineLimit(1)
                Text(sinceLine(client))
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "paperplane")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WidgetTheme.deepMint)
        }
    }

    private func sinceLine(_ client: CompactClient) -> String {
        guard let since = client.since, since > 0 else { return "Active client" }
        let date = Date(timeIntervalSince1970: since)
        return "Client since \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

struct CoachClientsWidget: Widget {
    let kind = "CoachClientsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClientsProvider()) { entry in
            CoachClientsView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Coach Clients")
        .description("Your active clients — one tap to message them.")
        .supportedFamilies([
            .systemMedium, .systemLarge
        ])
    }
}
