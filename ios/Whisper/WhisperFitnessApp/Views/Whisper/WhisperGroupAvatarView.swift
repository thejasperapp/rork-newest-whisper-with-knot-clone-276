import SwiftUI
import Supabase

/// Group identity uses private storage, fetched with the viewer's session (no public URL).
struct WhisperGroupAvatarView: View {
    let group: WhisperGroup
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?

    var body: some View {
        Circle().fill(WhisperTheme.card(colorScheme))
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().allowsHitTesting(false)
                } else {
                    Text(String(group.name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased())
                        .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5) }
            .task(id: "\(AccountStorage.generation)|\(group.avatarPath ?? "")") {
                image = nil
                guard let path = group.avatarPath, path.hasPrefix(group.id.uuidString.lowercased() + "/") else { return }
                let account = AccountStorage.currentUserID; let generation = AccountStorage.generation
                do {
                    let data = try await SupabaseService.shared.client.storage.from("whisper-group-avatars").download(path: path)
                    try WhisperChatMediaService.checkAccount(account, generation: generation)
                    try Task.checkCancellation()
                    image = UIImage(data: data)
                } catch { image = nil }
            }
            .accessibilityLabel("\(group.name) group picture")
    }
}
