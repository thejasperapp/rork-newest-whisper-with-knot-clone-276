import SwiftUI

/// Collaborative grocery list embed. Sent via `/grocery <theme>` and from
/// the recipe detail sheet. Each user keeps their own check state locally
/// keyed by the embed `id` so both can tick items off without the chat
/// turning into a flood of edit messages.
nonisolated enum WhisperGroceryListEmbed {
    static let prefix = "::whisper-grocery-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let items: [String]
        let authorUsername: String
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }
}

/// Per-device check state for grocery list items. Two users see their own
/// progress on the same shared list — fits the "I'll grab milk, you grab
/// bread" workflow without needing a server-side sync table.
@MainActor
final class WhisperGroceryStore {
    static let shared = WhisperGroceryStore()
    private let keyPrefix = "whisper_grocery_state_v1::"
    private var cache: [String: Set<String>] = [:]

    private init() {}

    func checked(forListID id: String) -> Set<String> {
        if let hit = cache[id] { return hit }
        let raw = UserDefaults.standard.stringArray(forKey: keyPrefix + id) ?? []
        let set = Set(raw)
        cache[id] = set
        return set
    }

    func toggle(listID: String, item: String) -> Set<String> {
        var set = checked(forListID: listID)
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
        cache[listID] = set
        UserDefaults.standard.set(Array(set), forKey: keyPrefix + listID)
        return set
    }
}

struct WhisperGroceryInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperGroceryListEmbed.Payload
    let mine: Bool

    @State private var checked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cart.fill")
                    .font(.subheadline.weight(.bold))
                Text(payload.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Spacer()
                Text("\(checked.count)/\(payload.items.count)")
                    .font(.caption2.weight(.heavy))
                    .opacity(0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(payload.items.prefix(20).enumerated()), id: \.offset) { _, item in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.25)) {
                            checked = WhisperGroceryStore.shared.toggle(listID: payload.id, item: item)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: checked.contains(item) ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline)
                                .foregroundStyle(
                                    checked.contains(item)
                                    ? .green
                                    : (mine ? WhisperTheme.surface(colorScheme).opacity(0.8)
                                            : WhisperTheme.muted(colorScheme))
                                )
                            Text(item)
                                .font(.caption.weight(.semibold))
                                .strikethrough(checked.contains(item))
                                .opacity(checked.contains(item) ? 0.55 : 1.0)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(.rect)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Tap items to check off — your taps stay on this device.")
                .font(.caption2)
                .opacity(0.6)
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
        .background(
            mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(mine ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .onAppear {
            checked = WhisperGroceryStore.shared.checked(forListID: payload.id)
        }
    }
}
