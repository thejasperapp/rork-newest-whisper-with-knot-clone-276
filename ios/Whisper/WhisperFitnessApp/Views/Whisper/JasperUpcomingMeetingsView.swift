import SwiftUI

struct JasperUpcomingMeetingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: JasperCalendarViewModel = JasperCalendarViewModel()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Coming up.").font(.title2.weight(.semibold))
                    Text("Whisper events and your connected Google primary calendar. Read-only; Jasper won’t change your events. Use the Google account with the same email as your Whisper account.").font(.subheadline).foregroundStyle(.secondary)
                    Button(model.connected ? "Disconnect Google Calendar" : "Connect Google Calendar") { Task { if model.connected { await model.disconnect() } else if let url = await model.connect() { _ = await UIApplication.shared.open(url) } } }.frame(minHeight: 44)
                    Button("Refresh calendars") { Task { await model.load() } }.frame(minHeight: 44)
                }
                Section("Next 30 days") {
                    ForEach(model.events.prefix(60)) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.title).font(.headline)
                            Text(event.allDay ? "\(event.start) · All day" : WhisperBackendService.parseISO(event.start)?.formatted(date: .abbreviated, time: .shortened) ?? event.start).font(.subheadline)
                            Text(event.source).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                if let url = URL(string: event.link), url.scheme == "https" { Link("Open meeting", destination: url).font(.caption).frame(minHeight: 44) }
                                Spacer()
                                if !event.allDay { Button(model.remindedIDs.contains(event.id) ? "Reminder set" : "Remind me") { Task { await model.remind(event) } }.font(.caption).frame(minHeight: 44) }
                            }
                        }.padding(.vertical, 6)
                    }
                    if model.isLoading { ProgressView("Loading upcoming meetings…") }
                    if model.events.isEmpty && !model.isLoading && model.errorText == nil { WhisperEmptyState(icon: "calendar", title: "A little room in your calendar", message: "No upcoming events returned for the next 30 days.", isCard: false) }
                    if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red) }
                    if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }
            }.navigationTitle("Upcoming").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .whisperRefreshable { await model.load() }
                .task(id: scenePhase) { if scenePhase == .active { await model.load() } }
        }
    }
}
