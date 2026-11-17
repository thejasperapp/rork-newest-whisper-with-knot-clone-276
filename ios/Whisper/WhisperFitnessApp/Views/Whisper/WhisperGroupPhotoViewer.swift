import SwiftUI
import Supabase

/// Private group artwork stays in memory and is never turned into a public link.
struct WhisperGroupPhotoViewer: View {
    let group: WhisperGroup
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var error: String?
    @State private var retry: Int = 0
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .padding(24)
                    .scaleEffect(min(4, max(1, scale * magnification)))
                    .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                        .onEnded { scale = min(4, max(1, scale * $0.magnification)) })
                    .onTapGesture(count: 2) { withAnimation(.smooth(duration: 0.2)) { scale = scale > 1 ? 1 : 2 } }
                    .accessibilityLabel("\(group.name) group picture")
            } else if let error {
                VStack(spacing: 16) {
                    Text(error).multilineTextAlignment(.center)
                    Button("Try again") { retry += 1 }.frame(minHeight: 44)
                }.foregroundStyle(.white).padding(24)
            } else if group.avatarPath == nil {
                VStack(spacing: 16) {
                    WhisperGroupAvatarView(group: group, size: 180)
                    Text("No group picture yet").foregroundStyle(.white)
                }
            } else { ProgressView().tint(.white) }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text(group.name).font(.headline).lineLimit(1)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close group picture")
            }.foregroundStyle(.white).padding(.horizontal, 16).background(.black)
        }
        .accessibilityAction(.escape) { dismiss() }
        .whisperEdgeBack { dismiss() }
        .task(id: "\(group.id)|\(group.avatarPath ?? "")|\(AccountStorage.generation)|\(retry)") {
            image = nil; error = nil; scale = 1
            guard let path = group.avatarPath else { return }
            guard path.hasPrefix(group.id.uuidString.lowercased() + "/") else { error = "This picture is unavailable."; return }
            let account = AccountStorage.currentUserID; let epoch = AccountStorage.generation
            do {
                let data = try await SupabaseService.shared.client.storage.from("whisper-group-avatars").download(path: path)
                try WhisperChatMediaService.checkAccount(account, generation: epoch)
                guard let decoded = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                image = decoded
            } catch {
                guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                self.error = "Couldn't load the group picture. Check your connection and try again."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in image = nil; dismiss() }
        .onDisappear { image = nil }
    }
}
