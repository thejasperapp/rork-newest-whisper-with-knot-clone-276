import SwiftUI

/// The Captions tool: one tap listens to every clip on this iPhone and writes
/// word-timed captions; then five looks, six spoken-word colors, and Size and
/// Height rulers that move the block live on the footage. Words open in a
/// sheet for fixing a typo or dropping a phrase. Nothing is uploaded.
struct WhisperWaveCaptionsPanel: View {
    @Binding var captions: WhisperWaveCaptions?
    let generator: WhisperWaveCaptionGenerator
    let hasClips: Bool
    let onGenerate: () -> Void
    let onEditWords: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if generator.isRunning {
                progressRow
            } else if captions != nil {
                styleRow
                highlightRow
                dials
            } else if let error = generator.error {
                errorState(error)
            } else {
                emptyState
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Header

    /// A failed re-run keeps the existing captions and reports in the subtitle.
    private var showsInlineError: Bool { !generator.isRunning && captions != nil && generator.error != nil }

    private var subtitle: String {
        if generator.isRunning { return generator.stage }
        if showsInlineError, let error = generator.error { return error }
        if let captions {
            let count = captions.words.count
            return "\(count) word\(count == 1 ? "" : "s") · \(Self.languageName(captions.language))"
        }
        return "Word by word · recognized on this iPhone"
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Captions")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(showsInlineError ? WhisperBrandGradient.amber : Color.white.opacity(0.5))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            if generator.isRunning {
                WhisperWavePanelChip(title: "Cancel", systemImage: "xmark", selected: false) {
                    generator.cancel()
                }
                .accessibilityLabel("Cancel captioning")
            } else if captions != nil {
                WhisperWavePanelChip(title: "Edit words", systemImage: "text.cursor", selected: false) {
                    onEditWords()
                }
                WhisperWavePanelIconButton(systemImage: "arrow.clockwise", label: "Caption again") {
                    onGenerate()
                }
                WhisperWavePanelIconButton(systemImage: "xmark", label: "Remove captions", role: .destructive) {
                    withAnimation(.snappy(duration: 0.25)) { captions = nil }
                }
            }
        }
        .frame(height: 40)
    }

    // MARK: States

    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: min(1, max(0, generator.progress)))
                .tint(WhisperBrandGradient.accent)
            HStack(spacing: 8) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Listening on this iPhone · nothing is uploaded")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Whisper listens to your clips right here on your iPhone and writes captions that pop word by word with the speech. Nothing is uploaded.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                WhisperWavePanelChip(title: "Generate captions", systemImage: "waveform.and.mic", selected: true) {
                    onGenerate()
                }
                .disabled(!hasClips)
                .opacity(hasClips ? 1 : 0.5)
                Text("Recognizes \(generator.languageName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }

    private func errorState(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(WhisperBrandGradient.amber)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                WhisperWavePanelChip(title: "Try again", systemImage: "arrow.clockwise", selected: true) {
                    onGenerate()
                }
                .disabled(!hasClips)
                if generator.isDenied {
                    WhisperWavePanelChip(title: "Open Settings", systemImage: "gear", selected: false) {
                        generator.openSettings()
                    }
                }
            }
        }
    }

    // MARK: Look

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WhisperWaveCaptionStyle.allCases) { style in
                    WhisperWavePanelChip(title: style.title, systemImage: style.systemImage, selected: captions?.style == style) {
                        captions?.style = style
                    }
                    .accessibilityLabel("\(style.title) caption look")
                }
            }
        }
        .frame(height: 28)
    }

    private var highlightRow: some View {
        let usesHighlight = captions?.style.highlightsWords ?? false
        return HStack(spacing: 8) {
            Text(usesHighlight ? "Spoken word" : "Classic has no spoken-word color")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            if usesHighlight {
                ForEach(WhisperWaveCaptions.highlightHexes, id: \.self) { hex in
                    swatch(hex)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
    }

    private func swatch(_ hex: String) -> some View {
        let selected = (captions?.highlightHex ?? "").uppercased() == hex.uppercased()
        return Button {
            Haptics.selection()
            captions?.highlightHex = hex
        } label: {
            Circle()
                .fill(WaveTextPalette.color(hex))
                .frame(width: 22, height: 22)
                .overlay {
                    Circle().strokeBorder(selected ? Color.white : Color.white.opacity(0.18), lineWidth: selected ? 2.5 : 1)
                }
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spoken word color \(hex)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Size + height

    private var dials: some View {
        HStack(spacing: 14) {
            WhisperWaveRuler(
                value: Binding(get: { captions?.clampedScale ?? 1 }, set: { captions?.scale = $0 }),
                range: 0.7...1.6, defaultValue: 1, tick: 0.05, detents: [1], pointsPerUnit: 220,
                label: "Size", format: { String(format: "%.0f%%", $0 * 100) }
            )
            // Height is measured up from the bottom edge so dragging left lifts the block.
            WhisperWaveRuler(
                value: Binding(get: { 1 - (captions?.clampedY ?? 0.74) }, set: { captions?.y = 1 - $0 }),
                range: 0.08...0.9, defaultValue: 0.26, tick: 0.02, detents: [0.26, 0.5], pointsPerUnit: 300,
                label: "Height", format: { String(format: "%.0f", $0 * 100) }
            )
        }
        .frame(height: 44)
    }

    private static func languageName(_ tag: String) -> String {
        Locale.current.localizedString(forIdentifier: tag) ?? tag
    }
}
