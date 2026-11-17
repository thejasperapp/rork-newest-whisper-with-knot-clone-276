import SwiftUI

/// Full-screen shared calendar for badged role users. Mirrors the web
/// calendar: month grid with mini profile pics on busy days, event cards
/// with RSVP, notes, meeting links, and roles. Tapping a day shows that
/// day's events below the grid. A "+" button opens the create event sheet.
///
/// Accessible from the briefcase (role tools) for any user with a badge.
struct WhisperCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var cal = WhisperCalendarService.shared
    @State private var cursor: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var showCreate: Bool = false
    @State private var showExport: Bool = false
    @State private var refreshRevision = 0

    private let monthNames = ["January", "February", "March", "April", "May", "June",
                              "July", "August", "September", "October", "November", "December"]
    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    private var year: Int { Calendar.current.component(.year, from: cursor) }
    private var month: Int { Calendar.current.component(.month, from: cursor) }

    private var monthStart: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? cursor
    }
    private var monthEnd: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? cursor
    }

    private var firstWeekday: Int {
        Calendar.current.component(.weekday, from: monthStart)
    }
    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    private var isToday: (Int) -> Bool {
        let now = Date()
        let cal = Calendar.current
        return { day in
            cal.component(.year, from: now) == year &&
            cal.component(.month, from: now) == month &&
            cal.component(.day, from: now) == day
        }
    }

    private var selectedEvents: [WhisperCalendarService.CalendarEventRow] {
        guard let d = selectedDate else { return [] }
        let calendar = Calendar.current
        let key = "\(calendar.component(.year, from: d))-\(calendar.component(.month, from: d))-\(calendar.component(.day, from: d))"
        return cal.eventsByDay()[key] ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        calendarGrid
                        if cal.isLoading {
                            ProgressView("Refreshing calendar…")
                                .font(.footnote)
                                .tint(WhisperTheme.ink(colorScheme))
                        }
                        if let error = cal.lastError {
                            VStack(spacing: 8) {
                                Text(error).font(.footnote).foregroundStyle(.secondary)
                                Button("Refresh calendar") { refreshRevision += 1 }
                                    .font(.footnote.weight(.semibold))
                                    .disabled(cal.isLoading)
                            }
                        }
                        if let d = selectedDate {
                            selectedDateSection(d)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Shared Calendar")
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
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 2) {
                        if !cal.events.isEmpty {
                            Button {
                                Haptics.tap()
                                showExport = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                            }
                            .accessibilityLabel("Save to calendar")
                        }
                        Button {
                            Haptics.tap()
                            showCreate = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.bold))
                                .foregroundStyle(WhisperTheme.surface(colorScheme))
                                .frame(width: 30, height: 30)
                                .background(WhisperTheme.ink(colorScheme), in: Circle())
                        }
                        .accessibilityLabel("New event")
                    }
                }
            }
            .task(id: "\(AccountStorage.currentUserID)-\(monthStart.timeIntervalSince1970)-\(refreshRevision)") {
                await cal.fetchMonth(start: monthStart, end: monthEnd, force: refreshRevision > 0)
            }
            .onChange(of: cursor) { _, _ in selectedDate = nil; refreshRevision = 0 }
            .sheet(isPresented: $showExport) {
                WhisperCalendarExportSheet(
                    events: cal.events,
                    icsURL: cal.events.isEmpty ? nil : cal.exportICSFile()
                )
                .whisperSheetBorder()
            }
            .sheet(isPresented: $showCreate) {
                WhisperCalendarCreateSheet(defaultDate: selectedDate ?? Date())
                    .whisperSheetBorder()
                    .onDisappear {
                        refreshRevision += 1
                    }
            }
        }
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        VStack(spacing: 0) {
            // Month navigation
            HStack {
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) {
                        cursor = Calendar.current.date(byAdding: .month, value: -1, to: cursor) ?? cursor
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(monthNames[month - 1]) \(year)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) {
                        cursor = Calendar.current.date(byAdding: .month, value: 1, to: cursor) ?? cursor
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            // Weekday labels
            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }

            // Day cells
            let totalCells = firstWeekday - 1 + daysInMonth
            let rows = Int(ceil(Double(totalCells) / 7.0))
            let dayMap = cal.eventsByDay()

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { rowIdx in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { colIdx in
                            let cellIdx = rowIdx * 7 + colIdx
                            let dayNum = cellIdx - (firstWeekday - 1) + 1
                            if dayNum >= 1 && dayNum <= daysInMonth {
                                let key = "\(year)-\(month)-\(dayNum)"
                                let dayEvents = dayMap[key] ?? []
                                dayCell(day: dayNum, events: dayEvents)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 92)
                            }
                        }
                    }
                }
            }
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
    }

    private func dayCell(day: Int, events: [WhisperCalendarService.CalendarEventRow]) -> some View {
        let isSelected = selectedDate != nil &&
            Calendar.current.component(.year, from: selectedDate!) == year &&
            Calendar.current.component(.month, from: selectedDate!) == month &&
            Calendar.current.component(.day, from: selectedDate!) == day
        let todayCheck = isToday(day)
        // Collect participant IDs for avatar display
        let participantIDs: [String] = events.flatMap { e in
            cal.participants(for: e.id, event: e)
        }
        let uniqueIDs = Array(Set(participantIDs))
        let visiblePics = uniqueIDs.prefix(3)
        let overflow = max(0, uniqueIDs.count - 3)

        return Button {
            Haptics.tap()
            selectedDate = Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        } label: {
            VStack(spacing: 0) {
                // Day number
                Text("\(day)")
                    .font(.subheadline.weight(todayCheck ? .heavy : .semibold))
                    .foregroundStyle(todayCheck ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                    .frame(width: todayCheck ? 26 : 22, height: todayCheck ? 26 : 22)
                    .background(todayCheck ? WhisperTheme.ink(colorScheme) : Color.clear, in: Circle())
                    .padding(.top, 6)

                // Event dots
                if !events.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(events.prefix(4), id: \.id) { e in
                            Circle()
                                .fill(WhisperCalendarEmbed.typeColor(e.event_type))
                                .frame(width: 5, height: 5)
                        }
                        if events.count > 4 {
                            Text("+\(events.count - 4)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)

                // Mini profile pics
                if !visiblePics.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(Array(visiblePics), id: \.self) { uid in
                            let profile = cal.participantProfiles[uid]
                            WhisperAvatar(
                                username: profile?.username ?? "?",
                                size: 18,
                                imageURL: profile?.profile_image_url.flatMap(URL.init(string:)),
                                ring: false
                            )
                            .overlay { Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 1.5) }
                        }
                        if overflow > 0 {
                            Text("+\(overflow)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(WhisperTheme.surface(colorScheme), in: Capsule())
                                .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5) }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(isSelected ? WhisperTheme.hairline(colorScheme).opacity(0.3) : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected day events

    private func selectedDateSection(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let f = DateFormatter()
            let dateLabel: String = {
                f.dateFormat = "EEEE, MMM d"
                return f.string(from: date)
            }()

            Text(dateLabel)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .textCase(.uppercase)
                .tracking(0.5)

            if selectedEvents.isEmpty {
                VStack(spacing: 8) {
                    WhisperMeetDoodle(symbol: "calendar", height: 144)
                    Text("No events on this day")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Button {
                        Haptics.tap()
                        showCreate = true
                    } label: {
                        Text("Add an event")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            } else {
                if cal.isLoadingNotes {
                    ProgressView("Refreshing notes…").font(.footnote)
                }
                if let error = cal.notesError {
                    Button {
                        Task { await cal.fetchNotesForEvents(selectedEvents.map(\.id)) }
                    } label: {
                        Label("\(error) Retry", systemImage: "arrow.clockwise").font(.footnote)
                    }
                    .disabled(cal.isLoadingNotes)
                }
                let conflicts = cal.conflictEventIDs()
                ForEach(selectedEvents, id: \.id) { event in
                    WhisperCalendarEventCard(
                        event: event,
                        hasConflict: conflicts.contains(event.id),
                        dayLabel: selectedDate.flatMap { WhisperCalendarService.multiDayLabel(event, on: $0) }
                    )
                }
            }
        }
        .padding(.top, 8)
        .task(id: "\(AccountStorage.generation)-\(monthStart.timeIntervalSince1970)-\(cal.monthContentRevision)-\(selectedEvents.map(\.id).sorted().joined(separator: ","))") {
            await cal.fetchNotesForEvents(selectedEvents.map(\.id))
        }
    }
}

// MARK: - Event card

struct WhisperCalendarEventCard: View {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    @Environment(\.colorScheme) private var colorScheme
    @State private var cal = WhisperCalendarService.shared
    let event: WhisperCalendarService.CalendarEventRow
    var hasConflict: Bool = false
    /// "Day 2 of 3" when a multi-day event is viewed on one of its days.
    var dayLabel: String? = nil
    @State private var expanded: Bool = false
    @State private var noteText: String = ""
    @State private var recapText: String = ""

    private var myRSVP: String? {
        let uid = AccountStorage.currentUserID.lowercased()
        return (cal.rsvpsByEventID[event.id] ?? []).first { $0.user_id.lowercased() == uid }?.status
    }

    private var goingCount: Int {
        (cal.rsvpsByEventID[event.id] ?? []).filter { $0.status == "going" }.count
    }

    private var allParticipants: [(uid: String, username: String?, status: String)] {
        var map: [String: (uid: String, username: String?, status: String)] = [:]
        map[event.created_by] = (event.created_by, event.created_by_username, "creator")
        for (i, uid) in event.tagged_user_ids.enumerated() {
            if map[uid] == nil {
                let uname = i < event.tagged_usernames.count ? event.tagged_usernames[i] : nil
                map[uid] = (uid, uname, "tagged")
            }
        }
        for r in cal.rsvpsByEventID[event.id] ?? [] {
            if let existing = map[r.user_id] {
                map[r.user_id] = (existing.uid, r.username ?? existing.username, r.status)
            } else {
                map[r.user_id] = (r.user_id, r.username, r.status)
            }
        }
        return Array(map.values)
    }

    private var isCreator: Bool {
        event.created_by.lowercased() == AccountStorage.currentUserID.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header
            Button {
                Haptics.tap()
                withAnimation(.whisperSnappy) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        // Color bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(WhisperCalendarEmbed.typeColor(event.event_type))
                            .frame(width: 3, height: 44)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.body.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                // Time
                                if let date = WhisperBackendService.parseISO(event.start_time) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(Self.timeFormatter.string(from: date))
                                            .font(.caption.weight(.semibold))
                                        if let end = event.end_time.flatMap(WhisperBackendService.parseISO),
                                           WhisperCalendarService.dayKeys(for: event).count > 1 {
                                            Text("– " + end.formatted(.dateTime.month(.abbreviated).day()))
                                                .font(.caption.weight(.semibold))
                                        }
                                    }
                                }
                                if let dayLabel {
                                    Text(dayLabel)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                                // Type pill
                                Text(WhisperCalendarEmbed.typeLabel(event.event_type))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(WhisperCalendarEmbed.typeColor(event.event_type))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(WhisperCalendarEmbed.typeColor(event.event_type).opacity(0.15), in: Capsule())
                                // Recurring badge
                                if let rec = event.recurrence, rec != "none" {
                                    HStack(spacing: 3) {
                                        Image(systemName: "repeat")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(rec == "weekly" ? "Weekly" : rec == "biweekly" ? "Biweekly" : "Monthly")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(WhisperTheme.muted(colorScheme).opacity(0.12), in: Capsule())
                                }
                                // Conflict badge
                                if hasConflict {
                                    HStack(spacing: 3) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("Conflict")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.15), in: Capsule())
                                }
                                // Location
                                if let loc = event.location, !loc.isEmpty {
                                    HStack(spacing: 3) {
                                        Image(systemName: "mappin")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(loc)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                                // Meeting link
                                if let link = event.meeting_link, !link.isEmpty {
                                    HStack(spacing: 3) {
                                        Image(systemName: "video")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("Online")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(WhisperCalendarEmbed.typeColor("meet"))
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)

                    // Participant avatars
                    if !allParticipants.isEmpty {
                        HStack(spacing: 8) {
                            HStack(spacing: -6) {
                                ForEach(allParticipants.prefix(5), id: \.uid) { p in
                                    let profile = cal.participantProfiles[p.uid]
                                    WhisperAvatar(
                                        username: p.username ?? "?",
                                        size: 22,
                                        imageURL: profile?.profile_image_url.flatMap(URL.init(string:)),
                                        ring: false
                                    )
                                    .overlay { Circle().strokeBorder(WhisperTheme.card(colorScheme), lineWidth: 1.5) }
                                }
                            }
                            if allParticipants.count > 5 {
                                Text("+\(allParticipants.count - 5)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            if goingCount > 0 {
                                Text("\(goingCount) going")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().overlay(WhisperTheme.hairline(colorScheme))

                    // Description
                    if let desc = event.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                    }

                    // Ordinary Whisper invitations hand off to Meet through the OS.
                    if let link = event.meeting_link, !link.isEmpty, let url = URL(string: link) {
                        Button {
                            Haptics.tap()
                            if !WhisperMeetingLinkRouter.handle(url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "video.fill")
                                    .font(.caption.weight(.bold))
                                Text("Join meeting")
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(WhisperCalendarEmbed.typeColor("meet"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(WhisperCalendarEmbed.typeColor("meet").opacity(0.1), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    // Created by
                    Text("Created by @\(event.created_by_username ?? "user")")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))

                    // Who's involved
                    if !allParticipants.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WHO'S INVOLVED")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .tracking(0.5)
                            ForEach(allParticipants, id: \.uid) { p in
                                let profile = cal.participantProfiles[p.uid]
                                HStack(spacing: 10) {
                                    WhisperAvatar(
                                        username: p.username ?? "?",
                                        size: 28,
                                        imageURL: profile?.profile_image_url.flatMap(URL.init(string:)),
                                        ring: false
                                    )
                                    Text("@\(profile?.username ?? p.username ?? "user")")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    // Role badge
                                    if let role = WhisperCalendarService.roleLabel(for: profile) {
                                        Text(role)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(roleColor(role))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(roleColor(role).opacity(0.15), in: Capsule())
                                    }
                                    // Status badge
                                    if p.status == "creator" {
                                        Text("Host")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(WhisperTheme.ink(colorScheme).opacity(0.1), in: Capsule())
                                    } else if p.status == "going" {
                                        Text("Going")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.15), in: Capsule())
                                    } else if p.status == "maybe" {
                                        Text("Maybe")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.15), in: Capsule())
                                    }
                                }
                            }
                        }
                    }

                    // RSVP buttons
                    HStack(spacing: 8) {
                        rsvpButton("going", icon: "checkmark", label: "Going")
                        rsvpButton("maybe", icon: "questionmark", label: "Maybe")
                        rsvpButton("declined", icon: "xmark", label: "Can't")
                    }

                    // Post-event recap prompt
                    if WhisperCalendarService.hasEnded(event) {
                        recapSection
                    }

                    // Notes
                    notesSection

                    // Delete (creator only)
                    if isCreator {
                        Button(role: .destructive) {
                            Haptics.warning()
                            Task {
                                await cal.deleteEvent(eventID: event.id)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete event")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - RSVP button

    private func rsvpButton(_ status: String, icon: String, label: String) -> some View {
        let active = myRSVP == status
        let activeColor: Color = status == "going"
            ? Color(red: 0.13, green: 0.77, blue: 0.37)
            : status == "maybe"
                ? Color(red: 0.96, green: 0.62, blue: 0.04)
                : Color(red: 0.94, green: 0.27, blue: 0.27)
        return Button {
            Haptics.tap()
            Task { await cal.setRSVP(eventID: event.id, status: status) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(active ? .white : WhisperTheme.ink(colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(active ? activeColor : WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(active ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recap

    /// Post-event recap — a lightweight content log. Recaps are notes marked
    /// with `WhisperCalendarService.recapPrefix`.
    private var recapSection: some View {
        let recaps = (cal.notesByEventID[event.id] ?? []).filter { $0.body.hasPrefix(WhisperCalendarService.recapPrefix) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "camera")
                    .font(.caption.weight(.bold))
                Text("EVENT RECAP")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            ForEach(recaps, id: \.id) { note in
                let profile = cal.participantProfiles[note.user_id]
                HStack(alignment: .top, spacing: 8) {
                    WhisperAvatar(
                        username: note.username ?? "?",
                        size: 22,
                        imageURL: profile?.profile_image_url.flatMap(URL.init(string:)),
                        ring: false
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(profile?.username ?? note.username ?? "user")")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text(String(note.body.dropFirst(WhisperCalendarService.recapPrefix.count)))
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 8) {
                TextField("How did it go? Drop a quick recap…", text: $recapText)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                Button {
                    let body = recapText
                    recapText = ""
                    Haptics.tap()
                    Task { await cal.addRecap(eventID: event.id, body: body) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(recapText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(WhisperTheme.surface(colorScheme).opacity(0.5), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "note.text")
                    .font(.caption.weight(.bold))
                Text("NOTES")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))

            let notes = (cal.notesByEventID[event.id] ?? []).filter { !$0.body.hasPrefix(WhisperCalendarService.recapPrefix) }
            ForEach(notes, id: \.id) { note in
                let profile = cal.participantProfiles[note.user_id]
                HStack(alignment: .top, spacing: 8) {
                    WhisperAvatar(
                        username: note.username ?? "?",
                        size: 22,
                        imageURL: profile?.profile_image_url.flatMap(URL.init(string:)),
                        ring: false
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("@\(profile?.username ?? note.username ?? "user")")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            if let role = WhisperCalendarService.roleLabel(for: profile) {
                                Text(role)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(roleColor(role))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(roleColor(role).opacity(0.15), in: Capsule())
                            }
                        }
                        Text(note.body)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    if note.user_id.lowercased() == AccountStorage.currentUserID.lowercased() {
                        Button {
                            Haptics.tap()
                            Task { await cal.deleteNote(noteID: note.id, eventID: event.id) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(WhisperTheme.surface(colorScheme).opacity(0.5), in: .rect(cornerRadius: 10))
            }

            // Add note input
            HStack(spacing: 8) {
                TextField("Leave a quick note…", text: $noteText)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                Button {
                    let body = noteText
                    noteText = ""
                    Haptics.tap()
                    Task { await cal.addNote(eventID: event.id, body: body) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "Coach": return Color(red: 0.98, green: 0.55, blue: 0.20)
        case "Athlete": return Color(red: 0.94, green: 0.27, blue: 0.27)
        case "Creator": return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "Recruiter": return Color(red: 0.66, green: 0.33, blue: 0.91)
        default: return WhisperTheme.muted(colorScheme)
        }
    }
}

// MARK: - Create event sheet

struct WhisperCalendarCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var cal = WhisperCalendarService.shared
    let defaultDate: Date

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var eventType: String = "meet"
    @State private var date: Date
    @State private var time: Date
    /// Multi-day events — an end DATE later than the start date.
    @State private var multiDay: Bool = false
    @State private var endDate: Date
    @State private var endTime: Date
    @State private var location: String = ""
    @State private var meetingLink: String = ""
    @State private var recurrence: String = "none"
    @State private var tagQuery: String = ""
    @State private var tagged: [WhisperUserRow] = []
    @State private var searchResults: [WhisperUserRow] = []
    @State private var searching: Bool = false
    @State private var creating: Bool = false
    @State private var generatingMeet: Bool = false
    @State private var meetError: String?

    private let eventTypes: [(value: String, label: String)] = [
        ("meet", "Meet up"), ("content_collab", "Content collab"),
        ("training", "Training"), ("event", "Event"),
        ("deadline", "Deadline"), ("other", "Other")
    ]

    private let recurrenceOptions: [(value: String, label: String)] = [
        ("none", "Doesn't repeat"), ("weekly", "Every week"),
        ("biweekly", "Every 2 weeks"), ("monthly", "Every month")
    ]

    init(defaultDate: Date) {
        self.defaultDate = defaultDate
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month, .day], from: defaultDate)
        let day = cal.date(from: components) ?? defaultDate
        _date = State(initialValue: day)
        _time = State(initialValue: cal.date(bySettingHour: 12, minute: 0, second: 0, of: defaultDate) ?? defaultDate)
        _endDate = State(initialValue: cal.date(byAdding: .day, value: 1, to: day) ?? day)
        _endTime = State(initialValue: cal.date(bySettingHour: 13, minute: 0, second: 0, of: defaultDate) ?? defaultDate)
    }

    /// The event's end when it spans days; nil keeps the default one-hour window.
    private var combinedEndDateTime: Date? {
        guard multiDay else { return nil }
        let cal = Calendar.current
        let datePart = cal.dateComponents([.year, .month, .day], from: endDate)
        let timePart = cal.dateComponents([.hour, .minute], from: endTime)
        let end = cal.date(from: DateComponents(
            year: datePart.year, month: datePart.month, day: datePart.day,
            hour: timePart.hour, minute: timePart.minute
        )) ?? endDate
        return end > combinedDateTime ? end : nil
    }

    private var spanDays: Int {
        guard let end = combinedEndDateTime else { return 1 }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: combinedDateTime), to: cal.startOfDay(for: end)).day ?? 0
        return max(1, days + 1)
    }

    private var combinedDateTime: Date {
        let cal = Calendar.current
        let datePart = cal.dateComponents([.year, .month, .day], from: date)
        let timePart = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(from: DateComponents(
            year: datePart.year, month: datePart.month, day: datePart.day,
            hour: timePart.hour, minute: timePart.minute
        )) ?? date
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    TextField("Event title", text: $title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .padding(.vertical, 4)

                    // Event type
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TYPE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(eventTypes, id: \.value) { type in
                                    Button {
                                        Haptics.tap()
                                        eventType = type.value
                                    } label: {
                                        Text(type.label)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(eventType == type.value ? .white : WhisperTheme.ink(colorScheme))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                eventType == type.value
                                                    ? WhisperCalendarEmbed.typeColor(type.value)
                                                    : Color.clear,
                                                in: Capsule()
                                            )
                                            .overlay {
                                                Capsule()
                                                    .strokeBorder(
                                                        eventType == type.value ? Color.clear : WhisperTheme.hairline(colorScheme),
                                                        lineWidth: 1
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Date + Time
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DATE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .tracking(0.5)
                            DatePicker("", selection: $date, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(WhisperTheme.ink(colorScheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TIME")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .tracking(0.5)
                            DatePicker("", selection: $time, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(WhisperTheme.ink(colorScheme))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Multi-day — pick a later end date; it shows on every day it covers.
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $multiDay.animation(.whisperSnappy)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Multi-day event")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text(multiDay
                                     ? "\(spanDays) days — it shows on every day it covers."
                                     : "Spans more than one day.")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        .tint(WhisperTheme.ink(colorScheme))
                        if multiDay {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ENDS")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                        .tracking(0.5)
                                    DatePicker("", selection: $endDate, in: date..., displayedComponents: [.date])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .tint(WhisperTheme.ink(colorScheme))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("AT")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                        .tracking(0.5)
                                    DatePicker("", selection: $endTime, displayedComponents: [.hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .tint(WhisperTheme.ink(colorScheme))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    // Repeats
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "repeat")
                                .font(.caption.weight(.bold))
                            Text("REPEATS")
                                .font(.caption2.weight(.bold))
                                .tracking(0.5)
                        }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recurrenceOptions, id: \.value) { option in
                                    Button {
                                        Haptics.tap()
                                        recurrence = option.value
                                    } label: {
                                        Text(option.label)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(recurrence == option.value ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                recurrence == option.value ? WhisperTheme.ink(colorScheme) : Color.clear,
                                                in: Capsule()
                                            )
                                            .overlay {
                                                Capsule()
                                                    .strokeBorder(
                                                        recurrence == option.value ? Color.clear : WhisperTheme.hairline(colorScheme),
                                                        lineWidth: 1
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if recurrence != "none" {
                            Text("Creates the next 8 occurrences on the shared calendar.")
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }

                    // Location
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOCATION (OPTIONAL)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        TextField("e.g. Gold's Gym, Venice Beach", text: $location)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }

                    // Meeting link + Whisper Meet button
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "video")
                                .font(.caption.weight(.bold))
                            Text("MEETING LINK (OPTIONAL)")
                                .font(.caption2.weight(.bold))
                                .tracking(0.5)
                        }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))

                        HStack(spacing: 10) {
                            TextField("https://meet.google.com/…", text: $meetingLink)
                                .font(.subheadline)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }

                            Button {
                                Haptics.tap()
                                Task { await generateWhisperMeeting() }
                            } label: {
                                HStack(spacing: 5) {
                                    if generatingMeet {
                                        ProgressView()
                                            .tint(WhisperTheme.surface(colorScheme))
                                            .frame(width: 18, height: 18)
                                    } else {
                                        Image(systemName: "plus")
                                            .font(.subheadline.weight(.bold))
                                    }
                                    Text("Whisper Meet")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(WhisperTheme.surface(colorScheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(generatingMeet)
                        }

                        if let meetError {
                            Text(meetError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Text("Creates an in-app video meeting with AI notes \u{2014} everyone tagged can join right inside Whisper.")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIPTION (OPTIONAL)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)
                        TextField("What's this about?", text: $description, axis: .vertical)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(3...6)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                    }

                    // Tag people
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TAG PEOPLE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .tracking(0.5)

                        // Tagged chips
                        if !tagged.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tagged, id: \.user_id) { user in
                                        HStack(spacing: 5) {
                                            Text("@\(user.username)")
                                                .font(.subheadline.weight(.semibold))
                                            Button {
                                                tagged.removeAll { $0.user_id == user.user_id }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                                        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                                    }
                                }
                            }
                        }

                        // Search field
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            TextField("Search by username…", text: $tagQuery)
                                .font(.subheadline)
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .autocapitalization(.none)
                                .onChange(of: tagQuery) { _, newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard trimmed.count >= 1 else {
                                        searchResults = []
                                        return
                                    }
                                    searching = true
                                    Task {
                                        let results = await WhisperUserService.shared.search(trimmed, limit: 8)
                                        await MainActor.run {
                                            searchResults = results
                                            searching = false
                                        }
                                    }
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }

                        // Search results
                        if !searchResults.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(searchResults.prefix(5), id: \.user_id) { user in
                                    Button {
                                        Haptics.tap()
                                        if !tagged.contains(where: { $0.user_id == user.user_id }) {
                                            tagged.append(user)
                                        }
                                        tagQuery = ""
                                        searchResults = []
                                    } label: {
                                        HStack(spacing: 10) {
                                            WhisperAvatar(
                                                username: user.username,
                                                size: 28,
                                                imageURL: user.profile_image_url.flatMap(URL.init(string:)),
                                                ring: false
                                            )
                                            Text("@\(user.username)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    if user.user_id != searchResults.last?.user_id {
                                        Divider().overlay(WhisperTheme.hairline(colorScheme))
                                    }
                                }
                            }
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.success()
                        creating = true
                        Task {
                            let result = await cal.createEvent(
                                title: title,
                                description: description.isEmpty ? nil : description,
                                eventType: eventType,
                                startTime: combinedDateTime,
                                endTime: combinedEndDateTime,
                                location: location.isEmpty ? nil : location,
                                meetingLink: meetingLink.isEmpty ? nil : meetingLink,
                                taggedUserIDs: tagged.map(\.user_id),
                                taggedUsernames: tagged.map { $0.username },
                                recurrence: recurrence
                            )
                            creating = false
                            if result != nil {
                                dismiss()
                            }
                        }
                    } label: {
                        if creating {
                            ProgressView()
                        } else {
                            Text("Create")
                                .font(.body.weight(.bold))
                        }
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || creating)
                }
            }
        }
    }

    // MARK: - Whisper Meet

    /// Creates a scheduled Whisper Meeting and fills the meeting link field.
    private func generateWhisperMeeting() async {
        guard !generatingMeet else { return }
        generatingMeet = true
        meetError = nil
        defer { generatingMeet = false }
        do {
            let meeting = try await WhisperMeetingService.shared.create(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Meeting" : title
            )
            meetingLink = WhisperMeetingService.link(for: meeting.id)
        } catch {
            meetError = "Couldn't create the meeting. Try again."
        }
    }
}
