import SwiftUI

/// "Tune your feed" — Whisper's own take on feed tuning. Not a chip cloud on a
/// black canvas: an adaptive surface with a JASPER'S READ hero card (the
/// one-liner types in wearing the brand gradient and settles to ink, with
/// your activity receipts as quiet pills), then a MIXER — "Turn up" and
/// "Turn down" as grouped cards where every topic is a row with a level bar
/// (fuller when your activity backs it), a ⋯ menu, and an add row — and a
/// "Jasper noticed" rail of one-tap suggestions between them. Every steer
/// feeds the wave ranking immediately.
struct WhisperAlgorithmView: View {
    /// The loaded wave pool the signals are computed from.
    let pool: [WhisperPost]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var prefs = WhisperAlgorithmPreferences.shared
    @State private var signals: [WhisperAlgorithmSignal] = []
    @State private var activity = WhisperAlgorithmActivity()
    @State private var summary: String?
    @State private var summarizing: Bool = false
    @State private var presentSignals: Bool = false
    @State private var presentHow: Bool = false
    @State private var addTarget: AddTarget?
    @State private var addText: String = ""
    @State private var confirmReset: Bool = false
    @State private var appeared: Bool = false

    private enum AddTarget: Identifiable {
        case more, less
        var id: Int { self == .more ? 0 : 1 }
    }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var card: Color { WhisperTheme.card(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }

    private var suggestions: [WhisperAlgorithmSignal] {
        WhisperAlgorithmSignals.suggestions(from: signals)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Tuning strength").font(.headline)
                            Spacer()
                            Text(prefs.strength, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().foregroundStyle(muted)
                        }
                        Slider(value: Binding(get: { prefs.strength }, set: { prefs.setStrength($0) }), in: 0...1)
                            .tint(ink)
                            .accessibilityLabel("Algorithm tuning strength")
                        Text("Applies your Turn up and Turn down choices to Discover and Waves. Zero keeps the standard ranking.")
                            .font(.caption).foregroundStyle(muted)
                    }
                    .padding(16)
                    .background(card, in: .rect(cornerRadius: 18))
                    heroCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)

