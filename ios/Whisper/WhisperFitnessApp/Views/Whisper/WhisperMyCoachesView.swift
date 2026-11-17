import SwiftUI

/// Client-side view of every coach the local user has interacted with —
/// active (accepted), pending, declined. Lets them re-send a snapshot or
/// revoke access at any time.
struct WhisperMyCoachesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var requests = WhisperCoachRequestService.shared
    @State private var snapshots = WhisperClientSnapshotService.shared
    @State private var toRevoke: WhisperCoachRequestRow?

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        syncBanner
                        if requests.outgoing.isEmpty {
                            empty
                        } else {
                            section("Active", rows: requests.outgoing.filter { $0.status == "accepted" })
                            section("Pending", rows: requests.outgoing.filter { $0.status == "pending" })
                            section("Past", rows: requests.outgoing.filter { $0.status == "declined" || $0.status == "cancelled" })
                        }
                    }
                    .padding(.bottom, 32)
                }
                .whisperRefreshable { await requests.refresh() }
            }
            .navigationTitle("My coaches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
            }
            .task { await requests.refresh() }
            .confirmationDialog(
                "Stop sharing with @\(toRevoke?.coach_username ?? "")?",
                isPresented: Binding(get: { toRevoke != nil }, set: { if !$0 { toRevoke = nil } }),
                titleVisibility: .visible,
                presenting: toRevoke
            ) { row in
                Button("Revoke access", role: .destructive) {
                    Task {
                        await requests.end(row)
                        toRevoke = nil
                    }
                }
                Button("Cancel", role: .cancel) { toRevoke = nil }
            } message: { _ in
                Text("They'll lose access to your nutrition, sleep and progress photos.")
            }
        }
    }

    private var syncBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .foregroundStyle(WhisperTheme.coachAccent)
                Text("Health sync")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if let t = snapshots.lastUploadedAt {
                    Text(relativeShort(t))
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            Text("Your nutrition, sleep, weight, steps and latest progress photos are shared automatically with active coaches only.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Button {
                Haptics.tap()
                Task { await snapshots.uploadIfNeeded(force: true) }
            } label: {
                HStack(spacing: 6) {
                    if snapshots.isUploading { ProgressView().tint(.white).controlSize(.mini) }
                    Text(snapshots.isUploading ? "Syncing…" : "Sync now")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(WhisperTheme.coachAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(snapshots.isUploading)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func section(_ title: String, rows: [WhisperCoachRequestRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 16)
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        coachCard(row)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func coachCard(_ row: WhisperCoachRequestRow) -> some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: row.coach_username, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.coach_username).lineLimit(1)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    WhisperCoachBadge(size: 11)
                }
                Text(statusLabel(row.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(row.status))
            }
            Spacer()
            if row.status == "accepted" || row.status == "pending" {
                Menu {
                    if row.status == "accepted" {
                        Button(role: .destructive) {
                            toRevoke = row
                        } label: { Label("Revoke access", systemImage: "xmark.shield") }
                    } else {
                        Button(role: .destructive) {
                            Task { await requests.cancel(row) }
                        } label: { Label("Cancel request", systemImage: "xmark") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "accepted": return "Sharing health data"
        case "pending":  return "Awaiting their response"
        case "declined": return "Declined"
        case "cancelled": return "Cancelled"
        default: return s
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "accepted": return WhisperTheme.coachAccent
        case "pending":  return .yellow
        case "declined", "cancelled": return WhisperTheme.muted(colorScheme)
        default: return WhisperTheme.muted(colorScheme)
        }
    }

    private func relativeShort(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var empty: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: "person.2", height: 120)
            Text("No coaches yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Find a verified coach on Whisper and tap “Ask to coach me” on their profile to get started.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 32)
        }
        .padding(.top, 32)
    }
}
