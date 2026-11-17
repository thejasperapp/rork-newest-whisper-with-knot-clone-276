import SwiftUI
import AVFoundation

/// Section authoring sits over the unchanged Story; only Done mutates its soundtrack.
struct WhisperStoryMusicSegmentView: View {
    let music: WhisperStoryMusic
    let onCancel: () -> Void
    let onApply: (WhisperStoryMusic) -> Void
    @State private var start: Double = 0
    @State private var length: Double = 7
    @State private var available: Double?
    @State private var errorMessage: String?
    @State private var attempt: Int = 0
    @State private var player: WhisperStoryMusicPlayer = .init()
    @State private var generation: UUID = AccountStorage.generation
    @State private var envelope: [Float] = []
    @State private var dragStart: Double?

    private var selected: WhisperStoryMusic {
        var result = music.storyPreview
        let slice = WhisperStoryMusicSelection(startSeconds: start, durationSeconds: length, availableDuration: available ?? 30)
        result.startSeconds = slice.startSeconds; result.durationSeconds = slice.durationSeconds
        result.previewDuration = available
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { player.stop(); onCancel() }.frame(minWidth: 60, minHeight: 44)
                Spacer()
                artwork.frame(width: 34, height: 34)
                Spacer()
                Button("Done") {
                    guard available != nil, generation == AccountStorage.generation else { return }
                    player.stop(); onApply(selected)
                }.fontWeight(.semibold).frame(minWidth: 60, minHeight: 44).disabled(available == nil)
            }.padding(.horizontal, 16).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
            VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(music.title).font(.title3.weight(.semibold)).lineLimit(2)
                Text(music.artist).font(.subheadline).opacity(0.75).lineLimit(2)
            }.multilineTextAlignment(.center).padding(.horizontal, 24)
            if let available {
                VStack(spacing: 12) {
                    Text("\(start, specifier: "%.1f")–\(start + length, specifier: "%.1f")s")
                        .font(.caption.monospacedDigit()).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: .capsule)
                    HStack(spacing: 16) {
                        Menu {
                            ForEach([7, 15, 20, 30], id: \.self) { seconds in
                                Button("\(seconds) seconds") {
                                    length = min(Double(seconds), available)
                                    start = min(start, max(0, available - length)); replay()
                                }
                            }
                        } label: {
                            Text("\(Int(length))").font(.subheadline.monospacedDigit())
                                .frame(width: 44, height: 44).overlay { Circle().strokeBorder(.white, lineWidth: 1) }
                        }.accessibilityLabel("Music duration, \(Int(length)) seconds")
                        Slider(value: $start, in: 0...max(0.001, available - length)) { editing in
                            player.stop(); if !editing { replay() }
                        }.accessibilityLabel("Music start time").disabled(available <= length)
                        Button {
                            if player.isPlaying { player.pause() } else { replay() }
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .frame(width: 44, height: 44).background(.white, in: .circle).foregroundStyle(.black)
                        }.accessibilityLabel(player.isPlaying ? "Pause section" : "Play section")
                    }
                    waveform(duration: available)
                    Text("Available song preview · drag to choose your section")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }.padding(20).background(.black.opacity(0.35), in: .rect(cornerRadius: 24)).padding(.bottom, 12)
            } else if let errorMessage {
                Text(errorMessage).font(.subheadline).padding(20)
                Button("Try again") { attempt += 1 }.frame(minHeight: 44)
            } else { ProgressView("Loading preview…").padding(28) }
            }.padding(.horizontal, 12).padding(.vertical, 20)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white).tint(.white).buttonStyle(.plain)
        .task(id: attempt) { await prepare() }
        .onDisappear { player.stop() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in player.stop(); onCancel() }
    }

    private var artwork: some View {
        Color.white.opacity(0.1).overlay {
            if let value = music.artworkURL, let url = URL(string: value) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill().allowsHitTesting(false) }
                    placeholder: { Image(systemName: "music.note") }
            } else { Image(systemName: "music.note") }
        }.clipShape(.rect(cornerRadius: 6))
    }

    private func waveform(duration: Double) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let count = max(1, Int(size.width / 5))
                    for index in 0..<count {
                        let sample = envelope.isEmpty ? 0 : envelope[min(envelope.count - 1, index * envelope.count / count)]
                        let height = envelope.isEmpty ? 3.0 : max(3, CGFloat(sample) * 38)
                        let rect = CGRect(x: CGFloat(index) * 5, y: (size.height - height) / 2, width: 2.5, height: height)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.25), with: .color(.white.opacity(0.85)))
                    }
                }
                RoundedRectangle(cornerRadius: 5).strokeBorder(.white, lineWidth: 3)
                    .frame(width: max(14, width * length / duration), height: 48)
                    .offset(x: width * start / duration)
            }.contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil { dragStart = start; player.stop() }
                        start = min(max(0, (dragStart ?? start) + Double(value.translation.width / max(1, width)) * duration), max(0, duration - length))
                    }
                    .onEnded { _ in dragStart = nil; replay() })
        }.frame(height: 56).accessibilityHidden(true)
    }

    private func replay() { player.stop(); player.play(selected) }
    private func prepare() async {
        errorMessage = nil
        guard let url = URL(string: music.previewURL) else { errorMessage = "This song has no playable preview."; return }
        do {
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            guard duration.isFinite, duration >= 0.5 else { throw CocoaError(.fileReadCorruptFile) }
            available = duration
            let slice = WhisperStoryMusicSelection(startSeconds: music.startSeconds, durationSeconds: music.durationSeconds ?? 7, availableDuration: duration)
            start = slice.startSeconds; length = slice.durationSeconds; replay()
            let samples = await WhisperStoryAudioEnvelope.load(url)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            envelope = samples
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            errorMessage = "Couldn't load the song preview. Check your connection and try again."
        }
    }
}
