import SwiftUI

/// The Clips tool: thumbnails in order (drag to reorder), a transition dot
/// between neighbours (tap to cycle Cut → Fade → Dip), "+" to add more from
/// the library, and split / duplicate / delete for the selected clip.
struct WhisperWaveClipStripPanel: View {
    @Binding var clips: [WhisperWaveClip]
    let selectedID: UUID?
    let thumbs: [UUID: UIImage]
    let maxClips: Int
    let onSelect: (WhisperWaveClip) -> Void
    let onAdd: () -> Void
    let onSplit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var draggingID: UUID?

    private static let tile = CGSize(width: 58, height: 92)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            strip
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Clips")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(clips.count) of \(maxClips) · drag to reorder")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            WhisperWavePanelIconButton(systemImage: "scissors", label: "Split at playhead", action: onSplit)
            WhisperWavePanelIconButton(systemImage: "plus.square.on.square", label: "Duplicate clip", action: onDuplicate)
            WhisperWavePanelIconButton(systemImage: "trash", label: "Delete clip", role: clips.count > 1 ? .destructive : nil, action: onDelete)
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    clipTile(clip)
                    if index < clips.count - 1 {
                        transitionDot(for: clip)
                    }
                }
                if clips.count < maxClips {
                    addTile
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: Self.tile.height + 4)
    }

    private func clipTile(_ clip: WhisperWaveClip) -> some View {
        let isSelected = clip.id == selectedID
        return Button {
            Haptics.tap()
            onSelect(clip)
        } label: {
            tileArtwork(clip, isSelected: isSelected)
                .scaleEffect(draggingID == clip.id ? 1.06 : 1)
                .opacity(draggingID == clip.id ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .draggable(clip.id.uuidString) {
            Color.clear.frame(width: Self.tile.width, height: Self.tile.height)
                .overlay {
                    if let thumb = thumbs[clip.id] {
                        Image(uiImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onAppear { draggingID = clip.id }
                .onDisappear { draggingID = nil }
        }
        .dropDestination(for: String.self) { items, _ in
            move(items.first, before: clip)
        }
        .accessibilityLabel("Clip \(WhisperWaveClipsEditor.clock(clip.effectiveSeconds))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func tileArtwork(_ clip: WhisperWaveClip, isSelected: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.08)
                .frame(width: Self.tile.width, height: Self.tile.height)
                .overlay {
                    if let thumb = thumbs[clip.id] {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(width: Self.tile.width, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                if clip.speed != 1 {
                    Text(WhisperWaveClipsEditor.speedLabel(clip.speed))
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                }
                Text(WhisperWaveClipsEditor.clock(clip.effectiveSeconds))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(6)
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.12), lineWidth: isSelected ? 2.5 : 0.75)
        }
    }

    private func transitionDot(for clip: WhisperWaveClip) -> some View {
        Button {
            Haptics.selection()
            guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
            clips[index].transitionAfter = clips[index].transitionAfter.next
        } label: {
            VStack(spacing: 3) {
                Image(systemName: clip.transitionAfter.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(clip.transitionAfter == .cut ? .white.opacity(0.55) : .white)
                    .frame(width: 26, height: 26)
                    .background(clip.transitionAfter == .cut ? Color.white.opacity(0.08) : Color.white.opacity(0.22), in: Circle())
                Text(clip.transitionAfter.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Transition: \(clip.transitionAfter.label)")
    }

    private var addTile: some View {
        Button {
            Haptics.tap()
            onAdd()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                Text("Add")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: Self.tile.width, height: Self.tile.height)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .buttonStyle(WhisperMenuPressStyle())
        .accessibilityLabel("Add clips")
    }

    /// Reorders a dragged clip in front of `target`.
    private func move(_ raw: String?, before target: WhisperWaveClip) -> Bool {
        guard let raw, let fromID = UUID(uuidString: raw),
              let from = clips.firstIndex(where: { $0.id == fromID }),
              let to = clips.firstIndex(where: { $0.id == target.id }),
              from != to else { return false }
        Haptics.rigid()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            let moved = clips.remove(at: from)
            clips.insert(moved, at: to)
        }
        draggingID = nil
        return true
    }
}
