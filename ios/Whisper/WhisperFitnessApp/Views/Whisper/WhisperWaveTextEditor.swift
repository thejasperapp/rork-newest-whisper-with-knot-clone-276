import SwiftUI

/// The wave TEXT tool — Instagram's Aa done Whisper's way: several layers,
/// each with a font (Classic · Modern · Neon · Typewriter · Strong), a color,
/// a plate (none · black · white), a size, an entrance animation (Pop · Fade
/// · Rise · Type), a timing window, and a position — plus one-tap emoji
/// STICKERS. Everything here bakes onto the video at publish.
struct WaveTextEditorSheet: View {
    @Binding var overlays: [WaveTextOverlay]
    let duration: Double
    let onDone: () -> Void
    var embedded: Bool = false
    var showsInput: Bool = true
    /// Adds a first layer on appear. The dial editor turns this off so
    /// spinning past Text never adds a layer or raises the keyboard.
    var autoAddsFirstLayer: Bool = true
    /// Beat times (output clock) the timing sliders snap to; empty = free.
    var snapTimes: [Double] = []
    var onEditText: ((UUID) -> Void)?

    init(overlays: Binding<[WaveTextOverlay]>, duration: Double, selectedID: Binding<UUID?>, embedded: Bool = false, showsInput: Bool = true, autoAddsFirstLayer: Bool = true, snapTimes: [Double] = [], onEditText: ((UUID) -> Void)? = nil, onDone: @escaping () -> Void) {
        self._overlays = overlays
        self.duration = duration
        self._selectedID = selectedID
        self.embedded = embedded
        self.showsInput = showsInput
        self.autoAddsFirstLayer = autoAddsFirstLayer
        self.snapTimes = snapTimes
        self.onEditText = onEditText
        self.onDone = onDone
    }

    /// Pulls a slider value onto the nearest beat when snapping is on.
    private func snapped(_ value: Double) -> Double {
        guard !snapTimes.isEmpty else { return value }
        return WhisperWaveBeatGrid.nearest(in: snapTimes, to: value, within: 0.12) ?? value
    }

    @Binding var selectedID: UUID?
    @FocusState private var textFocused: Bool

