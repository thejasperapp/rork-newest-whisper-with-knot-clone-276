import SwiftUI

struct WhisperMeetCallsView: View {
    @State private var query: String = ""
    @State private var people: [WhisperUserRow] = []
    @State private var searching: Bool = false
    @State private var ringing: Bool = false
    @State private var searchError: String?
    @State private var searchAttempt = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A conversation away.").font(.title2.bold())
            Text("Find someone by @username, then ring them on Whisper.").font(.subheadline).foregroundStyle(.secondary)
            TextField("Search people", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).background(.quaternary, in: Capsule())
            if searching { ProgressView() }
            if let searchError {
                Text(searchError).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { searchAttempt = UUID() }.frame(minHeight: 44)
            }
            ForEach(people) { person in
                HStack {
                    VStack(alignment: .leading) { Text(person.display_name ?? person.username).font(.subheadline.bold()); Text("@\(person.username)").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    callButton(person, video: false)
                    callButton(person, video: true)
                }
            }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && people.isEmpty && !searching && searchError == nil { Text("No people found. Try another username.").font(.caption).foregroundStyle(.secondary) }
            if WhisperCallService.shared.active != nil { Text("You already have a call open. Finish it before ringing someone else.").font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: "\(query)/\(searchAttempt)/\(AccountStorage.generation)") {
            let generation = AccountStorage.generation
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            people = []; searching = false; searchError = nil
            guard term.count >= 2 else { return }
            searching = true
            defer { if !Task.isCancelled, generation == AccountStorage.generation { searching = false } }
            do {
                try await Task.sleep(for: .milliseconds(300))
                let found = try await WhisperUserService.shared.mentionSuggestions(term, limit: 12, matchingNames: true)
                guard !Task.isCancelled, generation == AccountStorage.generation,
                      term == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                people = found.filter { $0.user_id.lowercased() != AccountStorage.currentUserID.lowercased() }
            } catch {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                searchError = "People couldn’t load just now."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            query = ""; people = []; searching = false; searchError = nil
        }
    }
    private func callButton(_ person: WhisperUserRow, video: Bool) -> some View {
        Button {
            ringing = true
            Task {
                await WhisperCallService.shared.startOutgoing(otherUserID: person.user_id, otherUsername: person.username, avatarURL: person.profile_image_url.flatMap(URL.init(string:)), mode: video ? .video : .audio)
                ringing = false
            }
        } label: { Image(systemName: video ? "video" : "phone").frame(width: 44, height: 44).background(.quaternary, in: Circle()) }
            .disabled(ringing || WhisperCallService.shared.active != nil)
            .accessibilityLabel("\(video ? "Video call" : "Call") \(person.username)")
    }
}
