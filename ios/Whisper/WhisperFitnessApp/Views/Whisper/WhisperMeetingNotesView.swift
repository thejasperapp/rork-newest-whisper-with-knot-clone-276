import SwiftUI
import UIKit

// MARK: - Notes DM message grammar

/// The notes auto-DM keeps its plain-text body ("📋 Meeting notes — Title…")
/// so the web renders it fine — iOS detects the signature and upgrades it
/// into a tappable card that opens the full formatted notes modal. Old
/// messages upgrade retroactively.
enum WhisperMeetingNotesMessage {
    nonisolated static let signature = "\u{1F4CB} Meeting notes \u{2014} "

    nonisolated struct Payload: Identifiable, Hashable, Sendable {
        let id = UUID()
        let title: String
        let notes: String
        /// "speaker: line" transcript that rode the message (newer senders).
        var transcript: String? = nil
        /// The room link, when the sender included one.
        var link: String? = nil

        /// Database id derived from the link — lets the notes screen fetch the
        /// transcript for messages that predate the inline block.
        var meetingID: String? {
            guard let link, let url = URL(string: link) else { return nil }
            let last = url.lastPathComponent
            guard !last.isEmpty, last != "/", last.lowercased() != "meet" else { return nil }
            return WhisperMeetingService.resolveRoomID(last)
        }
    }

    nonisolated static let linkLinePrefix = "\u{1F517} Full notes & transcript: "

