import SwiftUI

/// Focuses the real sticker renderer over the Story. Done commits one draft.
struct WhisperStoryAttachmentEditor: View {
    let kind: WhisperStorySticker.Kind
    var existing: WhisperStorySticker? = nil
    var reaction: Bool = false
    let onCancel: () -> Void
    let onSave: (WhisperStorySticker) -> Void
    @State private var text: String = ""
    @State private var options: [String] = ["Yes", "No"]
    @State private var emoji: String = "\u{1F60D}"
    @State private var date: Date = .now.addingTimeInterval(86_400)
    @State private var allDay: Bool = true
    @State private var palette: Int = 0
    @State private var didChangeColor: Bool = false
    @State private var didChangeDeadline: Bool = false
    @State private var didLoad: Bool = false
    @State private var closed: Bool = false
    @State private var showsEmojiGrid: Bool = false
    @State private var showsDate: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    @FocusState private var focused: Bool
    private let faces: [String] = ["\u{1F60D}", "\u{1F602}", "\u{1F62E}", "\u{1F622}", "\u{1F525}", "\u{2764}\u{FE0F}"]
    private let colors: [Color] = [.white, Color(red: 1, green: 0.84, blue: 0.88), Color(red: 1, green: 0.91, blue: 0.59), Color(red: 0.7, green: 0.86, blue: 1)]
    private var cleanOptions: [String] { options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var canSave: Bool {
        didLoad && !closed && (kind != .countdown || (existing != nil && !didChangeDeadline) || deadline > .now) &&
        (kind == .poll || kind == .question || reaction || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (kind != .poll || cleanOptions.count >= 2)
    }
    private var draft: WhisperStorySticker {
        var layer = existing ?? WhisperStorySticker(kind: kind)
        layer.text = text
        if existing == nil || didChangeColor { layer.color = "#111111"; layer.background = colors[palette].toHex() }
        if kind == .poll { layer.pollOptions = options }
        if kind == .slider { layer.sliderEmoji = emoji; if reaction { layer.style = 9; layer.text = "" } }
        if kind == .countdown {
            layer.label = text
            layer.text = existing != nil && !didChangeDeadline ? existing?.text : ISO8601DateFormatter().string(from: deadline)
        }
        return layer
    }
    var body: some View {
        VStack(spacing: 0) {
            WhisperStoryToolHeader(inline: true, canConfirm: canSave, onConfirm: save, onCancel: cancel)
                .overlay {
                    if !reaction {
                        Button { palette = (palette + 1) % colors.count; didChangeColor = true; Haptics.tap() } label: {
                            Circle().fill(AngularGradient(colors: [.pink, .yellow, .mint, .blue, .pink], center: .center))
                                .frame(width: 22, height: 22).overlay { Circle().stroke(.white, lineWidth: 2) }
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("Change sticker color")
                    }
                }
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        if reaction { Text("Customize your reaction sticker").font(.footnote).foregroundStyle(.white) }
                        WhisperStoryStickerView(sticker: draft, authoring: WhisperStoryStickerAuthoring(
                            text: input($text, limit: 180), options: $options, focus: $focused,
                            chooseDeadline: { focused = false; showsDate = true }),
                            authorUsername: AuthenticationService.shared.currentUser.username ?? "you")
                            .environment(\.colorScheme, .light)
                        if kind == .question {
                            Text("Viewers can reply to your question.").font(.caption2).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height))
                }.scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
            }
            if kind == .countdown && showsDate { countdownControls }
            if kind == .slider {
                if showsEmojiGrid {
                    WhisperStoryEmojiGrid(selected: $emoji, onClose: { showsEmojiGrid = false })
                        .frame(maxHeight: 310)
                } else { emojiPicker }
            }
        }
        .buttonStyle(.plain).environment(\.colorScheme, .dark)
        .task {
            guard !didLoad, !closed else { return }
            if let existing {
                text = kind == .countdown ? existing.label ?? "" : existing.text ?? ""
                options = existing.pollOptions ?? ["Yes", "No"]
                while options.count < 2 { options.append("") }
                emoji = existing.sliderEmoji ?? emoji
                if kind == .countdown, let raw = existing.text, let parsed = parseDeadline(raw) {
                    date = parsed; allDay = abs(parsed.timeIntervalSince(endOfDay(parsed))) < 0.01
                } else if kind == .countdown { allDay = false }
            }
            didLoad = true
            showsDate = kind == .countdown
            focused = !reaction && kind != .countdown
        }
        .onChange(of: focused) { _, value in if value { showsDate = false; showsEmojiGrid = false } }
        .onDisappear { closed = true }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in cancel() }
        .accessibilityAction(.escape) { cancel() }
    }
    private var emojiPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(faces, id: \.self) { face in
                    Button { emoji = face; Haptics.tap() } label: {
                        Text(face).font(.system(size: 28)).frame(width: 44, height: 48)
                            .background(emoji == face ? .white.opacity(0.15) : .clear, in: .circle)
                    }.accessibilityLabel("Reaction \(face)").accessibilityAddTraits(emoji == face ? .isSelected : [])
                }
                Button { focused = false; showsEmojiGrid = true } label: {
                    Image(systemName: "plus.circle").font(.title2).foregroundStyle(.white).frame(width: 44, height: 48)
                }.accessibilityLabel("More emoji")
            }
        }.contentMargins(.horizontal, 16).padding(.vertical, 8).background(.black.opacity(0.65))
    }
    private var countdownControls: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("All day", isOn: Binding(get: { allDay }, set: { allDay = $0; didChangeDeadline = true }))
                Button("Set") { showsDate = false }.frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 20)
            DatePicker("End date", selection: Binding(get: { date }, set: { date = $0; didChangeDeadline = true }), displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                .datePickerStyle(.wheel).labelsHidden().frame(height: 160).clipped()
            if (existing == nil || didChangeDeadline) && deadline <= .now { Text("Choose a future end date.").font(.caption).padding(.bottom, 8) }
        }.foregroundStyle(.white).background(.black.opacity(0.75))
    }
    private var deadline: Date { allDay ? endOfDay(date) : date }
    private func endOfDay(_ value: Date) -> Date {
        (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: value)) ?? value).addingTimeInterval(-1)
    }
    private func parseDeadline(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: raw) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
    private func input(_ binding: Binding<String>, limit: Int) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = String($0.prefix(max(limit, binding.wrappedValue.count))) })
    }
    private func cancel() { closed = true; focused = false; onCancel() }
    private func save() {
        guard canSave, generation == AccountStorage.generation else { return }
        var layer = draft
        if kind == .countdown { layer.label = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        else { layer.text = layer.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
        if kind == .question && layer.text?.isEmpty != false { layer.text = "Ask me a question" }
        if kind == .poll { layer.pollOptions = cleanOptions }
        closed = true; focused = false; Haptics.tap(); onSave(layer)
    }
}
