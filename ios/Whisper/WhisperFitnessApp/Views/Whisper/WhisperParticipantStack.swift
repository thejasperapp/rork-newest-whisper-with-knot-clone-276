import SwiftUI

/// Compact, overlapping identities with a readable disclosure for the full list.
struct WhisperParticipantStack: View {
    let people: [WhisperGroupMember]
    let label: String
    var compact: Bool = false
    @Environment(\.colorScheme) private var scheme
    @State private var expanded: Bool = false
    @State private var avatars: [String: String] = [:]
    @State private var generation: UUID = AccountStorage.generation

    private var uniquePeople: [WhisperGroupMember] {
        var seen: Set<String> = []
        return people.filter { seen.insert($0.user_id.lowercased()).inserted }
    }

    var body: some View {
        let members = uniquePeople
        if !members.isEmpty {
            Group {
            if compact {
                HStack(spacing: -5) {
                    ForEach(Array(members.prefix(3)), id: \.user_id) { person in
                        WhisperAvatar(username: person.username, size: 18, imageURL: (person.profile_image_url ?? avatars[person.user_id]).flatMap(URL.init(string:)), ring: false)
                            .overlay { Circle().strokeBorder(WhisperChatAppearance.classic.palette(scheme).canvas, lineWidth: 1) }
                    }
                    if members.count > 3 {
                        Text("+\(members.count - 3)").font(.system(size: 9, weight: .medium)).padding(.leading, 7)
                    }
                }
                .accessibilityElement(children: .ignore)
            } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(members, id: \.user_id) { person in
                    HStack(spacing: 8) {
                        WhisperAvatar(username: person.username, size: 24, imageURL: (person.profile_image_url ?? avatars[person.user_id]).flatMap(URL.init(string:)), ring: false)
                        Text(verbatim: person.username).font(.caption).lineLimit(2)
                        Spacer(minLength: 0)
                    }.padding(.vertical, 4)
                }
            } label: {
                HStack(spacing: 8) {
                    HStack(spacing: -8) {
                        ForEach(Array(members.prefix(5)), id: \.user_id) { person in
                            WhisperAvatar(username: person.username, size: 24, imageURL: (person.profile_image_url ?? avatars[person.user_id]).flatMap(URL.init(string:)), ring: false)
                                .overlay { Circle().strokeBorder(WhisperTheme.surface(scheme), lineWidth: 2) }
                        }
                    }.accessibilityHidden(true)
                    Text("\(label) · \(members.count)").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 44)
            }
            }
            }
            .accessibilityLabel("\(label): \(members.map(\.username).joined(separator: ", "))")
            .task(id: members.map(\.user_id).joined(separator: ",")) {
                let rows = await WhisperBackendService.shared.fetchPublicProfiles(userIDs: members.filter { $0.profile_image_url == nil }.map(\.user_id))
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                avatars = rows.compactMapValues(\.profile_image_url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in avatars = [:] }
        }
    }
}
