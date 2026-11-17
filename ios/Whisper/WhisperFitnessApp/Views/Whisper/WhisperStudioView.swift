import Foundation
import Supabase
import SwiftUI
import PhotosUI

/// Whisper Studio — the media team's full production workspace on iOS.
/// Directors upload and publish Featured Film Friday premieres, plan
/// projects with the real Jasper assistant (tuned to a director's needs),
/// and manage the films they've shipped. Mirrors the web `/director` page.
struct WhisperStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum StudioTab: String, CaseIterable {
        case upload = "Upload"
        case films = "Films"
        case articles = "Articles"
        case tools = "Tools"

        var icon: String {
            switch self {
            case .upload: return "square.and.arrow.up"
            case .films: return "film.stack"
            case .articles: return "doc.text"
            case .tools: return "sparkles"
            }
        }
    }

    @State private var studioTab: StudioTab = .upload
    @State private var studioService = WhisperStudioService.shared
    @State private var articlesService = WhisperArticlesService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                // The Jasper Intelligence canvas — painted OUTSIDE the width-pin
                // clip so it genuinely reaches the physical top and bottom edges.
                // (The old clipped frame cut it at the safe areas, leaving bare
                // gaps above and below the workspace.)
                WhisperEmberSheetTheme.Backdrop(mode: WhisperEmberCoachMode.load())
                    .ignoresSafeArea()
                // HARD width pin — the GeometryReader adopts exactly the screen
                // size and re-proposes it downward, so no card, form row, or
                // oversized text can push the workspace wider than the phone.
                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            studioHero
                            studioTabPicker
                            switch studioTab {
                            case .upload: PublishFilmCard()
                            case .films: StudioFilmsHub()
                            case .articles: DirectorArticlesCard()
                            case .tools: EmberStudioToolsCard()
                            }
                        }
                        .padding(.horizontal, 16)
                        // Headroom for the ghost peeking above the hero box —
                        // the ScrollView clips at its bounds, so the head
                        // needs real space, not an offset illusion.
                        .padding(.top, 42)
                        .padding(.bottom, 96)
                        // Pin the content column to the visible width — no
                        // child can widen it past the screen edges.
                        .containerRelativeFrame(.horizontal)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            }
            .task {
                // The production desk in the hero reads live numbers — pull
                // the slate + articles the moment the studio opens.
                await studioService.refreshFilms()
                await articlesService.fetchMyArticles()
            }
            .navigationTitle("Whisper Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .overlay(alignment: .bottom) {
                // The meeting-style Jasper dock — steady right above the
                // bottom edge, same placement language as the inbox.
                JasperAnalysisDock(
                    pillLabel: "Knot's read",
                    boxTitle: "Studio analysis",
                    focus: """
                    You are analyzing a Whisper Studio production workspace (films + premieres). From the film slate below, give the director a tight read: what's live, what's missing (no poster, no synopsis, no premiere date), which film should premiere next Friday and why, then ONE concrete next move. Name the actual titles.
                    """,
                    buildContext: { studioAnalysisContext() },
                    emptyText: "No films yet — upload your first film and I'll analyze the slate here.",
                    actions: [
                        JasperDockAction(
                            id: "angles",
                            label: "Article angles",
                            icon: "doc.text",
                            kind: .lens("From the slate below, pitch 2 companion-article angles (director's note, behind-the-scenes, or review) for the films that most need press — one line each, film named. End with which one to write first and why.")
                        ),
                        JasperDockAction(
                            id: "marketing",
                            label: "Premiere hype",
                            icon: "megaphone",
                            kind: .lens("From the slate below, write a short hype plan for the next premiere: one wall-post caption (copy-ready), one story beat, and the best day/time to post. Name the actual film.")
                        ),
                    ]
                )
                .padding(.bottom, 10)
            }
        }
        // Cap dynamic type so accessibility text sizes can never blow the
        // workspace wider than the screen — the clipping bug in the field.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// Live slate context for the studio dock — real titles, real gaps.
    private func studioAnalysisContext() -> String? {
        let films = WhisperStudioService.shared.films
        guard !films.isEmpty else { return nil }
        var lines: [String] = ["WHISPER STUDIO SLATE (live films)"]
        for film in films.prefix(12) {
            var bits: [String] = [film.title]
            if let secs = film.duration_seconds, secs > 0 { bits.append("\(max(1, secs / 60)) min") }
            bits.append(film.poster_url == nil ? "no poster" : "poster ✓")
            if let synopsis = film.synopsis, !synopsis.isEmpty {
                bits.append("synopsis: \(String(synopsis.prefix(90)))")
            } else {
                bits.append("no synopsis")
            }
            if let featured = film.featured_date, !featured.isEmpty {
                bits.append("premiere \(featured)")
            }
            lines.append("- " + bits.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    /// Studios identity banner — the marquee. The living ghost peeks over
    /// the TOP CENTER of the opaque card exactly like the Jasper pills
    /// (head above the edge, body genuinely behind), with film-perforation
    /// strips running along the card's top and bottom edges.
    private var studioHero: some View {
        let mode = WhisperEmberCoachMode.load()
        return VStack(spacing: 7) {
            Text("WHISPER STUDIOS")
                .font(.caption2.weight(.black))
                .tracking(2.4)
                .foregroundStyle(mode.deepAccent)
            Text("The production floor")
                .font(.system(size: 23, weight: .black))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Films, Friday premieres, articles — Jasper works the set with you.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
            // The production desk — live numbers off the real slate, not
            // static labels: what's live, when the next premiere lands,
            // and how many companion pieces exist.
            HStack(spacing: 8) {
                studioDeskStat(
                    value: "\(studioService.films.count)",
                    label: studioService.films.count == 1 ? "Film live" : "Films live",
                    icon: "film.fill", mode: mode)
                studioDeskStat(
                    value: nextPremiereLabel,
                    label: "Next premiere",
                    icon: "calendar", mode: mode)
                studioDeskStat(
                    value: "\(articlesService.myArticles.count)",
                    label: articlesService.myArticles.count == 1 ? "Article" : "Articles",
                    icon: "doc.text.fill", mode: mode)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(mode.accent.opacity(0.28), lineWidth: 1)
        }
        // Film-reel perforations — the marquee reads like a strip of film.
        .overlay(alignment: .top) {
            studioPerforationStrip(mode: mode).padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            studioPerforationStrip(mode: mode).padding(.bottom, 8)
        }
        .shadow(color: mode.accent.opacity(0.14), radius: 14, y: 5)
        // The ghost peeks ABOVE the hero box — centered, genuinely behind
        // the opaque card, only the head over the top edge (pill language).
        .background(alignment: .top) {
            WhisperEmberMascot(
                size: 58,
                isActive: false,
                expression: mode.signatureExpression,
                coachMode: mode,
                usesIntelligenceStyle: true
            )
            .frame(width: 58, height: 62)
            .offset(y: -36)
            .accessibilityHidden(true)
        }
    }

    /// Soonest scheduled premiere on or after today — "Aug 22" or an
    /// honest em-dash when nothing is on the calendar.
    private var nextPremiereLabel: String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        let today = Calendar.current.startOfDay(for: Date())
        let upcoming = studioService.films
            .compactMap { $0.featured_date.flatMap { parser.date(from: $0) } }
            .filter { $0 >= today }
            .min()
        guard let upcoming else { return "—" }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: upcoming)
    }

    private func studioDeskStat(value: String, label: String, icon: String, mode: WhisperEmberCoachMode) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(mode.deepAccent)
                Text(value)
                    .font(.system(size: 15, weight: .black).monospacedDigit())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(mode.accent.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(mode.accent.opacity(0.22), lineWidth: 1)
        }
    }

    private func studioPerforationStrip(mode: WhisperEmberCoachMode) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<16, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(mode.accent.opacity(0.18))
                    .frame(width: 9, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Native iOS segmented control for switching between studio workflows.
    /// Keeps the phone dashboard from becoming one endless scroll.
    private var studioTabPicker: some View {
        HStack(spacing: 0) {
            ForEach(StudioTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) { studioTab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.caption2.weight(.bold))
                        Text(tab.rawValue)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(studioTab == tab ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(studioTab == tab ? WhisperTheme.ink(colorScheme) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
    }
}

// MARK: - Films hub

/// Combined "Films" tab — published films, public shelf preview, and quick
/// link to the live site. Replaces the two separate film cards so the phone
/// dashboard stays focused.
struct StudioFilmsHub: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperStudioService.shared
    @State private var showFilmOnSite: Bool = false
    /// Tapping a slate row screens the film in the real theater — hydrated
    /// through the same engagement service the feed cards use.
    @State private var screeningFilm: WhisperFeedFilm?
    @State private var presentingScreening: Bool = false
    @State private var hydratingFilmID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.subheadline.weight(.bold))
                Text("Your films")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button {
                    Haptics.tap()
                    showFilmOnSite = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption2.weight(.bold))
                        Text("Public site")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.ink(colorScheme).opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))

            if service.isLoadingFilms && service.films.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(WhisperTheme.muted(colorScheme))
                    Text("Loading films…")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if service.films.isEmpty {
                WhisperStudioEmptyState(
                    icon: "film.stack",
                    title: "No published films yet",
                    subtitle: "Upload your first short film and schedule a Friday premiere."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(service.films.prefix(8)) { film in
                        studioFilmRow(film)
                    }
                }
                Text("Tap a film to screen it in the theater — exactly what viewers see.")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .task { await service.refreshFilms() }
        .sheet(isPresented: $showFilmOnSite) {
            if let url = URL(string: "\(WhisperBillingBackend.webOrigin)/films") {
                WhisperPitchSafariSheet(url: url)
            }
        }
        .fullScreenCover(isPresented: $presentingScreening) {
            if let screeningFilm {
                WhisperFilmDetailView(film: screeningFilm)
            }
        }
    }

    /// Hydrate the studio row into the real feed film and open the theater.
    private func screen(_ film: WhisperStudioFilm) {
        Haptics.tap()
        guard hydratingFilmID == nil else { return }
        hydratingFilmID = film.id
        Task {
            let fetched = await WhisperFilmEngagementService.shared.fetchFilm(id: film.id)
            await MainActor.run {
                hydratingFilmID = nil
                if let fetched {
                    screeningFilm = fetched
                    presentingScreening = true
                } else {
                    Haptics.warning()
                }
            }
        }
    }

    @ViewBuilder
    private func studioFilmRow(_ film: WhisperStudioFilm) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black)
                if let p = film.poster_url, let url = URL(string: p) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "film.fill")
                                .foregroundStyle(.white.opacity(0.5))
                                .font(.caption)
                        }
                    }
                } else {
                    Image(systemName: "film.fill")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.caption)
                }
            }
            .frame(width: 80, height: 50)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(film.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let date = film.featured_date, !date.isEmpty {
                        Label(date, systemImage: "calendar")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    } else {
                        Text("Unscheduled")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    if let duration = film.duration_seconds, duration > 0 {
                        Text("• \(duration)s")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
            }
            Spacer()
            if hydratingFilmID == film.id {
                ProgressView()
                    .controlSize(.small)
                    .tint(WhisperTheme.muted(colorScheme))
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.8))
            }
        }
        .padding(10)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
        .contentShape(.rect)
        .onTapGesture { screen(film) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Screen \(film.title)")
    }
}

