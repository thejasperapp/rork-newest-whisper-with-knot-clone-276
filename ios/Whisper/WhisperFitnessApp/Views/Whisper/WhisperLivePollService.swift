import SwiftUI
import Supabase

/// Live-room polls — 1:1 with the web (`lib/livePolls.ts`): same tables
/// (`whisper_live_chat_polls` + `whisper_live_chat_poll_votes`), so polls
/// created on either platform render and count votes on both. iOS refreshes
/// on an 8s cadence while the room is open (plus instantly after any local
/// action), which tracks the web's realtime channel closely enough for a
/// live overlay.
@MainActor
@Observable
final class WhisperLivePollService {
    static let shared = WhisperLivePollService()
    private let client = SupabaseService.shared.client
    private init() {}

    nonisolated struct Poll: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let room_id: String
        let question: String
        let options: [String]
        let creator_id: String
        let creator_username: String
        let created_at: String
        let closed_at: String?
    }

    private(set) var polls: [Poll] = []
    /// poll id → votes per option (normalized to `options.count`).
    private(set) var voteCounts: [String: [Int]] = [:]
    /// poll id → my picked option index.
    private(set) var myVotes: [String: Int] = [:]

    func reset() {
        polls = []
        voteCounts = [:]
        myVotes = [:]
    }

    func refresh(roomID: String) async {
        do {
            let rows: [Poll] = try await client
                .from("whisper_live_chat_polls")
                .select()
                .eq("room_id", value: roomID)
                .order("created_at", ascending: false)
                .execute()
                .value
            polls = rows
        } catch {
            // Table may predate the polls migration — stay silent.
            return
        }
        await refreshVotes()
    }

    private nonisolated struct VoteRow: Codable, Sendable {
        let poll_id: String
        let option_index: Int
        let user_id: String?
    }

    private nonisolated struct PollInsert: Encodable, Sendable {
        let room_id: String
        let question: String
        let options: [String]
        let creator_id: String
        let creator_username: String
    }

    private nonisolated struct VoteUpsert: Encodable, Sendable {
        let poll_id: String
        let user_id: String
        let option_index: Int
    }

    private nonisolated struct CloseUpdate: Encodable, Sendable {
        let closed_at: String
    }

    private func refreshVotes() async {
        let ids = polls.map(\.id)
        guard !ids.isEmpty else {
            voteCounts = [:]
            myVotes = [:]
            return
        }
        do {
            let rows: [VoteRow] = try await client
                .from("whisper_live_chat_poll_votes")
                .select("poll_id,option_index,user_id")
                .in("poll_id", values: ids)
                .execute()
                .value
            var counts: [String: [Int]] = [:]
            var mine: [String: Int] = [:]
            let me = AccountStorage.currentUserID.lowercased()
            for poll in polls {
                counts[poll.id] = Array(repeating: 0, count: poll.options.count)
            }
            for row in rows {
                guard var arr = counts[row.poll_id] else { continue }
                if row.option_index >= arr.count {
                    arr.append(contentsOf: Array(repeating: 0, count: row.option_index - arr.count + 1))
                }
                arr[row.option_index] += 1
                counts[row.poll_id] = arr
                if (row.user_id ?? "").lowercased() == me {
                    mine[row.poll_id] = row.option_index
                }
            }
            voteCounts = counts
            myVotes = mine
        } catch { /* best effort */ }
    }

    func create(roomID: String, question: String, options: [String]) async {
        let cleaned = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard cleaned.count >= 2 else { return }
        let username = LeaderboardService.shared.savedUsername ?? "host"
        do {
            try await client
                .from("whisper_live_chat_polls")
                .insert(PollInsert(
                    room_id: roomID,
                    question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                    options: cleaned,
                    creator_id: AccountStorage.currentUserID,
                    creator_username: username
                ))
                .execute()
            await refresh(roomID: roomID)
        } catch { /* best effort */ }
    }

    func vote(pollID: String, optionIndex: Int, roomID: String) async {
        do {
            try await client
                .from("whisper_live_chat_poll_votes")
                .upsert(
                    VoteUpsert(
                        poll_id: pollID,
                        user_id: AccountStorage.currentUserID,
                        option_index: optionIndex
                    ),
                    onConflict: "poll_id,user_id"
                )
                .execute()
            myVotes[pollID] = optionIndex
            await refresh(roomID: roomID)
        } catch { /* best effort */ }
    }

    func close(pollID: String, roomID: String) async {
        do {
            try await client
                .from("whisper_live_chat_polls")
                .update(CloseUpdate(closed_at: ISO8601DateFormatter().string(from: Date())))
                .eq("id", value: pollID)
                .execute()
            await refresh(roomID: roomID)
        } catch { /* best effort */ }
    }
}

