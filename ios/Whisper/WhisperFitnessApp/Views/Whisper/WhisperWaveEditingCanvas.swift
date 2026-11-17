import SwiftUI
import AVFoundation

/// A fixed 9:16 canvas; video framing and text placement use normalized export coordinates.
struct WhisperWaveEditingCanvas: View {
    let model: WhisperWavePreviewModel
    @Binding var clips: [WhisperWaveClip]
    let selectedID: UUID?
    @Binding var texts: [WaveTextOverlay]
    @Binding var selectedTextID: UUID?
    @Binding var editingTextID: UUID?
    let isEditingText: Bool
    let allowsFraming: Bool
    let onSelectText: () -> Void
    let onAddText: () -> Void
    /// Shows the "tap to type" pill on the footage until the first layer exists.
    var showsTypeHint: Bool = false
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var translation: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, min(geometry.size.width, geometry.size.height * 9 / 16))
            let stage = CGSize(width: width, height: width * 16 / 9)
            ZStack {
                Color.black
                WaveTimelinePlayerView(player: model.player)
                    .scaleEffect(magnification)
                    .offset(translation)
                    .allowsHitTesting(false)
                if allowsFraming {
                    canvasButton
                        .highPriorityGesture(framingDrag(stage))
                        .simultaneousGesture(framingZoom)
                } else {
                    canvasButton
                }
                ForEach($texts) { $layer in
                    if isEditingText || (model.time >= layer.start && (layer.end <= 0 || model.time < layer.end)) {
                        // Keep the gesture-owning view mounted when selection
                        // changes. Replacing it with a field used to kill drags.
                        WaveDraggableText(layer: $layer, stage: stage,
                            isSelected: selectedTextID == layer.id,
                            isTyping: isEditingText && editingTextID == layer.id && !layer.isSticker,
                            onSelect: {
                                model.pause()
                                selectedTextID = layer.id
                                editingTextID = layer.isSticker ? nil : layer.id
                                onSelectText()
                            }, onMove: {
                                model.pause()
                                selectedTextID = layer.id
                            }, onMoveEnded: {
                                editingTextID = nil
                            })
                    }
                }
            }
            .frame(width: stage.width, height: stage.height)
            .coordinateSpace(name: "waveCanvas")
            .overlay(alignment: .bottom) {
                if showsTypeHint {
                    Text("Tap the video to type")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 14)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: 26, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false) }
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var canvasButton: some View {
        Button(action: onAddText) { Color.clear.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(editingTextID == nil ? "Tap video to add text" : "Finish typing")
            .accessibilityIdentifier("wave.textCanvas")
    }

    private var framingZoom: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onChanged { _ in model.pause() }
            .onEnded { value in
                guard let index = clips.firstIndex(where: { $0.id == selectedID }) else { return }
                clips[index].zoom = min(4, max(1, clips[index].zoom * value.magnification))
            }
    }

    private func framingDrag(_ stage: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .updating($translation) { value, state, _ in state = value.translation }
            .onChanged { _ in model.pause() }
            .onEnded { value in
                guard let index = clips.firstIndex(where: { $0.id == selectedID }) else { return }
                clips[index].offsetX = min(2, max(-2, clips[index].offsetX + value.translation.width / stage.width))
                clips[index].offsetY = min(2, max(-2, clips[index].offsetY + value.translation.height / stage.height))
            }
    }
}

struct WaveTimelinePlayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> WaveClipPlayerLayerView {
        let view = WaveClipPlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: WaveClipPlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
    static func dismantleUIView(_ view: WaveClipPlayerLayerView, coordinator: ()) { view.playerLayer.player = nil }
}

private struct WaveDraggableText: View {
    @Binding var layer: WaveTextOverlay
    let stage: CGSize
    let isSelected: Bool
    let isTyping: Bool
    let onSelect: () -> Void
    let onMove: () -> Void
    let onMoveEnded: () -> Void
    @State private var origin: CGPoint?
    @State private var scaleOrigin: Double?

    var body: some View {
        let size = WhisperWaveStudio.textLayerGroup(layer, renderSize: stage).bounds.size
        ZStack {
            if isTyping {
                WaveInlineTextField(layer: $layer, stage: stage)
            } else {
                Button(action: onSelect) {
                    WaveTextArtwork(layer: layer, stage: stage)
                        .frame(width: max(44, size.width), height: max(44, size.height))
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.white : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .highPriorityGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("waveCanvas"))
            .onChanged { value in
                if origin == nil { origin = CGPoint(x: layer.x, y: layer.y); onMove() }
                guard let origin else { return }
                let marginX = min(0.5, size.width / stage.width / 2)
                let marginY = min(0.5, size.height / stage.height / 2)
                layer.x = min(1 - marginX, max(marginX, origin.x + value.translation.width / stage.width))
                layer.y = min(1 - marginY, max(marginY, origin.y + value.translation.height / stage.height))
            }
            .onEnded { _ in origin = nil; onMoveEnded(); Haptics.selection() })
        .simultaneousGesture(MagnifyGesture().onChanged { value in
            if scaleOrigin == nil { scaleOrigin = layer.scale; onMove() }
            layer.scale = min(2.6, max(0.7, (scaleOrigin ?? 1) * value.magnification))
        }.onEnded { _ in scaleOrigin = nil; onMoveEnded() })
        .position(x: stage.width * layer.x, y: stage.height * layer.y)
        .accessibilityLabel(layer.text.isEmpty ? "Edit text layer" : "Edit text: \(layer.text)")
        .accessibilityHint("Drag to position the text on the video")
        .accessibilityAction(named: "Center text") { layer.x = 0.5; layer.y = 0.5 }
        .accessibilityAction(named: "Move text up") { layer.y = max(0.08, layer.y - 0.05) }
        .accessibilityAction(named: "Move text down") { layer.y = min(0.92, layer.y + 0.05) }
    }
}

/// Typing happens directly on the video, Stories-style; the keyboard appears only for the selected layer.
private struct WaveInlineTextField: View {
    @Binding var layer: WaveTextOverlay
    let stage: CGSize
    @FocusState private var focused: Bool

    var body: some View {
        let scale = stage.width / 1080
        TextField("Type here", text: $layer.text, axis: .vertical)
            .focused($focused)
            .font(Font(layer.font.uiFont(size: max(14, 64 * scale * layer.scale))))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(uiColor: layer.uiTextColor))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(layer.style == 2 ? Color.white.opacity(0.9) : Color.black.opacity(layer.style == 1 ? 0.6 : 0.18), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            .frame(width: min(stage.width * 0.86, max(100, WhisperWaveStudio.textLayerGroup(layer, renderSize: stage).bounds.width + 20)))
            .lineLimit(1...6)
            .fixedSize(horizontal: false, vertical: true)
            .tint(.white)
            .task { focused = true }
            .onDisappear { focused = false }
            .accessibilityLabel("Text on video")
            .accessibilityIdentifier("wave.inlineText")
    }
}

private struct WaveTextArtwork: UIViewRepresentable {
    let layer: WaveTextOverlay
    let stage: CGSize
    func makeUIView(context: Context) -> UIView { let view = UIView(); view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ view: UIView, context: Context) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        view.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let group = WhisperWaveStudio.textLayerGroup(layer, renderSize: stage)
        group.position = CGPoint(x: max(44, group.bounds.width) / 2, y: max(44, group.bounds.height) / 2)
        view.layer.addSublayer(group)
        CATransaction.commit()
    }
}
