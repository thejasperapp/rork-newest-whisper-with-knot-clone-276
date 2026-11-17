import Foundation
import Observation
import Supabase

@MainActor @Observable
final class WhisperMeetAgendaViewModel {
    private var events: [WhisperCalendarService.CalendarEventRow] = []
    private var operation: UUID = UUID()
    private(set) var isLoading: Bool = true
    private(set) var errorText: String?

    func load(day: Date) async {
        let token = UUID(); operation = token
        let generation = AccountStorage.generation
        isLoading = true; errorText = nil; events = []
        defer { if operation == token { isLoading = false } }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: day), to: calendar.startOfDay(for: day)) ?? day
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }
        do {
            let rows: [WhisperCalendarService.CalendarEventRow] = try await SupabaseService.shared.client
                .from("whisper_calendar_events").select()
                .gte("start_time", value: start.ISO8601Format()).lt("start_time", value: end.ISO8601Format())
                .order("start_time", ascending: true).execute().value
            guard !Task.isCancelled, token == operation, generation == AccountStorage.generation else { return }
            events = rows
        } catch {
            guard token == operation, generation == AccountStorage.generation, !Task.isCancelled else { return }
            errorText = "Calendar couldn’t refresh. Your meeting links are still available."
        }
    }

    func hasItems(on day: Date, meetings: [WhisperMeetingRow]) -> Bool { !items(on: day, meetings: meetings).isEmpty }

    func items(on day: Date, meetings: [WhisperMeetingRow], now: Date = Date()) -> [WhisperMeetAgendaItem] {
        let rows = meetings.filter { !$0.title.hasPrefix("Video call with @") && !$0.title.hasPrefix("Audio call with @") }
        var used: Set<String> = []
        var result: [WhisperMeetAgendaItem] = []
        func live(_ row: WhisperMeetingRow?) -> Bool {
            guard let row, row.isLive, let opened = WhisperBackendService.parseISO(row.started_at ?? row.created_at) else { return false }
            return now.timeIntervalSince(opened) >= 0 && now.timeIntervalSince(opened) < 86_400
        }
        for event in events {
            guard let start = WhisperBackendService.parseISO(event.start_time), Calendar.current.isDate(start, inSameDayAs: day) else { continue }
            let id = event.meeting_link.flatMap { WhisperMeetingService.meetingID(fromText: $0) }
            let meeting = rows.first { $0.id.lowercased() == id?.lowercased() }
            if let meeting { used.insert(meeting.id) }
            let ended = meeting?.isEnded == true || (meeting?.isLive == true && !live(meeting)) || (WhisperBackendService.parseISO(event.end_time).map { $0 < now } ?? false)
            result.append(WhisperMeetAgendaItem(id: "calendar-" + event.id, title: event.title, start: start, subtitle: "@\(event.created_by_username ?? "host") · \(event.tagged_usernames.count) guests", link: event.meeting_link, meeting: meeting, group: live(meeting) ? "Happening now" : ended ? "Earlier" : "Upcoming"))
        }
        for meeting in rows where !used.contains(meeting.id) {
            let iso = meeting.status == "scheduled" ? meeting.scheduled_at : meeting.started_at ?? meeting.created_at
            guard let start = WhisperBackendService.parseISO(iso), Calendar.current.isDate(start, inSameDayAs: day) else { continue }
            let ended = meeting.isEnded || (meeting.isLive && !live(meeting))
            result.append(WhisperMeetAgendaItem(id: meeting.id, title: meeting.title, start: start, subtitle: live(meeting) ? "Live · @\(meeting.host_username)" : "@\(meeting.host_username)", link: WhisperMeetingService.link(for: meeting.id), meeting: meeting, group: live(meeting) ? "Happening now" : ended ? "Earlier" : "Upcoming"))
        }
        return result.sorted { $0.start < $1.start }
    }
}
