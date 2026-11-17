import SwiftUI

struct WhisperChatAttachmentMenu: View {
    let items: [WhisperChatAttachItem]
    let onSelect: (@escaping () -> Void) -> Void
    @State private var group: WhisperChatAttachItem?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if group != nil {
                    Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { group = nil } } label: {
                        Label("Back", systemImage: "chevron.left").font(.subheadline).frame(minHeight: 44)
                    }.padding(.horizontal, 18)
                }
                ForEach(group?.children ?? items) { item in
                    Button {
                        Haptics.tap()
                        if item.children.isEmpty { onSelect(item.action) }
                        else { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { group = item } }
                    } label: {
                        HStack(spacing: 14) {
                            if item.id == "meet" || item.id == "notes" {
                                Image(item.id == "notes" ? "WhisperNotesApp" : "WhisperMeetApp")
                                    .renderingMode(.original).resizable().scaledToFit().frame(width: 40, height: 40)
                                    .clipShape(.rect(cornerRadius: 11)).accessibilityHidden(true)
                            } else {
                                WhisperAttachmentIllustration(id: item.id, symbol: item.systemImage, jasper: item.jasper)
                            }
                            Text(item.title).font(.body).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if !item.children.isEmpty { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.horizontal, 16).padding(.vertical, 7).frame(minHeight: 54).contentShape(.rect)
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical, 8)
        }.scrollBounceBehavior(.basedOnSize).frame(width: 280, height: min(430, CGFloat((group?.children.count ?? items.count) * 54 + (group == nil ? 16 : 60))))
            .foregroundStyle(WhisperTheme.ink(scheme)).background(WhisperTheme.surface(scheme))
    }
}
