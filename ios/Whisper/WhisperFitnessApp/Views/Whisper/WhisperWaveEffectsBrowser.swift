import SwiftUI

/// The camera stays visible above a three-column catalog; choosing an effect returns to the shutter carousel.
struct WhisperWaveEffectsBrowser: View {
    let selected: WhisperWaveCameraEffect
    let thumbnails: WhisperWaveEffectThumbnails
    @Binding var saved: Set<String>
    let onPick: (WhisperWaveCameraEffect) -> Void
    let onClose: () -> Void
    @State private var category: String = "Featured"
    @State private var query: String = ""
    @State private var searching: Bool = false

    private var effects: [WhisperWaveCameraEffect] {
        WhisperWaveCameraEffect.available.filter {
            (category == "Featured" || (category == "Saved" ? saved.contains($0.id) : $0.category == category)) &&
            (query.isEmpty || $0.name.localizedStandardContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.black.opacity(0.22)).frame(width: 32, height: 4).padding(.top, 9)
            HStack(spacing: 0) {
                Button { searching.toggle() } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                    .accessibilityLabel("Search effects")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(["Saved", "Featured", "Face", "Looks", "Creative"], id: \.self) { name in
                            Button { category = name; Haptics.tap() } label: {
                                VStack(spacing: 7) {
                                    Text(name).font(.subheadline.weight(category == name ? .semibold : .regular))
                                    Capsule().fill(category == name ? Color.black : .clear).frame(height: 2)
                                }.padding(.top, 10).frame(minHeight: 44)
                            }
                        }
                    }
                }.contentMargins(.horizontal, 4)
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close effect browser")
            }.foregroundStyle(.black)
            if searching {
                TextField("Search effects", text: $query).textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            ScrollView {
                if let hint = selected.interactionHint {
                    Text(hint).font(.footnote).foregroundStyle(.black.opacity(0.65))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                }
                if effects.isEmpty {
                    WhisperEmptyState(icon: category == "Saved" ? "bookmark" : "magnifyingglass", title: category == "Saved" ? "No saved effects" : "No matching effects", message: category == "Saved" ? "Use the bookmark beside an effect's name to keep it here." : "Try another name.", isCard: false, compact: true).environment(\.colorScheme, .light)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                    ForEach(effects) { effect in
                        Button { Haptics.tap(); onPick(effect) } label: {
                            VStack(spacing: 9) {
                                WhisperWaveEffectTile(effect: effect, image: thumbnails.images[effect.id], size: 62)
                                Text(effect.name).font(.caption.weight(.medium)).lineLimit(2).frame(height: 30)
                            }
                            .foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Color(white: 0.94), in: .rect(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected == effect ? Color.black : .clear, lineWidth: 1.5) }
                        }.buttonStyle(.plain)
                            .accessibilityLabel(effect.name + (effect.faceKind.accessory == nil ? "" : ", 3D effect"))
                            .accessibilityHint(effect.interactionHint ?? "Select this camera effect")
                            .accessibilityAddTraits(selected == effect ? .isSelected : [])
                    }
                }.padding(.horizontal, 6).padding(.bottom, 16)
            }
        }
        .background(.white, in: .rect(topLeadingRadius: 24, topTrailingRadius: 24))
        .environment(\.colorScheme, .light)
    }
}