// MARK: - Empty state

struct WhisperStudioEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: icon, height: 120)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Publish film card

/// Upload + publish a new film. The director picks a video (and an optional
/// poster) from Photos, fills in the metadata, and schedules the Friday
/// premiere. Mirrors the web PublishFilmSection.
struct PublishFilmCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperStudioService.shared

    @State private var title: String = ""
    @State private var synopsis: String = ""
    @State private var durationText: String = ""
    @State private var featuredDate: Date = Date()
    @State private var hasFeaturedDate: Bool = false
    @State private var published: Bool = true

    @State private var videoItem: PhotosPickerItem?
    @State private var posterItem: PhotosPickerItem?
    @State private var trailerItem: PhotosPickerItem?
    @State private var videoURL: String?
    @State private var posterURL: String?
    @State private var trailerURL: String?
    @State private var uploadingVideo: Bool = false
    @State private var uploadingPoster: Bool = false
    @State private var uploadingTrailer: Bool = false
    @State private var isPublishing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.bold))
                Text("Upload a film")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))

            WhisperStudioTextField(text: $title, placeholder: "Film title")

            WhisperStudioTextEditor(text: $synopsis, placeholder: "Synopsis — what's this film about?", height: 84)

            // Video picker
            VStack(alignment: .leading, spacing: 6) {
                Text("FILM FILE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.black)
                        if let videoURL, let url = URL(string: videoURL) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "film.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        } else {
                            Image(systemName: "film.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 96, height: 56)
                    .clipShape(.rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        PhotosPicker(selection: $videoItem, matching: .videos) {
                            HStack(spacing: 5) {
                                if uploadingVideo { ProgressView().controlSize(.small) }
                                else { Image(systemName: "film") }
                                Text(videoURL == nil ? "Upload video" : "Replace video")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(WhisperTheme.ink(colorScheme).opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if videoURL != nil {
                            Button {
                                videoURL = nil
                            } label: {
                                Text("Remove")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
            }

            // Trailer picker
            VStack(alignment: .leading, spacing: 6) {
                Text("TRAILER (OPTIONAL)")
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.black)
                        if let trailerURL, let url = URL(string: trailerURL) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "film.fill")
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        } else {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 96, height: 56)
                    .clipShape(.rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        PhotosPicker(selection: $trailerItem, matching: .videos) {
                            HStack(spacing: 5) {
                                if uploadingTrailer { ProgressView().controlSize(.small) }
                                else { Image(systemName: "play.rectangle") }
                                Text(trailerURL == nil ? "Upload trailer" : "Replace trailer")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(WhisperTheme.ink(colorScheme).opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if trailerURL != nil {
                            Button {
                                trailerURL = nil
                            } label: {
                                Text("Remove")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
            }

            // Cover photo picker
            VStack(alignment: .leading, spacing: 6) {
                Text("COVER PHOTO")
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("This image is used in the feed, the Films page, and the Friday premiere card.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(2)
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(WhisperTheme.card(colorScheme))
                        if let posterURL, let url = URL(string: posterURL) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "photo")
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                            }
                        } else {
                            Image(systemName: "photo")
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                    .frame(width: 96, height: 56)
                    .clipShape(.rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        PhotosPicker(selection: $posterItem, matching: .images) {
                            HStack(spacing: 5) {
                                if uploadingPoster { ProgressView().controlSize(.small) }
                                else { Image(systemName: "photo") }
                                Text(posterURL == nil ? "Upload cover photo" : "Replace cover photo")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(WhisperTheme.ink(colorScheme).opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if posterURL != nil {
                            Button {
                                posterURL = nil
                            } label: {
                                Text("Remove")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
            }

            // Duration
            WhisperStudioTextField(text: $durationText, placeholder: "Duration (sec)", keyboard: .numberPad)

            // Featured date toggle + picker
            Toggle(isOn: $hasFeaturedDate) {
                Text("Schedule premiere")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .tint(WhisperTheme.ink(colorScheme))

            if hasFeaturedDate {
                DatePicker("Premiere date", selection: $featuredDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            Toggle(isOn: $published) {
                Text("Publish immediately")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .tint(WhisperTheme.ink(colorScheme))

            Button {
                Task { await publish() }
            } label: {
                HStack(spacing: 8) {
                    if isPublishing {
                        ProgressView().tint(WhisperTheme.surface(colorScheme))
                    } else {
                        Image(systemName: "film.fill")
                    }
                    Text(isPublishing ? "Publishing…" : "Publish film")
                        .font(.body.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(WhisperMenuPressStyle())
            .disabled(isPublishing || title.trimmingCharacters(in: .whitespaces).isEmpty || videoURL == nil)
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .onChange(of: videoItem) { _, item in
            Task { await uploadVideo(item) }
        }
        .onChange(of: posterItem) { _, item in
            Task { await uploadPoster(item) }
        }
        .onChange(of: trailerItem) { _, item in
            Task { await uploadTrailer(item) }
        }
    }

    private func uploadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploadingVideo = true
        defer { uploadingVideo = false }
        if let url = await service.uploadVideo(from: item) {
            videoURL = url
        }
    }

    private func uploadTrailer(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploadingTrailer = true
        defer { uploadingTrailer = false }
        if let url = await service.uploadTrailer(from: item) {
            trailerURL = url
        }
    }

    private func uploadPoster(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploadingPoster = true
        defer { uploadingPoster = false }
        if let url = await service.uploadPoster(from: item) {
            posterURL = url
        }
    }

    private func publish() async {
        isPublishing = true
        defer { isPublishing = false }
        let duration = Int(durationText.trimmingCharacters(in: .whitespaces)) ?? 0
        let dateStr: String?
        if hasFeaturedDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            dateStr = f.string(from: featuredDate)
        } else {
            dateStr = nil
        }
        let result = await service.createFilm(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            synopsis: synopsis.trimmingCharacters(in: .whitespacesAndNewlines),
            videoURL: videoURL ?? "",
            trailerURL: trailerURL,
            posterURL: posterURL,
            durationSeconds: duration > 0 ? duration : nil,
            featuredDate: dateStr,
            published: published
        )
        switch result {
        case .success:
            Haptics.success()
            title = ""
            synopsis = ""
            durationText = ""
            videoURL = nil
            trailerURL = nil
            posterURL = nil
            hasFeaturedDate = false
        case .failure(let msg):
            Haptics.warning()
            service.lastErrorMessage = msg
        }
    }
}

// MARK: - Jasper studio tools card

/// The director-tuned Jasper assistant tools — real Jasper (WhisperEmberService)
/// with prompts shaped around what a Whisper media team director needs.
/// Opens in a real sheet with an interactive back-and-forth thread.
struct EmberStudioToolsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var openTool: WhisperStudioEmberTool?
    @State private var tilesAppeared: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                WhisperEmberBadge(size: 20)
                Text("Jasper toolbox")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Text("The real Jasper assistant, tuned for the media team. Pick a tool and work through it together.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(WhisperStudioEmberTool.allCases.enumerated()), id: \.element.id) { index, tool in
                    Button {
                        Haptics.tap()
                        openTool = tool
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 11)
                                    .fill(
                                        LinearGradient(
                                            colors: [tool.tint, tool.tint.opacity(0.72)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Image(systemName: tool.icon)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 34, height: 34)
                            .shadow(color: tool.tint.opacity(0.4), radius: 6, y: 3)
                            Text(tool.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text(tool.tagline)
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(tool.tint.opacity(0.26), lineWidth: 1)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(WhisperMenuPressStyle())
                    // Staggered set-call — tiles rise in one after another.
                    .opacity(tilesAppeared ? 1 : 0)
                    .offset(y: tilesAppeared ? 0 : 16)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.8)
                            .delay(Double(index) * 0.05),
                        value: tilesAppeared
                    )
                }
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .onAppear { tilesAppeared = true }
        .sheet(item: $openTool) { tool in
            WhisperStudioEmberSheet(tool: tool)
                .whisperSheetBorder()
        }
    }
}

// MARK: - Published films card

/// List of the director's published films, loaded from `whisper_films`.
struct PublishedFilmsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperStudioService.shared

    var body: some View {
        Group {
            if service.isLoadingFilms {
                HStack(spacing: 8) {
                    ProgressView().tint(WhisperTheme.muted(colorScheme))
                    Text("Loading films…")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if !service.films.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Published films")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    ForEach(service.films, id: \.id) { film in
                        filmRow(film)
                    }
                }
                .padding(16)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            }
        }
        .task {
            await service.refreshFilms()
        }
    }

    @ViewBuilder
    private func filmRow(_ film: WhisperStudioFilm) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black)
                if let p = film.poster_url, let url = URL(string: p) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "film.fill")
                                .foregroundStyle(.white.opacity(0.5))
                                .font(.caption)
                        }
                    }
                } else {
                    Image(systemName: "film.fill")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.caption)
                }
            }
            .frame(width: 64, height: 40)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(film.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text(film.featured_date ?? "Unscheduled")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
        }
    }
}

// MARK: - Director articles card

/// A director's article workspace — write the companion piece (director's
/// note, review, behind-the-scenes) right in the studio, with edit/delete.
/// Mirrors the web `DirectorStudio` article composer. Reuses the shared
/// `WhisperArticlesService` so the byline is locked server-side.
struct DirectorArticlesCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperArticlesService.shared
    @State private var showEditor: Bool = false
    @State private var editingArticle: WhisperArticle?
    @State private var newArticle: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline.weight(.bold))
                Text("Director's articles")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))

            Text("Write the companion piece — a director's note, review, or behind-the-scenes essay — and tag it to one of your films. Published articles show on the public site and in the in-app feed.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))

            Button {
                Haptics.tap()
                newArticle = true
                editingArticle = nil
                showEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Write new article")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)

            if service.isLoading && service.myArticles.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(WhisperTheme.muted(colorScheme))
                    Text("Loading articles…")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if !service.myArticles.isEmpty {
                VStack(spacing: 8) {
                    ForEach(service.myArticles.prefix(5)) { article in
                        articleRow(article)
                    }
                }
            }
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .task { await service.fetchMyArticles() }
        .sheet(isPresented: $showEditor) {
            WhisperArticleEditorView(article: newArticle ? nil : editingArticle)
        }
    }

    @ViewBuilder
    private func articleRow(_ article: WhisperArticle) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(article.category ?? "Film")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    if !article.published {
                        Text("DRAFT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 0.92, green: 0.63, blue: 0.18))
                    }
                }
            }
            Spacer()
            Button {
                Haptics.tap()
                newArticle = false
                editingArticle = article
                showEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                Haptics.warning()
                Task { await service.deleteArticle(id: article.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }
}

// MARK: - Featured films card

/// The public Featured Film Friday shelf — shows every published film so a
/// director can see what's live on the site without leaving the studio.
/// Tapping a film opens it in the in-app browser so the director can preview
/// the public premiere page.
struct FeaturedFilmsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var service = WhisperStudioService.shared
    @State private var showFilmOnSite: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "film.circle.fill")
                    .font(.subheadline.weight(.bold))
                Text("Featured Film Friday")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))

            if service.films.isEmpty {
                Text("No films published yet. Upload one above and schedule its Friday premiere — it'll show up here and on the public site.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            } else {
                VStack(spacing: 8) {
                    ForEach(service.films.prefix(6)) { film in
                        filmRow(film)
                    }
                }
            }

            Button {
                Haptics.tap()
                showFilmOnSite = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open public films page")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(WhisperTheme.ink(colorScheme).opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .task { await service.refreshFilms() }
        .sheet(isPresented: $showFilmOnSite) {
            if let url = URL(string: "\(WhisperBillingBackend.webOrigin)/films") {
                WhisperPitchSafariSheet(url: url)
            }
        }
    }

    @ViewBuilder
    private func filmRow(_ film: WhisperStudioFilm) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black)
                if let p = film.poster_url, let url = URL(string: p) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "film.fill")
                                .foregroundStyle(.white.opacity(0.5))
                                .font(.caption)
                        }
                    }
                } else {
                    Image(systemName: "film.fill")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.caption)
                }
            }
            .frame(width: 64, height: 40)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(film.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text(film.featured_date ?? "Unscheduled")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
        }
    }
}

