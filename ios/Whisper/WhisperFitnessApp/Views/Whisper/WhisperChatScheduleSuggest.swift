import SwiftUI

/// Detects a concrete future date being discussed in a DM thread and offers
/// to put it on the shared Whisper calendar — auto-categorized, with a
/// scheduled Whisper meeting attached so everyone can join with one tap.
enum WhisperChatScheduleDetector {
    struct Suggestion: Equatable, Identifiable {
        var id: String { messageID }
        let messageID: String
        let date: Date
        let snippet: String
        let suggestedTitle: String
        let eventType: String
    }

    /// Newest → oldest scan of the latest plain-text messages for a spoken
    /// future date ("tomorrow at 3", "Friday 2pm", "Aug 20 at noon").
    /// Embeds, links, and stale messages are skipped; relative phrases are
    /// only trusted on recent messages since NSDataDetector resolves them
    /// against "now".
    static func detect(
        messages: [WhisperMessageRow],
        otherUsername: String
    ) -> Suggestion? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return nil }
        let now = Date()

        for row in messages.suffix(14).reversed() {
            let body = row.body
            guard !body.hasPrefix("::"),
                  !body.lowercased().hasPrefix("http"),
                  body.count >= 8, body.count < 400 else { continue }
            // Only trust messages sent within the last 2 days — older threads
            // shouldn't resurrect "tomorrow" as a fresh suggestion.
            if let iso = row.created_at,
               let sent = WhisperBackendService.parseISO(iso),
               now.timeIntervalSince(sent) > 2 * 86400 { continue }

            let range = NSRange(body.startIndex..., in: body)
            for match in detector.matches(in: body, options: [], range: range) {
                guard let date = match.date,
                      match.range.length >= 3,
                      date > now.addingTimeInterval(10 * 60),
                      date < now.addingTimeInterval(90 * 86400) else { continue }
                let type = category(for: body)
                return Suggestion(
                    messageID: row.id,
                    date: date,
                    snippet: String(body.prefix(90)),
                    suggestedTitle: title(for: type, other: otherUsername),
                    eventType: type
                )
            }
        }
        return nil
    }

    /// Scans a single finalized voice utterance (meeting captions) for a
    /// concrete future date. Same NSDataDetector core as the DM scan, but
    /// utterances are always "fresh" so relative phrases are trusted.
    static func detectSpoken(text: String, now: Date = Date()) -> (date: Date, snippet: String, eventType: String)? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 8, clean.count < 400,
              let detector = try? NSDataDetector(
                  types: NSTextCheckingResult.CheckingType.date.rawValue
              ) else { return nil }
        let range = NSRange(clean.startIndex..., in: clean)
        for match in detector.matches(in: clean, options: [], range: range) {
            guard let date = match.date,
                  match.range.length >= 3,
                  date > now.addingTimeInterval(10 * 60),
                  date < now.addingTimeInterval(90 * 86400) else { continue }
            return (date, String(clean.prefix(90)), category(for: clean))
        }
        return nil
    }

    /// Title for a voice-detected suggestion inside a meeting — handles the
    /// group case where several people are on the call.
    static func groupTitle(for type: String, names: [String]) -> String {
        let base: String
        switch type {
        case "training": base = "Training"
        case "content_collab": base = "Content collab"
        case "event": base = "Event"
        case "deadline": base = "Deadline"
        default: base = "Follow-up"
        }
        guard let first = names.first, !first.isEmpty else { return base }
        if names.count == 1 { return "\(base) with @\(first)" }
        return "\(base) with @\(first) +\(names.count - 1)"
    }

    /// Keyword auto-categorization mirroring the web calendar's event types.
    static func category(for text: String) -> String {
        let lower = text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }
        if has(["train", "workout", "gym", "lift", "session", "cardio", "leg day", "run together"]) { return "training" }
        if has(["film", "shoot", "record", "collab", "content", "reel", "podcast"]) { return "content_collab" }
        if has(["deadline", "due by", "submit", "deliver by"]) { return "deadline" }
        if has(["competition", "race", "expo", "meetup", "launch party"]) { return "event" }
        return "meet"
    }

    static func label(for type: String) -> String {
        switch type {
        case "meet": return "Meet up"
        case "content_collab": return "Content collab"
        case "training": return "Training"
        case "event": return "Event"
        case "deadline": return "Deadline"
        default: return "Other"
        }
    }

    static func tint(for type: String) -> Color {
        switch type {
        case "meet": return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "content_collab": return Color(red: 0.66, green: 0.33, blue: 0.97)
        case "training": return Color(red: 0.13, green: 0.77, blue: 0.37)
        case "event": return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "deadline": return Color(red: 0.94, green: 0.27, blue: 0.27)
        default: return Color(red: 0.42, green: 0.45, blue: 0.50)
        }
    }

    /// Types that make sense to open the picker with a video meeting attached.
    static func attachesMeetingByDefault(_ type: String) -> Bool {
        type == "meet" || type == "content_collab"
    }

    private static func title(for type: String, other: String) -> String {
        switch type {
        case "training": return "Training with @\(other)"
        case "content_collab": return "Content collab with @\(other)"
        case "event": return "Event with @\(other)"
        case "deadline": return "Deadline \u{2014} @\(other)"
        default: return "Call with @\(other)"
        }
    }

    static let promptFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d \u{00B7} h:mm a"
        return f
    }()
}

// MARK: - Prompt banner

/// Floating suggestion above the composer: "you two mentioned a date — put
/// it on the shared calendar?" One tap opens the schedule sheet; the X
/// dismisses this detection permanently for that message.
struct WhisperChatSchedulePrompt: View {
    @Environment(\.colorScheme) private var colorScheme

    let suggestion: WhisperChatScheduleDetector.Suggestion
    var onAdd: () -> Void
    var onDismiss: () -> Void

