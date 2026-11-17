import SwiftUI

struct WorkspaceWorkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WorkspaceWorkViewModel = WorkspaceWorkViewModel()
    @State private var sharedLink: String = ""
    @State private var showIntake: Bool = false
    @State private var showTeams: Bool = false
    var body: some View {
        NavigationStack(path: $model.path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Move work forward.").font(.title2.weight(.semibold))
                        Text("Decide together. Deliver with clarity. Give every request a next step.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    Menu {
                        Button("My private workspace") { Task { await model.select(space: model.owner, team: false) } }
                        ForEach(model.teams) { team in Button(team.name) { Task { await model.select(space: team.id, team: true) } } }
                        Button("Refresh teams") { Task { await model.loadTeams() } }
                    } label: { Label(model.team ? model.teams.first { $0.id == model.space }?.name ?? "Team workspace" : model.space == model.owner ? "My private workspace" : "Invited workspace", systemImage: model.team ? "person.2" : "lock") }
                    Button("Set up or manage teams", systemImage: "person.2") { showTeams = true }
                    DisclosureGroup("Open a shared workspace link") {
                        TextField("Paste restricted link", text: $sharedLink).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Open invitation") { Task { await model.openLink(sharedLink) } }.disabled(sharedLink.isEmpty)
                        Text("Sign in with the invited account. A link alone never grants access.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = model.errorText { Section { Text(error).font(.caption).foregroundStyle(.red); Button("Retry") { Task { await model.load() } } } }
                if let board = model.board {
                    Section {
                        if board.member {
                            Picker("Work type", selection: $model.kind) {
                                Text("All work").tag("all")
                                Text("Decisions").tag("decision")
                                Text("Deliveries").tag("delivery")
                                Text("Requests").tag("request")
                            }
                        } else { Text("Only your shared deliveries and your own requests appear here.").font(.caption).foregroundStyle(.secondary) }
                        Picker("Show", selection: $model.filter) { Text("Active").tag("active"); Text("Needs attention").tag("attention"); Text("Assigned to me").tag("mine"); Text("Including archived").tag("all") }
                    }
                    Section("Your next steps") {
                        ForEach(model.visibleItems) { item in
                            NavigationLink(value: item.id) {
                                HStack(spacing: 12) {
                                    Image(systemName: WorkspaceWorkItem.icon(item.kind)).font(.title3).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.subheadline.weight(.semibold))
                                        Text(WorkspaceWorkItem.statusLabel(item.status)).font(.caption).foregroundStyle(.secondary)
                                        if item.needsAttention { Text("Needs attention").font(.caption2.weight(.medium)).foregroundStyle(.orange) }
                                        if !item.deadline.isEmpty { Text("Due \(item.deadline) · UTC").font(.caption2).foregroundStyle(.secondary) }
                                    }
                                }.padding(.vertical, 6)
                            }
                        }
                        if model.visibleItems.isEmpty { WhisperEmptyState(icon: "checkmark.circle", title: "A clear desk", message: "Create a brief or request. Nothing is imported automatically.", isCard: false) }
                    }
                    if board.member || board.canSubmit {
                        Section("Create") {
                            ForEach(board.member ? ["decision", "delivery", "request"] : ["request"], id: \.self) { kind in Button("New \(kind)", systemImage: WorkspaceWorkItem.icon(kind)) { create(kind) } }
                        }
                    }
                    if board.owner { Section { Button("Intake setup", systemImage: "tray.and.arrow.down") { showIntake = true }; if let link = model.link() { ShareLink("Share restricted intake link", item: link) } } }
                    Section { Text("Updates require a confirmed save. Due dates use UTC days. This desk does not verify meeting transcript completeness.").font(.caption).foregroundStyle(.secondary) }
                } else if model.isLoading { ProgressView("Loading workspace…") }
            }
            .searchable(text: $model.search, prompt: "Search workspace titles")
            .navigationTitle("Work desk").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }.disabled(model.isLoading) } }
            .navigationDestination(for: String.self) { id in WorkspaceWorkDetailView(model: model, itemID: id) }
            .whisperRefreshable { await model.load() }
            .task { await model.load(); await model.loadTeams() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in model.clear(); dismiss() }
            .sheet(item: Binding(get: { showIntake ? nil : model.draft }, set: { if !showIntake { model.draft = $0 } })) { draft in WorkspaceWorkEditor(draft: draft, model: model) }
            .fullScreenCover(isPresented: $showTeams, onDismiss: { Task { await model.loadTeams(); await model.load() } }) { WhisperBusinessWorkspaceView() }
            .sheet(isPresented: $showIntake) { WorkspaceIntakeView(model: model) }
        }
    }
    private func create(_ kind: String) {
        typealias Field = WorkspaceWorkDraft.Field
        var fields: [Field] = [.init(id: "title", label: "Title", required: true, maximum: 160), .init(id: "brief", label: kind == "request" ? "What do you need, and why?" : "Brief and desired outcome", required: true, multiline: true)]
        if kind == "decision" { fields += [.init(id: "alternatives", label: "Alternatives and trade-offs", maximum: 4000, multiline: true), .init(id: "reviewOn", label: "Outcome review date · YYYY-MM-DD (UTC)", maximum: 10)] }
        if model.board?.member == true { fields += [.init(id: "deadline", label: "Due date · YYYY-MM-DD (UTC)", maximum: 10), .init(id: "assigneeId", label: "Accountable owner / approver", required: true, options: model.people)] }
        if kind == "request" { fields += [.init(id: "category", label: "Category / service", maximum: 80), .init(id: "priority", label: "Priority", options: [.init(id: "normal", username: "Normal"), .init(id: "urgent", username: "Urgent")])] }
        model.draft = WorkspaceWorkDraft(title: kind == "request" ? "Submit reviewed request" : "Create \(kind)", audience: model.board?.member == true ? "Saved to this \(model.team ? "team" : "private") workspace. No meetings, recordings or private notes are imported. Client delivery publication is a separate review." : "\(model.board?.intakeInstructions ?? "") Your request is shared with the workspace team, not other requesters.", fields: fields, values: ["assigneeId": model.owner, "priority": "normal"], base: ["action": "create", "id": UUID().uuidString.lowercased(), "kind": kind])
    }
}
