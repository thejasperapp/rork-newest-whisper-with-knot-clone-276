import SwiftUI

struct WorkspaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WorkspaceSearchViewModel = WorkspaceSearchViewModel()
    @State private var query: String = ""
    @State private var kind: String = "All"
    @State private var selected: WorkspaceSearchResult?
    @State private var ask: Bool = false
    private let kinds: [String] = ["All", "Meetings", "Notes", "Recordings", "People", "Work"]
    private var results: [WorkspaceSearchResult] { model.results.filter { (kind == "All" || $0.kind == kind) && $0.matches(query) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Type", selection: $kind) { ForEach(kinds, id: \.self) { Text($0).tag($0) } }
                    if kind == "All" || kind == "Work" {
                        Menu {
                            Button("Private work") { Task { await model.work.select(space: model.owner, team: false) } }
                            ForEach(model.work.teams) { team in Button(team.name) { Task { await model.work.select(space: team.id, team: true) } } }
                        } label: { Label(model.work.team ? "Work: selected team" : "Work: private workspace", systemImage: "briefcase") }
                    }
                } footer: { Text("Searches loaded meeting titles and notes, private writing on this device, permitted recording transcripts, your People list and the selected work board. Nothing is sent to Jasper by searching.") }
                if !model.isCurrent { ContentUnavailableView("Sign in to search", systemImage: "lock") }
                else {
                    ForEach(results) { result in
                        HStack(spacing: 10) {
                            Button { ask = false; selected = result } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: result.icon).frame(width: 24).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(result.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Text(result.kind + " · " + String(result.date.prefix(10))).font(.caption).foregroundStyle(.secondary)
                                        if !query.isEmpty { Text(String(result.text.prefix(180))).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                    Spacer(minLength: 0)
                                }.frame(minHeight: 50).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Menu {
                                Button("Open", systemImage: "arrow.up.right") { ask = false; selected = result }
                                Button("Ask Jasper about this", systemImage: "sparkles") { ask = true; selected = result }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Actions for \(result.title)")
                        }
                    }
                    if results.isEmpty && !model.meetings.isLoading && !model.recordings.isLoading && !model.loadingPeople && !model.work.isLoading && model.errorText == nil && model.meetings.errorText == nil && model.recordings.errorText == nil && model.work.errorText == nil {
                        WhisperEmptyState(icon: "magnifyingglass", title: "No matches on loaded pages", message: "Try another word or load older items below.", isCard: false, compact: true)
                    }
                    loadingSection
                }
            }
            .navigationTitle("Search workspace").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Meetings, notes, people, work…")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.load() }
            .whisperRefreshable { await model.load() }
            .sheet(item: $selected) { result in
                if model.isCurrent { WorkspaceSearchDestinationView(result: result, ask: ask, search: model).id(result.id).presentationContentInteraction(.scrolls) }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active, selected == nil { Task { await model.load() } } }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in selected = nil; query = ""; model.clear(); dismiss() }
        }
    }
    private var loadingSection: some View {
        Section("Search coverage") {
            if model.meetings.isLoading || model.recordings.isLoading || model.loadingPeople || model.work.isLoading { ProgressView("Loading permitted items…") }
            ForEach([model.errorText, model.meetings.errorText, model.recordings.errorText, model.work.errorText].compactMap { $0 }, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            Button("Refresh sources") { Task { await model.load() } }
            if model.meetings.canLoadMore { Button("Load older meetings") { Task { await model.meetings.load(more: true, includeWithoutSummary: true) } }.disabled(model.meetings.isLoading) }
            if model.recordings.canLoadMore { Button("Load older recordings") { Task { await model.recordings.load(more: true) } }.disabled(model.recordings.isLoading) }
            if model.peopleMore { Button("Load more people") { Task { await model.loadPeople() } }.disabled(model.loadingPeople) }
        }
    }
}
