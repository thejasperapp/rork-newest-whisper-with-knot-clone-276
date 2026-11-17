import SwiftUI

/// Threads-style "Search topics" sheet. Used by the composer's topic
/// chip + community detail composer entry point. Shows a search field at
/// the top, a "Recent" section of communities the user has visited, then
/// a full "Communities" list pulled from `WhisperCommunity.catalog`.
struct WhisperTopicSearchSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selected: String
    @Binding var isPresented: Bool

    @State private var query: String = ""

    private let recentKey = "whisper.topic.recents"

    private var recentNames: [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var allCommunities: [WhisperCommunity] { WhisperCommunity.catalog }

    private var filteredCommunities: [WhisperCommunity] {
        guard !trimmed.isEmpty else { return allCommunities }
        return allCommunities.filter {
            $0.name.lowercased().contains(trimmed)
            || $0.tagline.lowercased().contains(trimmed)
            || $0.keywords.contains(where: { $0.lowercased().contains(trimmed) })
        }
    }

    private var recentCommunities: [WhisperCommunity] {
        let names = Set(recentNames.map { $0.lowercased() })
        return allCommunities.filter { names.contains($0.name.lowercased()) }
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            VStack(spacing: 0) {
                searchField
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !recentCommunities.isEmpty && trimmed.isEmpty {
                            sectionHeader("Recent")
                            ForEach(recentCommunities) { c in
                                row(c)
                                divider
                            }
                            Color.clear.frame(height: 8)
                        }
                        sectionHeader(trimmed.isEmpty ? "Communities" : "Results")
                        ForEach(filteredCommunities) { c in
                            row(c)
                            divider
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search topics", text: $query)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func row(_ c: WhisperCommunity) -> some View {
        Button {
            Haptics.tap()
            selected = c.name.lowercased()
            persistRecent(c.name)
            isPresented = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.28, green: 0.55, blue: 0.98))
                    Text(c.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(red: 0.28, green: 0.55, blue: 0.98))
                }
                Text("\(memberDisplay(for: c)) members")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func memberDisplay(for c: WhisperCommunity) -> String {
        var seen = Set<String>()
        // EXPLICIT-ONLY: membership counts only explicit community picks.
        for row in WhisperBackendService.shared.posts where (row.community_id ?? "") == c.id {
            seen.insert(row.user_id.lowercased())
        }
        let n = seen.count
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return v >= 10 ? String(format: "%.0fM", v) : String(format: "%.1fM", v)
        }
        if n >= 1_000 {
            let v = Double(n) / 1_000
            return v >= 10 ? String(format: "%.0fK", v) : String(format: "%.1fK", v)
        }
        return "\(n)"
    }

    private func persistRecent(_ name: String) {
        var list = recentNames.filter { $0.lowercased() != name.lowercased() }
        list.insert(name, at: 0)
        if list.count > 6 { list = Array(list.prefix(6)) }
        UserDefaults.standard.set(list, forKey: recentKey)
    }
}
