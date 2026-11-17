import SwiftUI

/// Mod / admin / owner-only dashboard for triaging `whisper_reports`.
/// Each open report can be marked **Helpful** (bumps the reporter's
/// `helpful_report_count` so they progress toward the Community Guardian
/// badge), **Dismissed**, or **Actioned** (mod took some other step).
struct WhisperReportsDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var service = WhisperReportsService.shared
    @State private var presentDetail: WhisperReportRow?
    @State private var noteText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if service.isLoading && service.open.isEmpty {
                            ProgressView()
                                .tint(WhisperTheme.ink(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if service.open.isEmpty {
                            if service.lastError == nil { emptyState }
                        } else {
                            section("Open reports", rows: service.open, showActions: true)
                        }
                        if !service.recent.isEmpty {
                            section("Recent decisions", rows: service.recent, showActions: false)
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
            .navigationTitle("Reports")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Report review")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Marking a report **Helpful** credits the reporter toward the Community Guardian badge. Three helpful reports unlock the chip.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.horizontal, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "tray", height: 144)
            Text("Inbox zero")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("No open reports right now.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    private func section(_ title: String, rows: [WhisperReportRow], showActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 18)
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    reportRow(row, showActions: showActions)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func reportRow(_ row: WhisperReportRow, showActions: Bool) -> some View {
        Button {
            Haptics.tap()
            presentDetail = row
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: kindIcon(row.target_kind))
                        .font(.body)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(WhisperTheme.surface(colorScheme), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.reason.capitalized)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            statusPill(row.status)
                        }
                        Text("\(row.target_kind) · target: @\(row.target_username ?? "—")")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        if let r = row.reporter_username {
                            Text("Reported by @\(r)")
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                    Spacer()
                }
                if let d = row.details, !d.isEmpty {
                    Text(d)
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(3)
                }
                if showActions {
                    HStack(spacing: 10) {
                        actionButton("Helpful", filled: true) {
                            Haptics.success()
                            Task { _ = await service.markHelpful(row) }
                        }
                        actionButton("Dismiss", filled: false) {
                            Haptics.warning()
                            Task { _ = await service.dismiss(row) }
                        }
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

    @ViewBuilder
    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    filled ? Color(red: 0.13, green: 0.55, blue: 0.96) : WhisperTheme.surface(colorScheme),
                    in: Capsule()
                )
                .foregroundStyle(filled ? .white : WhisperTheme.ink(colorScheme))
                .overlay {
                    if !filled {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ status: String) -> some View {
        let (color, label): (Color, String) = {
            switch status {
            case "helpful":   return (Color(red: 0.14, green: 0.55, blue: 0.62), "Helpful")
            case "dismissed": return (Color.gray, "Dismissed")
            case "actioned":  return (Color.orange, "Actioned")
            default:          return (Color.red, "Open")
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func kindIcon(_ kind: String) -> String {
        switch kind {
        case "user":    return "person"
        case "story":   return "circle.dashed"
        case "post":    return "text.bubble"
        case "dm":      return "envelope"
        case "comment": return "bubble.left"
        case "reel":    return "play.rectangle"
        default:        return "flag"
        }
    }

    // MARK: - Detail sheet

    private func detailSheet(row: WhisperReportRow) -> some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        detailRow("Reason", row.reason.capitalized)
                        detailRow("Target", "\(row.target_kind) · @\(row.target_username ?? "—")")
                        if let r = row.reporter_username { detailRow("Reporter", "@\(r)") }
                        if let d = row.details, !d.isEmpty { detailRow("Details", d) }
                        if let note = row.review_note, !note.isEmpty { detailRow("Review note", note) }
                        if row.status == "open" {
                            TextField("Optional note", text: $noteText, axis: .vertical)
                                .lineLimit(1...4)
                                .padding(10)
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                                }
                            HStack(spacing: 10) {
                                actionButton("Helpful", filled: true) {
                                    Haptics.success()
                                    Task {
                                        _ = await service.markHelpful(row, note: noteText.isEmpty ? nil : noteText)
                                        presentDetail = nil
                                        noteText = ""
                                    }
                                }
                                actionButton("Dismiss", filled: false) {
                                    Haptics.warning()
                                    Task {
                                        _ = await service.dismiss(row, note: noteText.isEmpty ? nil : noteText)
                                        presentDetail = nil
                                        noteText = ""
                                    }
                                }
                            }
                            actionButton("Mark actioned", filled: false) {
                                Haptics.tap()
                                Task {
                                    _ = await service.markActioned(row, note: noteText.isEmpty ? nil : noteText)
                                    presentDetail = nil
                                    noteText = ""
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Report")
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
