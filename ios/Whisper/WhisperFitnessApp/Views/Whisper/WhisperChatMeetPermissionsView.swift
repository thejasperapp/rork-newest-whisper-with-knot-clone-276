import SwiftUI

struct WhisperChatMeetPermissionsView: View {
    let peerName: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WhisperChatMeetPermissionsViewModel
    @State private var pendingAction: WhisperChatMeetPermission.Action?
    @State private var pendingPermission: WhisperChatMeetPermission?

    init(peerID: String, peerName: String) {
        self.peerName = peerName
        _model = State(initialValue: WhisperChatMeetPermissionsViewModel(peerID: peerID))
    }

    var body: some View {
        Form {
            Section {
                Label("Direct invitations only", systemImage: "person.badge.shield.checkmark")
                    .font(.headline)
                Text("Each direction needs its own permission. Allowing \(peerName) to invite you does not let you invite them.")
                Text("This does not grant messaging, dating, group membership, media or Notes access. Each invitation still has its own RSVP and explicit Join.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if WhisperChatMeetService.holdsNewInvitations {
                Section("Rollout paused") {
                    Text(WhisperChatMeetService.Failure.clientRolloutHold.localizedDescription)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if model.isLoading || model.isSaving {
                Section { ProgressView(model.isSaving ? "Checking and updating permission…" : "Loading permissions…") }
            }
            if model.hasLoaded {
                incomingSection
                outgoingSection
            }
            if let error = model.error {
                Section("Couldn't confirm") { Text(error).font(.subheadline).foregroundStyle(.red) }
            }
            if let notice = model.notice {
                Section { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                Button("Refresh permissions") { model.refresh() }
                    .frame(minHeight: 44).disabled(model.isLoading || model.isSaving || scenePhase != .active)
                Text("Only permissions returned by Meet are shown. Blocked pairs are omitted; a missing row is not approval. Denied or revoked permissions cannot be reopened by requesting again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Meet permissions").navigationBarTitleDisplayMode(.inline)
        .whisperNavigationBack()
        .onAppear { model.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            pendingAction = nil; pendingPermission = nil
            model.setActive(phase == .active)
        }
        .onDisappear { pendingAction = nil; pendingPermission = nil; model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
            pendingAction = nil; pendingPermission = nil; model.invalidateAccount()
        }
        .confirmationDialog("\(pendingAction == .deny ? "Deny" : "Revoke") Meet invitation permission?", isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil; pendingPermission = nil } }
        ), titleVisibility: .visible) {
            Button(pendingAction == .deny ? "Deny permission" : "Revoke permission", role: .destructive) {
                if let action = pendingAction, let snapshot = pendingPermission { model.change(action, snapshot: snapshot) }
                pendingAction = nil; pendingPermission = nil
            }
            Button("Keep permission", role: .cancel) { pendingAction = nil; pendingPermission = nil }
        } message: {
            Text("This direction cannot be accepted again under the current Meet permission rules. It does not change the separate permission for you to invite them, and it is not a Leave-call action.")
        }
    }

    private var incomingSection: some View {
        Section("They invite you") {
            if let permission = model.incoming {
                permissionSummary(permission)
                if permission.state == .pending {
                    Button("Allow their Meet invitations") { model.change(.accept, snapshot: permission) }
                        .frame(minHeight: 44)
                        .disabled(!model.canInteract || WhisperChatMeetService.holdsNewInvitations)
                    Button("Deny permission", role: .destructive) { confirm(.deny, permission) }
                        .frame(minHeight: 44).disabled(!model.canInteract)
                } else if permission.state == .accepted {
                    Button("Revoke permission", role: .destructive) { confirm(.revoke, permission) }
                        .frame(minHeight: 44).disabled(!model.canInteract)
                }
            } else {
                Text("No incoming permission is currently shown.").foregroundStyle(.secondary)
            }
        }
    }

    private var outgoingSection: some View {
        Section("You invite them") {
            if let permission = model.outgoing {
                permissionSummary(permission)
                Text("Only the other person can approve, deny or revoke this direction.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("No outgoing permission is currently shown.").foregroundStyle(.secondary)
                Button("Request invitation permission") { model.change(.request) }
                    .frame(minHeight: 44)
                    .disabled(!model.canInteract || WhisperChatMeetService.holdsNewInvitations)
            }
        }
    }

    private func permissionSummary(_ permission: WhisperChatMeetPermission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(permission.username.map { "@\($0)" } ?? peerName).font(.headline)
            Text(permission.state.label).font(.subheadline)
            Text("Server revision \(String(permission.revision))").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }

    private func confirm(_ action: WhisperChatMeetPermission.Action, _ permission: WhisperChatMeetPermission) {
        pendingPermission = permission
        pendingAction = action
    }
}
