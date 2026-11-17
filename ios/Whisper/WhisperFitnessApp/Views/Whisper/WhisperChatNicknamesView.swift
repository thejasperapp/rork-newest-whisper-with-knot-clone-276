import SwiftUI

struct WhisperChatNicknamesView: View {
    let thread: String
    let members: [WhisperGroupMember]
    @State private var selected: WhisperGroupMember?
    @State private var draft: String = ""
    @State private var revision: Int = 0
    @State private var epoch: UUID = AccountStorage.generation

    static func nickname(thread: String, userID: String) -> String? {
        AccountStorage.string(forKey: "whisper.nickname.\(thread.lowercased()).\(userID.lowercased())")
    }

    var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    Button {
                        epoch = AccountStorage.generation
                        draft = Self.nickname(thread: thread, userID: member.user_id) ?? ""
                        selected = member
                    } label: {
                        HStack(spacing: 12) {
                            WhisperAvatar(username: member.username, size: 40, imageURL: member.profile_image_url.flatMap(URL.init(string:)), ring: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Self.nickname(thread: thread, userID: member.user_id) ?? member.username).font(.body)
                                Text("@\(member.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: 48)
                    }.buttonStyle(.plain)
                }
            } header: { Text("Nicknames only appear for you in this chat on this device. Public usernames never change.") }
        }
        .listStyle(.plain)
        .navigationTitle("Nicknames").navigationBarTitleDisplayMode(.inline)
        .whisperNavigationBack()
        .alert("Set nickname", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            TextField("Nickname", text: $draft)
            Button("Save") {
                guard epoch == AccountStorage.generation, let selected else { return }
                let key = "whisper.nickname.\(thread.lowercased()).\(selected.user_id.lowercased())"
                let name = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                if name.isEmpty { AccountStorage.removeObject(forKey: key) } else { AccountStorage.set(name, forKey: key) }
                revision += 1
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Leave it blank to use their username.") }
        .id(revision)
    }
}