// MARK: - Jasper tool sheet

/// The Jasper tool sheet — a real back-and-forth with Jasper. Jasper opens
/// with a targeted question, the director replies, and Jasper responds.
struct WhisperStudioEmberSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let tool: WhisperStudioEmberTool

    @State private var seed: String = ""
    @State private var phase: SeedPhase = .seed
    @State private var turns: [EmberTurn] = []
    @State private var input: String = ""
    @State private var isThinking: Bool = false
    @State private var isGeneratingPoster: Bool = false
    @State private var hasGeneratedPoster: Bool = false
    @State private var mode: WhisperEmberCoachMode = WhisperEmberCoachMode.load()
    private let openAIService = OpenAIService()

    var body: some View {
        ZStack {
            // The same living Jasper canvas as the studio itself — the tool
            // room is part of the production floor, not a plain form.
            WhisperJasperIntelligenceBackdrop()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                toolHeader
                if phase == .seed {
                    seedView
                } else {
                    chatView
                }
            }
        }
        .onAppear { mode = WhisperEmberCoachMode.load() }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// Custom header — the mint pill with the living mascot peeking from
    /// behind it (the exact dock language), close circle on the left.
    private var toolHeader: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(WhisperTheme.ink(colorScheme).opacity(0.07), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                WhisperJasperIntelligencePill(compact: true, working: isThinking || isGeneratingPoster)
                Text(tool.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    private var seedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Tool marquee — the gradient tile from the toolbox, blown up.
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [tool.tint, tool.tint.opacity(0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: tool.icon)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)
                    .shadow(color: tool.tint.opacity(0.4), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.label)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text(tool.tagline)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(tool.tint.opacity(0.3), lineWidth: 1)
                }

                Text("Tell Jasper what you're working on — he asks one sharp question, then you build it together.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))

                if !starterChips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FAST STARTS")
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.4)
                            .foregroundStyle(mode.deepAccent)
                        ForEach(starterChips, id: \.self) { starter in
                            Button {
                                Haptics.tap()
                                seed = starter
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(mode.deepAccent)
                                    Text(starter)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(mode.accent.opacity(0.09), in: .rect(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(mode.accent.opacity(0.22), lineWidth: 1)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextEditor(text: $seed)
                    .font(.body)
                    .frame(height: 100)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(mode.accent.opacity(0.3), lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if seed.isEmpty {
                            Text(tool.seedPlaceholder)
                                .font(.body)
                                .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.6))
                                .padding(.leading, 12)
                                .padding(.top, 12)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    Task { await start() }
                } label: {
                    HStack(spacing: 8) {
                        if isThinking {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isThinking ? "Jasper is preparing…" : "Start with Jasper")
                            .font(.body.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [mode.deepAccent, mode.deepAccent.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: mode.deepAccent.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(WhisperMenuPressStyle())
                .disabled(isThinking || seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Tool-tailored seeds plus real films off the slate — one tap fills
    /// the brief so the room never starts cold.
    private var starterChips: [String] {
        var chips = tool.starters
        for film in WhisperStudioService.shared.films.prefix(2) {
            chips.append(tool.filmStarter(title: film.title))
        }
        return Array(chips.prefix(4))
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(turns) { turn in
                            turnBubble(turn).id(turn.id)
                        }
                        if isThinking || isGeneratingPoster {
                            WhisperEmberThinkingSteps(
                                coachMode: mode,
                                resolvedLabel: nil,
                                isAnalytical: false,
                                onDark: colorScheme == .dark,
                                flavor: .meeting,
                                listenState: .hidden
                            )
                            .padding(.horizontal, 16)
                            .id("thinking")
                        }
                    }
                    .padding(.vertical, 14)
                }
                .onChange(of: turns.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(turns.last?.id, anchor: .bottom)
                    }
                }
            }
            composer
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Reply to Jasper…", text: $input, axis: .vertical)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(mode.accent.opacity(0.25), lineWidth: 1)
                }
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(mode.deepAccent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isThinking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(isThinking || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Jasper turns render as the dock's reply card — JASPER kicker with
    /// the personality chip, tinted accent bar, rich styled text. Director
    /// turns stay as ink bubbles on the trailing edge.
    @ViewBuilder
    private func turnBubble(_ turn: EmberTurn) -> some View {
        if turn.role == .ember {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(mode.deepAccent)
                    Text("JASPER")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(mode.deepAccent)
                    Spacer(minLength: 6)
                    Text(mode.shortTitle.uppercased())
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(WhisperTheme.ink(colorScheme).opacity(0.06), in: Capsule())
                }
                WhisperEmberRichText(text: turn.text, onDark: colorScheme == .dark, baseSize: 15)
                if let imageData = turn.image, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(mode.accent.opacity(0.3), lineWidth: 1)
                        }
                        .shadow(color: tool.tint.opacity(0.25), radius: 12, y: 5)
                }
            }
            .padding(.vertical, 12)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                WhisperTheme.card(colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.8),
                in: .rect(cornerRadius: 18)
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(mode.accent.opacity(0.7))
                    .frame(width: 3)
                    .padding(.vertical, 12)
                    .padding(.leading, 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(mode.accent.opacity(0.2), lineWidth: 1)
            }
            .padding(.horizontal, 16)
        } else {
            HStack {
                Spacer(minLength: 40)
                Text(turn.text)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 16))
            }
            .padding(.horizontal, 16)
        }
    }

    private func start() async {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .chat
        turns = [EmberTurn(role: .director, text: trimmed, image: nil)]
        await runEmber(tool.opener(trimmed))
    }

    private func send() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        input = ""
        turns.append(EmberTurn(role: .director, text: trimmed, image: nil))
        let history = turns.map { t in
            t.role == .director ? "Director: \(t.text)" : "Jasper: \(t.text)"
        }.joined(separator: "\n")
        let prompt = """
        \(tool.system)

        Conversation so far:
        \(history)

        Director: \(trimmed)

        Continue as Jasper. Stay in character, keep it short, and ask the next useful question if it helps move the work forward.
        """
        await runEmber(prompt)
        // For the poster tool: once the director has answered the opener
        // question, ask Jasper for a single image-generation prompt and then
        // generate the poster with OpenAIService.generateImage.
        if tool.generatesPoster, !hasGeneratedPoster, !isGeneratingPoster {
            await maybeGeneratePoster()
        }
    }

    /// Ask Jasper to turn the conversation into a single image-generation
    /// prompt, then generate the poster image. Renders the image inline.
    private func maybeGeneratePoster() async {
        isGeneratingPoster = true
        defer { isGeneratingPoster = false }
        let history = turns.map { t in
            t.role == .director ? "Director: \(t.text)" : "Jasper: \(t.text)"
        }.joined(separator: "\n")
        let promptRequest = """
        \(tool.system)

        Conversation so far:
        \(history)

        Now write a single, vivid image-generation prompt for the movie poster. One sentence: composition, subject, palette, lighting, and negative space for the title. Do not include any other text.
        """
        let imagePrompt = await WhisperEmberService.shared.ask(promptRequest)
        guard !imagePrompt.isEmpty else { return }
        do {
            let imageData = try await openAIService.generateImage(prompt: imagePrompt)
            hasGeneratedPoster = true
            turns.append(EmberTurn(role: .ember, text: "Here's your poster. Save it or ask me to try a different mood.", image: imageData))
        } catch {
            turns.append(EmberTurn(role: .ember, text: "I couldn't generate the poster just now — try again in a moment.", image: nil))
        }
    }

    private func runEmber(_ prompt: String) async {
        isThinking = true
        defer { isThinking = false }
        let reply = await WhisperEmberService.shared.ask(prompt)
        turns.append(EmberTurn(role: .ember, text: reply, image: nil))
    }
}

