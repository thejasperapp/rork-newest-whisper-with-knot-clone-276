import Foundation
import Observation
import Supabase
import UserNotifications

@MainActor @Observable final class JasperCalendarViewModel {
    private(set) var events: [JasperCalendarEvent] = []
    private(set) var connected: Bool = false
    private(set) var configured: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var remindedIDs: Set<String> = []
    var errorText: String?
    var notice: String?
    let owner = AccountStorage.currentUserID.lowercased()
    private let generation = AccountStorage.generation
    private var isCurrent: Bool { owner == AccountStorage.currentUserID.lowercased() && generation == AccountStorage.generation }
    func load() async {
        guard isCurrent, !isLoading else { return }; isLoading = true; errorText = nil; defer { isLoading = false }
        var all: [JasperCalendarEvent] = []
        do {
            let rows: [WhisperCalendarService.CalendarEventRow] = try await SupabaseService.shared.client.from("whisper_calendar_events").select().or("created_by.eq.\(owner),tagged_user_ids.cs.{\(owner)}").gte("start_time", value: Date().ISO8601Format()).lt("start_time", value: Date().addingTimeInterval(30 * 86400).ISO8601Format()).order("start_time", ascending: true).limit(250).execute().value
            guard isCurrent else { return }
            all = rows.map { .init(id: "whisper:\($0.id)", title: $0.title, start: $0.start_time, end: $0.end_time ?? "", allDay: false, link: $0.meeting_link ?? "", source: "Whisper Calendar") }
        } catch { errorText = "Whisper Calendar could not load. Please refresh." }
        do {
            struct Status: Decodable { let connected: Bool; let configured: Bool }
            let status: Status = try await JasperMeetingService.request("google/status", owner: owner)
            guard isCurrent else { return }; connected = status.connected; configured = status.configured
            if connected {
                struct Events: Decodable { let events: [JasperCalendarEvent]; let partial: Bool }
                let result: Events = try await JasperMeetingService.request("google/events", owner: owner)
                guard isCurrent else { return }; all += result.events
                if result.partial { notice = "Some Google events are outside this window. Open Google Calendar for your full schedule." }
            }
        } catch { if isCurrent { errorText = error.localizedDescription } }
        guard isCurrent else { return }; events = all.sorted { $0.start < $1.start }
    }
    func connect() async -> URL? {
        do { struct Link: Decodable { let url: String }; let result: Link = try await JasperMeetingService.request("google/connect", owner: owner, body: [:]); guard isCurrent, let url = URL(string: result.url), url.scheme == "https" else { return nil }; return url }
        catch { if isCurrent { errorText = error.localizedDescription }; return nil }
    }
    func disconnect() async {
        do {
            struct Result: Decodable { let disconnected: Bool; let revoked: Bool }
            let result: Result = try await JasperMeetingService.request("google/disconnect", owner: owner, body: [:])
            guard isCurrent else { return }; connected = false; events.removeAll { $0.source == "Google Calendar" }
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("jasper-calendar:\(owner):google:") })
            if !result.revoked { notice = "Disconnected here. You can also revoke access in Google account settings." }
        } catch { if isCurrent { errorText = error.localizedDescription } }
    }
    func remind(_ event: JasperCalendarEvent) async {
        guard isCurrent, !event.allDay, let start = WhisperBackendService.parseISO(event.start), start > Date() else { return }
        do {
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound]), isCurrent else { errorText = "Enable notifications in Settings to receive meeting reminders."; return }
            let content = UNMutableNotificationContent(); content.title = "Upcoming meeting"; content.body = "A meeting on your Jasper agenda starts soon. Open Whisper for details."; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, start.timeIntervalSinceNow - 300), repeats: false)
            try await center.add(UNNotificationRequest(identifier: "jasper-calendar:\(owner):\(event.id)", content: content, trigger: trigger))
            guard isCurrent else { center.removePendingNotificationRequests(withIdentifiers: ["jasper-calendar:\(owner):\(event.id)"]); return }
            remindedIDs.insert(event.id); notice = "Reminder set for this event. Refresh and set it again if the event is rescheduled."
        } catch { if isCurrent { errorText = "The reminder could not be scheduled. Please try again." } }
    }
}
