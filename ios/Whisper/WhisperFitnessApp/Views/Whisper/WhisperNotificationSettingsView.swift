import SwiftUI

/// Per-category notification preferences. Master switch at the top, then
/// a card with one toggle per `WhisperNotificationCategory`. Quiet mode
/// is a separate row that silences everything for the night without
/// touching per-category state.
struct WhisperNotificationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let sync = WhisperPushPreferenceSync.shared

    @State private var master: Bool = WhisperNotificationPrefs.masterEnabled
    @State private var quiet: Bool = WhisperNotificationPrefs.quietMode
    @State private var values: [WhisperNotificationCategory: Bool] = {
        var v: [WhisperNotificationCategory: Bool] = [:]
        for c in WhisperNotificationCategory.allCases {
            v[c] = WhisperNotificationPrefs.isEnabled(c) || !WhisperNotificationPrefs.masterEnabled || WhisperNotificationPrefs.quietMode
            // Persisted value (ignoring master/quiet) is read from storage:
            v[c] = AccountStorage.object(forKey: "whisper.push.\(c.rawValue)") as? Bool ?? true
        }
        return v
    }()

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    section(title: nil) {
                        toggleRow(
                            icon: "bell.fill",
                            title: "Push notifications",
                            subtitle: "Master switch for all Whisper alerts",
                            isOn: Binding(
                                get: { master },
                                set: { v in
                                    master = v
                                    WhisperNotificationPrefs.masterEnabled = v
                                }
                            )
                        )
                        divider
                        toggleRow(
                            icon: "moon.fill",
                            title: "Quiet mode",
                            subtitle: "Silence banners without changing categories",
                            isOn: Binding(
                                get: { quiet },
                                set: { v in
                                    quiet = v
                                    WhisperNotificationPrefs.quietMode = v
                                }
                            )
                        )
                    }

                    section(title: "Categories") {
                        let cats = WhisperNotificationCategory.allCases
                        ForEach(Array(cats.enumerated()), id: \.element.id) { idx, cat in
                            toggleRow(
                                icon: cat.icon,
                                title: cat.title,
                                subtitle: cat.subtitle,
                                isOn: Binding(
                                    get: { values[cat] ?? true },
                                    set: { v in
                                        values[cat] = v
                                        WhisperNotificationPrefs.setEnabled(cat, v)
                                    }
                                ),
                                disabled: !master || quiet
                            )
                            if idx < cats.count - 1 { divider }
                        }
                    }

                    if let error = sync.lastError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("Retry syncing") { sync.refresh() }
                            .frame(minHeight: 44)
                    } else if sync.isSyncing {
                        ProgressView("Syncing preferences…").font(.caption)
                    }
                    if let error = sync.newPostSyncError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("Retry New posts sync") { sync.refresh() }.frame(minHeight: 44)
                    }
                    Text("Messages and activity preferences sync across devices. New posts covers occasional return-to-posting alerts after server rollout: followed contacts, recent interaction, and strict limits—not every post. iPhone Settings → Notifications → Whisper controls system permission.")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .task { sync.refresh() }
        .onChange(of: sync.revision) { _, _ in
            master = WhisperNotificationPrefs.masterEnabled
            quiet = WhisperNotificationPrefs.quietMode
            for category in WhisperNotificationCategory.allCases {
                values[category] = AccountStorage.object(forKey: "whisper.push.\(category.rawValue)") as? Bool ?? true
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section<Content: View>(title: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .padding(.leading, 16)
            }
            VStack(spacing: 0) { content() }
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 58)
    }

    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        disabled: Bool = false
    ) -> some View {
        let tint = disabled ? WhisperTheme.muted(colorScheme) : WhisperTheme.ink(colorScheme)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(colorScheme == .dark ? 0.13 : 0.06), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .accessibilityHint(subtitle)
                .tint(WhisperTheme.ink(colorScheme))
                .disabled(disabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
