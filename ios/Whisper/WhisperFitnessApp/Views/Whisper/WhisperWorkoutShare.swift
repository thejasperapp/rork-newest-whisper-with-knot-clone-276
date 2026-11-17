import SwiftUI
import UIKit
import Supabase
import Auth

/// Encodes/decodes a `WorkoutSessionRecord` summary inside a DM message body so
/// users can send a workout card inline in chat — and the recipient can save it
/// to their Whisper with one tap. The prefix is unique enough that plain text
/// can never collide.
enum WhisperWorkoutEmbed {
    static let prefix = "::whisper-workout-v1::"

    /// One set inside the optional full-detail embed — keeps the JSON compact.
    nonisolated struct SetDetail: Codable, Sendable, Hashable {
        /// Weight in the lifter's working unit.
        let w: Double
        /// Reps performed.
        let r: Int
    }

    /// Full per-exercise detail so "Save to Whisper" preserves real sets,
    /// reps and weights instead of zeroed placeholders. Optional so old
    /// payloads (and the web client, which ignores extra fields) keep working.
    nonisolated struct ExerciseDetail: Codable, Sendable, Hashable {
        let name: String
        let sets: [SetDetail]
    }

    nonisolated struct Payload: Codable, Sendable, Hashable {
        let id: String
        let displayName: String
        let focus: String
        let durationSeconds: Int
        let calories: Int
        let exerciseNames: [String]
        let totalSets: Int
        let date: TimeInterval
        /// Optional full-detail exercises (added later — old embeds omit it).
        var exercises: [ExerciseDetail]?

        var dateValue: Date { Date(timeIntervalSince1970: date) }
    }

    static func encode(_ w: WorkoutSessionRecord) -> String {
        let payload = Payload(
            id: w.id.uuidString,
            displayName: w.displayName,
            focus: w.focus,
            durationSeconds: Int(w.duration),
            calories: Int(w.caloriesBurned),
            exerciseNames: w.exercises.map { $0.exerciseName },
            totalSets: w.exercises.reduce(0) { $0 + $1.sets.count },
            date: w.date.timeIntervalSince1970,
            exercises: w.exercises.map { ex in
                ExerciseDetail(
                    name: ex.exerciseName,
                    sets: ex.sets.map { SetDetail(w: $0.weight, r: $0.reps) }
                )
            }
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return payload
    }

    /// Encode a dictionary payload directly (for coach training plans in live rooms).
    static func encodePayload(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }
}

// MARK: - Inline (chat-bubble / feed) card

/// Compact workout card — used inline in DM bubbles and as a tappable preview.
struct WhisperWorkoutInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperWorkoutEmbed.Payload
    let mine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "dumbbell.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .frame(width: 30, height: 30)
                    .background(
                        (mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                            .opacity(0.92),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workout")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .opacity(0.7)
                    Text(payload.displayName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                stat(value: "\(payload.durationSeconds / 60)", unit: "min")
                stat(value: "\(payload.calories)", unit: "cal")
                stat(value: "\(payload.totalSets)", unit: "sets")
            }
            if !payload.exerciseNames.isEmpty {
                Text(payload.exerciseNames.prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .lineLimit(1)
                    .opacity(0.8)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption2.weight(.bold))
                Text("Tap to save to Whisper")
                    .font(.caption2.weight(.semibold))
            }
            .opacity(0.7)
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
        .background(
            (mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme)),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    mine ? WhisperTheme.ink(colorScheme).opacity(0.001) : WhisperTheme.hairline(colorScheme),
                    lineWidth: 1
                )
        }
    }

    private func stat(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.subheadline.weight(.heavy))
            Text(unit).font(.caption2.weight(.semibold)).opacity(0.7)
        }
    }
}

// MARK: - Story / shareable card (9:16)

/// Full-bleed 9:16 workout card used to render a story image users can post.
/// Designed so `ImageRenderer` produces a clean shareable PNG.
struct WhisperWorkoutStoryCard: View {
    let record: WorkoutSessionRecord
    let username: String
    /// When true, render the white-on-black variant (use in light mode).
    /// When false, render black-on-white (use in dark mode).
    var inverted: Bool = true

    private var bg: Color { inverted ? .black : .white }
    private var fg: Color { inverted ? .white : .black }
    private var hair: Color { fg.opacity(0.12) }
    private var mute: Color { fg.opacity(0.55) }

