import SwiftUI

struct JasperMeetingAssistantView: View {
    @Bindable var model: JasperMeetingsViewModel
    let meetingID: String?
    var folderID: String? = nil
    var recordingContext: [String: Any]? = nil
    var onSeekRecording: ((String, Double) -> Void)? = nil
    var embedded: Bool = false
    /// Offers the full-screen Jasper Intelligence handoff for general exploration. Off inside live calls so the call stays primary.
    var allowsJasperIntelligence: Bool = true
    /// A handed-off question (for example from Jasper Intelligence) only prefills the composer; asking still requires scope approval.
    var initialQuestion: String? = nil
    @State private var question: String = ""
    @State private var scope: String = "all"
    @State private var approval: Bool = false
    @State private var scan: Bool = false
    @State private var pendingQuestion: String = ""
    @State private var pendingScope: String = "all"
    @State private var showPreferences: Bool = false
    @State private var showConnections: Bool = false
    @State private var showJasperIntelligence: Bool = false
    @State private var confirmClear: Bool = false
    @State private var consumedHandoff: Bool = false
    @State private var destinations: [String: String] = [:]
    @State private var approvedScopes: Set<String> = []

    private var recipes: [JasperSidekickRecipe] { JasperSidekickRecipe.recipes(forMeeting: meetingID != nil) }
    private var starters: [String] {
        meetingID == nil ? ["Summarize my recent meetings", "Find my follow-ups", "Explain what a retainer agreement is"] : ["What did I miss?", "What decisions were made?", "Explain a term someone just used"]
    }

    var body: some View {
        Group {
            if embedded {
                ScrollView { content.padding(.horizontal, 16).padding(.vertical, 8) }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) { composer.padding(.horizontal, 16).padding(.vertical, 8).background(.bar) }
            } else {
                VStack(alignment: .leading, spacing: 16) { content; composer }
            }
        }
        .task { scope = meetingID != nil ? "current" : folderID ?? "all"; await model.load() }
        .onAppear {
            guard !consumedHandoff, let initialQuestion, question.isEmpty else { return }
            consumedHandoff = true
            question = String(initialQuestion.prefix(600))
        }
        .sheet(isPresented: $showConnections) { JasperNoteConnectionsView() }
        .sheet(isPresented: $showPreferences) { JasperMeetingPreferencesView(model: model) }
        .fullScreenCover(isPresented: $showJasperIntelligence) { WhisperEmberChatView().presentationBackground(.clear) }
        .confirmationDialog("Clear temporary answers?", isPresented: $confirmClear) { Button("Clear conversation", role: .destructive) { model.clear() } } message: { Text("Answers kept with meetings remain saved.") }
        .alert("Let Jasper read this context?", isPresented: $approval) {
            Button("Cancel", role: .cancel) {}
            Button("Continue with Jasper") { approvedScopes.insert(pendingScope); send() }
        } message: {
            Text(recordingContext != nil ? "Only your selected private recording passages and your question go to cloud AI. No other meeting sources are included and nothing is added to the shared transcript. Jasper may also answer general questions from its own knowledge; those parts are labeled and never presented as recording facts." : "Your question plus saved transcript and original meeting-note excerpts from the selected scope go to cloud AI. Notes are labeled as summaries, not verbatim speech. Jasper may also answer general questions from its own knowledge; those parts are labeled and never presented as meeting facts. Calendar events and private voice questions are not included. Nothing is sent to attendees.")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if recordingContext == nil {
                Button("Find connections in my notes", systemImage: "link") { showConnections = true }.font(.caption).buttonStyle(.bordered).controlSize(.large).disabled(model.isAsking)
            }
            if model.answers.isEmpty { emptyState }
            answersList
            if model.isAsking { HStack { ProgressView().controlSize(.small); Text("Reading meeting evidence…").font(.caption); Spacer(); Button("Stop") { model.stop() }.frame(minHeight: 44) } }
            if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private var header: some View {
        HStack {
            if !embedded { JasperSidekickMascot(size: 36, isWorking: model.isAsking); Text("Jasper").font(.subheadline.weight(.semibold)) }
            if recordingContext != nil { Text("Selected recording · Private").font(.caption).foregroundStyle(.secondary) }
            else {
                Picker("Search meeting scope", selection: $scope) {
                    Text("All my meetings").tag("all")
                    if meetingID != nil { Text("This meeting").tag("current") }
                    ForEach(model.library?.folders ?? []) { folder in Text(folder.name).tag(folder.id) }
                }.font(.caption).disabled(model.isAsking)
            }
            Spacer()
            Menu {
                if meetingID != nil { Button("Scan & organize transcript", systemImage: "viewfinder") { prepare(scan: true) }.disabled(model.isAsking) }
                Button("Personalize Jasper", systemImage: "slider.horizontal.3") { showPreferences = true }
                if !model.answers.isEmpty { Button("Clear chat", role: .destructive) { confirmClear = true }.disabled(model.isAsking) }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Jasper options")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(meetingID == nil ? "Ask across your meetings, or anything else. Meeting facts are cited; general answers are labeled as Jasper’s knowledge." : "Ask about this meeting, or anything else. Meeting facts are cited; general answers are labeled as Jasper’s knowledge.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(starters, id: \.self) { prompt in
                Button { prepare(scan: false, prompt: prompt) } label: { HStack { Text(prompt).font(.subheadline); Spacer(); Image(systemName: "arrow.up.left").font(.caption) }.padding(.horizontal, 12).frame(minHeight: 44).background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 16)) }.buttonStyle(.plain).disabled(model.isAsking)
            }
        }
    }

