import SwiftUI

/// Mod / admin / owner-only dashboard for reviewing verification applications.
/// Lists pending requests with approve / decline actions. Approval flips
/// `profiles.is_verified = true` so the blue check goes live instantly.
struct WhisperVerificationDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var service = WhisperVerificationService.shared
    @State private var presentDetail: WhisperVerificationRequestRow?
    @State private var noteText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if service.isLoading && service.pending.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if service.pending.isEmpty {
                            if service.lastError == nil { emptyState }
                        } else {
                            section("Pending review", rows: service.pending, showActions: true)
                        }
                        if !service.recentDecisions.isEmpty {
                            section("Recent decisions", rows: service.recentDecisions, showActions: false)
                        }
                        if let err = service.lastError {
                            Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 18)
                            Button("Try again") { Task { await service.loadDashboard() } }.frame(minHeight: 44)
                        }
                        Color.clear.frame(height: 32)
                    }
                    .padding(.top, 6)
                }
                .whisperRefreshable { await service.loadDashboard() }
            }
            .navigationTitle("Verification review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .sheet(item: $presentDetail) { row in
                detailSheet(row: row)
            }
            .task { await service.loadDashboard() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verification review")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Approve or decline blue-check applications. Approving flips `is_verified` on the user's profile immediately.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.horizontal, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "checkmark.seal", height: 144)
            Text("No pending applications")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("New applications will appear here.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private func section(_ title: String, rows: [WhisperVerificationRequestRow], showActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 18)
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    requestRow(row, showActions: showActions)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func requestRow(_ row: WhisperVerificationRequestRow, showActions: Bool) -> some View {
        Button {
            Haptics.tap()
            presentDetail = row
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    WhisperAvatar(username: row.username, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.full_name)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            statusPill(row.status)
                        }
                        Text("@\(row.username) · \(row.category.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        if (row.followers ?? 0) > 0 {
                            Text("\(row.followers ?? 0) followers")
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                    Spacer()
                }
                Text(row.reason)
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(3)
                if showActions {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.success()
                            Task { _ = await service.approve(row) }
                        } label: {
                            Text("Approve")
                                .font(.footnote.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.13, green: 0.55, blue: 0.96), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        Button {
                            Haptics.warning()
                            Task { _ = await service.deny(row) }
                        } label: {
                            Text("Decline")
                                .font(.footnote.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(WhisperTheme.surface(colorScheme), in: Capsule())
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .overlay {
                                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ status: String) -> some View {
        let (color, label): (Color, String) = {
            switch status {
            case "approved": return (Color(red: 0.13, green: 0.55, blue: 0.96), "Approved")
            case "denied":   return (Color.red, "Denied")
            default:         return (Color.orange, "Pending")
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Detail

    private func detailSheet(row: WhisperVerificationRequestRow) -> some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            WhisperAvatar(username: row.username, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.full_name)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text("@\(row.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        detailRow("Category", row.category.replacingOccurrences(of: "_", with: " "))
                        if let e = row.email, !e.isEmpty { detailRow("Email", e) }
                        if (row.followers ?? 0) > 0 { detailRow("Followers", "\(row.followers ?? 0)") }
                        detailRow("Reason", row.reason)
                        if let links = row.links, !links.isEmpty { detailRow("Links", links) }
                        if let note = row.review_note, !note.isEmpty { detailRow("Review note", note) }
                        if row.status == "pending" {
                            TextField("Optional note for the applicant", text: $noteText, axis: .vertical)
                                .lineLimit(1...4)
                                .padding(10)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            HStack(spacing: 10) {
                                Button {
                                    Haptics.success()
                                    Task {
                                        _ = await service.approve(row, note: noteText.isEmpty ? nil : noteText)
                                        presentDetail = nil
                                        noteText = ""
                                    }
                                } label: {
                                    Text("Approve")
                                        .font(.headline.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color(red: 0.13, green: 0.55, blue: 0.96), in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    Haptics.warning()
                                    Task {
                                        _ = await service.deny(row, note: noteText.isEmpty ? nil : noteText)
                                        presentDetail = nil
                                        noteText = ""
                                    }
                                } label: {
                                    Text("Decline")
                                        .font(.headline.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        .overlay {
                                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { presentDetail = nil }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text(value)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