private enum SeedPhase { case seed, chat }

private struct EmberTurn: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    /// Optional generated poster image (poster tool only).
    var image: Data?
    enum Role { case ember, director }
}

// MARK: - Studio service

/// Backend + storage service for Whisper Studio. Uploads film files to
/// `whisper-media`, publishes films via `/films/create`, and loads the
/// published films list.
@MainActor
@Observable
final class WhisperStudioService {
    static let shared = WhisperStudioService()

    var films: [WhisperStudioFilm] = []
    var isLoadingFilms: Bool = false
    var lastErrorMessage: String?

    private let client = SupabaseService.shared.client
    private var currentUID: String { AccountStorage.currentUserID.lowercased() }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    // MARK: - Uploads

    func uploadVideo(from item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await uploadData(data, ext: "mp4", contentType: "video/mp4")
    }

    /// Trailer upload — same storage path as the full film, just a separate
    /// file. Shown on any article written about this film.
    func uploadTrailer(from item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await uploadData(data, ext: "mp4", contentType: "video/mp4")
    }

    func uploadPoster(from item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
        return await uploadData(jpeg, ext: "jpg", contentType: "image/jpeg")
    }

    private func uploadData(_ data: Data, ext: String, contentType: String) async -> String? {
        guard isRemote, !data.isEmpty else { return nil }
        let path = "\(currentUID)/studio/\(UUID().uuidString).\(ext)"
        do {
            _ = try await client.storage
                .from("whisper-media")
                .upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: contentType, upsert: true))
            let url = try client.storage.from("whisper-media").getPublicURL(path: path)
            return url.absoluteString
        } catch {
            lastErrorMessage = "Couldn't upload the file. Try again."
            return nil
        }
    }

    // MARK: - Films

    func refreshFilms() async {
        guard isRemote else { return }
        isLoadingFilms = true
        defer { isLoadingFilms = false }
        do {
            nonisolated struct Row: Codable, Sendable {
                let id: String
                let title: String
                let synopsis: String?
                let video_url: String
                let poster_url: String?
                let duration_seconds: Int?
                let featured_date: String?
                let published: Bool
            }
            let rows: [Row] = try await client
                .from("whisper_films")
                .select("id,title,synopsis,video_url,poster_url,duration_seconds,featured_date,published")
                .eq("published", value: true)
                .order("featured_date", ascending: false)
                .order("created_at", ascending: false)
                .limit(30)
                .execute()
                .value
            films = rows.map {
                WhisperStudioFilm(
                    id: $0.id,
                    title: $0.title,
                    synopsis: $0.synopsis,
                    video_url: $0.video_url,
                    poster_url: $0.poster_url,
                    duration_seconds: $0.duration_seconds,
                    featured_date: $0.featured_date
                )
            }
        } catch {
            // Silent — the card just hides.
        }
    }

    /// Fetches published films with director profiles joined, shaped for the
    /// feed carousel. Tries the backend first (so the director's profile is
    /// joined server-side), then falls back to a direct Supabase read with
    /// client-side director hydration. Returns up to 12 films — the feed shelf
    /// only shows the first few.
    func fetchFeedFilms() async -> [WhisperFeedFilm] {
        guard isRemote else { return [] }
        // Backend first — joins director_name + director_username.
        if let url = URL(string: "\(WhisperBillingBackend.url)/films") {
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    struct FilmsResponse: Decodable { let films: [BackendFilmRow]? }
                    struct BackendFilmRow: Decodable, Sendable {
                        let id: String
                        let title: String
                        let synopsis: String?
                        let video_url: String
                        let poster_url: String?
                        let duration_seconds: Int?
                        let featured_date: String?
                        let director_id: String?
                        let director_name: String?
                        let director_username: String?
                    }
                    let body = try JSONDecoder().decode(FilmsResponse.self, from: data)
                    return (body.films ?? []).map {
                        WhisperFeedFilm(
                            id: $0.id,
                            title: $0.title,
                            synopsis: $0.synopsis,
                            video_url: $0.video_url,
                            poster_url: $0.poster_url,
                            duration_seconds: $0.duration_seconds,
                            featured_date: $0.featured_date,
                            director_id: $0.director_id,
                            director_name: $0.director_name,
                            director_username: $0.director_username
                        )
                    }
                }
            } catch {
                // Fall through to the Supabase read.
            }
        }
        // Supabase fallback — fetch films, then batch-hydrate director profiles.
        do {
            nonisolated struct FilmRow: Codable, Sendable {
                let id: String
                let director_id: String?
                let title: String
                let synopsis: String?
                let video_url: String
                let poster_url: String?
                let duration_seconds: Int?
                let featured_date: String?
            }
            let rows: [FilmRow] = try await client
                .from("whisper_films")
                .select("id,director_id,title,synopsis,video_url,poster_url,duration_seconds,featured_date")
                .eq("published", value: true)
                .order("featured_date", ascending: false)
                .order("created_at", ascending: false)
                .limit(12)
                .execute()
                .value
            // Batch-fetch director profiles.
            let directorIds = Array(Set(rows.compactMap { $0.director_id })).filter { !$0.isEmpty }
            var profileMap: [String: (String?, String?)] = [:]
            if !directorIds.isEmpty {
                nonisolated struct ProfileRow: Codable, Sendable {
                    let user_id: String
                    let username: String?
                    let display_name: String?
                }
                let profiles: [ProfileRow] = (try? await client
                    .from("whisper_profiles")
                    .select("user_id,username,display_name")
                    .in("user_id", values: directorIds)
                    .execute()
                    .value) ?? []
                for p in profiles {
                    profileMap[p.user_id] = (p.username, p.display_name)
                }
            }
            return rows.map { row in
                let (uname, dname) = profileMap[row.director_id ?? ""] ?? (nil, nil)
                return WhisperFeedFilm(
                    id: row.id,
                    title: row.title,
                    synopsis: row.synopsis,
                    video_url: row.video_url,
                    poster_url: row.poster_url,
                    duration_seconds: row.duration_seconds,
                    featured_date: row.featured_date,
                    director_id: row.director_id,
                    director_name: dname,
                    director_username: uname
                )
            }
        } catch {
            return []
        }
    }

    enum CreateResult {
        case success
        case failure(String)
    }

    func createFilm(
        title: String,
        synopsis: String,
        videoURL: String,
        trailerURL: String?,
        posterURL: String?,
        durationSeconds: Int?,
        featuredDate: String?,
        published: Bool
    ) async -> CreateResult {
        guard isRemote else { return .failure("Sign in to publish films.") }
        guard !title.isEmpty, !videoURL.isEmpty else { return .failure("Add a title and upload the video.") }

        nonisolated struct Body: Encodable {
            let title: String
            let synopsis: String
            let videoUrl: String
            let trailerUrl: String
            let posterUrl: String
            let durationSeconds: Int?
            let featuredDate: String?
            let published: Bool
        }
        let body = Body(
            title: title,
            synopsis: synopsis,
            videoUrl: videoURL,
            trailerUrl: trailerURL ?? "",
            posterUrl: posterURL ?? "",
            durationSeconds: durationSeconds,
            featuredDate: featuredDate,
            published: published
        )

        guard let url = URL(string: "\(WhisperBillingBackend.url)/films/create") else {
            return .failure("Couldn't reach the backend.")
        }
        do {
            let token = try await client.auth.session.accessToken
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let code = (json?["error"] as? String) ?? "save_failed"
                return .failure(self.friendlyMessage(for: code))
            }
            await refreshFilms()
            return .success
        } catch {
            return .failure("Couldn't publish that film. Try again.")
        }
    }

    private func friendlyMessage(for code: String) -> String {
        switch code {
        case "forbidden": return "Your account can't publish films."
        case "title_required": return "Add a film title."
        case "video_url_required": return "Upload the video file."
        case "save_failed": return "Couldn't save the film. Try again."
        default: return "Couldn't publish that film. Try again."
        }
    }
}

