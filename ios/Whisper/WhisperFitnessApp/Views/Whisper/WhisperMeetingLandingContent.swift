import SwiftUI

/// Meet's web visual language adapted to a day-first native scroll surface.
struct WhisperMeetingLandingContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let meetings: [WhisperMeetingRow]
    @Binding var joinCode: String
    let busy: Bool
    let errorText: String?
    let onStart: () -> Void
    let onJoin: () -> Void
    let onLink: () -> Void
    let onSchedule: () -> Void
    let onLibrary: () -> Void
    let onCalendar: () -> Void
    let onOpen: (WhisperMeetingRow) -> Void
    @State private var day: Date = Date()
    @State private var calls: Bool = false
    @State private var monthOpen: Bool = false
    @State private var agenda = WhisperMeetAgendaViewModel()
    @State private var jasperMeeting: WhisperMeetingRow?

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let sunday = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: start), to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: sunday) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                frontDoor
                HStack(spacing: 24) {
                    tab("Meetings", selected: !calls) { calls = false }
                    tab("Calls", selected: calls) { calls = true }
                    Spacer()
                }.overlay(alignment: .bottom) { Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5) }
                if calls {
                    WhisperMeetCallsView()
                } else {
                    dayHeader
                    weekStrip
                    agendaContent
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: Calendar.current.startOfDay(for: day)) { await agenda.load(day: day) }
        .whisperRefreshable {
            async let mine: Void = WhisperMeetingService.shared.refreshMine()
            async let today: Void = agenda.load(day: day)
            _ = await (mine, today)
        }
        .sheet(isPresented: $monthOpen) {
            NavigationStack {
                DatePicker("Choose a day", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.graphical).padding()
                    .navigationTitle("Your calendar").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { monthOpen = false } } }
            }.presentationDetents([.medium])
        }
        .sheet(item: $jasperMeeting) { meeting in
            WorkspaceMeetingJasperView(meeting: meeting).id(meeting.id + AccountStorage.currentUserID)
        }
        .tint(ink)
    }

    private var frontDoor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHISPER MEET").font(.caption2.bold()).tracking(1.8).foregroundStyle(.secondary)
            WhisperGradientTypeInText(text: "Meet, the Whisper way.", font: .system(size: 32, weight: .heavy), speed: 26, settleColor: ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("One link, everyone in — Jasper takes the notes.").font(.subheadline).foregroundStyle(.secondary)
            Menu {
                Button("Start an instant meeting", systemImage: "video") { onStart() }
                Button("Create a link for later", systemImage: "link") { onLink() }
                Button("Schedule a meeting", systemImage: "calendar.badge.plus") { onSchedule() }
            } label: {
                Label("New meeting", systemImage: "video.badge.plus")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(WhisperBrandGradient.diagonal, in: Capsule())
            }.disabled(busy).padding(.top, 6)
            HStack(spacing: 8) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                TextField("Enter a code or link", text: $joinCode)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.join).onSubmit(onJoin)
                Button("Join", action: onJoin).fontWeight(.bold).frame(minWidth: 44, minHeight: 48)
                    .disabled(busy || joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.font(.subheadline).padding(.horizontal, 14)
                .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme)) }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
            Divider().padding(.top, 4)
            door("Schedule a meeting", hint: "Calendar, guests, email invites", icon: "calendar.badge.plus", action: onSchedule)
            door("Meeting library", hint: "Folders, original notes & recordings", icon: "note.text", action: onLibrary)
            door("Whisper Calendar", hint: "The full shared calendar", icon: "calendar", action: onCalendar)
        }
        .padding(22)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                WhisperTheme.card(colorScheme)
                Circle().fill(WhisperBrandGradient.diagonal).frame(width: 150, height: 150).blur(radius: 48).opacity(0.15).offset(x: 45, y: -50)
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
    }

    private var dayHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Calendar.current.isDateInToday(day) ? "TODAY" : day.formatted(.dateTime.year())).font(.caption2.bold()).tracking(1.5).foregroundStyle(.secondary)
                Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.title2.bold())
            }
            Spacer(minLength: 4)
            Button { monthOpen = true } label: { Image(systemName: "calendar").frame(width: 44, height: 44) }.accessibilityLabel("Choose a day")
        }
    }

    private var weekStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { date in
                    let selected = Calendar.current.isDate(date, inSameDayAs: day)
                    Button { Haptics.tap(); day = date } label: {
                        VStack(spacing: 6) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 10, weight: .bold)).textCase(.uppercase)
                            Text(date.formatted(.dateTime.day())).font(.subheadline.bold())
                                .frame(width: 38, height: 38)
                                .foregroundStyle(selected ? WhisperTheme.surface(colorScheme) : ink)
                                .background(selected ? ink : .clear, in: Circle())
                            Circle().fill(WhisperBrandGradient.linear).frame(width: 4, height: 4)
                                .opacity(agenda.hasItems(on: date, meetings: meetings) ? 1 : 0)
                        }.frame(maxWidth: .infinity, minHeight: 66)
                    }.buttonStyle(.plain).accessibilityLabel(date.formatted(date: .complete, time: .omitted)).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack {
                weekButton("chevron.left", label: "Previous week", days: -7)
                Spacer()
                Button("Today") { day = Date() }.font(.caption.bold()).frame(minHeight: 44)
                Spacer()
                weekButton("chevron.right", label: "Next week", days: 7)
            }
        }
    }

    private var agendaContent: some View {
        let items = agenda.items(on: day, meetings: meetings)
        return VStack(alignment: .leading, spacing: 16) {
            if agenda.isLoading { ProgressView("Loading your day…").frame(maxWidth: .infinity).padding() }
            if let error = agenda.errorText {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("Retry calendar") { Task { await agenda.load(day: day) } }
            }
            if items.isEmpty && !agenda.isLoading && agenda.errorText == nil {
                VStack(spacing: 14) {
                    WhisperMeetDoodle()
                    Text(Calendar.current.isDateInToday(day) ? "Nothing on the books today." : "Nothing on \(day.formatted(.dateTime.month(.abbreviated).day())).")
                        .font(.title3.bold())
                    Text("Start a meeting right now, or put one on the calendar and Whisper sends the invites.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button(action: onStart) { Label("Start now", systemImage: "video").font(.subheadline.bold()).padding(.horizontal, 18).frame(minHeight: 44).foregroundStyle(.white).background(WhisperBrandGradient.diagonal, in: Capsule()) }.disabled(busy)
                        Button("Schedule", action: onSchedule).font(.subheadline.bold()).frame(minHeight: 44)
                    }
                }.frame(maxWidth: .infinity).padding(22)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 24))
                    .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
            }
            ForEach(["Happening now", "Upcoming", "Earlier"], id: \.self) { group in
                let rows = items.filter { $0.group == group }
                if !rows.isEmpty {
                    Text(group.uppercased()).font(.caption2.bold()).tracking(1.4).foregroundStyle(.secondary)
                    ForEach(rows) { item in
                        Button {
                            if let meeting = item.meeting { onOpen(meeting) }
                            else if let link = item.link { joinCode = link; onJoin() }
                            else { onCalendar() }
                        } label: {
                            HStack(spacing: 14) {
                                Text(item.start.formatted(date: .omitted, time: .shortened)).font(.caption.bold()).frame(width: 60, alignment: .leading)
                                Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(width: 1, height: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.subheadline.bold()).lineLimit(2)
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: item.group == "Earlier" ? "note.text" : "arrow.up.right")
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
                                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
                        }.buttonStyle(.plain)
                        .contextMenu {
                            if let meeting = item.meeting {
                                Button("Ask Jasper about this", systemImage: "sparkles") { jasperMeeting = meeting }
                                ShareLink(item: meeting.isGroupCall ? WhisperMeetingService.socialCallLink(for: meeting.id) : WhisperMeetingService.link(for: WhisperMeetingInvitation.fromText(item.link)?.idOrCode ?? meeting.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private func weekButton(_ icon: String, label: String, days: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) { day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day }
        } label: { Image(systemName: icon).font(.caption.bold()).frame(width: 44, height: 44).foregroundStyle(WhisperTheme.surface(colorScheme)).background(ink, in: Circle()) }.accessibilityLabel(label)
    }
    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline.bold()).foregroundStyle(selected ? ink : .secondary).frame(minHeight: 44).overlay(alignment: .bottom) { Rectangle().fill(selected ? ink : .clear).frame(height: 2) } }.buttonStyle(.plain)
    }
    private func door(_ title: String, hint: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 36, height: 36).overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme)) }
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.bold()); Text(hint).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.frame(minHeight: 44)
        }.buttonStyle(.plain)
    }
}
