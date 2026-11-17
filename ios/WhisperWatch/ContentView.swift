import SwiftUI

/// The wrist app — Whisper's SOCIAL pulse, crown-paged: Today (your counts +
/// who posted), Inbox (latest DMs), Activity, the shared calendar and the
/// coach's client roster when they apply, and Jasper's daily whisper.
/// Everything renders from the iPhone-synced snapshot — no network on-wrist.
/// Design language = the home-screen widgets: cream PAPER cards with ink
/// type on the black canvas, deep-mint accents, the heat gradient for
/// activity, and the REAL living mascot.
struct ContentView: View {
    @State private var store = WatchSocialStore()

    var body: some View {
        TabView {
            TodayPage(store: store)
            InboxPage(store: store)
            ActivityPage(store: store)
            if !store.events.isEmpty {
                CalendarPage(store: store)
            }
            if store.isCoach && !store.clients.isEmpty {
                ClientsPage(store: store)
            }
            JasperPage()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Shared pieces

/// Mint monogram disc — the wrist's avatar language (ink initial on mint).
struct WatchMonogram: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().fill(WatchTheme.mint.opacity(0.55))
            Text(watchDisplayName(name).first.map(String.init)?.uppercased() ?? "?")
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(WatchTheme.ink)
        }
        .frame(width: size, height: size)
    }
}

private func relativeTime(_ unix: Double) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: Date(timeIntervalSince1970: unix), relativeTo: Date())
}

// MARK: - Page 1 · Today

struct TodayPage: View {
    let store: WatchSocialStore

    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        WatchKicker(text: "WHISPER")
                        Text(dateLine)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(WatchTheme.dim)
                    }
                    Spacer()
                    WatchJasperGhost(size: 32, tilt: 4)
                }

                statCard(
                    icon: "paperplane.fill",
                    chip: WatchTheme.mint,
                    iconColor: WatchTheme.ink,
                    value: store.unread,
                    label: store.unread == 1 ? "unread message" : "unread messages"
                )
                statCard(
                    icon: "heart.fill",
                    chip: WatchTheme.heat,
                    iconColor: .white,
                    value: store.activityCount,
                    label: "new activity"
                )
                statCard(
                    icon: "person.2.fill",
                    chip: WatchTheme.deepMint,
                    iconColor: .white,
                    value: store.followers,
                    label: "followers"
                )

                if !store.storyAuthors.isEmpty {
                    storiesRail
                }

                syncFooter
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black)
    }

    private func statCard(icon: String, chip: Color, iconColor: Color, value: Int, label: String) -> some View {
        WatchPaperCard(padding: 9) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 22)
                    .background(chip, in: Circle())
                Text("\(value)")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchTheme.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
    }

    private var storiesRail: some View {
        WatchPaperCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STORIES")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(WatchTheme.deepMint)
                HStack(spacing: -6) {
                    ForEach(store.storyAuthors.prefix(5)) { author in
                        ZStack {
                            Circle()
                                .strokeBorder(
                                    AngularGradient(
                                        colors: [WatchTheme.deepMint, WatchTheme.mint, WatchTheme.deepMint],
                                        center: .center
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 30, height: 30)
                            WatchMonogram(name: author.name, size: 23)
                                .overlay(Circle().stroke(WatchTheme.cream, lineWidth: 1.5))
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text("\(max(store.storyCount, store.storyAuthors.count)) friends posted")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchTheme.deepMint)
            }
        }
    }

    @ViewBuilder
    private var syncFooter: some View {
        if let synced = store.lastSynced {
            Text("Synced \(relativeTime(synced.timeIntervalSince1970))")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(WatchTheme.dim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        } else {
            WatchPaperCard(padding: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Waiting for your iPhone")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchTheme.ink)
                    Text("Open Whisper on your iPhone once and your feed syncs here.")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(WatchTheme.inkDim)
                }
            }
        }
    }
}

// MARK: - Page 2 · Inbox

