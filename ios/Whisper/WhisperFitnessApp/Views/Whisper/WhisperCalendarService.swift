import Foundation
import Supabase
import SwiftUI

/// Supabase-backed shared calendar for badged role users (coaches, creators,
/// athletes, recruiters, brands). Mirrors the web calendar: events with
/// tagged users, RSVPs, mini notes, and meeting links.
///
/// When an event is created with tagged users, a "team message" DM is sent
/// to each tagged user via `WhisperCalendarEmbed` so they get a tappable
/// invite card in their inbox.
@MainActor
@Observable
final class WhisperCalendarService {
    static let shared = WhisperCalendarService()

    private let client = SupabaseService.shared.client
    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    var events: [CalendarEventRow] = []
    var rsvpsByEventID: [String: [CalendarRSVPRow]] = [:]
    var notesByEventID: [String: [CalendarNoteRow]] = [:]
    var participantProfiles: [String: WhisperBackendService.WhisperPublicProfile] = [:]
    var isLoading: Bool = false
    var lastError: String?
    private var monthRequestID = UUID()
    private var displayedRange: String?
    private var displayedStart: Date?
    private var displayedEnd: Date?
    // Private calendar details stay in memory, never in the display cache or widgets.
    private struct MonthSnapshot {
        let events: [CalendarEventRow]
        let rsvps: [String: [CalendarRSVPRow]]
        let profiles: [String: WhisperBackendService.WhisperPublicProfile]
        let savedAt: Date
    }
    private var recentMonths = WhisperRecentMemoryCache<String, MonthSnapshot>(capacity: 4)
    private var monthMutationRevision = UUID()
    private var notesRequestID = UUID()
    private var noteRevisions: [String: UUID] = [:]
    private(set) var monthContentRevision = UUID()
    private(set) var isLoadingNotes = false
    private(set) var notesError: String?

    private func invalidateMonthReads() {
        monthMutationRevision = UUID()
        recentMonths.removeAll()
    }

    func resetForAccountChange() {
        monthRequestID = UUID()
        notesRequestID = UUID()
        monthMutationRevision = UUID()
        monthContentRevision = UUID()
        recentMonths.removeAll()
        noteRevisions = [:]
        isLoadingNotes = false
        notesError = nil
        displayedRange = nil
        displayedStart = nil
        displayedEnd = nil
        events = []
        rsvpsByEventID = [:]
        notesByEventID = [:]
        participantProfiles = [:]
        isLoading = false
        lastError = nil
    }

    // MARK: - Row types

