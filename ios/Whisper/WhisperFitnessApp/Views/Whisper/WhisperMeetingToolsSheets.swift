import SwiftUI

// MARK: - Email the notes (branded backend email, not bare mailto)

/// Emails the AI meeting notes through the backend — recipients get a
/// branded, formatted Whisper email via Resend. Mirrors the web client's
/// notes-email dialog; if the deployment has no email wired, it falls back
/// to the system mail composer.
struct WhisperMeetingNotesEmailSheet: View {
    let meeting: WhisperMeetingRow
    let notes: String

    @Environment(\.dismiss) private var dismiss
    @State private var emailsText: String = ""
    @State private var sending: Bool = false
    @State private var errorMessage: String?
    @State private var sentCount: Int?
    @FocusState private var fieldFocused: Bool

    private var parsedEmails: [String] {
        emailsText
            .components(separatedBy: CharacterSet(charactersIn: ",;\n "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isLikelyEmail($0) }
    }

    private func isLikelyEmail(_ raw: String) -> Bool {
        raw.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .font(.title3)
                            .foregroundStyle(.black)
                            .frame(width: 42, height: 42)
                            .background(.white, in: .rect(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Email the notes")
                                .font(.headline.weight(.black))
                            Text(meeting.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text("Recipients get a branded Whisper email with the formatted meeting notes — no Mail app needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField(
                        "name@example.com, teammate@example.com",
                        text: $emailsText,
                        axis: .vertical
                    )
                    .font(.subheadline)
                    .lineLimit(2...4)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    if let sentCount {
                        Label(
                            "Notes emailed to \(sentCount) recipient\(sentCount == 1 ? "" : "s")",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                    }

                    Button {
                        Haptics.tap()
                        send()
                    } label: {
                        HStack(spacing: 8) {
                            if sending {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            Text(sending ? "Sending…" : "Send notes")
                                .font(.subheadline.weight(.black))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: Capsule())
                        .opacity(sending || parsedEmails.isEmpty ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || parsedEmails.isEmpty)
                }
                .padding(16)
            }
            .navigationTitle("Email notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func send() {
        let emails = Array(parsedEmails.prefix(20))
        guard !emails.isEmpty else {
            errorMessage = "Add at least one email address."
            return
        }
        guard !sending else { return }
        sending = true
        errorMessage = nil
        Task {
            let result = await WhisperMeetingService.shared.emailNotes(
                meetingID: meeting.id,
                title: meeting.title,
                notes: notes,
                emails: emails
            )
            sending = false
            switch result {
            case .sent(let count):
                Haptics.tap()
                sentCount = count
                try? await Task.sleep(for: .seconds(1.1))
                dismiss()
            case .notConfigured:
                // Email isn't wired on this deployment — fall back to Mail.
                openMailFallback(to: emails)
                dismiss()
            case .failed:
                errorMessage = "Couldn't send the email — check the addresses and try again."
            }
        }
    }

    /// Last-resort path when the backend has no email provider configured.
    private func openMailFallback(to emails: [String]) {
        var components = URLComponents(string: "mailto:\(emails.joined(separator: ","))")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: "Meeting notes — \(meeting.title)"),
            URLQueryItem(
                name: "body",
                value: String(WhisperMeetingCompanion.notesDmText(title: meeting.title, notes: notes).prefix(1800))
            ),
        ]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Stat card helper (extracted to avoid type-check timeout)

private func statCard(_ label: String, _ value: Int, _ color: Color) -> some View {
    VStack(spacing: 2) {
        Text("\(value)")
            .font(.title2.weight(.black))
            .foregroundStyle(color)
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
}

private func summaryCard(_ label: String, _ value: Int, _ color: Color) -> some View {
    VStack(spacing: 2) {
        Text("\(value)")
            .font(.title.weight(.black))
            .foregroundStyle(color)
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
}

private func emptyStateView(icon: String, message: String) -> some View {
    VStack(spacing: 10) {
        WhisperMeetDoodle(symbol: icon, height: 120)
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
}

// MARK: - Recruiter tools

/// One captured application Q&A pair from the live meeting transcript.
nonisolated struct WhisperCapturedApplicationAnswer: Identifiable, Hashable, Sendable {
    let id: String
    let question: String
    let answer: String
}

struct WhisperMeetingRecruiterToolsSheet: View {
    /// Live application-capture wiring passed from the meeting room. When
    /// nil (outside meetings) the section is hidden.
    struct ApplicationCapture {
        @Binding var isOn: Bool
        @Binding var prospectName: String
        var answers: [WhisperCapturedApplicationAnswer]
        var busy: Bool
        var saving: Bool
        var savedAt: Date?
        var onFile: () -> Void
    }

    @Environment(\.dismiss) private var dismiss
    @State private var recruiter = WhisperRecruiterService.shared

    /// The sample pitch deck — shows the exact formatting Jasper produces
    /// after a real recruiting meeting.
    @State private var showSampleDeck: Bool = false

    // Quick-create — add someone to the pipeline WHILE the meeting is
    // happening so a great conversation lands as a prospect instantly.
    @State private var showNewProspect: Bool = false
    @State private var npName: String = ""
    @State private var npUsername: String = ""
    @State private var npLocation: String = ""
    @State private var npRole: String = "creator"
    @State private var npNotes: String = ""
    @State private var npSaving: Bool = false
    @State private var npConfirmation: String?
    @State private var npError: String?

    /// When set (in-meeting), each prospect row gains a "Present" action that
    /// pins their phone-shaped profile card into the presenter's frame for
    /// everyone on the call.
    let onPresent: ((WhisperRecruiterService.ProspectRow) -> Void)?
    let capture: ApplicationCapture?

    /// The deck Jasper drafted for THIS meeting, when one exists — rendered
    /// inline in the deck section so the mid-call popup has a real home.
    let liveDeck: WhisperPitchDeck?

    /// Explicit init — the synthesized memberwise init is private because of
    /// the private wrapped properties, which breaks cross-file construction.
    init(
        liveDeck: WhisperPitchDeck? = nil,
        onPresent: ((WhisperRecruiterService.ProspectRow) -> Void)? = nil,
        capture: ApplicationCapture? = nil
    ) {
        self.liveDeck = liveDeck
        self.onPresent = onPresent
        self.capture = capture
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pipelineGrid
                    deckSection
                    captureSection
                    newProspectSection
                    prospectsSection
                }
                .padding(16)
            }
            .navigationTitle("Recruiter Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if recruiter.prospects.isEmpty {
                    await recruiter.refreshProspects()
                }
            }
        }
    }

    /// Jasper's pitch deck — the live draft flips through right here when it
    /// exists; otherwise the explainer with an inline sample.
    private var deckSection: some View {
        let mint = Color(red: 0.055, green: 0.624, blue: 0.463)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "book.pages")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jasper pitch deck")
                        .font(.subheadline.weight(.bold))
                    Text(liveDeck != nil
                         ? "Drafted live from this meeting — the final deck lands right in your meeting notes when the call ends."
                         : "Jasper listens to this meeting and builds your close plan — what they care about, key moments, close odds, and next steps. The deck lives right in your meeting notes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let deck = liveDeck {
                WhisperMeetingDeckView(deck: deck)
                    .padding(.top, 2)
            } else {
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                        showSampleDeck.toggle()
                    }
                } label: {
                    Label(showSampleDeck ? "Hide the sample" : "See a sample deck",
                          systemImage: showSampleDeck ? "chevron.up" : "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(mint, in: Capsule())
                }
                .buttonStyle(.plain)
                if showSampleDeck {
                    WhisperMeetingDeckView(deck: .sampleDeck)
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Text("ONLY YOU SEE YOUR DECKS")
                .font(.system(size: 7.5, weight: .black))
                .tracking(0.9)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private var pipelineGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            statCard("Discovered", count("discovered"), WhisperRecruiterService.statusColor("discovered"))
            statCard("Contacted", count("contacted"), WhisperRecruiterService.statusColor("contacted"))
            statCard("Interested", count("interested"), WhisperRecruiterService.statusColor("interested"))
            statCard("In Meeting", count("meeting"), WhisperRecruiterService.statusColor("meeting"))
            statCard("Ready", count("ready"), WhisperRecruiterService.statusColor("ready"))
            statCard("Promoted", recruiter.promotions.count, WhisperRecruiterService.statusColor("ready"))
        }
    }

    private func count(_ status: String) -> Int {
        recruiter.prospects.filter { $0.status == status }.count
    }

    /// Live application capture — Jasper fills the recruiter's standard
    /// application questions from the conversation and files them as a real
    /// applicant response. Mirrors the web meeting's capture panel.
    @ViewBuilder
    private var captureSection: some View {
        if let capture {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live application capture")
                            .font(.subheadline.weight(.bold))
                        Text("Jasper fills your standard application questions from the conversation — only you see this.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: capture.$isOn)
                        .labelsHidden()
                        .tint(.cyan)
                }
                if capture.isOn {
                    TextField("Prospect name — used when filing", text: capture.$prospectName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 11))
                    if capture.busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Jasper is listening for answers…")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if capture.answers.isEmpty {
                        Text("Nothing captured yet — answers appear here as the prospect talks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(capture.answers) { pair in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pair.question)
                                    .font(.caption.weight(.bold))
                                Text(pair.answer)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 10))
                        }
                        Button {
                            Haptics.tap()
                            capture.onFile()
                        } label: {
                            HStack(spacing: 8) {
                                if capture.saving {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: "tray.and.arrow.down.fill")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                Text(capture.saving ? "Saving…" : "Save to applicants")
                                    .font(.subheadline.weight(.black))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.cyan, in: Capsule())
                            .opacity(capture.saving ? 0.55 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(capture.saving)
                        if let savedAt = capture.savedAt {
                            Label(
                                "Saved to your applicants at \(savedAt.formatted(date: .omitted, time: .shortened))",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
        }
    }

    /// Mid-meeting prospect capture: name + a couple of optional details,
    /// saved straight into the pipeline with status "meeting".
    private var newProspectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.spring(duration: 0.3)) { showNewProspect.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showNewProspect ? "minus.circle.fill" : "person.crop.circle.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text(showNewProspect ? "Hide new prospect" : "Add prospect from this meeting")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showNewProspect ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showNewProspect {
                VStack(spacing: 8) {
                    TextField("Name (required)", text: $npName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 11))
                    HStack(spacing: 8) {
                        TextField("@username", text: $npUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 11))
                        TextField("Location", text: $npLocation)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 11))
                    }
                    Picker("Best fit", selection: $npRole) {
                        Text("Coach").tag("coach")
                        Text("Creator").tag("creator")
                        Text("Athlete").tag("athlete")
                    }
                    .pickerStyle(.segmented)
                    TextField("Notes — what stood out?", text: $npNotes, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 11))
                    Button {
                        Haptics.tap()
                        saveNewProspect()
                    } label: {
                        HStack(spacing: 8) {
                            if npSaving {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(npSaving ? "Saving…" : "Save to pipeline")
                                .font(.subheadline.weight(.black))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.cyan, in: Capsule())
                        .opacity(npSaving || npName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(npSaving || npName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let npConfirmation {
                Label(npConfirmation, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            }
            if let npError {
                Label(npError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }

    private func saveNewProspect() {
        let name = npName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !npSaving else { return }
        npSaving = true
        npConfirmation = nil
        npError = nil
        Task {
            let extraNotes = npNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let noteParts = [extraNotes, "Added live during a meeting."].filter { !$0.isEmpty }
            let ok = await recruiter.addProspect(
                username: npUsername
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "@", with: ""),
                displayName: name,
                location: npLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                niche: nil,
                instagram: nil,
                suggestedRole: npRole,
                notes: noteParts.joined(separator: "\n"),
                rating: nil,
                status: "meeting"
            )
            npSaving = false
            if ok {
                Haptics.success()
                npConfirmation = "\(name) added to your pipeline"
                npName = ""; npUsername = ""; npLocation = ""; npNotes = ""
                withAnimation(.spring(duration: 0.3)) { showNewProspect = false }
            } else {
                Haptics.warning()
                npError = "Couldn't save — check your connection and try again."
            }
        }
    }

    @ViewBuilder
    private var prospectsSection: some View {
        if recruiter.prospects.isEmpty {
            emptyStateView(icon: "chart.line.uptrend.xyaxis", message: "No prospects in your pipeline yet.")
        } else {
            VStack(spacing: 8) {
                ForEach(Array(recruiter.prospects.prefix(20)), id: \.id) { prospect in
                    prospectRow(prospect)
                }
            }
        }
    }

    private func prospectRow(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: p.prospect_username ?? "?", size: 36, imageURL: p.prospect_image_url.flatMap(URL.init(string:)))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.prospect_display_name ?? p.prospect_username ?? "Unknown")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text("@\(p.prospect_username ?? "unknown") \u{00B7} \(p.niche ?? "No niche")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let onPresent {
                Button {
                    Haptics.tap()
                    onPresent(p)
                } label: {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 28, height: 28)
                        .background(Color.cyan.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Present \(p.prospect_display_name ?? p.prospect_username ?? "prospect") to everyone")
            }
            ShareLink(item: prospectShareText(p)) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            Text(p.status.capitalized)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(WhisperRecruiterService.statusColor(p.status), in: Capsule())
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }

    private func prospectShareText(_ p: WhisperRecruiterService.ProspectRow) -> String {
        var parts: [String] = []
        parts.append("Prospect: \(p.prospect_display_name ?? p.prospect_username ?? "Unknown")")
        parts.append("@\(p.prospect_username ?? "unknown")")
        parts.append("Status: \(p.status)")
        if let niche = p.niche { parts.append("Niche: \(niche)") }
        if let loc = p.location { parts.append("Location: \(loc)") }
        if let role = p.suggested_role { parts.append("Suggested role: \(role)") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Coach tools

struct WhisperMeetingCoachToolsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var coachRequests = WhisperCoachRequestService.shared

    /// When set (in-meeting), each client row gains a "Present" action that
    /// pins their live fitness card into the call for everyone — the coach
    /// twin of the recruiter's prospect presenting.
    let onPresent: ((WhisperCoachRequestRow) -> Void)?

    /// Explicit init — the synthesized memberwise init is private because of
    /// the private wrapped properties, which breaks cross-file construction.
    init(onPresent: ((WhisperCoachRequestRow) -> Void)? = nil) {
        self.onPresent = onPresent
    }

    private var pending: [WhisperCoachRequestRow] {
        coachRequests.incoming.filter { $0.status == "pending" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        summaryCard("Active Clients", coachRequests.myClients.count, .orange)
                        summaryCard("Pending Requests", pending.count, .yellow)
                    }
                    clientsSection
                    pendingSection
                }
                .padding(16)
            }
            .navigationTitle("Coach Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if coachRequests.myClients.isEmpty {
                    await coachRequests.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private var clientsSection: some View {
        if coachRequests.myClients.isEmpty {
            emptyStateView(icon: "person.2.fill", message: "No active clients yet.")
        } else {
            VStack(spacing: 8) {
                ForEach(Array(coachRequests.myClients.prefix(20)), id: \.id) { c in
                    clientRow(c)
                }
            }
        }
    }

    private func clientRow(_ c: WhisperCoachRequestRow) -> some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: c.client_username, size: 36, imageURL: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.client_username)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(c.message ?? "No message")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let onPresent {
                Button {
                    Haptics.tap()
                    onPresent(c)
                } label: {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background(Color.orange.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Present \(c.client_username) to everyone")
            }
            ShareLink(item: "Client: @\(c.client_username) \u{00B7} Active coaching relationship\(c.message.map { " \u{00B7} Note: \($0)" } ?? "")") {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            statusPill("Active", Color.green)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !pending.isEmpty {
            Text("Pending Requests")
                .font(.subheadline.weight(.bold))
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            VStack(spacing: 8) {
                ForEach(Array(pending.prefix(10)), id: \.id) { r in
                    pendingRow(r)
                }
            }
        }
    }

    private func pendingRow(_ r: WhisperCoachRequestRow) -> some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: r.client_username, size: 36, imageURL: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.client_username)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(r.message ?? "Wants coaching")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            statusPill("Pending", Color.yellow)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }

    private func statusPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }
}