    private var tint: Color { WhisperChatScheduleDetector.tint(for: suggestion.eventType) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text("Add to your shared calendar?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("\(WhisperChatScheduleDetector.promptFormatter.string(from: suggestion.date)) \u{00B7} \(WhisperChatScheduleDetector.label(for: suggestion.eventType))")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                Haptics.tap()
                onAdd()
            } label: {
                Text("Add")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(width: 26, height: 26)
                    .background(WhisperTheme.surface(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss schedule suggestion")
        }
        .padding(10)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Schedule sheet

/// Creates the shared-calendar event (auto-categorized) with an optional
/// scheduled Whisper meeting attached. The tagged person automatically gets
/// the tappable invite card in this same DM thread.
struct WhisperChatScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Everyone (besides me) who gets tagged on the calendar event — one
    /// person for a DM thread, every participant for a group meeting. Each
    /// tagged user automatically receives the invite card in DMs.
    let taggedIDs: [String]
    let taggedNames: [String]
    /// Short provenance line stored in the event description, e.g.
    /// "Planned in chat with @sam" or "Planned live in a Whisper meeting".
    let contextNote: String
    let initial: WhisperChatScheduleDetector.Suggestion
    /// Called with a confirmation toast message on success.
    var onScheduled: (String) -> Void

    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var eventType: String = "meet"
    @State private var attachMeeting: Bool = true
    @State private var creating: Bool = false
    @State private var errorText: String?

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    private let allTypes: [String] = ["meet", "training", "content_collab", "event", "deadline", "other"]

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // What was said — grounding context.
                        HStack(spacing: 8) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(muted)
                            Text(initial.snippet)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(muted)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))

                        fieldLabel("TITLE")
                        TextField("Event title", text: $title)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                            }

                        fieldLabel("CATEGORY \u{00B7} AUTO-DETECTED")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                            ForEach(allTypes, id: \.self) { type in
                                categoryChip(type)
                            }
                        }

                        fieldLabel("WHEN")
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

                        Toggle(isOn: $attachMeeting) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Attach a Whisper meeting")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(ink)
                                Text("A scheduled video room is created and linked on the event \u{2014} everyone joins with one tap.")
                                    .font(.caption2)
                                    .foregroundStyle(muted)
                            }
                        }
                        .tint(.green)
                        .padding(14)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))

                        Text("Goes on your shared Whisper calendar. \(namesLine) \(taggedNames.count == 1 ? "is" : "are") tagged and get\(taggedNames.count == 1 ? "s" : "") the invite card in DMs.")
                            .font(.caption2)
                            .foregroundStyle(muted)

                        if let errorText {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Haptics.tap()
                            Task { await create() }
                        } label: {
                            HStack(spacing: 8) {
                                if creating {
                                    ProgressView().tint(WhisperTheme.surface(colorScheme))
                                } else {
                                    Image(systemName: "calendar.badge.plus")
                                }
                                Text(creating ? "Scheduling\u{2026}" : "Add to shared calendar")
                            }
                            .font(.headline.weight(.black))
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(ink, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(creating)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Schedule from chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ink)
                }
            }
        }
        .onAppear {
            title = initial.suggestedTitle
            date = initial.date
            eventType = initial.eventType
            attachMeeting = WhisperChatScheduleDetector.attachesMeetingByDefault(initial.eventType)
        }
    }

    /// "@a", "@a and @b", or "@a, @b +2" — keeps the footer copy compact
    /// for group meetings with many participants.
    private var namesLine: String {
        let handles = taggedNames.map { "@\($0)" }
        switch handles.count {
        case 0: return "Everyone"
        case 1: return handles[0]
        case 2: return "\(handles[0]) and \(handles[1])"
        default: return "\(handles[0]), \(handles[1]) +\(handles.count - 2)"
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .tracking(1.1)
            .foregroundStyle(muted)
    }

    private func categoryChip(_ type: String) -> some View {
        let selected = eventType == type
        let tint = WhisperChatScheduleDetector.tint(for: type)
        return Button {
            Haptics.tap()
            eventType = type
        } label: {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(WhisperChatScheduleDetector.label(for: type))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? WhisperTheme.surface(colorScheme) : ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                selected ? AnyShapeStyle(ink) : AnyShapeStyle(WhisperTheme.card(colorScheme)),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    selected ? Color.clear : WhisperTheme.hairline(colorScheme),
                    lineWidth: 0.75
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func create() async {
        guard !creating else { return }
        creating = true
        errorText = nil
        defer { creating = false }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? initial.suggestedTitle : cleanTitle

        // 1. Optional attached meeting — created as scheduled so it waits in
        //    everyone's Meetings tab until the host starts it.
        var meetingLink: String?
        if attachMeeting {
            if let meeting = try? await WhisperMeetingService.shared.create(
                title: finalTitle,
                scheduledAt: date
            ) {
                meetingLink = WhisperMeetingService.link(for: meeting.id)
            }
        }

        // 2. The shared calendar event — tagging everyone makes the calendar
        //    service DM each person the tappable invite card automatically.
        let row = await WhisperCalendarService.shared.createEvent(
            title: finalTitle,
            description: contextNote,
            eventType: eventType,
            startTime: date,
            location: nil,
            meetingLink: meetingLink,
            taggedUserIDs: taggedIDs,
            taggedUsernames: taggedNames
        )

        if row != nil {
            Haptics.tap()
            onScheduled(
                meetingLink == nil
                    ? "Added to your shared calendar"
                    : "Added to your shared calendar \u{2014} meeting attached"
            )
            dismiss()
        } else {
            errorText = WhisperCalendarService.shared.lastError
                ?? "Couldn't create the event. Try again."
        }
    }
}