                    mixerCard(
                        title: "Turn up",
                        subtitle: "Matching posts and Waves rank higher — up to 2.25× when they stack.",
                        terms: prefs.moreOf,
                        less: false
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
                    .animation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.06), value: appeared)

                    if !suggestions.isEmpty {
                        noticedRail
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.1), value: appeared)
                    }

                    mixerCard(
                        title: "Turn down",
                        subtitle: "These sink to the bottom of your feed (0.3×).",
                        terms: prefs.lessOf,
                        less: true
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 22)
                    .animation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.14), value: appeared)

                    footer
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
        .whisperEdgeBack(controller: backTransition) { backTransition.perform { dismiss() } }
        .task { await load() }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { appeared = true }
        }
        .sheet(isPresented: $presentSignals) {
            WhisperAlgorithmSignalsSheet(signals: signals, activity: activity)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $presentHow) {
            howSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(addTarget == .less ? "Turn down" : "Turn up", isPresented: Binding(
            get: { addTarget != nil },
            set: { if !$0 { addTarget = nil; addText = "" } }
        )) {
            TextField("Topic, #hashtag or @creator", text: $addText)
                .textInputAutocapitalization(.never)
            Button("Add") {
                let text = addText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    if addTarget == .less { prefs.addLess(text) } else { prefs.addMore(text) }
                    Haptics.success()
                    Task { await refreshSummary(force: true) }
                }
                addTarget = nil
                addText = ""
            }
            Button("Cancel", role: .cancel) {
                addTarget = nil
                addText = ""
            }
        } message: {
            Text(addTarget == .less
                 ? "Posts and Waves about this sink to the bottom of your feed."
                 : "Posts and Waves about this rank higher in your feed.")
        }
        .confirmationDialog("Reset your tuning?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                prefs.reset()
                Haptics.success()
                Task { await load(force: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears everything you've turned up or down and the watch history the feed learned from. Likes and saves stay.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                backTransition.perform { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 1) {
                Text("Tune your feed")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text("What plays next is yours to steer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    presentHow = true
                } label: {
                    Label("How this works", systemImage: "questionmark.circle")
                }
                Button {
                    Task { await refreshSummary(force: true) }
                } label: {
                    Label("Refresh Jasper's read", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("Reset your tuning", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More")

            ShareLink(item: shareText) {
                Image(systemName: "paperplane")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Share")
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var shareText: String {
        (summary ?? WhisperAlgorithmSignals.templatedSummary(signals: signals)) + " — my Whisper Waves, tuned."
    }

    // MARK: - Hero: Jasper's read

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("JASPER'S READ")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(muted)
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    presentSignals = true
                } label: {
                    HStack(spacing: 4) {
                        Text(signals.isEmpty ? "No signals yet" : "\(signals.count) signals")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(hairline, lineWidth: 0.75) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Based on your activity")
            }

            headline

            HStack(spacing: 8) {
                statPill("heart.fill", activity.likes, "likes")
                statPill("bookmark.fill", activity.saves, "saves")
                statPill("play.fill", activity.watched, "watched")
            }
        }
        .padding(18)
        .background(card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
        .overlay(alignment: .topTrailing) {
            // A soft brand bloom in the corner — the one place the gradient
            // paints a surface here; everything else is ink on paper.
            Circle()
                .fill(WhisperBrandGradient.diagonal)
                .frame(width: 140, height: 140)
                .blur(radius: 48)
                .opacity(colorScheme == .dark ? 0.22 : 0.14)
                .offset(x: 40, y: -50)
                .allowsHitTesting(false)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var headline: some View {
        if let summary {
            WhisperGradientTypeInText(
                text: summary,
                font: .system(size: 23, weight: .bold),
                settleColor: ink
            )
            .id(summary)
        } else {
            Text("Reading what you've been watching…")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(ink.opacity(0.3))
                .redacted(reason: summarizing ? .placeholder : [])
        }
    }

    private func statPill(_ icon: String, _ n: Int, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text("\(n)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(ink.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(WhisperTheme.surface(colorScheme), in: Capsule())
    }

    // MARK: - Mixer cards

    private func mixerCard(title: String, subtitle: String, terms: [String], less: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: less ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(less ? muted : WhisperBrandGradient.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ink)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if terms.isEmpty {
                Text(less
                     ? "Nothing turned down. Add a topic you're tired of and it sinks."
                     : "Nothing turned up yet. Add a topic, #hashtag or @creator — or tap what Jasper noticed below.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(terms.enumerated()), id: \.element) { idx, term in
                        levelRow(term, less: less)
                        if idx < terms.count - 1 {
                            Rectangle()
                                .fill(hairline)
                                .frame(height: 0.5)
                                .padding(.leading, 38)
                        }
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: terms)
            }

            Rectangle()
                .fill(hairline)
                .frame(height: 0.5)

            Button {
                Haptics.tap()
                addTarget = less ? .less : .more
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ink)
                        .frame(width: 26, height: 26)
                        .background(ink.opacity(colorScheme == .dark ? 0.12 : 0.06), in: Circle())
                    Text(less ? "Turn something down" : "Turn something up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                    Spacer()
                    Text("Topic · #tag · @creator")
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .background(card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    /// Normalized activity weight behind a steer (0 when your activity has
    /// nothing to say about it yet).
    private func signalStrength(for term: String) -> Double {
        let key = term.lowercased()
        guard let maxWeight = signals.first?.weight, maxWeight > 0,
              let match = signals.first(where: { $0.label.lowercased() == key }) else {
            return 0
        }
        return min(1, max(0, match.weight / maxWeight))
    }

    /// One steer as a mixer row: dot · label + level bar · ⋯ menu.
    private func levelRow(_ term: String, less: Bool) -> some View {
        let strength: Double = signalStrength(for: term)
        let level: Double = less ? 0.3 : min(1.0, 0.55 + 0.45 * strength)
        return HStack(spacing: 12) {
            Circle()
                .fill(less ? AnyShapeStyle(muted.opacity(0.5)) : AnyShapeStyle(WhisperBrandGradient.diagonal))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(term)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    if !less && strength > 0.35 {
                        Text("backed by your activity")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(ink.opacity(colorScheme == .dark ? 0.12 : 0.07))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(less ? AnyShapeStyle(muted.opacity(0.7)) : AnyShapeStyle(WhisperBrandGradient.linear))
                                .frame(width: max(8, geo.size.width * CGFloat(level)))
                        }
                }
                .frame(height: 5)
            }
            Spacer(minLength: 6)
            Menu {
                if less {
                    Button {
                        prefs.addMore(term)
                        Haptics.tap()
                        Task { await refreshSummary(force: true) }
                    } label: {
                        Label("Turn up instead", systemImage: "arrow.up.right")
                    }
                } else {
                    Button {
                        prefs.addLess(term)
                        Haptics.tap()
                        Task { await refreshSummary(force: true) }
                    } label: {
                        Label("Turn down instead", systemImage: "arrow.down.right")
                    }
                }
                Button(role: .destructive) {
                    if less { prefs.removeLess(term) } else { prefs.removeMore(term) }
                    Haptics.tap()
                    Task { await refreshSummary(force: true) }
                } label: {
                    Label("Remove", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(muted)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Options for \(term)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    // MARK: - Jasper noticed

    /// What your activity suggests — one-tap pills; long-press for turn-down /
    /// not-interested.
    private var noticedRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WhisperBrandGradient.accent)
                Text("Jasper noticed you're into")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { s in
                        suggestionPill(s)
                    }
                }
                .padding(.horizontal, 2)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: prefs.dismissed)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: prefs.moreOf)
        }
    }

    private func suggestionPill(_ s: WhisperAlgorithmSignal) -> some View {
        Button {
            Haptics.success()
            prefs.addMore(s.label)
            Task { await refreshSummary(force: true) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(s.label)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(card, in: Capsule())
            .overlay { Capsule().strokeBorder(hairline, lineWidth: 0.75) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                prefs.addLess(s.label)
                Haptics.tap()
                Task { await refreshSummary(force: true) }
            } label: {
                Label("Turn this down", systemImage: "arrow.down.right")
            }
            Button(role: .destructive) {
                prefs.dismissSuggestion(s.label)
                Haptics.tap()
            } label: {
                Label("Not interested", systemImage: "eye.slash")
            }
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Every steer changes Discover and Waves at your chosen tuning strength. Your likes, saves, and watch time stay on this phone — only the topic list leaves it, for the one-liner.")
                .font(.system(size: 12.5))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                presentHow = true
            } label: {
                HStack(spacing: 4) {
                    Text("How this works")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - How sheet

    private var howSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How your tuning works")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ink)
                    .padding(.top, 22)
                howRow("heart.fill", "Likes and saves", "A like counts 3×, a save 4× toward the communities, hashtags, and creators on that wave.")
                howRow("play.fill", "Watch time", "Waves you actually watched count too — longer watches count more. Only stored on this phone.")
                howRow("person.2.fill", "Follows", "Creators you follow nudge their topics up a little.")
                howRow("arrow.up.right", "Turn up / turn down", "Every \"turn up\" ranks matching waves 1.5× higher (stacking up to 2.25×). \"Turn down\" sinks them to 0.3×.")
                howRow("sparkles", "Jasper's read", "Summarized by AI from those signals once a day, or whenever you steer. Nothing about you is sent except the topic list.")
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
    }

    private func howRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: 30, height: 30)
                .background(card, in: Circle())
                .overlay { Circle().strokeBorder(hairline, lineWidth: 0.75) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Data

    private func load(force: Bool = false) async {
        let computed = WhisperAlgorithmSignals.compute(pool: pool)
        signals = computed.signals
        activity = computed.activity
        await refreshSummary(force: force)
    }

    private func refreshSummary(force: Bool) async {
        let computed = WhisperAlgorithmSignals.compute(pool: pool)
        signals = computed.signals
        activity = computed.activity
        if force {
            // Steering changed the signature, so the cache misses naturally;
            // clear the line so the new one types in again.
            withAnimation(.easeOut(duration: 0.15)) { summary = nil }
        }
        summarizing = true
        let line = await WhisperAlgorithmSignals.summarize(signals: computed.signals)
        summarizing = false
        withAnimation(.easeOut(duration: 0.2)) { summary = line }
    }
}

// MARK: - Gradient type-in

/// The Whisper type-in entrance (the algorithm screen, the paywalls): the
/// sentence types in wearing THE Whisper brand gradient (the live rose →
/// orange → amber sweep) with a soft leading edge, then the whole line
/// settles to the surface's ink (`settleColor` — white on dark canvases,
/// theme ink on paywall sheets). Layout is stable from the first frame (the
/// unrevealed remainder is laid out transparent). Set `settles` false to keep
/// the gradient on permanently.
struct WhisperGradientTypeInText: View {
    let text: String
    var font: Font = .system(size: 26, weight: .bold)
    /// Characters per second while typing.
    var speed: Double = 30
    /// The color the line settles to once typed.
    var settleColor: Color = .white
    /// Whether the line settles at all (false = stays gradient).
    var settles: Bool = true
    /// Text alignment for multi-line wraps.
    var alignment: TextAlignment = .leading

    @State private var revealed: Int = 0
    @State private var settled: Bool = false
    @State private var startedAt: Date?

    private let gradient: LinearGradient = WhisperBrandGradient.linear

    private var characters: [Character] { Array(text) }

    private var frameAlignment: Alignment {
        switch alignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(font)
                .multilineTextAlignment(alignment)
                .foregroundStyle(settleColor)
                .opacity(settled ? 1 : 0)

            if !settled {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: revealed >= characters.count)) { context in
                    typed(at: context.date)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .accessibilityLabel(text)
        .onAppear {
            startedAt = Date()
        }
    }

    /// The partially revealed line: revealed characters wear the gradient,
    /// the next three fade out like a soft cursor, the rest are laid out
    /// clear so wrapping never shifts.
    private func typed(at date: Date) -> some View {
        let start = startedAt ?? date
        let elapsed = max(0, date.timeIntervalSince(start) - 0.25)
        let count = min(characters.count, Int(elapsed * speed))
        if count != revealed {
            DispatchQueue.main.async {
                revealed = count
                if count >= characters.count && !settled && settles {
                    Task {
                        try? await Task.sleep(for: .milliseconds(650))
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.9)) { settled = true }
                        }
                    }
                }
            }
        }
        let head = String(characters.prefix(count))
        let edge1 = count < characters.count ? String(characters[count]) : ""
        let edge2 = count + 1 < characters.count ? String(characters[count + 1]) : ""
        let edge3 = count + 2 < characters.count ? String(characters[count + 2]) : ""
        let restStart = min(characters.count, count + 3)
        let rest = String(characters[restStart...])

        return (
            Text(head).foregroundStyle(gradient)
            + Text(edge1).foregroundStyle(gradient.opacity(0.55))
            + Text(edge2).foregroundStyle(gradient.opacity(0.28))
            + Text(edge3).foregroundStyle(gradient.opacity(0.12))
            + Text(rest).foregroundStyle(.clear)
        )
        .font(font)
        .multilineTextAlignment(alignment)
        .opacity(settled ? 0 : 1)
    }
}

// MARK: - Signals sheet

/// "Based on your activity" — the receipts: the counts the summary came
/// from and every signal with its weight bar. Adaptive to the theme now (it
/// used to force a black canvas).
struct WhisperAlgorithmSignalsSheet: View {
    let signals: [WhisperAlgorithmSignal]
    let activity: WhisperAlgorithmActivity

    @Environment(\.colorScheme) private var colorScheme

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    private var maxWeight: Double { max(signals.first?.weight ?? 1, 0.01) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your activity")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ink)
                    .padding(.top, 22)

                HStack(spacing: 10) {
                    stat(activity.likes, "likes", "heart.fill")
                    stat(activity.saves, "saves", "bookmark.fill")
                    stat(activity.watched, "watched", "play.fill")
                    stat(activity.following, "following", "person.2.fill")
                }

                if signals.isEmpty {
                    Text("Like, save, and watch a few waves — the topics and creators you gravitate to will show up here.")
                        .font(.system(size: 14))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("WHAT IT ADDS UP TO")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(muted)
                    VStack(spacing: 12) {
                        ForEach(signals.prefix(14)) { s in
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: s.kind))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(ink)
                                    .frame(width: 26, height: 26)
                                    .background(WhisperTheme.card(colorScheme), in: Circle())
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(s.label)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(ink)
                                        .lineLimit(1)
                                    GeometryReader { geo in
                                        Capsule()
                                            .fill(ink.opacity(colorScheme == .dark ? 0.12 : 0.07))
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(WhisperBrandGradient.linear)
                                                    .frame(width: max(6, geo.size.width * CGFloat(s.weight / maxWeight)))
                                            }
                                    }
                                    .frame(height: 5)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
    }

    private func stat(_ n: Int, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ink.opacity(0.85))
            Text("\(n)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ink)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func icon(for kind: WhisperAlgorithmSignal.Kind) -> String {
        switch kind {
        case .community: return "circle.hexagongrid.fill"
        case .hashtag: return "number"
        case .creator: return "person.fill"
        }
    }
}
