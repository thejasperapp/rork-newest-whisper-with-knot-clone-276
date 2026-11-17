import SwiftUI

/// Account-scoped suggestions while typing a trailing @handle, without stealing keyboard focus.
struct WhisperMentionSuggestionsBar: View {
    @Binding var text: String
    var onSelect: ((WhisperUserRow) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var remoteResults: [WhisperUserRow] = []
    @State private var isSearching: Bool = false
    @State private var searchFailed: Bool = false
    @State private var retry: Int = 0

    private var token: String? { WhisperMentionToken.trailing(in: text) }
    private var queryID: String { "\(AccountStorage.generation)|\(token ?? "<closed>")|\(retry)" }

    private var names: [String] {
        guard let token else { return [] }
        let query = token.lowercased()
        let local = ["knot"] + Array(WhisperFollowService.shared.followingUsernames.values)
            + WhisperBackendService.shared.threads.map(\.otherUsername)
            + WhisperBackendService.shared.postAuthorProfiles.values.compactMap(\.username)
        var seen: Set<String> = []
        let matches = local.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) } + remoteResults.map(\.username)
        return Array(matches.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(20))
    }

    var body: some View {
        Group {
            if token != nil {
                if !names.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(names, id: \.self) { name in
                                Button {
                                    Haptics.tap()
                                    text = WhisperMentionToken.replacingTrailing(in: text, username: name)
                                    if let row = remoteResults.first(where: { $0.username == name }) { onSelect?(row) }
                                } label: {
                                    HStack(spacing: 8) {
                                        WhisperAvatar(username: name, size: 28, ring: false)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("@\(name)").font(.footnote.weight(.semibold))
                                            if let display = remoteResults.first(where: { $0.username == name })?.display_name, !display.isEmpty {
                                                Text(display).font(.caption2).lineLimit(1)
                                            }
                                        }
                                    }
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                                }.buttonStyle(.plain).accessibilityLabel("Mention \(name)")
                            }
                        }.padding(.vertical, 6)
                    }.contentMargins(.horizontal, 14)
                } else if isSearching {
                    ProgressView("Finding people…").font(.footnote).padding(10)
                } else if searchFailed {
                    Button("Couldn't find people. Tap to retry") { retry += 1 }.font(.footnote).frame(minHeight: 44)
                } else if token?.isEmpty == false {
                    Text("No matching people").font(.footnote).foregroundStyle(.secondary).padding(12)
                }
            }
        }
        .task(id: queryID) {
            remoteResults = []; searchFailed = false; isSearching = false
            guard let query = token, !query.isEmpty else { return }
            let generation = AccountStorage.generation
            isSearching = true
            do {
                try await Task.sleep(for: .milliseconds(220))
                let rows = try await WhisperUserService.shared.mentionSuggestions(query)
                guard !Task.isCancelled, token == query, generation == AccountStorage.generation else { return }
                remoteResults = rows; isSearching = false
            } catch {
                guard !Task.isCancelled, token == query, generation == AccountStorage.generation else { return }
                isSearching = false; searchFailed = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
            remoteResults = []; isSearching = false
        }
    }
}