struct WhisperStudioFilm: Identifiable, Sendable {
    let id: String
    let title: String
    let synopsis: String?
    let video_url: String
    let poster_url: String?
    let duration_seconds: Int?
    let featured_date: String?
}

// MARK: - Jasper tools catalog

/// The director-tuned Jasper tools. Each tool shapes Jasper's system prompt
/// and opener so the assistant asks the right first question for that tool.
enum WhisperStudioEmberTool: String, CaseIterable, Identifiable {
    case writersBlock, shotList, synopsisPolish, titleIdeas, releasePlan, directorsStatement, readTheFilm, posterConcept

    var id: String { rawValue }

    var label: String {
        switch self {
        case .writersBlock:        return "Writer's block"
        case .shotList:            return "Shot list"
        case .synopsisPolish:      return "Synopsis polish"
        case .titleIdeas:          return "Title ideas"
        case .releasePlan:         return "Release plan"
        case .directorsStatement:  return "Director's note"
        case .readTheFilm:         return "Read the film"
        case .posterConcept:       return "Movie poster"
        }
    }

    var tagline: String {
        switch self {
        case .writersBlock:        return "Find the opening hook"
        case .shotList:            return "Plan the coverage"
        case .synopsisPolish:      return "Tighten the logline"
        case .titleIdeas:          return "Name the film"
        case .releasePlan:         return "Plan the premiere"
        case .directorsStatement:  return "Write the statement"
        case .readTheFilm:         return "Jasper reads your film"
        case .posterConcept:       return "Generate a poster"
        }
    }

