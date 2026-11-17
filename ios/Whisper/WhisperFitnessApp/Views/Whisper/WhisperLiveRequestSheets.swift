import SwiftUI

// MARK: - Speaker request sheet

struct SpeakerRequestSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let roomID: String
    let service: WhisperLiveRoomService
    let onSent: () -> Void

    @State private var role: String = "general"
    @State private var answers: [String: String] = [:]
    @State private var busy: Bool = false
    @State private var submitError: String?

    private let roles = [
        ("athlete", "Athlete"),
        ("coach", "Coach"),
        ("creator", "Creator"),
        ("general", "General")
    ]

    private var questions: [(id: String, label: String, required: Bool)] {
        switch role {
        case "athlete":
            return [("sport", "Primary sport or discipline", true), ("experience", "Years competing", true), ("level", "Current level", true), ("goals", "Your athletic goals", true)]
        case "coach":
            return [("certifications", "Certifications or credentials", true), ("specialty", "Specialty or niche", true), ("experience", "Years coaching", true), ("approach", "Coaching philosophy", true)]
        case "creator":
            return [("platforms", "Primary platforms and handles", true), ("followers", "Approximate follower count", true), ("content", "What kind of content do you make?", true), ("goal", "What do you want to share?", true)]
        default:
            return [("topic", "What topic would you like to speak about?", true), ("background", "What is your background?", true)]
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Request to join")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))

                        Picker("Role", selection: $role) {
                            ForEach(roles, id: \.0) { r in
                                Text(r.1).tag(r.0)
                            }
                        }
                        .pickerStyle(.segmented)

                        ForEach(questions, id: \.id) { q in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(q.label + (q.required ? " *" : ""))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                TextField("Answer", text: binding(for: q.id), axis: .vertical)
                                    .lineLimit(3...6)
                                    .padding(12)
                                    .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        if let submitError {
                            Text(submitError)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Text("Send request")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.green, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Join request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { answers[key] ?? "" }, set: { answers[key] = $0 })
    }

    private func submit() async {
        let missing = questions.filter { $0.required && (answers[$0.id]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }
        guard missing.isEmpty else {
            submitError = "Please fill in all required fields."
            return
        }
        submitError = nil
        busy = true
        do {
            try await service.createSpeakerRequest(roomID: roomID, desiredRole: role, answers: answers)
            onSent()
        } catch {
            submitError = "Could not send request: \(error.localizedDescription)"
            print("[WhisperLiveRoom] submit request error: \(error)")
        }
        busy = false
    }
}

// MARK: - Host requests panel

struct SpeakerRequestsPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let roomID: String
    let service: WhisperLiveRoomService
    let requests: [WhisperLiveSpeakerRequest]
    let onUpdated: () -> Void

    /// user_id (lowercased) → public profile, so rows show real @usernames
    /// and avatars instead of raw UUID strings.
    @State private var profiles: [String: WhisperBackendService.WhisperPublicProfile] = [:]

    private func profile(_ request: WhisperLiveSpeakerRequest) -> WhisperBackendService.WhisperPublicProfile? {
        profiles[request.user_id.lowercased()]
    }

    private func displayName(_ request: WhisperLiveSpeakerRequest) -> String {
        let p = profile(request)
        if let username = p?.username, !username.isEmpty { return username }
        if let display = p?.display_name, !display.isEmpty { return display }
        return "member"
    }

    private func avatarURL(_ request: WhisperLiveSpeakerRequest) -> URL? {
        profile(request)?.profile_image_url.flatMap(URL.init(string:))
    }

    private func hydrateProfiles() async {
        let ids = requests.map { $0.user_id }.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        let fetched = await service.hydrateProfiles(userIDs: ids)
        var normalized: [String: WhisperBackendService.WhisperPublicProfile] = [:]
        for (key, value) in fetched { normalized[key.lowercased()] = value }
        profiles = normalized
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                List {
                    ForEach(requests) { request in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                WhisperAvatar(
                                    username: displayName(request),
                                    size: 36,
                                    imageURL: avatarURL(request),
                                    ring: false
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("@\(displayName(request))")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(request.desired_role.capitalized)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                                Spacer()
                                Text(request.status)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(statusColor(request.status))
                            }
                            ForEach(Array(request.answers.keys.sorted()), id: \.self) { key in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    Text(request.answers[key] ?? "")
                                        .font(.caption)
                                }
                            }
                            if request.status == "pending" {
                                HStack(spacing: 12) {
                                    Button {
                                        Task { await decide(request, accept: true) }
                                    } label: {
                                        Text("Accept")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(Color.green, in: Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        Task { await decide(request, accept: false) }
                                    } label: {
                                        Text("Decline")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(Color.red, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task(id: requests.map(\.user_id).joined(separator: ",")) {
                await hydrateProfiles()
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "accepted": return .green
        case "rejected": return .red
        default: return .orange
        }
    }

    private func decide(_ request: WhisperLiveSpeakerRequest, accept: Bool) async {
        do {
            try await service.decideSpeakerRequest(request: request, accept: accept)
            onUpdated()
        } catch {
            print("[WhisperLiveRoom] decide error: \(error)")
        }
    }
}
