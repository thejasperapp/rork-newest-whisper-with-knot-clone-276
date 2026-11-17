import SwiftUI

struct WhisperStoryTemplateBuilder: View {
    let stickers: [WhisperStorySticker]
    let stageWidth: Double
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var title: String = "My template"
    @State private var previewing: Bool = false
    @State private var error: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    private var eligible: [WhisperStorySticker] { stickers.filter { [.text, .photo, .gif, .sticker].contains($0.kind) } }
    private var chosen: [WhisperStorySticker] { eligible.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            WhisperStoryToolHeader(title: previewing ? "Template preview" : "Pin your template", confirmation: "Save", canConfirm: !chosen.isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, onConfirm: save, onCancel: { dismiss() })
            ScrollView {
                VStack(spacing: 18) {
                    TextField("Template name", text: $title).textFieldStyle(.roundedBorder).onChange(of: title) { _, value in title = String(value.prefix(60)) }
                    Text(previewing ? "These layers will be kept. Add a new background whenever you reuse this template." : "Choose the text, photos and GIFs to keep. Your background, replies and music are not saved in the template.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    GeometryReader { geo in
                        ZStack {
                            Color(white: 0.18)
                            ForEach(previewing ? chosen : eligible) { layer in
                                Button {
                                    if selected.contains(layer.id) { selected.remove(layer.id) } else { selected.insert(layer.id) }
                                    Haptics.tap()
                                } label: {
                                    WhisperStoryStickerView(sticker: layer, stageWidth: stageWidth)
                                        .overlay { if !previewing { RoundedRectangle(cornerRadius: 8).stroke(selected.contains(layer.id) ? Color.yellow : .white.opacity(0.5), lineWidth: 3) } }
                                        .scaleEffect(layer.scale).rotationEffect(.radians(layer.rotation))
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .disabled(previewing)
                                .position(x: layer.x * stageWidth, y: layer.y * stageWidth * 16 / 9)
                                .accessibilityLabel("\(selected.contains(layer.id) ? "Unpin" : "Pin") \(layer.text ?? layer.kind.rawValue)")
                            }
                        }.frame(width: stageWidth, height: stageWidth * 16 / 9)
                            .scaleEffect(geo.size.width / max(1, stageWidth))
                            .frame(width: geo.size.width, height: geo.size.height)
                    }.aspectRatio(9.0 / 16.0, contentMode: .fit).frame(maxWidth: 270).clipShape(.rect(cornerRadius: 24))
                    if eligible.isEmpty { Text("Add text, photos or GIFs to your Story first, then return here to save your template.").font(.subheadline) }
                    if !eligible.isEmpty {
                        if !previewing {
                            ForEach(eligible) { layer in
                                Button {
                                    if selected.contains(layer.id) { selected.remove(layer.id) } else { selected.insert(layer.id) }
                                } label: {
                                    HStack {
                                        Text(layer.text ?? layer.kind.rawValue.capitalized).lineLimit(2)
                                        Spacer()
                                        Image(systemName: selected.contains(layer.id) ? "checkmark.circle.fill" : "circle")
                                    }.frame(minHeight: 44)
                                }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(layer.id) ? .isSelected : [])
                            }
                        }
                        Button(previewing ? "Edit pinned layers" : "Preview \(selected.count) pinned layers") { previewing.toggle() }.frame(minHeight: 44).disabled(selected.isEmpty)
                    }
                    if error { Text("Couldn't save this template. Try fewer layers.").foregroundStyle(.orange).font(.caption) }
                }.padding(16)
            }
        }.presentationDetents([.large]).environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in closed = true; selected = []; dismiss() }
    }

    private func save() {
        guard !closed, generation == AccountStorage.generation, !chosen.isEmpty else { return }
        let template = WhisperStorySavedTemplate(title: title.trimmingCharacters(in: .whitespacesAndNewlines), stickers: chosen, referenceWidth: stageWidth)
        if WhisperStoryTemplateStore.save(template, generation: generation) { onSaved(); dismiss() } else { error = true }
    }
}
