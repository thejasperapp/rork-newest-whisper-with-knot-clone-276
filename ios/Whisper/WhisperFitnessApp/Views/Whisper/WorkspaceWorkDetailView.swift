import SwiftUI

struct WorkspaceWorkDetailView: View {
    @Bindable var model: WorkspaceWorkViewModel
    let itemID: String
    var focusJasper: Bool = false
    @State private var connections: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red); Button("Refresh access") { Task { await model.loadItem(itemID) } } }
                if let item = model.item, item.id == itemID {
                    Text(WorkspaceWorkItem.name(item.kind)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(item.title).font(.title2.weight(.semibold))
                    Text(WorkspaceWorkItem.statusLabel(item.status)).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary, in: .capsule)
                    Text(item.external ? "Shared with you" : model.team ? "Team workspace" : "Private workspace").font(.caption).foregroundStyle(.secondary)
                    if !item.assigneeId.isEmpty { Text("Accountable owner: \(model.name(item.assigneeId))").font(.caption) }
                    if !item.deadline.isEmpty { Text("Due \(item.deadline) · UTC").font(.caption) }
                    if !item.reviewOn.isEmpty { Text("Outcome review \(item.reviewOn) · UTC").font(.caption) }
                    Text(item.brief).font(.subheadline).textSelection(.enabled)
                    if !item.alternatives.isEmpty { content("Alternatives & trade-offs", item.alternatives) }
                    if !item.outcome.isEmpty { content("Recorded outcome", item.outcome) }
                    if !item.internalNote.isEmpty { DisclosureGroup("Internal context") { Text(item.internalNote).font(.subheadline) } }
                    actions(item)
                    if !item.versions.isEmpty { Text("Delivery versions").font(.headline) }
                    ForEach(item.versions.reversed()) { version in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Version \(version.number) · \(String(version.at.prefix(10)))").font(.caption).foregroundStyle(.secondary)
                            Text(version.title).font(.headline)
                            Text(version.summary).font(.subheadline)
                            if !version.milestones.isEmpty { Text(version.milestones).font(.subheadline) }
                            if let url = URL(string: version.url), url.scheme == "https" { Link("Open deliverable", destination: url).frame(minHeight: 44) }
                            if let response = version.response { Divider(); Text(WorkspaceWorkItem.statusLabel(response.status)).font(.subheadline.weight(.semibold)); Text("\(model.name(response.actor)) · \(String(response.at.prefix(10)))").font(.caption).foregroundStyle(.secondary); Text(response.text).font(.subheadline) }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 18))
                    }
                    if !item.comments.isEmpty { Text("Discussion").font(.headline) }
                    ForEach(item.comments) { comment in
                        VStack(alignment: .leading, spacing: 8) { Text("\(model.name(comment.author)) · \(comment.audience == "internal" ? "Internal only" : "Shared")").font(.caption).foregroundStyle(.secondary); Text(comment.text).font(.subheadline) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
                    }
                    if !item.external {
                        DisclosureGroup("Activity history · revision \(item.revision)") {
                            ForEach(item.events.reversed()) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(WorkspaceWorkItem.statusLabel(event.action)) · \(model.name(event.actor)) · \(String(event.at.prefix(16)))")
                                    if let revision = event.contentRevision { Text("Content revision \(revision)").foregroundStyle(.secondary) }
                                    if let detail = event.detail { Text(detail) }
                                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }
                        }
                    }
                    if let url = model.link(item.id) { ShareLink("Share restricted link", item: url).frame(minHeight: 44) }
                } else if model.errorText == nil { ProgressView("Loading item…") }
            }.padding(.horizontal, 16).padding(.vertical, 20)
        }
        .navigationTitle("Workspace item").navigationBarTitleDisplayMode(.inline)
        .whisperRefreshable { await model.loadItem(itemID) }
        .task(id: itemID) {
            await model.loadItem(itemID)
            if !Task.isCancelled, focusJasper, model.isCurrent, model.item?.id == itemID, model.item?.external == false { connections = true }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.loadItem(itemID) } } }
        .onChange(of: model.item?.revision) { prior, _ in if prior != nil { connections = false } }
        .onChange(of: model.item?.external) { _, external in if external != false { connections = false } }
        .sheet(isPresented: $connections) { if let item = model.item, !item.external { JasperNoteConnectionsView(initialNote: .init(title: item.title, text: item.brief)) } }
    }
    private func content(_ title: String, _ text: String) -> some View { VStack(alignment: .leading, spacing: 10) { Text(title).font(.headline); Text(text).font(.subheadline).textSelection(.enabled) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 18)) }
    @ViewBuilder private func actions(_ item: WorkspaceWorkItem) -> some View {
        if item.status != "archived" {
            VStack(alignment: .leading, spacing: 8) {
                if item.kind == "decision" {
                    if item.canManage && item.status == "draft" { action(item, "open", "Open discussion") }
                    if item.canDecide && item.status == "discussing" { action(item, "decide", "Record decision") }
                    if item.canDecide && item.status == "decided" { action(item, "review", "Record outcome review") }
                    if model.board?.owner == true && !item.external && item.status == "decided" { action(item, "reassign_reviewer", "Assign outcome reviewer") }
                }
                if item.kind == "request" {
                    if item.canManage { switch item.status { case "submitted": action(item, "triage", "Accept for triage"); case "triaged": action(item, "seek_approval", "Request approval"); case "approved": action(item, "start", "Start work"); case "in_progress": action(item, "complete", "Mark complete"); default: EmptyView() } }
                    if item.canDecide && item.status == "awaiting_approval" { action(item, "approve", "Approve request"); action(item, "decline", "Decline request") }
                }
                if item.canManage && !["decided", "reviewed", "completed", "declined"].contains(item.status) { action(item, "edit", "Edit brief") }
                if item.canManage && item.kind == "delivery" { action(item, "publish", "Publish reviewed version"); if item.publishedVersion != nil { action(item, "revoke", "Revoke client access") } }
                if item.canRespond { action(item, "respond", "Accept this version"); action(item, "respond", "Request changes") }
                if item.kind != "decision" || item.status == "discussing" { action(item, "comment", item.kind == "decision" ? "Add contribution or objection" : "Add comment") }
                if !item.external { Button("Ask Jasper about this", systemImage: "sparkles") { connections = true }.frame(minHeight: 44) }
                if item.canManage { action(item, "archive", "Archive this item") }
            }.buttonStyle(.bordered).controlSize(.large)
        }
    }
    private func action(_ item: WorkspaceWorkItem, _ action: String, _ label: String) -> some View { Button(label) { makeDraft(item, action, label) } }
    private func makeDraft(_ item: WorkspaceWorkItem, _ action: String, _ label: String) {
        typealias Field = WorkspaceWorkDraft.Field
        var fields: [Field] = []
        var values: [String: String] = ["title": item.title, "brief": item.brief, "alternatives": item.alternatives, "deadline": item.deadline, "reviewOn": item.reviewOn, "assigneeId": item.assigneeId, "internalNote": item.internalNote, "username": item.client?.username ?? "", "audience": item.external || item.kind == "decision" ? "shared" : "internal"]
        var base: [String: Any] = ["action": action, "id": item.id, "revision": item.revision, "assigneeId": item.assigneeId, "alternatives": item.alternatives, "reviewOn": item.reviewOn]
        if action == "reassign_reviewer" {
            fields = [.init(id: "assigneeId", label: "Outcome reviewer", required: true, options: model.people)]
        } else if action == "edit" {
            fields = [.init(id: "title", label: "Title", required: true, maximum: 160), .init(id: "brief", label: "Brief", required: true, multiline: true), .init(id: "deadline", label: "Due date · YYYY-MM-DD (UTC)", maximum: 10), .init(id: "internalNote", label: "Internal context — excluded from client portal", maximum: 4000, multiline: true)]
            if item.kind == "decision" { fields += [.init(id: "alternatives", label: "Alternatives and trade-offs", maximum: 4000, multiline: true), .init(id: "reviewOn", label: "Outcome review · YYYY-MM-DD (UTC)", maximum: 10)] }
            if model.board?.owner == true { fields.append(.init(id: "assigneeId", label: "Accountable owner / approver", required: true, options: model.people)) }
        } else if action == "publish" {
            fields = [.init(id: "username", label: "Client’s exact Whisper username", required: true, maximum: 40), .init(id: "title", label: "Client-facing title", required: true, maximum: 160), .init(id: "summary", label: "Reviewed delivery update", required: true, maximum: 6000, multiline: true), .init(id: "milestones", label: "Milestones, dates and progress", maximum: 3000, multiline: true), .init(id: "url", label: "Deliverable HTTPS link (optional)", maximum: 2000)]
        } else if action == "comment" {
            fields = [.init(id: "text", label: "Contribution, objection or comment", required: true, maximum: 2000, multiline: true)]
            if !item.external && item.kind != "decision" { fields.append(.init(id: "audience", label: "Visibility", options: [.init(id: "internal", username: "Internal only"), .init(id: "shared", username: "Also visible to client / requester")])) } else { base["audience"] = "shared" }
        } else if ["respond", "decide", "review", "approve", "decline"].contains(action) { fields = [.init(id: "text", label: "Reason, feedback or outcome", required: label != "Accept this version", maximum: 2000, multiline: true)] }
        if action == "respond" { base["version"] = item.publishedVersion ?? 0; base["status"] = label == "Accept this version" ? "accepted" : "changes_requested" }
        values["text"] = ""
        let audience = action == "publish" ? "Only the named client can view this published version. Internal briefs and discussions are excluded. Linked files keep their own permissions. Share the restricted link yourself; no email is sent." : "Saved to this \(model.team ? "team" : "private") workspace. Request briefs and outcomes and shared comments are visible to their requester. Delivery clients see only separately published content. Decisions and approvals are attributed to your signed-in account."
        model.draft = WorkspaceWorkDraft(title: label, audience: audience, fields: fields, values: values, base: base)
    }
}