    var body: some View {
        ZStack {
            bg

            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    WhisperAvatar(username: username, size: 38, ring: false)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("@\(username)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(fg)
                        Text("logged a workout")
                            .font(.caption2)
                            .foregroundStyle(mute)
                    }
                    Spacer()
                    Text("WHISPER")
                        .font(.system(size: 10, weight: .black))
                        .tracking(3)
                        .foregroundStyle(mute)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(record.focus.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(2)
                        .foregroundStyle(mute)
                    Text(record.displayName)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(fg)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                }

                HStack(spacing: 18) {
                    statBlock(value: "\(Int(record.duration / 60))", unit: "MIN")
                    Rectangle().fill(hair).frame(width: 0.5, height: 36)
                    statBlock(value: "\(Int(record.caloriesBurned))", unit: "CAL")
                    Rectangle().fill(hair).frame(width: 0.5, height: 36)
                    statBlock(value: "\(record.exercises.reduce(0) { $0 + $1.sets.count })", unit: "SETS")
                }

                if !record.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(record.exercises.count) exercises")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(mute)
                            .tracking(1.4)
                        ForEach(record.exercises.prefix(6)) { ex in
                            HStack(alignment: .firstTextBaseline) {
                                Text(ex.exerciseName)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(fg)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(ex.sets.count) × \(ex.targetReps)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(mute)
                            }
                            Rectangle().fill(hair).frame(height: 0.5)
                        }
                        if record.exercises.count > 6 {
                            Text("+ \(record.exercises.count - 6) more")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(mute)
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.bold))
                    Text("Save to Whisper")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(bg)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(fg, in: Capsule())
            }
            .padding(32)
        }
        .frame(width: 360, height: 640)
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(hair, lineWidth: 0.5)
        }
    }

    private func statBlock(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(fg)
            Text(unit)
                .font(.caption2.weight(.heavy))
                .tracking(2)
                .foregroundStyle(mute)
        }
    }
}

// MARK: - Share sheet