struct InboxPage: View {
    let store: WatchSocialStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    WatchKicker(text: "INBOX")
                    Spacer()
                    if store.unread > 0 {
                        WatchMintBadge(text: "\(store.unread) new")
                    }
                }

                if store.threads.isEmpty {
                    emptyPanel
                } else {
                    ForEach(store.threads) { thread in
                        threadRow(thread)
                    }
                    Text("Reply from Whisper on your iPhone.")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(WatchTheme.dim)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black)
    }

    private var emptyPanel: some View {
        WatchPaperCard(padding: 12) {
            VStack(spacing: 6) {
                WatchJasperGhost(size: 40, tilt: 5)
                Text(store.hasEverSynced ? "No messages yet" : "Nothing synced yet")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchTheme.ink)
                Text(store.hasEverSynced
                     ? "New DMs land here the moment they arrive."
                     : "Open Whisper on your iPhone to sync your inbox.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchTheme.inkDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func threadRow(_ thread: WatchThread) -> some View {
        WatchPaperCard(padding: 9) {
            HStack(spacing: 8) {
                WatchMonogram(name: thread.user, size: 26)
                    .overlay(alignment: .topTrailing) {
                        if thread.unread {
                            Circle().fill(WatchTheme.deepMint).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(WatchTheme.cream, lineWidth: 1.5))
                                .offset(x: 2, y: -2)
                        }
                    }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("@\(watchDisplayName(thread.user))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(WatchTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(relativeTime(thread.when))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(WatchTheme.inkDim)
                    }
                    Text(thread.fromMe ? "You: \(thread.preview)" : thread.preview)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(thread.unread ? WatchTheme.ink : WatchTheme.inkDim)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Page 3 · Activity

struct ActivityPage: View {
    let store: WatchSocialStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchKicker(text: "ACTIVITY")

                WatchPaperCard(padding: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(store.activityCount)")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                store.activityCount > 0
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [WatchTheme.heat, WatchTheme.deepMint],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    : AnyShapeStyle(WatchTheme.ink)
                            )
                        Text(store.activityCount == 1 ? "new ping" : "new pings")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(WatchTheme.inkDim)
                    }
                }

                if !store.activityPreview.isEmpty {
                    WatchPaperCard(padding: 10) {
                        Text(store.activityPreview)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(WatchTheme.ink)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 8) {
                    statPair(value: store.followers, label: "followers")
                    statPair(value: store.following, label: "following")
                }

                if !store.thought.isEmpty {
                    WatchPaperCard(padding: 10, tint: WatchTheme.mint.opacity(0.35)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TOP OF MIND")
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .tracking(1.5)
                                .foregroundStyle(WatchTheme.deepMint)
                            HStack(alignment: .top, spacing: 4) {
                                Text("\u{201C}")
                                    .font(.system(size: 26, weight: .black, design: .serif))
                                    .foregroundStyle(WatchTheme.deepMint)
                                    .offset(y: -2)
                                Text(store.thought)
                                    .font(.system(size: 12, weight: .semibold, design: .serif))
                                    .italic()
                                    .foregroundStyle(WatchTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black)
    }

    private func statPair(value: Int, label: String) -> some View {
        WatchPaperCard(padding: 8) {
            VStack(spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchTheme.inkDim)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Page 4 · Shared calendar (only when events exist)

struct CalendarPage: View {
    let store: WatchSocialStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    WatchKicker(text: "CALENDAR")
                    Spacer()
                    WatchMintBadge(text: "\(store.events.count)")
                }

                ForEach(store.events.prefix(4)) { event in
                    eventRow(event)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black)
    }

    private func eventRow(_ event: WatchEvent) -> some View {
        let date = Date(timeIntervalSince1970: event.when)
        return WatchPaperCard(padding: 9) {
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchTheme.deepMint)
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchTheme.ink)
                }
                .frame(width: 30, height: 30)
                .background(WatchTheme.mint.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchTheme.ink)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        if event.link {
                            Image(systemName: "video.fill")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(WatchTheme.deepMint)
                        }
                        Text(date.formatted(date: .omitted, time: .shortened) + (event.host.map { " · @\(watchDisplayName($0))" } ?? ""))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(WatchTheme.inkDim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Page 5 · Clients (coaches only)

struct ClientsPage: View {
    let store: WatchSocialStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    WatchKicker(text: "CLIENTS")
                    Spacer()
                    WatchMintBadge(text: "\(store.clients.count)")
                }

                ForEach(store.clients) { client in
                    clientRow(client)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black)
    }

    private func clientRow(_ client: WatchClient) -> some View {
        WatchPaperCard(padding: 9) {
            HStack(spacing: 8) {
                WatchMonogram(name: client.name, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(client.name)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WatchTheme.ink)
                        .lineLimit(1)
                    Text(sinceLine(client))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(WatchTheme.inkDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func sinceLine(_ client: WatchClient) -> String {
        guard let since = client.since, since > 0 else { return "Active client" }
        let date = Date(timeIntervalSince1970: since)
        return "Client since \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

// MARK: - Page 6 · Jasper's daily whisper

struct JasperPage: View {
    /// One line a day, deterministic — the same whisper all day long.
    /// Social lines — Whisper is a social platform, and Jasper knows it.
    private static let whispers: [String] = [
        "Post the thing. Someone needs it today.",
        "Check on your quiet friends.",
        "One real comment beats ten likes.",
        "Send the first message.",
        "Density over reach — talk to your room.",
        "Reply like a person, not a brand.",
        "Your story doesn't need a filter.",
        "Go live scared. Leave proud.",
        "The feed rewards consistency, not volume.",
        "Share the win — your room is rooting for you.",
        "Lurk less. Belong more.",
        "Kindness compounds here.",
        "Truth told quietly is still a whisper.",
        "Make one person's day in the comments.",
    ]

    private var line: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return Self.whispers[day % Self.whispers.count]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // The auto-analysis dock — the living mascot peeking over the
                // mint "Jasper's read" capsule, exactly the in-app pill.
                WatchJasperGhost(size: 56, tilt: -3)
                    .offset(y: 14)
                    .zIndex(0)
                HStack(spacing: 4) {
                    Text("Jasper's read")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(WatchTheme.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(WatchTheme.ink.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(WatchTheme.mint, in: Capsule())
                .overlay(Capsule().strokeBorder(WatchTheme.deepMint.opacity(0.35), lineWidth: 1))
                .zIndex(1)

                WatchPaperCard(padding: 11) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TODAY'S WHISPER")
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(WatchTheme.deepMint)
                        HStack(alignment: .top, spacing: 4) {
                            Text("\u{201C}")
                                .font(.system(size: 28, weight: .black, design: .serif))
                                .foregroundStyle(WatchTheme.deepMint)
                                .offset(y: -3)
                            Text(line)
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .italic()
                                .foregroundStyle(WatchTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 5)
                        }
                    }
                }
                .padding(.top, 10)

                Text("Ask Jasper anything in Whisper on your iPhone.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchTheme.dim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black)
    }
}
