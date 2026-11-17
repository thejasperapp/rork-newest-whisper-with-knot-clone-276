import SwiftUI

struct WhisperMeetingNotesListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var archive: WhisperNotebookArchiveViewModel = WhisperNotebookArchiveViewModel()
    @State private var jasper: JasperMeetingsViewModel = JasperMeetingsViewModel()
    @State private var search: String = ""
    @State private var folder: String = "all"
    @State private var selected: WhisperMeetingRow?
    @State private var showRecordings: Bool = false
    @State private var showEarlier: Bool = false
    @State private var showAssistant: Bool = false
    /// Question handed over by Jasper Intelligence's meeting_sidekick route. Prefill only; scope approval still applies.
    @State private var handoffQuestion: String?
    @State private var showCalendar: Bool = false
    @State private var showPreferences: Bool = false
    @State private var newFolder: Bool = false
    @State private var folderName: String = ""
    @State private var renameFolderID: String?
    @State private var prefs: [String: WhisperNotebookPrefRow] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filingID: String?
    @State private var filedFolder: String?
    @State private var undoMove: (meeting: String, folder: String?, destination: String?)?
    @State private var filingMessage: String?
    private var meetings: [WhisperMeetingRow] {
        archive.meetings.filter { meeting in
            (meeting.status != "scheduled" || !(meeting.summary ?? "").isEmpty) &&
            (folder == "all" || (folder == "unfiled" ? jasper.library?.filings[meeting.id] == nil : jasper.library?.filings[meeting.id] == folder)) &&
            (search.isEmpty || title(meeting).localizedStandardContains(search) || (meeting.summary ?? "").localizedStandardContains(search) || meeting.host_username.localizedStandardContains(search))
        }.sorted { a, b in
            let left = prefs[a.id]?.is_favorite == true, right = prefs[b.id]?.is_favorite == true
            return left != right ? left : (a.ended_at ?? a.created_at ?? "") > (b.ended_at ?? b.created_at ?? "")
        }
    }
    private func title(_ meeting: WhisperMeetingRow) -> String { prefs[meeting.id]?.custom_title ?? meeting.title }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your conversations, notes and recordings.").font(.subheadline).foregroundStyle(.secondary)
                        Button { showAssistant = true; Haptics.tap() } label: {
                            HStack(spacing: 14) {
                                JasperSidekickMascot(size: 48)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Ask Jasper").font(.headline)
                                    Text("Find a detail or your next step.").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.subheadline)
                            }.padding(16).foregroundStyle(.primary).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                        }.buttonStyle(.plain).accessibilityLabel("Open Jasper sidekick")
                        Button { showCalendar = true } label: { Label("Upcoming meetings", systemImage: "calendar").font(.subheadline).frame(minHeight: 44) }.tint(.primary)
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            folderButton("All meetings", id: "all")
                            folderButton("Unfiled", id: "unfiled")
                            ForEach(jasper.library?.folders ?? []) { item in
                                folderButton(item.name, id: item.id).contextMenu {
                                    Button("Rename folder") { renameFolderID = item.id; folderName = item.name; newFolder = true }
                                    Button("Remove folder only", role: .destructive) { Task { if await jasper.change(["action": "folder.remove", "id": item.id]), folder == item.id { folder = "all" } } }
                                }
                            }
                            Button { renameFolderID = nil; folderName = ""; newFolder = true } label: { Image(systemName: "folder.badge.plus").frame(width: 44, height: 44) }.accessibilityLabel("New folder").disabled(jasper.library == nil)
                        }
                    }.contentMargins(.horizontal, 0).scrollIndicators(.hidden)
                    if let error = jasper.errorText { Text(error).font(.caption).foregroundStyle(.secondary); Button("Refresh folders") { Task { await jasper.load() } } }
                }
                Section(folder == "all" ? "Recent conversations" : jasper.library?.folders.first(where: { $0.id == folder })?.name ?? "Meetings") {
                    ForEach(meetings) { meeting in
                        HStack(spacing: 4) {
                        Button { selected = meeting; Haptics.tap() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: prefs[meeting.id]?.is_favorite == true ? "star.fill" : "waveform").foregroundStyle(WhisperBrandGradient.rose).frame(width: 30)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(title(meeting)).font(.headline).foregroundStyle(.primary)
                                    Text("\(String((meeting.ended_at ?? meeting.created_at ?? "").prefix(10))) · @\(meeting.host_username)").font(.caption).foregroundStyle(.secondary)
                                    if let item = jasper.library?.folders.first(where: { $0.id == jasper.library?.filings[meeting.id] }) { Label(item.name, systemImage: "folder").font(.caption2).foregroundStyle(WhisperBrandGradient.rose) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.frame(minHeight: 70).padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu {
                            ForEach(jasper.library?.folders ?? []) { item in Button("File in \(item.name)", systemImage: "folder") { file(meeting.id, to: item.id) } }
                            Button("Unfile meeting", systemImage: "tray") { file(meeting.id, to: nil) }
                        } label: { Image(systemName: "folder.badge.plus").frame(width: 44, height: 44).foregroundStyle(.secondary) }.accessibilityLabel("File \(title(meeting))").disabled(jasper.isSaving || filingID != nil)
                        }.opacity(filingID == meeting.id ? 0.5 : 1)
                            .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.1, anchor: .topLeading).combined(with: .opacity)))
                    }
                    if archive.isLoading { ProgressView("Loading meetings…") }
                    if let error = archive.errorText { Text(error).font(.caption); Button("Try again") { Task { await archive.load(includeWithoutSummary: true) } } }
                    else if !archive.isLoading, meetings.isEmpty { WhisperEmptyState(icon: "folder", title: search.isEmpty ? "No meetings here yet" : "No matching meetings", message: "Start or join a meeting, or file an existing conversation here. Tap the folder beside a meeting to file it.", isCard: false) }
                    if archive.canLoadMore { Button("Load older meetings") { Task { await archive.load(more: true, includeWithoutSummary: true) } }.disabled(archive.isLoading) }
                }
            }.listStyle(.insetGrouped).animation(reduceMotion ? nil : .snappy(duration: 0.4), value: jasper.library?.revision)
                .searchable(text: $search, prompt: "Find a meeting…")
                .safeAreaInset(edge: .bottom) {
                    if let filingMessage {
                        HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(filingMessage).font(.caption); Spacer(); Button("Undo") { if let move = undoMove { file(move.meeting, to: move.folder, undo: true) } }.font(.caption.weight(.semibold)).frame(minHeight: 44).disabled(jasper.isSaving) }
                            .padding(.horizontal, 16).background(.regularMaterial, in: Capsule()).padding(.horizontal, 16).padding(.bottom, 8).transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .navigationTitle("Meetings").navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Personalize Jasper", systemImage: "slider.horizontal.3") { showPreferences = true }
                            Button("All recordings", systemImage: "play.rectangle") { showRecordings = true }
                            Button("Earlier private writing", systemImage: "clock.arrow.circlepath") { showEarlier = true }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Meeting library options")
                    }
                }
                .whisperRefreshable {
                    async let notes: Void = archive.load(includeWithoutSummary: true)
                    async let sidekick: Void = jasper.load()
                    _ = await (notes, sidekick)
                }
                .onAppear {
                    // Let this sheet finish presenting before the Sidekick sheet opens on top of it.
                    guard let question = WhisperEmberActionRouter.shared.consumeSidekickQuestion() else { return }
                    handoffQuestion = question
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard handoffQuestion == question else { return }
                        showAssistant = true
                    }
                }
                .task { await archive.load(includeWithoutSummary: true); prefs = await WhisperMeetingService.shared.fetchNotebookPrefs(); await jasper.load(); await WhisperTranscriptOutbox.shared.flush() }
                .alert(renameFolderID == nil ? "New folder" : "Rename folder", isPresented: $newFolder) {
                    TextField("Folder name", text: $folderName)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") { Task { var fields: [String: Any] = ["action": renameFolderID == nil ? "folder.create" : "folder.rename", "name": folderName]; if let renameFolderID { fields["id"] = renameFolderID }; await jasper.change(fields) } }
                }
                .sheet(isPresented: $showRecordings) { WhisperRecordingArchiveView().id(AccountStorage.currentUserID) }
                .sheet(isPresented: $showEarlier) { NavigationStack { ScrollView { JasperMeetingSavedContentView(meetingID: nil).padding(.horizontal, 20) }.navigationTitle("Earlier writing").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showEarlier = false } } } } }
                .sheet(isPresented: $showPreferences) { JasperMeetingPreferencesView(model: jasper) }
                .sheet(isPresented: $showCalendar) { JasperUpcomingMeetingsView() }
                .sheet(isPresented: $showAssistant, onDismiss: { handoffQuestion = nil }) { NavigationStack { ScrollView { JasperMeetingAssistantView(model: jasper, meetingID: nil, folderID: ["all", "unfiled"].contains(folder) ? nil : folder, initialQuestion: handoffQuestion).padding(.horizontal, 20).padding(.vertical, 16) }.navigationTitle("Sidekick").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showAssistant = false } } } } }
        }.overlay { if archive.isCurrent, let selected { WhisperMeetingNotesView(meeting: selected, onClose: { self.selected = nil }) } }
            .onChange(of: AuthenticationService.shared.currentUser.userID) { _, _ in selected = nil; dismiss() }
    }
    private func folderButton(_ name: String, id: String) -> some View {
        Button { withAnimation(reduceMotion ? nil : .snappy) { folder = id }; Haptics.tap() } label: {
            HStack(spacing: 8) {
                Image(systemName: id == "unfiled" ? "tray" : folder == id ? "folder.fill" : "folder").font(.subheadline).symbolEffect(.bounce, options: .nonRepeating, value: filedFolder == id)
                Text(name).font(.caption.weight(.semibold)).lineLimit(1)
            }.foregroundStyle(folder == id ? Color.primary : Color.secondary).padding(14).frame(minWidth: 112, alignment: .leading)
                .background(folder == id ? Color.primary.opacity(0.08) : Color.secondary.opacity(0.04), in: .rect(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityAddTraits(folder == id ? .isSelected : [])
    }
    private func file(_ meeting: String, to destination: String?, undo: Bool = false) {
        guard filingID == nil else { return }
        let previous = jasper.library?.filings[meeting]
        filingID = meeting
        Task {
            var fields: [String: Any] = ["action": "file", "meetingId": meeting]
            if let destination { fields["folderId"] = destination } else { fields["folderId"] = NSNull() }
            if undo {
                if let expected = undoMove?.destination { fields["expectedFolder"] = expected } else { fields["expectedFolder"] = NSNull() }
            }
            let success = await jasper.change(fields)
            guard jasper.isCurrent else { return }
            withAnimation(reduceMotion ? nil : .snappy) {
                filingID = nil
                if success {
                    filedFolder = destination ?? "unfiled"
                    undoMove = undo ? nil : (meeting, previous, destination)
                    filingMessage = undo ? nil : "Filed in \(jasper.library?.folders.first(where: { $0.id == destination })?.name ?? "Unfiled")"
                }
            }
            if success { Haptics.tap() }
        }
    }
}
