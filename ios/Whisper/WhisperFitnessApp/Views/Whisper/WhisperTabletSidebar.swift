import SwiftUI

struct WhisperTabletSidebar: View {
    let selection: Int
    let unread: Int
    let select: (Int) -> Void
    let openActivity: () -> Void
    let openCommunities: () -> Void
    let openCommunity: (WhisperCommunity) -> Void
    var communitiesSelected: Bool = false
    let compose: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var users = WhisperUserService.shared

    private var joined: [WhisperCommunity] {
        let names = Set((users.displayProfile?.interests ?? []).map { $0.lowercased() })
        return Array(WhisperCommunity.catalog.filter { names.contains($0.name.lowercased()) }.prefix(6))
    }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        row("Home", icon: "house", tag: 0) { select(0) }
                        row("Waves", icon: "play.rectangle", tag: 1) { select(1) }
                        row("Communities", icon: "person.3", tag: -1) { openCommunities() }
                        row("Messages", icon: "paperplane", tag: 2, badge: unread) { select(2) }
                        row("Activity", icon: "heart") { openActivity() }
                        row("Profile", icon: "person.crop.circle", tag: 4) { select(4) }
                        row("Search", icon: "magnifyingglass", tag: 3) { select(3) }
                    }.padding(16).background(WhisperTheme.surface(scheme), in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(scheme), lineWidth: 0.6))
                    if !joined.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR COMMUNITIES").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                            ForEach(joined) { item in
                                Button { openCommunity(item) } label: {
                                    Label(item.name, systemImage: item.symbol).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.buttonStyle(.plain)
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(WhisperTheme.surface(scheme), in: .rect(cornerRadius: 16))
                    }
                    Button(action: compose) { Label("Create a post", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46) }
                        .buttonStyle(.plain).foregroundStyle(WhisperTheme.surface(scheme)).background(WhisperTheme.ink(scheme), in: Capsule())
                }
            }.scrollIndicators(.hidden)
            Button { select(4) } label: {
                HStack(spacing: 10) {
                    WhisperAvatar(username: users.displayProfile?.username ?? "", size: 34, ring: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(users.displayProfile?.display_name ?? users.displayProfile?.username ?? "Your profile").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("@\(users.displayProfile?.username ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption)
                }.padding(12).background(WhisperTheme.surface(scheme), in: .rect(cornerRadius: 16))
            }.buttonStyle(.plain)
        }
        .foregroundStyle(WhisperTheme.ink(scheme))
        .padding(.vertical, 24).padding(.horizontal, 16).frame(width: 260)
    }

    private func row(_ title: String, icon: String, tag: Int? = nil, badge: Int = 0, action: @escaping () -> Void) -> some View {
        let selected = communitiesSelected ? tag == -1 : selection == tag
        return Button(action: action) {
            HStack(spacing: 12) {
                if tag == 2 { WhisperRoundedGlyph(kind: .plane, size: 22, selected: selected) }
                else { Image(systemName: icon).font(.system(size: 21)).frame(width: 22) }
                Text(title).font(.subheadline.weight(selected ? .bold : .medium))
                Spacer(minLength: 0)
                if badge > 0 { Text(badge > 99 ? "99+" : "\(badge)").font(.caption2.weight(.bold)).padding(4).background(WhisperTheme.card(scheme), in: Capsule()) }
            }.padding(.horizontal, 10).frame(minHeight: 44)
                .background(selected ? WhisperTheme.card(scheme) : .clear, in: .rect(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
