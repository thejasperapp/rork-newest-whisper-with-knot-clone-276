import SwiftUI

struct WhisperStoryLinkSheet: View {
    var existing: WhisperStorySticker? = nil
    let onDone: (WhisperStorySticker) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address: String = ""
    @State private var label: String = ""
    @State private var customize: Bool = false
    @State private var didLoad: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            WhisperStoryToolHeader(title: "Add link", canConfirm: Self.validURL(address) != nil, onConfirm: save, onCancel: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("URL").font(.caption).foregroundStyle(.secondary)
                    TextField("https://example.com", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                        .font(.body).padding(.horizontal, 14).frame(minHeight: 50)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
                    Text("Viewers will see the destination before opening the link.")
                        .font(.caption).foregroundStyle(.secondary)
                    if customize {
                        TextField("Sticker text", text: Binding(get: { label }, set: { label = String($0.prefix(max(60, label.count))) }))
                            .font(.body).frame(minHeight: 44)
                        Divider()
                    } else {
                        Button { customize = true } label: { Label("Customize sticker text", systemImage: "plus").font(.subheadline).frame(minHeight: 44) }
                    }
                    if let url = Self.validURL(address) {
                        Text(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url.host ?? "Link" : label)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 9).background(.white, in: .rect(cornerRadius: 8))
                            .frame(maxWidth: .infinity).padding(.top, 28)
                    }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
        }.environment(\.colorScheme, .dark).tint(.white)
            .task {
                guard !didLoad else { return }; didLoad = true
                address = existing?.linkURL ?? ""; label = existing?.text ?? ""; customize = !label.isEmpty; focused = true
            }
    }
    private func save() {
        guard generation == AccountStorage.generation, let url = Self.validURL(address) else { return }
        var sticker = existing ?? WhisperStorySticker(kind: .text)
        sticker.linkURL = url.absoluteString
        sticker.text = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url.host : label
        onDone(sticker); dismiss()
    }

    nonisolated static func validURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 2048, !value.contains(where: { $0.isWhitespace }), let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
}
