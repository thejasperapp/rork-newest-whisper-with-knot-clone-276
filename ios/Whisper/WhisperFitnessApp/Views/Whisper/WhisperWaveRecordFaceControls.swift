import SwiftUI

/// Compact live face/retouch controls; camera framing never changes when an effect is selected.
struct WhisperWaveRecordFaceControls: View {
    @Binding var setting: WhisperWaveFaceSetting
    private let choices = WhisperWaveFaceSetting.Kind.available

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(choices) { kind in
                        Button {
                            Haptics.selection()
                            setting.kind = kind
                            setting.amount = kind.accessory == nil ? 0.35 : 1
                            if kind == .none { setting.smoothing = 0 }
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 24, weight: .regular))
                                    .frame(width: 56, height: 54)
                                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
                                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(setting.kind == kind ? Color.white : .clear, lineWidth: 1.5) }
                                Text(kind.title).font(.caption2.weight(.medium)).lineLimit(1)
                            }.frame(width: 66)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(setting.kind == kind ? .isSelected : [])
                    }
                }
            }.contentMargins(.horizontal, 16)
            VStack(spacing: 4) {
                if setting.kind != .none {
                    HStack {
                        Text("Amount").font(.caption).frame(width: 76, alignment: .leading)
                        Slider(value: $setting.amount, in: 0...1).tint(.white)
                    }.frame(minHeight: 44)
                }
                HStack {
                    Text("Smooth").font(.caption).frame(width: 76, alignment: .leading)
                    Slider(value: $setting.smoothing, in: 0...1).tint(.white)
                }.frame(minHeight: 44)
                Text("Face the camera in good light. Smoothing keeps eyes and lips sharp. Saved for this take only.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 18)
        }.foregroundStyle(.white)
    }
}