    var icon: String {
        switch self {
        case .writersBlock:        return "wand.and.stars"
        case .shotList:            return "film"
        case .synopsisPolish:      return "pencil.line"
        case .titleIdeas:          return "sparkles"
        case .releasePlan:         return "calendar.badge.plus"
        case .directorsStatement:  return "megaphone.fill"
        case .readTheFilm:         return "doc.text.magnifyingglass"
        case .posterConcept:       return "photo.on.rectangle.angled"
        }
    }

    /// Signature tint for the tool's icon tile — keeps every glyph clearly
    /// visible in light and dark mode.
    var tint: Color {
        switch self {
        case .writersBlock:        return Color(red: 0.66, green: 0.48, blue: 0.98)
        case .shotList:            return Color(red: 0.30, green: 0.62, blue: 1.00)
        case .synopsisPolish:      return Color(red: 0.20, green: 0.76, blue: 0.70)
        case .titleIdeas:          return Color(red: 0.96, green: 0.70, blue: 0.16)
        case .releasePlan:         return Color(red: 0.26, green: 0.80, blue: 0.50)
        case .directorsStatement:  return Color(red: 0.97, green: 0.46, blue: 0.36)
        case .readTheFilm:         return Color(red: 0.50, green: 0.56, blue: 0.99)
        case .posterConcept:       return Color(red: 0.95, green: 0.42, blue: 0.70)
        }
    }