// MARK: - Poll card (overlay chat)

/// Glass poll card rendered above the live chat — tap an option to vote,
/// bars fill live, the winner glows mint once the poll closes.
struct WhisperLivePollCard: View {
    let poll: WhisperLivePollService.Poll
    let counts: [Int]
    let myVote: Int?
    let canClose: Bool
    let onVote: (Int) -> Void
    let onClose: () -> Void

    private var mint: Color { WhisperEmberPillPalette.glow }
    private var isClosed: Bool { poll.closed_at != nil }
    private var total: Int { counts.reduce(0, +) }
    private var winnerIndex: Int? {
        guard isClosed, total > 0, let maxVal = counts.max() else { return nil }
        return counts.firstIndex(of: maxVal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(poll.question)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Poll by @\(poll.creator_username) \u{00B7} \(total) vote\(total == 1 ? "" : "s")\(isClosed ? " \u{00B7} Final" : "")")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                if canClose {
                    Button {
                        Haptics.tap()
                        onClose()
                    } label: {
                        Text("Close")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 5) {
                ForEach(Array(poll.options.enumerated()), id: \.offset) { idx, option in
                    optionRow(idx: idx, option: option)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(mint.opacity(isClosed ? 0.20 : 0.40), lineWidth: 1)
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func optionRow(idx: Int, option: String) -> some View {
        let count = idx < counts.count ? counts[idx] : 0
        let share = total > 0 ? Double(count) / Double(total) : 0
        let picked = myVote == idx
        let isWinner = winnerIndex == idx
        let showBars = myVote != nil || isClosed
        return Button {
            guard !isClosed, myVote == nil else { return }
            Haptics.tap()
            onVote(idx)
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.10))
                if showBars {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isWinner || picked ? mint.opacity(0.45) : .white.opacity(0.14))
                            .frame(width: max(0, geo.size.width * share))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: share)
                    }
                }
                HStack(spacing: 6) {
                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(mint)
                    }
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(mint)
                    }
                    Text(option)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if showBars {
                        Text("\(Int((share * 100).rounded()))%")
                            .font(.system(size: 9, weight: .black).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isClosed || myVote != nil)
    }
}

// MARK: - Poll creator sheet

/// Host/coach/creator/recruiter tool — spin up a poll for the room.
struct WhisperLivePollCreatorSheet: View {
    let roomID: String
    @Environment(\.dismiss) private var dismiss
    @State private var question: String = ""
    @State private var options: [String] = ["", ""]
    @State private var starting: Bool = false

    private var mint: Color { WhisperEmberPillPalette.glow }
    private var canStart: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty &&
        options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QUESTION")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        TextField("What should we train next?", text: $question, axis: .vertical)
                            .font(.subheadline)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("OPTIONS")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        ForEach(options.indices, id: \.self) { idx in
                            HStack(spacing: 8) {
                                TextField("Option \(idx + 1)", text: $options[idx])
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                                if options.count > 2 {
                                    Button {
                                        Haptics.tap()
                                        options.remove(at: idx)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if options.count < 4 {
                            Button {
                                Haptics.tap()
                                options.append("")
                            } label: {
                                Label("Add option", systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(mint)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }

                    Button {
                        guard canStart, !starting else { return }
                        Haptics.tap()
                        starting = true
                        Task {
                            await WhisperLivePollService.shared.create(
                                roomID: roomID,
                                question: question,
                                options: options
                            )
                            starting = false
                            Haptics.success()
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if starting { ProgressView().tint(.black) }
                            Text("Start poll")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canStart ? mint : mint.opacity(0.4), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart || starting)

                    Text("Everyone in the room votes live \u{2014} results show on iPhone and the web.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .navigationTitle("New poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