    nonisolated struct CalendarEventRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let created_by: String
        let created_by_username: String?
        let title: String
        let description: String?
        let event_type: String
        let start_time: String
        let end_time: String?
        let location: String?
        let meeting_link: String?
        let tagged_user_ids: [String]
        let tagged_usernames: [String]
        var recurrence: String?
        var recurrence_group: String?
        let created_at: String?
    }

    nonisolated struct CalendarRSVPRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let event_id: String
        let user_id: String
        let username: String?
        let status: String
        let created_at: String?
    }

    nonisolated struct CalendarNoteRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let event_id: String
        let user_id: String
        let username: String?
        let body: String
        let created_at: String?
    }

    private init() {}

    // MARK: - Fetch

    /// Only the latest selected range may publish. Participant enrichment
    /// uses the freshly retrieved RSVPs, never the previous month's state.
    func fetchMonth(start: Date, end: Date, force: Bool = false) async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        let requestID = UUID()
        monthRequestID = requestID
        let startISO = ISO8601DateFormatter().string(from: start)
        let endISO = ISO8601DateFormatter().string(from: end)
        let range = "\(startISO)/\(endISO)"
        let snapshot = recentMonths.value(for: range)
        if displayedRange != range {
            notesRequestID = UUID()
            events = snapshot?.events ?? []
            rsvpsByEventID = snapshot?.rsvps ?? [:]
            notesByEventID = [:]
            participantProfiles = snapshot?.profiles ?? [:]
            isLoadingNotes = false
            notesError = nil
        }
        displayedRange = range
        displayedStart = start
        displayedEnd = end
        lastError = nil
        if !force, let snapshot, Date().timeIntervalSince(snapshot.savedAt) < 30 {
            isLoading = false
            return
        }
        let mutationRevision = monthMutationRevision
        isLoading = true
        defer {
            if generation == AccountStorage.generation, monthRequestID == requestID { isLoading = false }
        }
        do {
            let rows: [CalendarEventRow] = try await client
                .from("whisper_calendar_events")
                .select()
                .gte("start_time", value: startISO)
                .lt("start_time", value: endISO)
                .order("start_time", ascending: true)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation, monthRequestID == requestID else { return }
            guard mutationRevision == monthMutationRevision else { return }
            events = rows
            let eventIDs = Set(rows.map(\.id))
            rsvpsByEventID = rsvpsByEventID.filter { eventIDs.contains($0.key) }
            notesByEventID = notesByEventID.filter { eventIDs.contains($0.key) }
            monthContentRevision = UUID()
            // A failed RSVP read must not become a fresh, empty month snapshot.
            let rsvps = try await fetchRSVPs(eventIDs: Array(eventIDs))
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  monthRequestID == requestID, mutationRevision == monthMutationRevision else { return }
            rsvpsByEventID = rsvps
            let profiles = await fetchParticipantProfiles(events: rows, rsvps: rsvps)
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  monthRequestID == requestID, mutationRevision == monthMutationRevision else { return }
            participantProfiles = profiles
            recentMonths.insert(MonthSnapshot(events: rows, rsvps: rsvps, profiles: profiles, savedAt: Date()), for: range)
            mirrorUpcomingToWidgets(windowEnd: end)
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, monthRequestID == requestID else { return }
            lastError = "Couldn't refresh this month. Please try again."
        }
    }

    /// Mirrors the next upcoming events into the App Group so the Shared
    /// Calendar widget + the Apple Watch stay current. Skipped for windows
    /// that end in the past — browsing an old month must never clobber the
    /// widget's upcoming list.
    private func mirrorUpcomingToWidgets(windowEnd: Date) {
        guard windowEnd > Date() else { return }
        let cutoff = Date().addingTimeInterval(-30 * 60)
        let upcoming: [WhisperWidgetSync.CompactEvent] = events.compactMap { e in
            guard let start = WhisperBackendService.parseISO(e.start_time), start > cutoff else { return nil }
            return WhisperWidgetSync.CompactEvent(
                title: e.title,
                when: start.timeIntervalSince1970,
                type: e.event_type,
                host: e.created_by_username,
                link: (e.meeting_link?.isEmpty == false)
            )
        }
        WhisperWidgetSync.writeCalendar(Array(upcoming.prefix(8)))
    }

    private func fetchRSVPs(eventIDs: [String]) async throws -> [String: [CalendarRSVPRow]] {
        guard !eventIDs.isEmpty else { return [:] }
        do {
            let rows: [CalendarRSVPRow] = try await client
                .from("whisper_calendar_rsvps")
                .select()
                .in("event_id", values: eventIDs)
                .execute()
                .value
            var map: [String: [CalendarRSVPRow]] = [:]
            for r in rows {
                map[r.event_id, default: []].append(r)
            }
            return map
        } catch { throw error }
    }

    private func fetchNotes(eventIDs: [String]) async throws -> [String: [CalendarNoteRow]] {
        guard !eventIDs.isEmpty else { return [:] }
        do {
            let rows: [CalendarNoteRow] = try await client
                .from("whisper_calendar_notes")
                .select()
                .in("event_id", values: eventIDs)
                .order("created_at", ascending: true)
                .execute()
                .value
            var map: [String: [CalendarNoteRow]] = [:]
            for n in rows {
                map[n.event_id, default: []].append(n)
            }
            return map
        } catch { throw error }
    }

    /// The selected day's event IDs, not the entire month. Mutation tokens
    /// prevent a delayed read from restoring a deleted note or undoing a write.
    func fetchNotesForEvents(_ eventIDs: [String]) async {
        let allowed = Set(events.map(\.id))
        let ids = Array(Set(eventIDs).intersection(allowed)).sorted()
        let request = UUID(); notesRequestID = request
        let generation = AccountStorage.generation
        let range = displayedRange
        let revisions = noteRevisions
        notesError = nil
        isLoadingNotes = !ids.isEmpty
        defer { if notesRequestID == request { isLoadingNotes = false } }
        guard isRemote, !ids.isEmpty else { return }
        do {
            let notes = try await fetchNotes(eventIDs: ids)
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  notesRequestID == request, displayedRange == range else { return }
            let currentIDs = Set(events.map(\.id))
            for id in ids where currentIDs.contains(id) && revisions[id] == noteRevisions[id] {
                notesByEventID[id] = notes[id] ?? []
            }
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  notesRequestID == request, displayedRange == range else { return }
            notesError = "Notes couldn’t refresh just now."
        }
    }

    private func fetchParticipantProfiles(events: [CalendarEventRow], rsvps: [String: [CalendarRSVPRow]]) async -> [String: WhisperBackendService.WhisperPublicProfile] {
        var ids = Set<String>()
        for e in events {
            ids.insert(e.created_by)
            for uid in e.tagged_user_ids { ids.insert(uid) }
        }
        for (_, rsvps) in rsvps {
            for r in rsvps { ids.insert(r.user_id) }
        }
        guard !ids.isEmpty else { return [:] }
        // Use the backend service's batch profile fetcher
        let map = await WhisperBackendService.shared.fetchPublicProfiles(userIDs: Array(ids))
        return map
    }

    // MARK: - Create

    /// Number of materialized occurrences created for a recurring event.
    private static let recurrenceInstances = 8

    /// Advances a date by one recurrence step ("weekly", "biweekly", "monthly").
    nonisolated private static func nextOccurrence(_ date: Date, recurrence: String) -> Date {
        let cal = Calendar.current
        switch recurrence {
        case "weekly": return cal.date(byAdding: .day, value: 7, to: date) ?? date
        case "biweekly": return cal.date(byAdding: .day, value: 14, to: date) ?? date
        case "monthly": return cal.date(byAdding: .month, value: 1, to: date) ?? date
        default: return date
        }
    }

    /// Creates a calendar event and sends a team-message DM to each tagged user.
    /// Recurring events are materialized as real rows (up to 8 occurrences)
    /// sharing a `recurrence_group`, matching the web behavior.
    @discardableResult
    func createEvent(
        title: String,
        description: String?,
        eventType: String,
        startTime: Date,
        endTime: Date? = nil,
        location: String?,
        meetingLink: String?,
        taggedUserIDs: [String],
        taggedUsernames: [String],
        recurrence: String = "none"
    ) async -> CalendarEventRow? {
        guard isRemote else { return nil }
        let generation = AccountStorage.generation
        // A multi-day event carries its span into every recurrence instance.
        let span: TimeInterval? = endTime.map { $0.timeIntervalSince(startTime) }.flatMap { $0 > 0 ? $0 : nil }
        let hydrated = await LeaderboardService.shared.hydrateUsernameFromSupabase()
        guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
        let myUsername = WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? hydrated
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"

        let isRecurring = recurrence != "none"
        let group = isRecurring ? UUID().uuidString : nil
        let count = isRecurring ? Self.recurrenceInstances : 1
        var occurrence = startTime
        var firstRow: CalendarEventRow?
        var includeRecurrence = isRecurring

        for i in 0..<count {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
            let row = await insertEvent(
                title: title, description: description, eventType: eventType,
                startTime: occurrence,
                endTime: span.map { occurrence.addingTimeInterval($0) },
                location: location, meetingLink: meetingLink,
                taggedUserIDs: taggedUserIDs, taggedUsernames: taggedUsernames,
                myUsername: myUsername,
                recurrence: includeRecurrence ? recurrence : nil,
                recurrenceGroup: includeRecurrence ? group : nil,
                recurrenceColumnsSupported: &includeRecurrence
            )
            guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
            guard let row else {
                if firstRow != nil { break } // partial series is fine
                return nil
            }
            if firstRow == nil {
                firstRow = row
                // Only the first occurrence sends invites — no DM spam per instance.
                await sendTeamMessages(for: row, myUsername: myUsername, kind: "invite")
            }
            if !includeRecurrence && isRecurring && i == 0 { break }
            occurrence = Self.nextOccurrence(occurrence, recurrence: recurrence)
        }
        return firstRow
    }

    /// Inserts a single event row, dropping optional columns the deployed
    /// schema doesn't have yet. Sets `recurrenceColumnsSupported` to false
    /// when the recurrence columns are missing so callers stop materializing.
    private func insertEvent(
        title: String,
        description: String?,
        eventType: String,
        startTime: Date,
        endTime: Date? = nil,
        location: String?,
        meetingLink: String?,
        taggedUserIDs: [String],
        taggedUsernames: [String],
        myUsername: String,
        recurrence: String?,
        recurrenceGroup: String?,
        recurrenceColumnsSupported: inout Bool
    ) async -> CalendarEventRow? {
        let generation = AccountStorage.generation
        let isoFormatter = ISO8601DateFormatter()
        let iso = isoFormatter.string(from: startTime)
        let eventID = UUID().uuidString
        var payload: [String: AnyJSON] = [
            "id": .string(eventID),
            "created_by": .string(currentUID),
            "created_by_username": .string(myUsername),
            "title": .string(title),
            "description": .string(description ?? ""),
            "event_type": .string(eventType),
            "start_time": .string(iso),
            "tagged_user_ids": .array(taggedUserIDs.map { .string($0) }),
            "tagged_usernames": .array(taggedUsernames.map { .string($0) })
        ]
        if let endTime, endTime > startTime { payload["end_time"] = .string(isoFormatter.string(from: endTime)) }
        if let location { payload["location"] = .string(location) }
        if let meetingLink { payload["meeting_link"] = .string(meetingLink) }
        if let recurrence { payload["recurrence"] = .string(recurrence) }
        if let recurrenceGroup { payload["recurrence_group"] = .string(recurrenceGroup) }

        let droppable: Set<String> = ["description", "location", "meeting_link", "tagged_user_ids", "tagged_usernames", "created_by_username", "recurrence", "recurrence_group"]

        for _ in 0..<8 {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
            do {
                let inserted: [CalendarEventRow] = try await client
                    .from("whisper_calendar_events")
                    .insert(payload)
                    .select()
                    .execute()
                    .value
                guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
                if let row = inserted.first {
                    invalidateMonthReads()
                    // Recurring creation may include dates outside the viewed month.
                    if let displayedStart, let displayedEnd, startTime >= displayedStart, startTime < displayedEnd {
                        events.append(row)
                        events.sort { $0.start_time < $1.start_time }
                    }
                    lastError = nil
                    return row
                }
            } catch {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
                let msg = error.localizedDescription
                guard let column = Self.missingColumnName(in: msg),
                      droppable.contains(column),
                      payload[column] != nil else {
                    lastError = "Couldn't create this event. Please try again."
                    return nil
                }
                if column == "recurrence" || column == "recurrence_group" {
                    recurrenceColumnsSupported = false
                    payload.removeValue(forKey: "recurrence")
                    payload.removeValue(forKey: "recurrence_group")
                } else {
                    payload.removeValue(forKey: column)
                }
                continue
            }
        }
        lastError = "Couldn't create this event. Please try again."
        return nil
    }

    /// Sends a calendar team-message DM (invite/update/cancelled) from the
    /// organizer to each tagged user.
    private func sendTeamMessages(for event: CalendarEventRow, myUsername: String, kind: String) async {
        let generation = AccountStorage.generation
        let embed = WhisperCalendarEmbed.Payload(
            id: UUID().uuidString,
            eventID: event.id,
            title: event.title,
            eventType: event.event_type,
            startTime: event.start_time,
            location: event.location,
            meetingLink: event.meeting_link,
            createdByUsername: myUsername,
            taggedUsernames: event.tagged_usernames,
            kind: kind
        )
        let body = WhisperCalendarEmbed.encode(embed)
        for (idx, uid) in event.tagged_user_ids.enumerated() {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            guard uid.lowercased() != currentUID.lowercased() else { continue }
            let username = idx < event.tagged_usernames.count ? event.tagged_usernames[idx] : "user"
            _ = await WhisperBackendService.shared.sendMessage(
                toUserID: uid,
                toUsername: username,
                body: body
            )
        }
    }

    // MARK: - Delete

    /// Deletes an event and DMs every tagged user a cancellation notice from
    /// the organizer.
    func deleteEvent(eventID: String) async -> Bool {
        guard isRemote else { return false }
        let generation = AccountStorage.generation
        let cancelled = events.first { $0.id == eventID }
        do {
            try await client
                .from("whisper_calendar_events")
                .delete()
                .eq("id", value: eventID)
                .eq("created_by", value: currentUID)
                .execute()
            guard generation == AccountStorage.generation else { return false }
            invalidateMonthReads()
            noteRevisions[eventID] = UUID()
            events.removeAll { $0.id == eventID }
            rsvpsByEventID.removeValue(forKey: eventID)
            notesByEventID.removeValue(forKey: eventID)
            lastError = nil
            if let cancelled, !cancelled.tagged_user_ids.isEmpty {
                let myUsername = WhisperUserService.shared.me?.username
                    ?? LeaderboardService.shared.savedUsername
                    ?? "you"
                await sendTeamMessages(for: cancelled, myUsername: myUsername, kind: "cancelled")
            }
            return true
        } catch {
            guard generation == AccountStorage.generation else { return false }
            lastError = "Couldn't delete this event. Please try again."
            return false
        }
    }

    // MARK: - RSVP

    func setRSVP(eventID: String, status: String) async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        let myUsername = WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? "you"
        let payload: [String: AnyJSON] = [
            "event_id": .string(eventID),
            "user_id": .string(currentUID),
            "username": .string(myUsername),
            "status": .string(status)
        ]
        do {
            try await client
                .from("whisper_calendar_rsvps")
                .upsert(payload, onConflict: "event_id,user_id")
                .execute()
            guard generation == AccountStorage.generation else { return }
            invalidateMonthReads()
            // Refresh RSVPs for this event
            let rows: [CalendarRSVPRow] = try await client
                .from("whisper_calendar_rsvps")
                .select()
                .eq("event_id", value: eventID)
                .execute()
                .value
            guard generation == AccountStorage.generation else { return }
            if events.contains(where: { $0.id == eventID }) { rsvpsByEventID[eventID] = rows }
        } catch {
            guard generation == AccountStorage.generation else { return }
            lastError = "Couldn't update your RSVP. Please try again."
        }
    }

    // MARK: - Notes

    func addNote(eventID: String, body: String) async {
        guard isRemote, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let generation = AccountStorage.generation
        let myUsername = WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? "you"
        let notePayload: [String: AnyJSON] = [
            "event_id": .string(eventID),
            "user_id": .string(currentUID),
            "username": .string(myUsername),
            "body": .string(body.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        do {
            try await client
                .from("whisper_calendar_notes")
                .insert(notePayload)
                .execute()
            guard generation == AccountStorage.generation else { return }
            let revision = UUID(); noteRevisions[eventID] = revision
            // Refresh notes for this event
            let rows: [CalendarNoteRow] = try await client
                .from("whisper_calendar_notes")
                .select()
                .eq("event_id", value: eventID)
                .order("created_at", ascending: true)
                .execute()
                .value
            guard generation == AccountStorage.generation else { return }
            guard noteRevisions[eventID] == revision, events.contains(where: { $0.id == eventID }) else { return }
            notesByEventID[eventID] = rows
        } catch {
            guard generation == AccountStorage.generation else { return }
            lastError = "Couldn't add your note. Please try again."
        }
    }

    func deleteNote(noteID: String, eventID: String) async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        do {
            try await client
                .from("whisper_calendar_notes")
                .delete()
                .eq("id", value: noteID)
                .eq("user_id", value: currentUID)
                .execute()
            guard generation == AccountStorage.generation else { return }
            noteRevisions[eventID] = UUID()
            notesByEventID[eventID]?.removeAll { $0.id == noteID }
        } catch {
            guard generation == AccountStorage.generation else { return }
            lastError = "Couldn't delete this note. Please try again."
        }
    }

    // MARK: - Helpers

    /// Events grouped by day key "yyyy-M-d"
    /// Groups events by local day — a MULTI-DAY event (end_time on a later
    /// day) lands on EVERY day it spans, not just the day it starts.
    func eventsByDay() -> [String: [CalendarEventRow]] {
        var map: [String: [CalendarEventRow]] = [:]
        for e in events {
            for key in Self.dayKeys(for: e) {
                map[key, default: []].append(e)
            }
        }
        return map
    }

    /// The grid's day key (year-month-day, month 1-based like `Calendar`).
    nonisolated static func dayKey(_ date: Date) -> String {
        let cal = Calendar.current
        return "\(cal.component(.year, from: date))-\(cal.component(.month, from: date))-\(cal.component(.day, from: date))"
    }

    /// Every local day an event touches, start → end inclusive. An end
    /// exactly at midnight belongs to the previous day. Capped at 60 days.
    nonisolated static func dayKeys(for e: CalendarEventRow) -> [String] {
        guard let start = WhisperBackendService.parseISO(e.start_time) else { return [] }
        var keys = [dayKey(start)]
        guard let end = e.end_time.flatMap(WhisperBackendService.parseISO), end > start else { return keys }
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: start)
        var last = cal.startOfDay(for: end)
        let endComponents = cal.dateComponents([.hour, .minute], from: end)
        if endComponents.hour == 0 && endComponents.minute == 0 && last > cursor,
           let previous = cal.date(byAdding: .day, value: -1, to: last) {
            last = previous
        }
        var guardCount = 0
        while cursor < last && guardCount < 60 {
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            keys.append(dayKey(cursor))
            guardCount += 1
        }
        return keys
    }

    /// "Day 2 of 3" for a multi-day event viewed on `date`; nil otherwise.
    nonisolated static func multiDayLabel(_ e: CalendarEventRow, on date: Date) -> String? {
        let keys = dayKeys(for: e)
        guard keys.count > 1, let idx = keys.firstIndex(of: dayKey(date)) else { return nil }
        return "Day \(idx + 1) of \(keys.count)"
    }

    // MARK: - Conflicts, recaps, export

    /// Assumed duration when an event has no end time.
    nonisolated private static let defaultDurationSeconds: TimeInterval = 60 * 60

    nonisolated static func window(of e: CalendarEventRow) -> (start: Date, end: Date)? {
        guard let start = WhisperBackendService.parseISO(e.start_time) else { return nil }
        let end = e.end_time.flatMap(WhisperBackendService.parseISO) ?? start.addingTimeInterval(defaultDurationSeconds)
        return (start, end)
    }

    /// Event IDs where two events overlap in time AND share a participant.
    func conflictEventIDs() -> Set<String> {
        var conflicts = Set<String>()
        let rows = events
        for i in rows.indices {
            guard let wa = Self.window(of: rows[i]) else { continue }
            let pa = Set([rows[i].created_by] + rows[i].tagged_user_ids)
            for j in rows.indices where j > i {
                guard let wb = Self.window(of: rows[j]) else { continue }
                guard wa.start < wb.end && wb.start < wa.end else { continue }
                let pb = Set([rows[j].created_by] + rows[j].tagged_user_ids)
                if !pa.isDisjoint(with: pb) {
                    conflicts.insert(rows[i].id)
                    conflicts.insert(rows[j].id)
                }
            }
        }
        return conflicts
    }

    /// Marker prefix identifying a post-event recap in the shared notes table.
    nonisolated static let recapPrefix = "📸 Recap — "

    /// True once the event has finished (start + duration in the past).
    nonisolated static func hasEnded(_ e: CalendarEventRow) -> Bool {
        guard let w = window(of: e) else { return false }
        return w.end < Date()
    }

    /// Adds a post-event recap entry (stored as a marked note).
    func addRecap(eventID: String, body: String) async {
        await addNote(eventID: eventID, body: Self.recapPrefix + body)
    }

    /// Builds an RFC 5545 .ics document from the loaded events so the team
    /// calendar can be imported into Google / Apple Calendar.
    func buildICS() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0",
            "PRODID:-//Whisper//Team Calendar//EN",
            "CALSCALE:GREGORIAN", "X-WR-CALNAME:Whisper Team Calendar"
        ]
        for e in events {
            guard let w = Self.window(of: e) else { continue }
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(e.id)@whisper")
            lines.append("DTSTAMP:\(fmt.string(from: Date()))")
            lines.append("DTSTART:\(fmt.string(from: w.start))")
            lines.append("DTEND:\(fmt.string(from: w.end))")
            lines.append("SUMMARY:\(esc(e.title))")
            var desc = [String]()
            if let d = e.description, !d.isEmpty { desc.append(d) }
            if let link = e.meeting_link, !link.isEmpty { desc.append("Join: \(link)") }
            desc.append("Organized by @\(e.created_by_username ?? "user") on Whisper")
            lines.append("DESCRIPTION:\(esc(desc.joined(separator: "\n")))")
            if let loc = e.location, !loc.isEmpty { lines.append("LOCATION:\(esc(loc))") }
            if let link = e.meeting_link, !link.isEmpty { lines.append("URL:\(link)") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    /// Writes the .ics to a temp file for sharing via ShareLink.
    func exportICSFile() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-team-calendar.ics")
        do {
            try buildICS().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            lastError = "Couldn't export calendar: \(error.localizedDescription)"
            return nil
        }
    }

    /// All participant user IDs for a given event (creator + tagged + RSVP'd)
    func participants(for eventID: String, event: CalendarEventRow) -> [String] {
        var ids = Set<String>()
        ids.insert(event.created_by)
        for uid in event.tagged_user_ids { ids.insert(uid) }
        for r in rsvpsByEventID[eventID] ?? [] {
            if r.status == "going" { ids.insert(r.user_id) }
        }
        return Array(ids)
    }

    /// Role label for a participant profile. Uses the shared
    /// `WhisperRoleResolver` so coach / athlete / verified / admin / owner
    /// roles are resolved consistently across the app.
    @MainActor
    static func roleLabel(for profile: WhisperBackendService.WhisperPublicProfile?) -> String? {
        guard let p = profile, let username = p.username, !username.isEmpty else { return nil }
        return WhisperRoleResolver.descriptor(userID: p.id, username: username)?.text
    }

    /// Parses the missing column name out of a PostgREST schema-cache error.
    /// Mirrors the private method on `WhisperBackendService`.
    nonisolated private static func missingColumnName(in message: String) -> String? {
        let lower = message.lowercased()
        guard lower.contains("could not find") && lower.contains("column") else { return nil }
        guard let start = message.firstIndex(of: "'") else { return nil }
        let afterStart = message.index(after: start)
        guard let end = message[afterStart...].firstIndex(of: "'") else { return nil }
        return String(message[afterStart..<end])
    }
}
