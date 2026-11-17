import SwiftUI

/// Expands in the same editing surface, without navigating away from the sticker.
struct WhisperStoryEmojiGrid: View {
    @Binding var selected: String
    let onClose: () -> Void
    @State private var search: String = ""
    private let ranges: [ClosedRange<UInt32>] = [0x1F600...0x1F637, 0x1F910...0x1F917, 0x1F970...0x1F976]
    private var faces: [String] { ranges.flatMap { $0.compactMap { UnicodeScalar($0).map(String.init) } } + ["\u{2764}\u{FE0F}", "\u{1F525}", "\u{1F64C}", "\u{1F44F}", "\u{1F4AA}"] }
    private var results: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? faces : faces.filter { $0.contains(query) || ($0.unicodeScalars.first?.properties.name ?? "").localizedStandardContains(query) }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search emoji", text: $search).font(.subheadline).autocorrectionDisabled()
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close emoji choices")
            }.padding(.leading, 14).background(.white.opacity(0.1), in: .capsule).padding(.horizontal, 16)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 8) {
                    ForEach(results, id: \.self) { face in
                        Button { selected = face; Haptics.tap(); onClose() } label: {
                            Text(face).font(.system(size: 29)).frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel(face).accessibilityAddTraits(selected == face ? .isSelected : [])
                    }
                }.padding(.horizontal, 16)
                if results.isEmpty { Text("No matching emoji").font(.footnote).padding() }
            }.scrollDismissesKeyboard(.interactively)
        }.padding(.top, 10).foregroundStyle(.white).background(Color(white: 0.09))
    }
}