    private var followupHandler: ((String) -> Void)? {
        if model.isAsking { return nil }
        return { prompt in prepare(scan: false, prompt: prompt) }
    }
    private var continueHandler: ((String) -> Void)? {
        guard allowsJasperIntelligence else { return nil }
        return { text in continueInJasper(text) }
    }

    private var answersList: some View {
        ForEach(model.answers) { answer in
            JasperMeetingAnswerView(answer: answer, onSeekRecording: onSeekRecording, onFollowup: followupHandler, onContinueInJasper: continueHandler)
            if !answer.result.insufficient {
                if meetingID == nil, !answer.sources.isEmpty {
                    Picker("Save answer with", selection: Binding(get: { destinations[answer.id] ?? "" }, set: { destinations[answer.id] = $0 })) {
                        Text("Choose meeting").tag("")
                        ForEach(sourceMeetings(answer)) { meeting in Text(meeting.name).tag(meeting.id) }
                    }.font(.caption)
                }
                if meetingID != nil || !answer.sources.isEmpty {
                    Button(model.savedIDs.contains(answer.id) ? "Saved with meeting" : "Keep with meeting notes") { if let destination = meetingID ?? destinations[answer.id], !destination.isEmpty { Task { await model.keep(answer, meetingID: destination) } } }
                        .font(.caption).buttonStyle(.bordered).controlSize(.large).disabled(model.isSaving || model.savedIDs.contains(answer.id) || (meetingID == nil && (destinations[answer.id] ?? "").isEmpty))
                }
            }
            Divider()
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                if recordingContext == nil { recipesMenu }
                TextField("Ask Jasper anything…", text: $question, axis: .vertical).lineLimit(1...4).font(.subheadline).frame(minHeight: 44).accessibilityLabel("Ask Jasper about meetings")
                Button { prepare(scan: false) } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44).foregroundStyle(Color(.systemBackground)).background(Color.primary, in: Circle()) }
                    .accessibilityLabel("Send Jasper question").disabled(model.isAsking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.utf16.count > 600)
            }.padding(8).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 18))
            Text("Private replies · Meeting facts are cited · Jasper’s knowledge is labeled").font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Saved prompts run through the same scope approval as a typed question.
    private var recipesMenu: some View {
        Menu {
            ForEach(recipes) { recipe in
                Button { if recipe.isScan { prepare(scan: true) } else { prepare(scan: false, prompt: recipe.question) } } label: {
                    Text(recipe.title)
                    Text(recipe.hint)
                    Image(systemName: recipe.isScan ? "viewfinder" : "wand.and.stars")
                }
            }
        } label: { Image(systemName: "wand.and.stars").frame(width: 44, height: 44) }
            .accessibilityLabel("Sidekick recipes").disabled(model.isAsking)
    }

    private func sourceMeetings(_ answer: JasperMeetingAnswer) -> [JasperMeetingLibrary.Folder] {
        var seen: Set<String> = []
        return answer.sources.compactMap { source in seen.insert(source.meetingId).inserted ? .init(id: source.meetingId, name: source.meetingTitle) : nil }
    }

    private func prepare(scan: Bool, prompt: String? = nil) {
        guard !model.isAsking else { return }
        if let prompt { question = prompt }
        self.scan = scan; pendingScope = scan ? "current" : scope
        pendingQuestion = scan ? "Organize this meeting’s transcript and highlight the decisions, key numbers and follow-ups using my focus preferences." : (prompt ?? question)
        if approvedScopes.contains(pendingScope) { send() } else { approval = true }
    }

    private func send() {
        model.ask(pendingQuestion, meetingID: pendingScope == "current" ? meetingID : nil, folderID: ["all", "current"].contains(pendingScope) ? nil : pendingScope, scan: scan, recordingContext: recordingContext)
        if question == pendingQuestion { question = "" }
    }

    /// Hands the question to Jasper Intelligence prefilled; the user still sends it there.
    private func continueInJasper(_ text: String) {
        WhisperEmberActionRouter.shared.pendingJasperPrompt = String(text.prefix(600))
        Haptics.tap()
        showJasperIntelligence = true
    }
}