    var seedPlaceholder: String {
        switch self {
        case .synopsisPolish:  return "Paste your current synopsis…"
        case .readTheFilm:     return "Paste your synopsis — Jasper will read the whole thing…"
        case .posterConcept:   return "What's the film about? Jasper will ask about the mood, then generate a poster…"
        case .releasePlan:     return "What film are you scheduling?"
        default:               return "What's the film about?"
        }
    }

    /// Whether this tool generates a poster image (triggers the image
    /// generation step once Jasper has the mood + anchor image).
    var generatesPoster: Bool { self == .posterConcept }

    /// Ready-made briefs for the tool's fast-start chips.
    var starters: [String] {
        switch self {
        case .writersBlock:
            return ["A lifter chasing their first meet after an injury", "A 5am running crew that became a family"]
        case .shotList:
            return ["One-location gym shoot, two athletes, natural light"]
        case .synopsisPolish:
            return []
        case .titleIdeas:
            return ["A comeback story — raw and quiet, not heroic"]
        case .releasePlan:
            return []
        case .directorsStatement:
            return ["Why I filmed my own training year"]
        case .readTheFilm:
            return []
        case .posterConcept:
            return ["Stark portrait of a boxer mid-wrap, single hard light"]
        }
    }

    /// A fast-start line referencing a real film on the slate.
    func filmStarter(title: String) -> String {
        switch self {
        case .releasePlan:        return "Premiere plan for ‘\(title)’"
        case .directorsStatement: return "Director's note for ‘\(title)’"
        case .posterConcept:      return "Poster for ‘\(title)’"
        case .titleIdeas:         return "Alternate titles for ‘\(title)’"
        case .synopsisPolish:     return "Polish the synopsis of ‘\(title)’"
        case .readTheFilm:        return "Read my film ‘\(title)’"
        default:                  return "For my film ‘\(title)’"
        }
    }

