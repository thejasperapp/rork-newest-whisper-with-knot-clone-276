import SwiftUI
import PhotosUI

struct WhisperStoryBackgroundPicker: View {
    let original: UIImage
    let photo: UIImage?
    @Binding var selection: WhisperStoryBackgroundSelection
    @Binding var photoItem: PhotosPickerItem?
    let isLoading: Bool
    let error: String?
    let onDone: () -> Void

    private let swatches: [(String, String)] = [
        ("Ink", "#101419"), ("Stone", "#555352"), ("Cream", "#E6DFD2"),
        ("Rose", "#A8727D"), ("Ocean", "#365E74"), ("Forest", "#3A594E")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Background").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Done", action: onDone).font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                Text("Keep the post's soft blur, choose a color, or use a photo.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Button {
                        selection = .blurred; Haptics.selection()
                    } label: {
                        VStack(spacing: 8) {
                            WhisperSharedStoryBackdrop(original: original, selection: .blurred, photo: nil, size: CGSize(width: 88, height: 100))
                                .clipShape(.rect(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white, lineWidth: selection == .blurred ? 3 : 0) }
                            Text("Post blur").font(.caption.weight(.medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == .blurred ? .isSelected : [])
                    .accessibilityIdentifier("storyBackgroundBlur")
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        VStack(spacing: 8) {
                            Color.white.opacity(0.1)
                                .frame(width: 88, height: 100)
                                .overlay {
                                    if let photo {
                                        Image(uiImage: photo).resizable().scaledToFill().allowsHitTesting(false)
                                    }
                                }
                                .clipShape(.rect(cornerRadius: 16))
                                .overlay {
                                    if isLoading { ProgressView().tint(.white) }
                                    else { Image(systemName: "photo.badge.plus").font(.title2).shadow(radius: 4) }
                                }
                                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white, lineWidth: selection == .photo ? 3 : 0) }
                            Text("Choose photo").font(.caption.weight(.medium))
                        }
                    }
                    .buttonStyle(.plain).disabled(isLoading)
                    .accessibilityIdentifier("storyBackgroundPhoto")
                    if photo != nil && selection != .photo {
                        Button("Use selected photo") { selection = .photo }
                            .font(.caption).frame(minHeight: 44)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 14) {
                    ForEach(swatches, id: \.0) { name, hex in
                        Button {
                            selection = .color(hex); Haptics.selection()
                        } label: {
                            VStack(spacing: 6) {
                                Circle().fill(whisperColorFromHex(hex) ?? .black)
                                    .frame(width: 44, height: 44)
                                    .overlay { Circle().strokeBorder(.white.opacity(selection == .color(hex) ? 1 : 0.25), lineWidth: selection == .color(hex) ? 3 : 1) }
                                Text(name).font(.caption)
                            }
                            .frame(maxWidth: .infinity, minHeight: 66)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == .color(hex) ? .isSelected : [])
                    }
                }
                ColorPicker("Custom color", selection: Binding(
                    get: { if case .color(let hex) = selection { return whisperColorFromHex(hex) ?? .black }; return .black },
                    set: { selection = .color($0.toHex()) }
                ), supportsOpacity: false)
                .frame(minHeight: 44)
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                Text("Your background photo stays on this device until you share the story.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
        }
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(isLoading)
    }
}
