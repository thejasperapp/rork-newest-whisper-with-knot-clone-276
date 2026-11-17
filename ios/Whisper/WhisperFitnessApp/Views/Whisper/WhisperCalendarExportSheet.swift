import SwiftUI
import EventKit

/// Export options for the shared team calendar. The web app downloads an
/// .ics file, but on iOS that file can't be imported into Apple Calendar in
/// one tap — so this sheet writes events straight into Apple Calendar via
/// EventKit and deep-links individual events into Google Calendar. The .ics
/// share stays available for desktop/Google subscription workflows.
struct WhisperCalendarExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    let events: [WhisperCalendarService.CalendarEventRow]
    let icsURL: URL?

    @State private var savingAll: Bool = false
    @State private var savedAll: Bool = false
    @State private var savedEventIDs: Set<String> = []
    @State private var errorMessage: String?

    /// Only upcoming (or currently running) events are worth exporting.
    private var exportableEvents: [WhisperCalendarService.CalendarEventRow] {
        events.filter { !WhisperCalendarService.hasEnded($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        saveAllAppleCard
                        icsCard
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                        perEventSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Save to calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    // MARK: - Apple Calendar (all events)

    private var saveAllAppleCard: some View {
        Button {
            Haptics.tap()
            guard !savingAll, !savedAll else { return }
            Task { await saveToApple(exportableEvents, markAll: true) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: savedAll ? "checkmark.circle.fill" : "calendar.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 40, height: 40)
                    .background(WhisperTheme.ink(colorScheme), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(savedAll ? "Saved to Apple Calendar" : "Save all to Apple Calendar")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(savedAll
                         ? "\(exportableEvents.count) upcoming event\(exportableEvents.count == 1 ? "" : "s") added"
                         : "Adds every upcoming team event to your calendar")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                if savingAll {
                    ProgressView().tint(WhisperTheme.muted(colorScheme))
                } else if !savedAll {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(exportableEvents.isEmpty)
        .opacity(exportableEvents.isEmpty ? 0.5 : 1)
        .accessibilityLabel("Save all events to Apple Calendar")
    }

    // MARK: - .ics share

    @ViewBuilder
    private var icsCard: some View {
        if let icsURL {
            ShareLink(item: icsURL) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 40, height: 40)
                        .background(WhisperTheme.surface(colorScheme), in: Circle())
                        .overlay(Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share .ics file")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("Import into Google or Apple Calendar on desktop")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(14)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Per-event rows

    @ViewBuilder
    private var perEventSection: some View {
        if !exportableEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Upcoming events")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(exportableEvents.enumerated()), id: \.element.id) { index, event in
                        eventRow(event)
                        if index < exportableEvents.count - 1 {
                            Rectangle()
                                .fill(WhisperTheme.hairline(colorScheme))
                                .frame(height: 0.5)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            }
        } else {
            Text("No upcoming events to export this month.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
        }
    }

    private func eventRow(_ event: WhisperCalendarService.CalendarEventRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                if let w = WhisperCalendarService.window(of: event) {
                    Text(Self.rowFormatter.string(from: w.start))
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                Task { await saveToApple([event], markAll: false) }
            } label: {
                if savedEventIDs.contains(event.id) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                } else {
                    Text("Apple")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(WhisperTheme.ink(colorScheme).opacity(0.35), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save \(event.title) to Apple Calendar")
            Button {
                Haptics.tap()
                if let url = googleURL(for: event) {
                    openURL(url)
                }
            } label: {
                Text("Google")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(WhisperTheme.ink(colorScheme).opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save \(event.title) to Google Calendar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Apple Calendar writer

    private func saveToApple(
        _ rows: [WhisperCalendarService.CalendarEventRow],
        markAll: Bool
    ) async {
        errorMessage = nil
        if markAll { savingAll = true }
        defer { if markAll { savingAll = false } }

        let store = EKEventStore()
        let granted: Bool = await {
            do { return try await store.requestFullAccessToEvents() }
            catch { return false }
        }()
        guard granted else {
            errorMessage = "Calendar access denied — enable it in Settings → Privacy → Calendars."
            Haptics.warning()
            return
        }

        var savedCount = 0
        for event in rows {
            guard let w = WhisperCalendarService.window(of: event) else { continue }
            let ek = EKEvent(eventStore: store)
            ek.title = event.title
            ek.startDate = w.start
            ek.endDate = w.end
            ek.location = event.location
            var notes = [String]()
            if let d = event.description, !d.isEmpty { notes.append(d) }
            if let link = event.meeting_link, !link.isEmpty {
                notes.append("Join: \(link)")
                ek.url = URL(string: link)
            }
            notes.append("Organized by @\(event.created_by_username ?? "user") on Whisper")
            ek.notes = notes.joined(separator: "\n")
            ek.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(ek, span: .thisEvent)
                savedCount += 1
                savedEventIDs.insert(event.id)
            } catch {
                print("[CalendarExport] EventKit save failed: \(error.localizedDescription)")
            }
        }

        if savedCount > 0 {
            Haptics.success()
            if markAll { savedAll = true }
        } else {
            errorMessage = "Couldn't save to Apple Calendar. Please try again."
            Haptics.warning()
        }
    }

    // MARK: - Google Calendar deep link

    /// Google Calendar's event template URL — opens the pre-filled "add
    /// event" screen in the Google Calendar app (if installed) or Safari.
    private func googleURL(for event: WhisperCalendarService.CalendarEventRow) -> URL? {
        guard let w = WhisperCalendarService.window(of: event) else { return nil }
        var details = [String]()
        if let d = event.description, !d.isEmpty { details.append(d) }
        if let link = event.meeting_link, !link.isEmpty { details.append("Join: \(link)") }
        details.append("Organized by @\(event.created_by_username ?? "user") on Whisper")

        var comps = URLComponents(string: "https://calendar.google.com/calendar/render")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: event.title),
            URLQueryItem(
                name: "dates",
                value: "\(Self.utcFormatter.string(from: w.start))/\(Self.utcFormatter.string(from: w.end))"
            ),
            URLQueryItem(name: "details", value: details.joined(separator: "\n"))
        ]
        if let loc = event.location, !loc.isEmpty {
            items.append(URLQueryItem(name: "location", value: loc))
        }
        comps?.queryItems = items
        return comps?.url
    }

    private static let utcFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private static let rowFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d · h:mm a"
        return fmt
    }()
}
