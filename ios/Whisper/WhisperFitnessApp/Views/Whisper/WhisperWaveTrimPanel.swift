import SwiftUI

/// The Trim tool: the clip's frame strip with two handles — the kept window
/// lit, the offcuts dimmed. Dragging a handle scrubs the trim; a minimum
/// `minKept` seconds always survives.
struct WhisperWaveTrimPanel: View {
    let clip: WhisperWaveClip
    let frames: [UIImage]
    let ordinal: Int
    let count: Int
    let minKept: Double
    /// Beat snapping: given the handle (leading?) and the proposed source
    /// time, returns the time to use. nil leaves handles free.
    var snap: ((_ leading: Bool, _ time: Double) -> Double)? = nil
    let onTrim: (_ start: Double, _ end: Double) -> Void
    @State private var lastSnapTarget: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            strip
                .frame(height: 64)
                .padding(.horizontal, 8)
            Text(snap == nil ? "Drag the handles · the selected clip loops in the preview" : "Handles snap to the beat · the selected clip loops in the preview")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Trim")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Clip \(ordinal) of \(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text("Keeping \(WhisperWaveClipsEditor.clock(clip.keptSeconds)) of \(WhisperWaveClipsEditor.clock(clip.duration))")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var strip: some View {
        GeometryReader { geo in
            let w: CGFloat = max(geo.size.width, 1)
            let dur: Double = max(clip.duration, 0.1)
            let startX: CGFloat = CGFloat(clip.trimStart / dur) * w
            let endX: CGFloat = CGFloat(clip.trimEnd / dur) * w
            ZStack(alignment: .leading) {
                filmstrip(width: w)
                Rectangle().fill(Color.black.opacity(0.62)).frame(width: max(0, startX), height: 64)
                Rectangle().fill(Color.black.opacity(0.62)).frame(width: max(0, w - endX), height: 64).offset(x: endX)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2.5)
                    .frame(width: max(0, endX - startX), height: 64)
                    .offset(x: startX)
                    .allowsHitTesting(false)
                handle(x: startX)
                    .gesture(dragGesture(width: w, duration: dur, leading: true))
                handle(x: endX)
                    .gesture(dragGesture(width: w, duration: dur, leading: false))
            }
            .coordinateSpace(name: "wave-trim-strip")
        }
    }

    private func filmstrip(width w: CGFloat) -> some View {
        HStack(spacing: 1) {
            if frames.isEmpty {
                Rectangle().fill(Color.white.opacity(0.08))
            } else {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: max((w - CGFloat(frames.count - 1)) / CGFloat(frames.count), 4), height: 64)
                        .clipped()
                }
            }
        }
        .frame(width: w, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handle(x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white)
            .frame(width: 16, height: 64)
            .overlay {
                Capsule().fill(Color.black.opacity(0.35)).frame(width: 2, height: 20)
            }
            .contentShape(Rectangle().inset(by: -12))
            .offset(x: x - 8)
    }

    private func dragGesture(width w: CGFloat, duration dur: Double, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("wave-trim-strip"))
            .onChanged { value in
                let raw = Double(min(max(0, value.location.x), w) / w) * dur
                let t = snap?(leading, raw) ?? raw
                if t != raw, lastSnapTarget != t {
                    lastSnapTarget = t
                    Haptics.rigid()
                } else if t == raw {
                    lastSnapTarget = nil
                }
                if leading {
                    onTrim(min(max(0, t), clip.trimEnd - minKept), clip.trimEnd)
                } else {
                    onTrim(clip.trimStart, max(min(dur, t), clip.trimStart + minKept))
                }
            }
            .onEnded { _ in
                lastSnapTarget = nil
                Haptics.selection()
            }
    }
}
