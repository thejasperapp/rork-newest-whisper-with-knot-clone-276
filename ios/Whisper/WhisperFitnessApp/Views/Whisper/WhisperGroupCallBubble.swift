import SwiftUI

/// Group calls are not meeting invitations, including while the room is loading.
struct WhisperGroupCallBubble: View {
    let roomID: String
    let group: WhisperGroup
    let mode: WhisperCallSignal.Mode
    let mine: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var joining: Bool = false
    @State private var issue: String?
    @State private var joinTask: Task<Void, Never>?

    var body: some View {
        Button {
            guard !joining else { return }
            joining = true; issue = nil; Haptics.tap()
            let generation = AccountStorage.generation
            joinTask = Task { @MainActor in
                defer { joining = false }
                guard let room = await WhisperMeetingService.shared.fetch(id: roomID) else {
                    if !Task.isCancelled, generation == AccountStorage.generation { issue = "Couldn't load call · Try again" }
                    return
                }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                guard !room.isEnded else { issue = "This call has ended"; return }
                WhisperCallService.shared.joinGroupCall(room: room, groupHint: group, modeHint: mode)
                issue = WhisperCallService.shared.lastErrorMessage
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.green.opacity(0.18)).frame(width: 44, height: 44)
                    if joining { ProgressView() }
                    else { Image(systemName: mode == .audio ? "phone.fill" : "video.fill").foregroundStyle(.green) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Group \(mode == .audio ? "audio" : "video") call").font(.subheadline.weight(.semibold))
                    Text(issue ?? (joining ? "Joining call…" : "Join call")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
            }
            .padding(14).frame(width: 260, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.green.opacity(0.25)) }
        }
        .buttonStyle(.plain).disabled(joining)
        .accessibilityIdentifier("group.call.join")
        .onDisappear { joinTask?.cancel() }
    }
}
