import SwiftUI
import Supabase

/// Client-side review sheet for an incoming `jasper://coach-proposal/<id>`
/// deep link. Loads the proposal row, shows a diff, and lets the client
/// Accept (applies the patch) or Decline.
struct WhisperCoachProposalReviewSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let proposalID: String

    @State private var service = WhisperCoachProposalReviewService.shared
    @State private var row: WhisperCoachProposalRow?
    @State private var coachName: String = "Your coach"
    @State private var loading: Bool = true
    @State private var loadFailed: Bool = false
    @State private var working: Bool = false
    @State private var resultBanner: String?

    private var isCoachPreview: Bool {
        guard let row else { return false }
        return row.coach_user_id == AccountStorage.currentUserID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                content
            }
            .navigationTitle("Coach suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView().tint(WhisperTheme.coachAccent)
        } else if loadFailed || row == nil {
            unavailable
        } else if let row {
            ScrollView {
                VStack(spacing: 16) {
                    header(row: row)
                    if let banner = resultBanner {
                        Text(banner)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.coachAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(WhisperTheme.coachAccent.opacity(0.12), in: .rect(cornerRadius: 12))
                            .padding(.horizontal, 16)
                    }
                    diff(row: row)
                    if let note = row.note, !note.isEmpty {
                        noteCard(note: note)
                    }
                    if isCoachPreview {
                        coachPreviewBanner
                    } else if row.status == "pending" {
                        actionButtons(row: row)
                    } else {
                        statusBanner(row: row)
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.bubble")
                .font(.largeTitle)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text("Suggestion unavailable")
                .font(.headline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("This coach suggestion may have expired or isn't visible on this account.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 32)
        }
        .padding(24)
    }

    private func header(row: WhisperCoachProposalRow) -> some View {
        VStack(spacing: 8) {
            Image(systemName: kindIcon(row.kind))
                .font(.title2)
                .foregroundStyle(WhisperTheme.coachAccent)
                .frame(width: 52, height: 52)
                .background(WhisperTheme.coachAccent.opacity(0.15), in: Circle())
            Text(kindTitle(row.kind))
                .font(.title3.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("from \(coachName)")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func diff(row: WhisperCoachProposalRow) -> some View {
        if row.kind == "macros" || row.kind == "diet_plan" {
            macrosDiff(row: row)
        } else if let msg = row.patch?["message"]?.stringValue {
            messageCard(text: msg)
        } else {
            messageCard(text: "No details on this suggestion.")
        }
    }

    private func macrosDiff(row: WhisperCoachProposalRow) -> some View {
        let patch = row.patch ?? [:]
        let pairs: [(String, String, String)] = [
            ("Calories", "calories", "kcal"),
            ("Protein",  "protein_g", "g"),
            ("Carbs",    "carbs_g",   "g"),
            ("Fat",      "fat_g",     "g"),
        ]
        return VStack(spacing: 10) {
            ForEach(pairs.filter { patch[$0.1] != nil }, id: \.1) { label, key, unit in
                HStack {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Spacer()
                    Text(format(patch[key]) + " " + unit)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.coachAccent)
                }
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func messageCard(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 16)
    }

    private func noteCard(note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text(note)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func actionButtons(row: WhisperCoachProposalRow) -> some View {
        VStack(spacing: 10) {
            Button {
                Task { await respond(row: row, status: "accepted") }
            } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(.white) }
                    Text(working ? "Applying…" : "Accept & apply")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WhisperTheme.coachAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(working)

            Button {
                Task { await respond(row: row, status: "declined") }
            } label: {
                Text("Decline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.red.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var coachPreviewBanner: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text("Preview only")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("This is what your client sees in Whisper. They'll accept or decline on their device.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func statusBanner(row: WhisperCoachProposalRow) -> some View {
        let label: String = {
            switch row.status {
            case "accepted": return "You accepted this suggestion"
            case "declined": return "You declined this suggestion"
            case "modified": return "You modified this suggestion"
            case "expired":  return "This suggestion has expired"
            default:         return "Status: \(row.status)"
            }
        }()
        return Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func load() async {
        loading = true
        defer { loading = false }
        guard let fetched = await service.fetch(id: proposalID) else {
            loadFailed = true
            return
        }
        row = fetched
        coachName = await resolveCoachName(userID: fetched.coach_user_id)
    }

    private func respond(row: WhisperCoachProposalRow, status: String) async {
        working = true
        defer { working = false }
        let ok = await service.respond(to: row, status: status)
        if ok {
            Haptics.success()
            resultBanner = status == "accepted"
                ? "Applied! Your targets are updated."
                : "Suggestion declined."
            self.row = WhisperCoachProposalRow(
                id: row.id,
                coach_user_id: row.coach_user_id,
                client_user_id: row.client_user_id,
                kind: row.kind,
                target_id: row.target_id,
                patch: row.patch,
                note: row.note,
                status: status,
                created_at: row.created_at,
                updated_at: row.updated_at,
                responded_at: ISO8601DateFormatter().string(from: Date())
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
            }
        } else {
            Haptics.warning()
            resultBanner = "Couldn't update — try again in a moment."
        }
    }

    private func resolveCoachName(userID: String) async -> String {
        let client = SupabaseService.shared.client
        struct ProfileRow: Decodable, Sendable { let username: String? }
        if let rows: [ProfileRow] = try? await client
            .from("whisper_profiles")
            .select("username")
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value, let name = rows.first?.username, !name.isEmpty {
            return "@\(name)"
        }
        return "Your coach"
    }

    private func format(_ value: JSONValue?) -> String {
        guard let v = value?.doubleValue else { return "—" }
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))" }
        return String(format: "%.1f", v)
    }

    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case "macros":        return "Adjust macros"
        case "diet_plan":     return "New diet plan"
        case "workout":       return "Workout tweak"
        case "exercise_swap": return "Exercise swap"
        case "note":          return "Coaching note"
        default:              return "Suggestion"
        }
    }

    private func kindIcon(_ kind: String) -> String {
        switch kind {
        case "macros":        return "scalemass"
        case "diet_plan":     return "leaf.fill"
        case "workout":       return "figure.strengthtraining.traditional"
        case "exercise_swap": return "arrow.left.arrow.right"
        case "note":          return "text.bubble"
        default:              return "sparkles"
        }
    }
}
