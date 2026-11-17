import SwiftUI
import PhotosUI

/// One creation destination. Each mode retains its own editing state while
/// paging; captured media, quotes and Waves keep their dedicated flow.
struct WhisperComposerView: View {
    var initialQuotedPost: WhisperPost? = nil
    var isReelMode: Bool = false
    var initialTopic: String = ""
    var initialText: String = ""
    var initialPhotos: [Data] = []
    var initialPhotoPickerItems: [PhotosPickerItem] = []
    var onPosted: (() -> Void)? = nil

    @State private var mode = 0
    @State private var threadBusy = false
    @State private var gridBusy = false
    @State private var threadDirty = false
    @State private var gridDirty = false
    @State private var confirmExit = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var offersGrid: Bool {
        let username = WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username ?? "you"
        return WhisperAccountAccess.canPostGrid(username: username)
            && !isReelMode && initialQuotedPost == nil && initialTopic.isEmpty
            && initialPhotos.isEmpty && initialPhotoPickerItems.isEmpty
    }
    private var busy: Bool { threadBusy || gridBusy }
    private var selection: Binding<Int> {
        Binding(get: { mode }, set: { value in
            guard !busy else { return }
            mode = value
        })
    }

    var body: some View {
        Group {
            if offersGrid {
                TabView(selection: selection) {
                    thread.tag(0)
                    WhisperGridComposerView(embedded: true, isActive: mode == 1,
                        onBusyChanged: { gridBusy = $0 }, onPosted: onPosted,
                        onCancel: requestClose, onDirtyChanged: { gridDirty = $0 })
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .safeAreaInset(edge: .bottom, spacing: 0) { modeSelector }
                .interactiveDismissDisabled(busy || threadDirty || gridDirty)
                .confirmationDialog("Discard post edits?", isPresented: $confirmExit, titleVisibility: .visible) {
                    Button("Discard edits", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) { }
                } message: { Text("This closes both post types. Any unpublished thread and grid edits will be discarded.") }
            } else {
                thread
            }
        }
    }

    private var thread: some View {
        WhisperThreadComposerView(
            initialQuotedPost: initialQuotedPost, isReelMode: isReelMode,
            initialTopic: initialTopic, initialText: initialText,
            initialPhotos: initialPhotos, initialPhotoPickerItems: initialPhotoPickerItems,
            onPosted: onPosted, isActive: mode == 0, onBusyChanged: { threadBusy = $0 },
            onCancel: cancelAction, onDirtyChanged: { threadDirty = $0 }
        )
    }

    private var cancelAction: (() -> Void)? {
        guard offersGrid else { return nil }
        return { requestClose() }
    }

    private func requestClose() {
        guard !busy else { return }
        if threadDirty || gridDirty { confirmExit = true }
        else { dismiss() }
    }

    private var modeSelector: some View {
        VStack(spacing: 2) {
            HStack(spacing: 28) {
                modeButton("Thread", index: 0)
                modeButton("Grid post", index: 1)
            }
            Text(busy ? "Finish the current operation before changing modes" : "Swipe to change post type")
                .font(.caption2).foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func modeButton(_ title: String, index: Int) -> some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selection.wrappedValue = index }
        } label: {
            VStack(spacing: 4) {
                Text(title).font(.subheadline.weight(mode == index ? .semibold : .regular))
                Capsule().fill(mode == index ? WhisperTheme.ink(colorScheme) : .clear).frame(height: 2)
            }
            .frame(minWidth: 80, minHeight: 44)
            .foregroundStyle(mode == index ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
            .contentShape(.rect)
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityAddTraits(mode == index ? .isSelected : [])
    }
}