    private let accent: Color = WhisperBrandGradient.accent
    private let stickers: [String] = ["🔥", "😂", "❤️", "👻", "💪", "✨", "🎉", "😍", "👀", "💯", "🙌", "🤣", "😤", "🥶", "🫶", "⚡️"]

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return overlays.firstIndex { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { header } else {
                HStack {
                    Text("Text")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    if let idx = selectedIndex {
                        Button("Delete layer", role: .destructive) { Haptics.tap(); remove(at: idx) }.frame(minHeight: 32)
                    }
                    Button("Done") { textFocused = false; onDone() }.frame(minHeight: 32)
                }.font(.caption.weight(.semibold)).padding(.bottom, 6)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    layersStrip
                    if let idx = selectedIndex, overlays.indices.contains(idx) {
                        editor(for: $overlays[idx])
                    } else {
                        emptyHint
                    }
                }
                .padding(.horizontal, embedded ? 0 : 18)
                .padding(.bottom, 24)
            }
            if !embedded { doneBar }
        }
        .background { if !embedded { Color.black.ignoresSafeArea() } }
        .preferredColorScheme(.dark)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            overlays.removeAll { $0.text.isEmpty && !$0.isSticker && $0.id != selectedID }
            if overlays.isEmpty, autoAddsFirstLayer { addText() }
            if selectedID == nil, autoAddsFirstLayer { selectedID = overlays.first?.id }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Text & stickers")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if let idx = selectedIndex {
                Button {
                    Haptics.tap()
                    remove(at: idx)
                } label: {
                    Label("Delete layer", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Layers strip

    private var layersStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAYERS")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(overlays) { layer in
                        Button {
                            Haptics.tap()
                            selectedID = layer.id
                            if !layer.isSticker { onEditText?(layer.id) }
                        } label: {
                            Text(layer.text.isEmpty ? "Text" : String(layer.text.prefix(14)))
                                .font(layer.isSticker ? .system(size: 18) : .system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(selectedID == layer.id ? 0.18 : 0.08), in: Capsule())
                                .overlay { Capsule().strokeBorder(selectedID == layer.id ? accent : .clear, lineWidth: 1.5) }
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        Haptics.tap()
                        addText()
                    } label: {
                        Label("Text", systemImage: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            stickerRow
        }
    }

    /// One-tap emoji stickers — each becomes its own big, plate-less layer.
    private var stickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(stickers, id: \.self) { emoji in
                    Button {
                        Haptics.tap()
                        var s = WaveTextOverlay.sticker(emoji)
                        s.y = 0.32
                        s.x = [0.3, 0.5, 0.7][overlays.count % 3]
                        overlays.append(s)
                        selectedID = s.id
                    } label: {
                        Text(emoji)
                            .font(.system(size: 22))
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(emoji) sticker")
                }
            }
        }
    }

    private var emptyHint: some View {
        Text(overlays.isEmpty
             ? "Tap the video to type, add a text layer, or tap an emoji to place a sticker."
             : "Tap a layer above to style it, or tap the video to add another.")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.top, embedded ? 4 : 12)
    }

    // MARK: - Editor

    @ViewBuilder
    private func editor(for layer: Binding<WaveTextOverlay>) -> some View {
        if !layer.wrappedValue.isSticker {
            if showsInput {
            TextField("Say something on the video…", text: layer.text, axis: .vertical)
                .lineLimit(2...4)
                .font(layer.wrappedValue.font.swiftUIFont(size: 20))
                .foregroundStyle(WaveTextPalette.color(layer.wrappedValue.colorHex))
                .tint(.white)
                .focused($textFocused)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }

            fontRow(layer)
            colorRow(layer)
            plateRow(layer)
        }
        animationRow(layer)
        sizeRow(layer)
        Text("Drag the text on your video to place it. Tap a layer to edit it.")
            .font(.caption).foregroundStyle(.white.opacity(0.6))
        timingRow(layer)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.6))
    }

    private func fontRow(_ layer: Binding<WaveTextOverlay>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FONT")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WaveTextFont.allCases) { font in
                        Button {
                            Haptics.tap()
                            layer.wrappedValue.font = font
                        } label: {
                            VStack(spacing: 4) {
                                Text(font.uppercase ? "AA" : "Aa")
                                    .font(font.swiftUIFont(size: 18))
                                    .foregroundStyle(.white)
                                    .shadow(color: font.glows ? .white.opacity(0.9) : .clear, radius: 6)
                                Text(font.label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .frame(width: 74, height: 56)
                            .background(Color.white.opacity(layer.wrappedValue.font == font ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(layer.wrappedValue.font == font ? accent : .clear, lineWidth: 1.5) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func colorRow(_ layer: Binding<WaveTextOverlay>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("COLOR")
            HStack(spacing: 10) {
                ForEach(WaveTextPalette.hexes, id: \.self) { hex in
                    Button {
                        Haptics.tap()
                        layer.wrappedValue.colorHex = hex
                    } label: {
                        Circle()
                            .fill(WaveTextPalette.color(hex))
                            .frame(width: 30, height: 30)
                            .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                            .overlay {
                                Circle().strokeBorder(.white, lineWidth: layer.wrappedValue.colorHex == hex ? 3 : 0)
                            }
                            .scaleEffect(layer.wrappedValue.colorHex == hex ? 1.12 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func plateRow(_ layer: Binding<WaveTextOverlay>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("BACKGROUND")
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { style in
                    Button {
                        Haptics.tap()
                        layer.wrappedValue.style = style
                    } label: {
                        Text(style == 0 ? "None" : (style == 1 ? "Black" : "White"))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(style == 2 ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                style == 1 ? AnyShapeStyle(Color.black.opacity(0.85)) : (style == 2 ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.12))),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(layer.wrappedValue.style == style ? accent : .clear, lineWidth: 2) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func animationRow(_ layer: Binding<WaveTextOverlay>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ANIMATION")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WaveTextAnimation.allCases) { anim in
                        Button {
                            Haptics.tap()
                            layer.wrappedValue.animation = anim
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: anim.icon)
                                    .font(.system(size: 12, weight: .bold))
                                Text(anim.label)
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(layer.wrappedValue.animation == anim ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(layer.wrappedValue.animation == anim ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sizeRow(_ layer: Binding<WaveTextOverlay>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("SIZE")
                Spacer()
                Text(String(format: "%.1f×", layer.wrappedValue.scale))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Slider(value: layer.scale, in: 0.7...2.6, step: 0.1)
                .tint(accent)
        }
    }

    private func positionRow(_ layer: Binding<WaveTextOverlay>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("POSITION")
            Picker("Position", selection: Binding(
                get: { layer.wrappedValue.y < 0.4 ? 0 : (layer.wrappedValue.y > 0.6 ? 2 : 1) },
                set: { layer.wrappedValue.y = $0 == 0 ? 0.2 : ($0 == 2 ? 0.78 : 0.5) }
            )) {
                Text("Top").tag(0)
                Text("Middle").tag(1)
                Text("Bottom").tag(2)
            }
            .pickerStyle(.segmented)
        }
    }

    private func timingRow(_ layer: Binding<WaveTextOverlay>) -> some View {
        let total = max(1.0, duration)
        let start = layer.wrappedValue.start
        let end = layer.wrappedValue.end > 0 ? layer.wrappedValue.end : total
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("TIMING")
                Spacer()
                Text(layer.wrappedValue.start <= 0.05 && layer.wrappedValue.end <= 0
                     ? "Whole wave"
                     : "\(Self.seconds(start)) → \(Self.seconds(end))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text("From")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { min(layer.wrappedValue.start, max(0, total - 0.5)) },
                            set: { raw in
                                let v = min(snapped(raw), max(0, total - 0.5))
                                layer.wrappedValue.start = v
                                if layer.wrappedValue.end > 0, layer.wrappedValue.end < v + 0.5 {
                                    layer.wrappedValue.end = min(total, v + 0.5)
                                }
                            }
                        ),
                        in: 0...max(0.5, total - 0.5)
                    )
                    .tint(accent)
                }
                HStack(spacing: 10) {
                    Text("Until")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { layer.wrappedValue.end > 0 ? layer.wrappedValue.end : total },
                            set: { raw in
                                let v = snapped(raw)
                                layer.wrappedValue.end = v >= total - 0.05 ? 0 : max(v, layer.wrappedValue.start + 0.5)
                            }
                        ),
                        in: 0.5...total
                    )
                    .tint(accent)
                }
            }
        }
    }

    // MARK: - Done bar

    private var doneBar: some View {
        Button {
            Haptics.tap()
            overlays.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            onDone()
        } label: {
            Text("Done")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.9))
    }

    // MARK: - Mutations

    private func addText() {
        var layer = WaveTextOverlay()
        layer.y = [0.5, 0.2, 0.78][overlays.count % 3]
        overlays.append(layer)
        selectedID = layer.id
        if showsInput { textFocused = true }
        onEditText?(layer.id)
    }

    private func remove(at idx: Int) {
        guard overlays.indices.contains(idx) else { return }
        overlays.remove(at: idx)
        selectedID = overlays.first?.id
    }

    private static func seconds(_ s: Double) -> String {
        String(format: "%.1fs", s)
    }
}

/// The scaled-down rendering of one text layer on the composer's cover card
/// — the same font, color, plate, and position the bake uses, at stage size.
struct WaveTextLayerPreview: View {
    let layer: WaveTextOverlay
    let stage: CGSize

    var body: some View {
        let base = stage.width * (layer.isSticker ? 0.11 : 0.058)
        let size = base * CGFloat(max(0.5, min(3.0, layer.scale)))
        let color = Color(uiColor: layer.uiTextColor)
        Text(layer.displayText)
            .font(layer.font.swiftUIFont(size: size))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: layer.style == 0 && !layer.isSticker ? (layer.font.glows ? color.opacity(0.9) : .black.opacity(0.5)) : .clear, radius: layer.font.glows ? size * 0.3 : size * 0.12)
            .padding(.horizontal, layer.style == 0 ? 0 : size * 0.55)
            .padding(.vertical, layer.style == 0 ? 0 : size * 0.35)
            .background(
                layer.style == 1 ? Color.black.opacity(0.72) : (layer.style == 2 ? Color.white.opacity(0.94) : Color.clear),
                in: RoundedRectangle(cornerRadius: size * 0.45)
            )
            .frame(maxWidth: stage.width * 0.84)
            .position(x: stage.width * layer.x, y: stage.height * layer.y)
    }
}