    nonisolated static func parse(_ body: String) -> Payload? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(signature) else { return nil }
        let rest = trimmed.dropFirst(signature.count)
        guard let newline = rest.firstIndex(of: "\n") else { return nil }
        let title = String(rest[..<newline]).trimmingCharacters(in: .whitespaces)
        var notes = String(rest[newline...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // The transcript block rides last under its marker line.
        var transcript: String? = nil
        let marker = "\n\(WhisperMeetingCompanion.notesTranscriptMarker)\n"
        if let range = notes.range(of: marker) {
            let block = String(notes[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            transcript = block.isEmpty ? nil : block
            notes = String(notes[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Lift the link line out of the notes body.
        var link: String? = nil
        if let prefixRange = notes.range(of: linkLinePrefix) {
            let afterPrefix = notes[prefixRange.upperBound...]
            let lineEnd = afterPrefix.firstIndex(of: "\n") ?? notes.endIndex
            let value = String(notes[prefixRange.upperBound..<lineEnd]).trimmingCharacters(in: .whitespaces)
            link = value.isEmpty ? nil : value
            notes.removeSubrange(prefixRange.lowerBound..<lineEnd)
            notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !notes.isEmpty else { return nil }
        return Payload(title: title.isEmpty ? "Meeting" : title, notes: notes, transcript: transcript, link: link)
    }
}

// MARK: - DM inline card

/// Compact Jasper-dressed card rendered in a DM thread when meeting notes
/// arrive — replaces the old wall of plain text. Tap to read the full
/// formatted notes in a modal.
struct WhisperMeetingNotesDMCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperMeetingNotesMessage.Payload
    let mine: Bool
    let onOpen: () -> Void

    private var mode: WhisperEmberCoachMode { WhisperEmberCoachMode.load() }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    WhisperEmberBadge(size: 17)
                    Text("MEETING NOTES")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(mode.deepAccent)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(mode.accent.opacity(0.14))

                VStack(alignment: .leading, spacing: 6) {
                    Text(payload.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(previewLine)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 10, weight: .bold))
                        Text("Tap to read")
                            .font(.caption2.weight(.bold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .foregroundStyle(mode.deepAccent)
                    .padding(.top, 2)
                }
                .padding(12)
            }
            .frame(width: 250, alignment: .leading)
            .background(WhisperTheme.card(colorScheme))
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(mode.accent.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: mode.accent.opacity(0.14), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Meeting notes for \(payload.title). Tap to read.")
    }

    private var previewLine: String {
        let flat = payload.notes
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(140))
    }
}

// MARK: - Full notes screen

/// THE meeting notes screen — Jasper's adaptive canvas, a hero card,
/// formatted section cards (key points, decisions, action items), the
/// collapsible transcript, and share actions. The exact same screen shows
/// right when a meeting ends, from the Meetings list "Notes" button, AND
/// from notes DM cards — one design everywhere (the web twin is
/// `MeetingNotesScreen.tsx`).
struct WhisperMeetingNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperInsideMeetingNotebook) private var insideMeetingNotebook

    let meetingTitle: String
    /// Notes text when already known (DM card); nil → fetched by meeting ID.
    private let initialNotes: String?
    private let meetingID: String?
    private let notebookMeetingID: String?
    /// When set, Done calls this instead of `dismiss` — used when the notes
    /// render as an in-place overlay rather than a system presentation.
    private let onClose: (() -> Void)?
    /// Hero caption override — defaults to the standard Jasper line.
    private let subtitle: String?
    /// Raw "speaker: line" transcript — renders as a collapsible card.
    private let transcript: String?
    /// When set and no transcript was handed in, the transcript is fetched
    /// from the meeting so the card is never missing (Meetings list rows,
    /// older notes DMs that only carried the link).
    private let transcriptMeetingID: String?
    /// Small centered line under the share row ("Notes were sent…").
    private let footnote: String?
    /// True while Jasper is still writing (post-meeting live state).
    private let writing: Bool
    /// Empty-state override for the post-meeting participant case.
    private let emptyMessage: String?
    /// Adds an Email button to the share row (post-meeting host flow).
    private let onEmail: (() -> Void)?
    /// Extra sections below everything (recruiter eval console…).
    private let extraContent: AnyView?

    @State private var notes: String?
    @State private var loading: Bool = false
    @State private var transcriptExpanded: Bool = false
    @State private var fetchedTranscript: String?
    @State private var transcriptError: String?
    @State private var showSidekick: Bool = false
    @State private var sidekick: WhisperMeetingSidekickViewModel = WhisperMeetingSidekickViewModel(isArchived: true)

    /// The transcript on screen — the one handed in, else the one fetched.
    private var resolvedTranscript: String? {
        if let fetchedTranscript, !fetchedTranscript.isEmpty { return fetchedTranscript }
        if let fetchedTranscript { return fetchedTranscript }
        if let transcript, !transcript.isEmpty { return transcript }
        return nil
    }

    private typealias Theme = WhisperEmberSheetTheme
    private var mode: WhisperEmberCoachMode { WhisperEmberCoachMode.load() }

    /// From the Meetings list — fetches the freshest summary for the row
    /// (and the transcript, so the card matches the web notes view).
    init(meeting: WhisperMeetingRow, onClose: (() -> Void)? = nil) {
        self.meetingTitle = meeting.title
        self.meetingID = meeting.id
        self.notebookMeetingID = meeting.id
        self.initialNotes = meeting.summary
        self.onClose = onClose
        self.subtitle = nil
        self.transcript = nil
        self.transcriptMeetingID = meeting.id
        self.footnote = nil
        self.writing = false
        self.emptyMessage = nil
        self.onEmail = nil
        self.extraContent = nil
    }

    /// From a DM notes card — the notes text travelled with the message; the
    /// transcript rides along on newer cards, and older cards that only
    /// carried the room link fetch it by that id.
    init(title: String, notes: String, transcript: String? = nil, meetingID: String? = nil, onClose: (() -> Void)? = nil) {
        self.meetingTitle = title
        self.meetingID = nil
        self.notebookMeetingID = meetingID
        self.initialNotes = notes
        self.onClose = onClose
        self.subtitle = nil
        self.transcript = transcript
        self.transcriptMeetingID = meetingID
        self.footnote = nil
        self.writing = false
        self.emptyMessage = nil
        self.onEmail = nil
        self.extraContent = nil
    }

    /// The post-meeting recap — live notes (may still be writing), the
    /// transcript, email/share actions, and optional recruiter extras.
    init(
        title: String,
        liveNotes: String?,
        writing: Bool,
        notebookMeetingID: String? = nil,
        subtitle: String? = nil,
        transcript: String? = nil,
        footnote: String? = nil,
        emptyMessage: String? = nil,
        onEmail: (() -> Void)? = nil,
        extraContent: AnyView? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.meetingTitle = title
        self.meetingID = nil
        self.notebookMeetingID = notebookMeetingID
        self.initialNotes = liveNotes
        self.onClose = onClose
        self.subtitle = subtitle
        self.transcript = transcript
        self.transcriptMeetingID = notebookMeetingID
        self.footnote = footnote
        self.writing = writing
        self.emptyMessage = emptyMessage
        self.onEmail = onEmail
        self.extraContent = extraContent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Backdrop(mode: mode).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        heroCard
                        if let notes, !notes.isEmpty {
                            let sections = WhisperMeetingCompanion.notesSections(notes)
                            if sections.isEmpty {
                                plainNotesCard(notes)
                            } else {
                                ForEach(sections) { section in
                                    sectionCard(section)
                                }
                            }
                        } else if loading || writing {
                            loadingCard
                        } else {
                            emptyCard
                        }

                        if let resolvedTranscript {
                            transcriptCard(resolvedTranscript)
                        }
                        if let transcriptError {
                            Text(transcriptError).font(.caption).foregroundStyle(.red)
                        }
                        if transcriptMeetingID != nil {
                            Text("These notes are a saved snapshot. Later-arriving speech may not be reflected above. Jasper can review the latest saved transcript without replacing the original notes.").font(.caption).foregroundStyle(.secondary)
                            Button("Refresh saved transcript") { Task { await loadTranscriptIfNeeded(force: true) } }.font(.caption).frame(minHeight: 44)
                        }
                        if let notebookMeetingID, AuthenticationService.shared.isSignedIn {
                            JasperMeetingSavedContentView(meetingID: notebookMeetingID)
                            WhisperNotebookRecordingSourcesView(meetingID: notebookMeetingID)
                                .id("\(AccountStorage.currentUserID):\(notebookMeetingID)")
                        }

                        if let notes, !notes.isEmpty {
                            shareRow(notes)
                            if let footnote {
                                Text(footnote)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        if let extraContent {
                            extraContent
                        }
                        if notebookMeetingID != nil, AuthenticationService.shared.isSignedIn {
                            Button { showSidekick = true } label: {
                                Label("Ask Jasper about this meeting", systemImage: "sparkles")
                                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                    // Hard clamp to the scroll container's width — the recap
                    // renders inside the meeting window where a stray wide
                    // child once inflated the whole column past the screen
                    // edges. This pins the column to the visible width.
                    .containerRelativeFrame(.horizontal, alignment: .leading)
                }
            }
            .navigationTitle("Meeting notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if let onClose { onClose() } else { dismiss() }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                }
            }
            .sheet(isPresented: $showSidekick) {
                if let notebookMeetingID {
                    WhisperMeetingSidekickView(model: sidekick, meetingID: notebookMeetingID, title: meetingTitle, captureStatus: "Saved meeting transcript", interim: "", onRetryCapture: {}, isArchived: true)
                        .presentationDetents([.fraction(0.7), .large])
                        .presentationContentInteraction(.scrolls)
                }
            }
            .onDisappear { sidekick.cancel() }
            .task { await load() }
            .task { await loadTranscriptIfNeeded() }
            .onChange(of: initialNotes) { _, fresh in
                // Post-meeting: Jasper finishes writing while this screen is
                // already up — slot the notes in the moment they land.
                if let fresh, !fresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        notes = fresh
                    }
                }
            }
        }
    }

    /// Fetches the "speaker: line" transcript for the meeting when none was
    /// handed in — the notes card is never missing its transcript.
    private func loadTranscriptIfNeeded(force: Bool = false) async {
        guard let transcriptMeetingID, force || ((transcript ?? "").isEmpty && fetchedTranscript == nil) else { return }
        do {
            let plain = try await WhisperMeetingService.shared.readTranscriptPlain(meetingID: transcriptMeetingID)
            transcriptError = nil
            fetchedTranscript = plain
            if plain.isEmpty { transcriptError = "No saved speech is available yet. Captured speech may still be saving." }
        } catch { transcriptError = "The saved transcript could not load. Reconnect and refresh; this is not confirmation that no speech was captured." }
    }

    private func load() async {
        if let initialNotes, !initialNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = initialNotes
            return
        }
        guard let meetingID else { return }
        loading = true
        defer { loading = false }
        if let fresh = await WhisperMeetingService.shared.fetchArchived(id: meetingID),
           let summary = fresh.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            notes = summary
        }
    }

