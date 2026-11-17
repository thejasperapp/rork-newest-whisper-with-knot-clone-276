import SwiftUI

struct RecordingTranscriptTimelineView: View {
    let passages: [WhisperRecordingArchive.Passage]
    let position: Double
    let onSeek: (Double) -> Void
    var onAsk: (([WhisperRecordingArchive.Passage]) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var followsPlayback: Bool = true
    @State private var isOpen: Bool = true
    private var activeID: String? { passages.first { position >= $0.start && position < $0.end }?.id }
    private var canAskAll: Bool { !passages.isEmpty && passages.reduce(0, { $0 + ($1.text.utf16.count + 1099) / 1100 }) <= 160 && passages.reduce(0) { $0 + $1.text.utf16.count } <= 24000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { isOpen.toggle() } label: { Label("Recording transcript", systemImage: "waveform").font(.caption.weight(.semibold)).frame(minHeight: 44) }.buttonStyle(.plain)
                Spacer(minLength: 4)
                Button(followsPlayback ? "Following" : "Follow playback") { followsPlayback.toggle() }.font(.caption2).frame(minHeight: 44).accessibilityValue(followsPlayback ? "On" : "Off")
            }
            if isOpen {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(passages) { passage in
                                VStack(alignment: .leading, spacing: 0) {
                                    Button { onSeek(passage.start) } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(WhisperRecordingArchive.time(passage.start)).monospacedDigit().font(.caption.weight(.semibold))
                                                if passage.timing == "chunk" { Text("Approx.").font(.caption2) }
                                            }.foregroundStyle(WhisperBrandGradient.rose).frame(width: 46, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 4) {
                                                if let speaker = passage.speakerName { Text(speaker).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                                                Text(passage.text).font(.subheadline)
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                        }.frame(minHeight: 44).padding(10).background(activeID == passage.id ? WhisperBrandGradient.rose.opacity(0.10) : Color.clear, in: .rect(cornerRadius: 12))
                                    }.buttonStyle(.plain)
                                    if !canAskAll, let onAsk { Button("Ask about this passage") { onAsk([passage]) }.font(.caption).frame(minHeight: 44).padding(.leading, 56) }
                                }.id(passage.id)
                            }
                            if passages.isEmpty { Text("No timed transcript yet. Your recording is still available.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 16) }
                        }.padding(.horizontal, 2)
                    }.frame(maxHeight: 240)
                        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in followsPlayback = false })
                        .onChange(of: activeID) { _, id in
                            guard followsPlayback, let id else { return }
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { reader.scrollTo(id, anchor: .center) }
                        }
                        .onChange(of: followsPlayback) { _, follows in if follows, let activeID { reader.scrollTo(activeID, anchor: .center) } }
                }
                Divider()
                Text("Private · Times from recording start").font(.caption2).foregroundStyle(.secondary)
                if canAskAll, let onAsk { Button { onAsk(passages) } label: { Label("Ask Jasper about this recording", systemImage: "bubble.left").font(.caption).frame(minHeight: 44) } }
            }
        }.padding(12).background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 18))
    }
}
