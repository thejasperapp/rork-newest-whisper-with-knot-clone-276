import SwiftUI

/// Meetings lobby — start an instant video meeting, schedule one with email
/// invites, share it by link, and review past meetings with their
/// AI-generated notes. Mirrors the web Meetings page.
struct WhisperMeetingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var service = WhisperMeetingService.shared
    @State private var title: String = ""
    @State private var starting: Bool = false
    @State private var joinCode: String = ""
    @State private var joining: Bool = false
    @State private var errorText: String?
    @State private var showSchedule: Bool = false
    @State private var showNotebook: Bool = false
    @State private var showCalendar: Bool = false
    @State private var showMeetSettings: Bool = false
    @State private var showReport: Bool = false
    @State private var showWorkspaceSearch: Bool = false
    @State private var copiedLink: String?
    @State private var launchGeneration: UUID = UUID()
    /// Ended meeting whose AI notes are open in the notes modal.
    @State private var presentedNotes: WhisperMeetingRow?

    // Notebook parity with web — search, favorites, and per-user renames.
    @State private var searchText: String = ""
    @State private var notebookPrefs: [String: WhisperNotebookPrefRow] = [:]
    @State private var renameTarget: WhisperMeetingRow?
    @State private var renameDraft: String = ""

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    private var upcoming: [WhisperMeetingRow] {
        service.myMeetings
            .filter { $0.status == "scheduled" && matchesSearch($0) }
            .sorted { ($0.scheduled_at ?? "") < ($1.scheduled_at ?? "") }
    }

    private var recent: [WhisperMeetingRow] {
        let rows = service.myMeetings.filter { $0.status != "scheduled" && matchesSearch($0) }
        // Favorites pin to the top; everything else keeps the service order.
        return rows.filter { isFavorite($0) } + rows.filter { !isFavorite($0) }
    }

    private func matchesSearch(_ meeting: WhisperMeetingRow) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return displayTitle(meeting).lowercased().contains(query)
            || meeting.title.lowercased().contains(query)
            || (meeting.summary?.lowercased().contains(query) ?? false)
            || meeting.host_username.lowercased().contains(query)
    }

    /// The per-user custom title when set — the shared meeting row itself is
    /// never touched by renames (web Notebook parity).
    private func displayTitle(_ meeting: WhisperMeetingRow) -> String {
        if let custom = notebookPrefs[meeting.id]?.custom_title?
            .trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return meeting.title
    }

    private func isFavorite(_ meeting: WhisperMeetingRow) -> Bool {
        notebookPrefs[meeting.id]?.is_favorite == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                WhisperMeetingLandingContent(
                    meetings: service.myMeetings, joinCode: $joinCode,
                    busy: starting || joining, errorText: errorText,
                    onStart: { Task { await start() } }, onJoin: joinWithCode,
                    onLink: { Task { await start(linkOnly: true) } },
                    onSchedule: { showSchedule = true }, onLibrary: { showNotebook = true },
                    onCalendar: { showCalendar = true },
                    onOpen: { meeting in
                        if meeting.isEnded { presentedNotes = meeting }
                        else { WhisperMeetingWindow.shared.present(meeting) }
                    }
                )
                .id(AccountStorage.currentUserID)
                if starting || joining {
                    WhisperMeetingStartingView(title: starting ? "Starting meeting…" : "Opening meeting…")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = service.meetingsError {
                    HStack {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Button("Retry") { Task { await service.refreshMine() } }.frame(minHeight: 44)
                    }.padding().background(.regularMaterial)
                }
            }
            .navigationTitle("Meet")
            .onChange(of: WhisperMeetingWindow.shared.meeting?.id) { previous, current in
                if previous != nil, current == nil { Task { await service.refreshMine() } }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Meeting library", systemImage: "note.text") { showNotebook = true }
                        Button("Search workspace", systemImage: "magnifyingglass") { showWorkspaceSearch = true }
                        Button("Meeting settings", systemImage: "slider.horizontal.3") { showMeetSettings = true }
                        Button("Report a bug", systemImage: "ladybug") { showReport = true }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Meeting options")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .task(id: AccountStorage.generation) { await service.refreshMine() }
            .task(id: AccountStorage.generation) {
                let generation = AccountStorage.generation
                let prefs = await service.fetchNotebookPrefs()
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                notebookPrefs = prefs
            }
            .sheet(isPresented: $showNotebook) { WhisperMeetingNotesListView().id(AccountStorage.currentUserID) }
            .sheet(isPresented: $showCalendar) { WhisperCalendarView() }
            .sheet(isPresented: $showMeetSettings) { WhisperMeetSettingsView() }
            .sheet(isPresented: $showReport) { WhisperReportProblemSheet() }
            .sheet(isPresented: $showWorkspaceSearch) { WorkspaceSearchView().id(AccountStorage.currentUserID) }
            .alert("Your meeting link is ready", isPresented: Binding(get: { copiedLink != nil }, set: { if !$0 { copiedLink = nil } })) {
                Button("Copy link") { UIPasteboard.general.string = copiedLink; copiedLink = nil }
                Button("Done", role: .cancel) { copiedLink = nil }
            } message: { Text(copiedLink ?? "") }
            .onDisappear { launchGeneration = UUID() }
            .sheet(isPresented: $showSchedule) {
                WhisperScheduleMeetingSheet {
                    Task { await service.refreshMine() }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Rename note", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Meeting name", text: $renameDraft)
                Button("Save") { commitRename() }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            } message: {
                Text("Only you see this name — it syncs with your meeting library on the web.")
            }
        }
        // FULL PAGE — the notes are a whole-page experience (matching the
        // web's ended-meeting screen). Rendered as an in-place overlay, NOT a
        // system presentation: this screen often lives inside a sheet, and a
        // fullScreenCover launched from an inset sheet renders scaled and
        // cut off at the edges on iOS 26. The overlay always inherits the
        // exact visible geometry, so the notes can never overflow the page.
        .overlay {
            if let meeting = presentedNotes {
                WhisperMeetingNotesView(meeting: meeting, onClose: { presentedNotes = nil })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.headline)
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 38, height: 38)
                    .background(ink, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("New meeting")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ink)
                    Text("Instant call or schedule with email invites")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
            }

            HStack(spacing: 8) {
                TextField("Meeting title (optional)", text: $title)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                    }

                Button {
                    Haptics.tap()
                    Task { await start() }
                } label: {
                    HStack(spacing: 6) {
                        if starting {
                            ProgressView().tint(WhisperTheme.surface(colorScheme))
                        } else {
                            Image(systemName: "plus")
                        }
                        Text("Start")
                    }
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(starting)
            }

            Button {
                Haptics.tap()
                showSchedule = true
            } label: {
                Label("Schedule for later", systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                    }
            }
            .buttonStyle(.plain)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                TextField("Enter a code or link", text: $joinCode)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.join).onSubmit { joinWithCode() }
                Button(joining ? "Joining…" : "Join") { joinWithCode() }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(joining || joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.subheadline).padding(.horizontal, 14)
                .background(WhisperTheme.surface(colorScheme), in: Capsule())

            Text("Start here on iPhone or web. Find original notes, transcripts and recordings in your Meetings library. Ask Jasper across your neatly filed conversations.")
                .font(.caption2)
                .foregroundStyle(muted)
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private func meetingsSection(title sectionTitle: String, rows: [WhisperMeetingRow], emptyHint: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sectionTitle)
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(muted)
                .padding(.leading, 4)

            if rows.isEmpty {
                if emptyHint {
                    VStack(spacing: 10) {
                        Image(systemName: "clock")
                            .font(.title2)
                            .foregroundStyle(muted.opacity(0.5))
                        Text(searchText.isEmpty ? "No meetings yet" : "No matches")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 0.75, dash: [5]))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, meeting in
                        Button {
                            Haptics.tap()
                            // Past meetings always review in the same private Notebook.
                            if !meeting.isLive, meeting.status != "scheduled" {
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
                                    presentedNotes = meeting
                                }
                            } else {
                                WhisperMeetingWindow.shared.present(meeting)
                            }
                        } label: {
                            meetingRow(meeting)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                toggleFavorite(meeting)
                            } label: {
                                Label(
                                    isFavorite(meeting) ? "Unfavorite" : "Favorite",
                                    systemImage: isFavorite(meeting) ? "star.slash" : "star"
                                )
                            }
                            Button {
                                renameDraft = displayTitle(meeting)
                                renameTarget = meeting
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }
                        if index < rows.count - 1 {
                            Divider()
                                .background(WhisperTheme.hairline(colorScheme))
                                .padding(.leading, 62)
                        }
                    }
                }
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                }
            }
        }
    }

    private static let scheduledRowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d \u{00B7} h:mm a"
        return f
    }()

    private func subtitle(for meeting: WhisperMeetingRow) -> String {
        if meeting.isLive { return "Live now" }
        if meeting.status == "scheduled" {
            if let iso = meeting.scheduled_at, let date = WhisperBackendService.parseISO(iso) {
                return "Scheduled \u{00B7} \(Self.scheduledRowFormatter.string(from: date))"
            }
            return "Scheduled"
        }
        return meeting.summary != nil ? "Notes ready" : "Ended"
    }

    private func meetingRow(_ meeting: WhisperMeetingRow) -> some View {
        let isScheduled = meeting.status == "scheduled"
        let scheduleBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
        return HStack(spacing: 12) {
            Image(systemName: meeting.summary != nil
                  ? "doc.text.fill"
                  : (isScheduled ? "calendar.badge.clock" : "video.fill"))
                .font(.subheadline)
                .foregroundStyle(meeting.isLive ? .green : (isScheduled ? scheduleBlue : muted))
                .frame(width: 38, height: 38)
                .background(
                    meeting.isLive
                        ? Color.green.opacity(0.14)
                        : (isScheduled ? scheduleBlue.opacity(0.12) : WhisperTheme.surface(colorScheme)),
                    in: .rect(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if isFavorite(meeting) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.14))
                    }
                    Text(displayTitle(meeting))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }
                Text(subtitle(for: meeting))
                    .font(.caption)
                    .foregroundStyle(meeting.isLive ? .green : (isScheduled ? scheduleBlue : muted))
            }

            Spacer(minLength: 0)

            if let score = storedEvalScore(meeting.id) {
                Text("READ \(score)")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.5)
                    .foregroundStyle(scoreTint(score))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(scoreTint(score).opacity(0.13), in: Capsule())
            }

            if meeting.isLive {
                Text("LIVE")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green, in: Capsule())
            } else if isScheduled {
                Text("SCHEDULED")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(scheduleBlue, in: Capsule())
            } else if meeting.summary != nil {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("NOTES")
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.5)
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(ink, in: Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(muted.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    /// Last stored Jasper confidence read for this meeting — recruiter-only,
    /// cached locally by the meeting room's live scorer.
    private func storedEvalScore(_ meetingID: String) -> Int? {
        guard WhisperRecruiterService.shared.isMeRecruiter,
              let data = UserDefaults.standard.data(forKey: "whisper_meeting_eval:\(meetingID)"),
              let eval = try? JSONDecoder().decode(WhisperProspectEval.self, from: data) else { return nil }
        return eval.score
    }

    private func scoreTint(_ score: Int) -> Color {
        if score >= 70 { return Color(red: 0.20, green: 0.83, blue: 0.60) }
        if score >= 45 { return Color(red: 0.98, green: 0.75, blue: 0.14) }
        return Color(red: 0.97, green: 0.44, blue: 0.44)
    }

    private func joinWithCode() {
        let raw = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !joining, !starting else { return }
        joining = true; errorText = nil
        let operation = launchGeneration
        let generation = AccountStorage.generation
        Task {
            defer { joining = false }
            guard let invitation = WhisperMeetingInvitation.fromText(raw) else {
                errorText = "Enter a Whisper meeting link, UUID, or wsp-xxxx-xxxx code."
                return
            }
            let opened = await WhisperMeetingLinkRouter.open(invitation)
            guard operation == launchGeneration, generation == AccountStorage.generation else { return }
            if opened { joinCode = "" }
            else { errorText = "Couldn't open that invitation. Try again." }
        }
    }

    private func start(linkOnly: Bool = false) async {
        guard !starting, !joining else { return }
        let operation = launchGeneration
        let generation = AccountStorage.generation
        starting = true
        errorText = nil
        defer { starting = false }
        do {
            let meeting = try await WhisperMeetingService.shared.create(title: title)
            guard operation == launchGeneration, generation == AccountStorage.generation else { return }
            title = ""
            if linkOnly { copiedLink = WhisperMeetingService.link(for: meeting.id) }
            else { WhisperMeetingWindow.shared.present(meeting) }
            await service.refreshMine()
        } catch {
            errorText = "Couldn't start the meeting. Try again."
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted)
            TextField("Search meetings & notes", text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(muted.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay {
            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private func toggleFavorite(_ meeting: WhisperMeetingRow) {
        Haptics.tap()
        let next = !isFavorite(meeting)
        notebookPrefs[meeting.id] = WhisperNotebookPrefRow(
            meeting_id: meeting.id,
            custom_title: notebookPrefs[meeting.id]?.custom_title,
            is_favorite: next
        )
        Task { await service.saveNotebookPref(meetingID: meeting.id, isFavorite: next) }
    }

    private func commitRename() {
        guard let meeting = renameTarget else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reverting to the real title (or blank) clears the custom name.
        let stored: String? = (trimmed.isEmpty || trimmed == meeting.title) ? nil : trimmed
        notebookPrefs[meeting.id] = WhisperNotebookPrefRow(
            meeting_id: meeting.id,
            custom_title: stored,
            is_favorite: isFavorite(meeting)
        )
        renameTarget = nil
        Task { await service.saveNotebookPref(meetingID: meeting.id, customTitle: .some(stored)) }
    }
}

// MARK: - Schedule sheet

/// Schedule a meeting for later — date, time, and optional branded email
/// invites (matches the web scheduling modal).
struct WhisperScheduleMeetingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var onScheduled: () -> Void

    @State private var title: String = ""
    @State private var date: Date = Calendar.current.date(
        byAdding: .day, value: 1,
        to: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    ) ?? Date()
    @State private var emails: String = ""
    @State private var scheduling: Bool = false
    @State private var resultText: String?
    @State private var errorText: String?

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    private var emailList: [String] {
        emails
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("@") && $0.contains(".") }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        fieldLabel("TITLE")
                        TextField("Team sync, coaching call\u{2026}", text: $title)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                            }

                        fieldLabel("DATE & TIME")
                        DatePicker(
                            "Starts",
                            selection: $date,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                        }

                        fieldLabel("INVITE BY EMAIL (OPTIONAL)")
                        TextField(
                            "coach@example.com, athlete@gmail.com\u{2026}",
                            text: $emails,
                            axis: .vertical
                        )
                        .font(.subheadline)
                        .lineLimit(3...5)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                        }
                        Text("Separate with commas or new lines. Recipients get a branded Whisper invite \u{2014} they can join as a guest or sign up. You can also share the link in a DM after scheduling.")
                            .font(.caption2)
                            .foregroundStyle(muted)

                        if let errorText {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let resultText {
                            Label(resultText, systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }

                        Button {
                            Haptics.tap()
                            Task { await schedule() }
                        } label: {
                            HStack(spacing: 8) {
                                if scheduling {
                                    ProgressView().tint(WhisperTheme.surface(colorScheme))
                                } else {
                                    Image(systemName: "calendar.badge.plus")
                                }
                                Text(scheduling ? "Scheduling\u{2026}" : "Schedule meeting")
                            }
                            .font(.headline.weight(.black))
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(ink, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(scheduling)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Schedule meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ink)
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .tracking(1.1)
            .foregroundStyle(muted)
    }

    private func schedule() async {
        scheduling = true
        errorText = nil
        resultText = nil
        defer { scheduling = false }
        do {
            let meeting = try await WhisperMeetingService.shared.create(title: title, scheduledAt: date)
            var message = "Scheduled!"
            if !emailList.isEmpty {
                if let sent = await WhisperMeetingService.shared.sendInvites(
                    meetingID: meeting.id,
                    title: meeting.title,
                    scheduledAt: date,
                    emails: emailList
                ) {
                    message = "Scheduled \u{2014} \(sent) invite\(sent == 1 ? "" : "s") sent!"
                } else {
                    message = "Scheduled \u{2014} some invites couldn't be sent."
                }
            }
            UIPasteboard.general.string = WhisperMeetingService.link(for: meeting.id)
            resultText = message + " Link copied."
            onScheduled()
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
        } catch {
            errorText = "Couldn't schedule the meeting. Try again."
        }
    }
}

// MARK: - DM bubble

/// Invitation-only card. Merely displaying it never registers a participant or starts media.
struct WhisperMeetingDMBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let invitation: WhisperMeetingInvitation
    let mine: Bool

    @State private var opening: Bool = false
    @State private var openFailed: Bool = false

    private var ink: Color { WhisperTheme.ink(colorScheme) }

    private var statusLine: String {
        if opening { return "Opening…" }
        if openFailed { return "Couldn't open — tap to retry" }
        return invitation.isSocial ? "Open in Whisper" : "Open in Whisper Meet"
    }

    var body: some View {
        Button {
            Haptics.tap()
            guard !opening else { return }
            opening = true
            openFailed = false
            Task {
                let opened = await WhisperMeetingLinkRouter.open(invitation)
                openFailed = !opened
                opening = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(mine ? ink : WhisperTheme.surface(colorScheme))
                    .frame(width: 38, height: 38)
                    .background(
                        (mine ? WhisperTheme.surface(colorScheme) : ink).opacity(0.92),
                        in: .rect(cornerRadius: 12)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.speedDate ? "Date invitation" : invitation.socialCall ? "Call invitation" : "Whisper Meet")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.caption2)
                        .opacity(0.7)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .opacity(0.6)
            }
            .padding(12)
            .frame(width: 240, alignment: .leading)
            .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : ink)
            .background(
                mine ? ink : WhisperTheme.card(colorScheme),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        mine ? Color.clear : WhisperTheme.hairline(colorScheme),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(opening)
        .accessibilityLabel(invitation.isSocial ? "Open in Whisper" : "Open in Whisper Meet")
        .accessibilityHint(invitation.isSocial ? "Opens this social invitation" : "Meet handles sign-in and joining. Camera and microphone stay off here.")
    }
}
