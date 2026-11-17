import SwiftUI

struct WorkspaceIntakeView: View {
    @Bindable var model: WorkspaceWorkViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Invite requesters by their exact Whisper username, then send the restricted intake link. They can follow only their own requests. Removing access hides their requests from them; internal records remain.").font(.subheadline).foregroundStyle(.secondary) }
                if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red) }
                if let intake = model.intake, model.board?.owner == true, model.board?.member == true {
                    Section { Button("Routing & service target") { edit("configure_intake", intake) }; Button("Invite requester") { edit("invite_requester", intake) } }
                    Section("Invited requesters") { ForEach(intake.people) { person in HStack { Text("@\(person.username)"); Spacer(); Button("Revoke") { edit("revoke_requester", intake, userID: person.id) } } } }
                    if let link = model.link() { ShareLink("Share restricted intake link", item: link) }
                } else if model.errorText == nil { ProgressView() }
            }
            .navigationTitle("Intake setup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.loadIntake() }
            .onChange(of: model.board?.owner) { _, owner in if owner != true { dismiss() } }
            .sheet(item: $model.draft) { draft in WorkspaceWorkEditor(draft: draft, model: model) }
        }
    }
    private func edit(_ action: String, _ intake: WorkspaceWorkItem.Intake, userID: String = "") {
        typealias Field = WorkspaceWorkDraft.Field
        let fields: [Field] = action == "configure_intake" ? [.init(id: "instructions", label: "Request instructions", required: true, maximum: 2000, multiline: true), .init(id: "assigneeId", label: "Default accountable owner / approver", required: true, options: model.people), .init(id: "turnaroundDays", label: "Target calendar days (1–90)", required: true, maximum: 2)] : action == "invite_requester" ? [.init(id: "username", label: "Exact Whisper username", required: true, maximum: 40)] : []
        model.draft = WorkspaceWorkDraft(title: action == "configure_intake" ? "Configure intake" : action == "invite_requester" ? "Invite requester" : "Revoke requester access", audience: "Only invited accounts can submit external requests. Targets apply to new requests; they are not automatic reminders or guarantees.", fields: fields, values: ["instructions": intake.instructions, "assigneeId": intake.assigneeId, "turnaroundDays": String(intake.turnaroundDays)], base: ["action": action, "revision": intake.revision, "userId": userID], suffix: "/intake")
    }
}
