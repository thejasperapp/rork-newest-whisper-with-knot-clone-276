import SwiftUI

/// Native, source-anchored popover shared by conversation composers.
struct WhisperChatAttachmentButton: View {
    @Binding var isPresented: Bool
    let items: [WhisperChatAttachItem]
    let onOpen: () -> Void
    @State private var pending: (() -> Void)?
    @State private var generation: UUID = AccountStorage.generation

    var body: some View {
        WhisperChatPlusButton(isOpen: isPresented) {
            guard pending == nil else { return }
            onOpen(); generation = AccountStorage.generation; isPresented.toggle()
        }
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            WhisperChatAttachmentMenu(items: items) { action in
                pending = action; isPresented = false
            }.presentationCompactAdaptation(.popover)
        }
        .task(id: isPresented) {
            guard !isPresented, let action = pending else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled, generation == AccountStorage.generation else { pending = nil; return }
            pending = nil
            action()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in pending = nil; isPresented = false }
    }
}