    /// The director-tuned system prompt. Shapes Jasper's voice for the
    /// media team — cinematic, specific, practical.
    var system: String {
        let base = """
        You are Knot, the in-house creative assistant for the Whisper media team — a small studio that produces \
        short documentary films with fitness creators (lifters, runners, athletes). Your voice is cinematic, \
        specific, and practical. You think like a festival programmer and a working director: you care about \
        hook, structure, and what a small crew can actually shoot. Keep replies tight and vivid — no padding, \
        no generic advice. When you ask a question, ask one at a time, and make it specific enough that the \
        director can answer in a sentence.
        """
        switch self {
        case .readTheFilm:
            return base + "\n\nWhen reading a film, be specific and honest — name what's working and what's soft. Don't flatter. A director trusts you when you're precise."
        case .posterConcept:
            return base + "\n\nYou can also generate poster imagery. When the director gives you the mood and the anchor image, describe the poster as a single vivid image-generation prompt (composition, subject, palette, lighting, negative space for the title). Keep it to one sentence."
        default:
            return base
        }
    }

    /// The first message Jasper sends to kick off the tool.
    func opener(_ ctx: String) -> String {
        switch self {
        case .writersBlock:
            return "A director is stuck on a short film about: \"\(ctx)\". Before you pitch ideas, ask one specific question that will help you target the hook — about the subject, the stakes, or the moment that matters most."
        case .shotList:
            return "A director is planning coverage for: \"\(ctx)\". Ask one question about the location or the subject's movement so you can write a shot list a small crew can actually execute."
        case .synopsisPolish:
            return "Here's a working synopsis: \"\(ctx)\". Ask one question about the audience or the emotional core before you rewrite it into a tight, festival-catalogue logline."
        case .titleIdeas:
            return "A director needs a title for a short film about: \"\(ctx)\". Ask one question about the tone (raw, lyrical, punchy?) before you brainstorm."
        case .releasePlan:
            return "A director is scheduling a Featured Film Friday premiere for: \"\(ctx)\". Ask one question about the subject's availability or the community hook, then you'll shape a release plan around it."
        case .directorsStatement:
            return "A director is writing a director's statement for a film about: \"\(ctx)\". Ask one question about why they made this film before you draft the statement."
        case .readTheFilm:
            return "A director wants you to read their film. Here's the synopsis:\n\n\"\"\"\(ctx)\"\"\"\n\nGive them a tight structural read: the hook, the arc, the emotional core, and one moment that's working hardest. Then ask one question about what they want to strengthen — pacing, stakes, or the ending."
        case .posterConcept:
            return "A director wants a movie poster for: \"\(ctx)\". Ask one question about the mood (stark, warm, heroic, intimate?) and the one image that should anchor the frame, then you'll generate it."
        }
    }
}

// MARK: - Reusable field components

private struct WhisperStudioTextField: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    let placeholder: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.body)
            .keyboardType(keyboard)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
    }
}

private struct WhisperStudioTextEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    let placeholder: String
    let height: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .frame(height: height)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.6))
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
    }
}
