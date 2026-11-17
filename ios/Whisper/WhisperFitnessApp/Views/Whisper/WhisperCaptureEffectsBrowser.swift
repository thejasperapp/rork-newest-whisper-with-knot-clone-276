import SwiftUI

struct WhisperCaptureEffectsBrowser: View {
    let selected: WhisperWaveCameraEffect
    let thumbnails: WhisperWaveEffectThumbnails
    let onSelect: (WhisperWaveCameraEffect) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var category: String = "All"
    private let categories = ["All", "Face", "Looks", "Creative"]
    private var effects: [WhisperWaveCameraEffect] {
        WhisperWaveCameraEffect.available.filter {
            (category == "All" || $0.category == category) && (query.isEmpty || $0.name.localizedStandardContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Effect category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 16)
                ScrollView {
                    if let hint = selected.interactionHint {
                        Text(hint).font(.footnote).foregroundStyle(.white.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 6) {
                        ForEach(effects) { effect in
                            Button { onSelect(effect); dismiss() } label: {
                                VStack(spacing: 10) {
                                    WhisperWaveEffectTile(effect: effect, image: thumbnails.images[effect.id], size: 64)
                                    Text(effect.name).font(.caption.weight(.medium)).lineLimit(2).frame(minHeight: 30)
                                }.padding(.vertical, 16).frame(maxWidth: .infinity)
                                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 14))
                                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(selected == effect ? .white : .clear, lineWidth: 1.5) }
                            }.buttonStyle(.plain)
                                .accessibilityLabel(effect.name + (effect.faceKind.accessory == nil ? "" : ", 3D effect"))
                                .accessibilityHint(effect.interactionHint ?? "Select this camera effect")
                                .accessibilityAddTraits(selected == effect ? .isSelected : [])
                        }
                    }.padding(.horizontal, 16)
                    if effects.isEmpty { ContentUnavailableView.search(text: query) }
                }
            }.foregroundStyle(.white).background(Color(white: 0.055))
                .navigationTitle("Effects").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search effects")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.environment(\.colorScheme, .dark)
            .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}
