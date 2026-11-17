import SwiftUI

/// Small native forms for company, team roles and calendar events.
struct WhisperBusinessEditorView: View {
    enum Kind: Identifiable {
        case company(String), member(WhisperBusinessModels.Member?), event
        var id: String {
            switch self {
            case .company: "company"
            case .member(let member): "member-\(member?.id ?? "new")"
            case .event: "event"
            }
        }
        var title: String {
            switch self {
            case .company: "Company name"
            case .member(let member): member == nil ? "Add teammate" : "Edit role"
            case .event: "New business event"
            }
        }
    }
    let kind: Kind
    let service: WhisperBusinessWorkspaceService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var name: String = ""
    @State private var role: String = ""
    @State private var details: String = ""
    @State private var start: Date = Date().addingTimeInterval(3600)
    @State private var minutes: Int = 30
    @State private var meetingLink: String = ""
    @State private var eventID: String = UUID().uuidString
    @State private var saving: Bool = false
    @State private var error: String?
    @State private var openedVersion: UUID?

    private var valid: Bool {
        guard openedVersion == service.contextVersion, service.context != nil else { return false }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .company: return !clean.isEmpty && clean.count <= 100
        case .member: return !clean.isEmpty && clean.count <= 100 && role.count <= 80
        case .event:
            return !clean.isEmpty && clean.count <= 150 && details.count <= 4000
                && (meetingLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || WhisperServedAd.webURL(meetingLink) != nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .company:
                    Section("Company") { TextField("Company name", text: $name) }
                case .member(let member):
                    Section {
                        TextField("Whisper username", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(member != nil)
                        TextField("Role title", text: $role)
                    } footer: {
                        Text("Adding a teammate gives their existing Whisper account access to this workspace. Role titles are labels, not administrator permissions.")
                    }
                case .event:
                    Section("Event") {
                        TextField("Title", text: $name)
                        TextField("Details (optional)", text: $details, axis: .vertical).lineLimit(3...6)
                        DatePicker("Starts", selection: $start)
                        Picker("Duration", selection: $minutes) {
                            ForEach([15, 30, 45, 60, 90, 120], id: \.self) { duration in Text("\(duration) minutes").tag(duration) }
                        }
                    }
                    Section {
                        TextField("https://…", text: $meetingLink).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: { Text("Meeting link (optional)") } footer: {
                        Text("Paste a link from Whisper Meetings or another meeting service. This event appears in the shared calendar; it is not private.")
                    }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .scrollIndicators(.hidden)
            .disabled(saving)
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if saving { ProgressView() } else { Text("Save").fontWeight(.semibold) }
                    }.disabled(saving || !valid)
                }
            }
            .tint(WhisperTheme.ink(scheme))
            .onAppear {
                guard openedVersion == nil else { return }
                openedVersion = service.contextVersion
                switch kind {
                case .company(let company): name = company
                case .member(let member): name = member?.username ?? ""; role = member?.role_title ?? "Team member"
                case .event: break
                }
            }
            .onChange(of: service.contextVersion) { _, _ in
                error = WhisperBusinessModels.Failure.contextChanged.errorDescription
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() {
        guard valid, !saving else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                guard openedVersion == service.contextVersion, service.context != nil else {
                    throw WhisperBusinessModels.Failure.contextChanged
                }
                switch kind {
                case .company: try await service.renameCompany(name)
                case .member(let member): try await service.saveMember(username: name, role: role, existing: member)
                case .event: try await service.createEvent(id: eventID, title: name, details: details, start: start, minutes: minutes, meetingLink: meetingLink)
                }
                guard openedVersion == service.contextVersion else { throw WhisperBusinessModels.Failure.contextChanged }
                Haptics.tap()
                dismiss()
            } catch {
                self.error = (error as? WhisperBusinessModels.Failure)?.errorDescription ?? "The change wasn't saved. Check your connection and try again."
            }
        }
    }
}