/// Bottom sheet shown when the user taps a workout — lets them post it to
/// their story, send it as a DM, or just copy the share image.
struct WhisperShareWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let record: WorkoutSessionRecord

    @State private var stories = WhisperStoryService.shared
    @State private var posting: Bool = false
    @State private var posted: Bool = false
    @State private var error: String?
    @State private var presentRecipientPicker: Bool = false

    private var username: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        cardPreview
                            .padding(.top, 8)
                        actionList
                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Share workout")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .sheet(isPresented: $presentRecipientPicker) {
                WhisperPickRecipientSheet(payload: WhisperWorkoutEmbed.encode(record)) {
                    presentRecipientPicker = false
                    dismiss()
                }
            }
        }
    }

    /// Light mode → black card. Dark mode → white card.
    private var invertedForCurrentScheme: Bool {
        colorScheme == .light
    }

    private var cardPreview: some View {
        // Scale the fixed 360×640 export canvas down to a preview that fits
        // the screen — tighter on compact phones (SE / mini) so the action
        // list stays above the fold. The export image itself stays 360×640.
        let bounds = UIScreen.main.bounds
        let scale = min(
            0.62,
            (bounds.width - 48) / 360,
            (bounds.height * 0.47) / 640
        )
        return WhisperWorkoutStoryCard(
            record: record,
            username: username,
            inverted: invertedForCurrentScheme
        )
        .scaleEffect(scale)
        .frame(width: 360 * scale, height: 640 * scale)
        .frame(maxWidth: .infinity)
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            actionRow(icon: "plus.square.on.square", title: posted ? "Posted to your story" : "Add to your story", subtitle: "24-hour ephemeral story", busy: posting) {
                Task { await postStory() }
            }
            divider
            actionRow(icon: "paperplane.fill", title: "Send in a DM", subtitle: "Pick a friend") {
                Haptics.tap()
                presentRecipientPicker = true
            }
            divider
            actionRow(icon: "square.and.arrow.down.fill", title: "Save card to Photos", subtitle: "Saves the workout card as an image") {
                saveToPhotos()
            }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    private func actionRow(icon: String, title: String, subtitle: String, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(WhisperTheme.ink(colorScheme))
                        .frame(width: 36, height: 36)
                    if busy {
                        ProgressView().tint(WhisperTheme.surface(colorScheme))
                    } else {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(subtitle).font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    @MainActor
    private func renderCardImage() -> UIImage? {
        let view = WhisperWorkoutStoryCard(
            record: record,
            username: username,
            inverted: invertedForCurrentScheme
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    private func postStory() async {
        guard let image = renderCardImage() else {
            error = "Couldn't render the workout card."
            return
        }
        posting = true
        defer { posting = false }
        _ = await stories.postStory(image: image, caption: record.displayName)
        await stories.fetch()
        Haptics.success()
        posted = true
        try? await Task.sleep(for: .seconds(1.2))
        dismiss()
    }

    private func saveToPhotos() {
        guard let image = renderCardImage() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Recipient picker for DM

/// Existing forwarding entry points share the compact multi-recipient tray.
struct WhisperPickRecipientSheet: View {
    let payload: String
    var onSent: () -> Void

    var body: some View {
        WhisperRecipientShareSheet(payload: payload, onSent: onSent) { EmptyView() }
    }
}

// MARK: - Save to Whisper

/// Adds a workout payload to the local `workoutSessionHistory` blob, then
/// triggers the Supabase sync so it shows up across the user's devices.
enum WhisperWorkoutImport {
    enum SaveResult {
        case saved
        case alreadySaved
        case failed
    }

    /// Save a shared workout into Whisper's history. Returns whether it was
    /// saved, already existed, or failed — so callers can show real feedback.
    @MainActor
    @discardableResult
    static func saveToWhisper(_ payload: WhisperWorkoutEmbed.Payload) -> SaveResult {
        let id = UUID(uuidString: payload.id) ?? UUID()

        // Prefer the full-detail exercise list (real sets/reps/weights) when
        // the embed carries it; fall back to single-set name placeholders for
        // old embeds that only shipped exercise names.
        let exercises: [ExerciseLog]
        if let detail = payload.exercises, !detail.isEmpty {
            exercises = detail.map { ex in
                ExerciseLog(
                    id: UUID(),
                    exerciseName: ex.name,
                    sets: ex.sets.isEmpty
                        ? [SetLog(id: UUID(), weight: 0, reps: 0, isComplete: true)]
                        : ex.sets.map { SetLog(id: UUID(), weight: $0.w, reps: $0.r, isComplete: true) },
                    targetSets: max(1, ex.sets.count),
                    targetReps: ex.sets.first.map { "\($0.r)" } ?? "—",
                    restSeconds: 60,
                    userNotes: "Saved from Whisper"
                )
            }
        } else {
            exercises = payload.exerciseNames.map { name in
                ExerciseLog(
                    id: UUID(),
                    exerciseName: name,
                    sets: [SetLog(id: UUID(), weight: 0, reps: 0, isComplete: true)],
                    targetSets: 1,
                    targetReps: "—",
                    restSeconds: 60,
                    userNotes: "Saved from Whisper"
                )
            }
        }

        let record = WorkoutSessionRecord(
            id: id,
            programId: UUID(),
            dayName: payload.displayName,
            focus: payload.focus,
            date: payload.dateValue,
            duration: TimeInterval(payload.durationSeconds),
            exercises: exercises,
            averageHeartRate: 0,
            peakHeartRate: 0,
            heartRateTimeline: [],
            caloriesBurned: Double(payload.calories),
            avgOxygenSaturation: 0,
            customName: nil
        )

        var history: [WorkoutSessionRecord] = []
        if let data = AccountStorage.data(forKey: "workoutSessionHistory") {
            if let decoded = try? JSONDecoder().decode([WorkoutSessionRecord].self, from: data) {
                history = decoded
            } else if !data.isEmpty {
                // Corrupt blob — don't silently wipe the user's history.
                print("[WhisperWorkoutImport] workoutSessionHistory blob failed to decode")
                return .failed
            }
        }

        if history.contains(where: { $0.id == record.id }) {
            Haptics.tap()
            return .alreadySaved
        }

        history.insert(record, at: 0)
        guard let encoded = try? JSONEncoder().encode(history) else {
            return .failed
        }
        AccountStorage.set(encoded, forKey: "workoutSessionHistory")
        Haptics.success()

        // Mirror the updated blob to Supabase immediately so the workout
        // appears in Whisper on every device — not just this one.
        let uid = SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased()
            ?? AccountStorage.currentUserID.lowercased()
        Task {
            await SupabaseSyncService.shared.pushBlob(
                userID: uid,
                storageKey: "workoutSessionHistory"
            )
        }
        return .saved
    }
}