    private var heroCard: some View {
        HStack(spacing: 12) {
            WhisperEmberBadge(size: 40, isActive: writing)
            VStack(alignment: .leading, spacing: 3) {
                Text(meetingTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(subtitle ?? "AI notes by Jasper \u{00B7} key points, decisions, action items")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(mode.accent.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: Theme.cardShadow, radius: 9, y: 3)
    }

    private func sectionCard(_ section: WhisperMeetingNotesSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: WhisperMeetingCompanion.sectionIcon(section.title))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(mode.deepAccent)
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(Theme.muted)
            }
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, b in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(mode.accent)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(b)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        }
    }

    private func plainNotesCard(_ text: String) -> some View {
        Text(text.replacingOccurrences(of: "**", with: ""))
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            }
    }

    /// Collapsible "who said what" transcript — first lines visible
    /// immediately, expandable to the full conversation.
    private func transcriptCard(_ transcript: String) -> some View {
        let lines = transcript
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let visible = transcriptExpanded ? lines : Array(lines.prefix(6))
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    transcriptExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(mode.deepAccent)
                    Text("FULL TRANSCRIPT")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(Theme.muted)
                    Text("\(lines.count) lines")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(transcriptExpanded ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                    transcriptLine(line)
                }
            }

            if !transcriptExpanded && lines.count > visible.count {
                Text("+\(lines.count - visible.count) more \u{2014} tap to expand")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        }
    }

    private func transcriptLine(_ line: String) -> some View {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        return HStack(alignment: .top, spacing: 6) {
            if parts.count == 2 {
                Text(String(parts[0]))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Theme.ink)
                Text(String(parts[1]).trimmingCharacters(in: .whitespaces))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shareRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ShareLink(item: WhisperMeetingCompanion.notesDmText(title: meetingTitle, notes: text, transcript: resolvedTranscript)) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .bold))
                    Text("Share")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Theme.primaryInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.primaryFill, in: Capsule())
            }
            .buttonStyle(.plain)
            if let onEmail {
                Button {
                    Haptics.tap()
                    onEmail()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Email")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.surfaceStrong, in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.stroke, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            Button {
                UIPasteboard.general.string = WhisperMeetingCompanion.notesDmText(title: meetingTitle, notes: text, transcript: resolvedTranscript)
                Haptics.success()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .bold))
                    Text("Copy")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surfaceStrong, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.stroke, lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            WhisperEmberBadge(size: 22, isActive: true)
            Text(writing ? "Jasper is writing your notes\u{2026}" : "Fetching the notes\u{2026}")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted)
            WhisperJasperMiniDots(tint: mode.accent)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            WhisperEmberBadge(size: 44)
            Text("Notes aren't ready yet")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(emptyMessage ?? "Jasper writes the notes when the meeting ends. Check back in a moment.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
    }
}
