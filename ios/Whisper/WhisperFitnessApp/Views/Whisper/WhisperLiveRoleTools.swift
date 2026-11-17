import SwiftUI

// MARK: - Coach tools sheet

struct CoachToolsSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let roomID: String
    let userID: String
    let username: String
    let chatService: WhisperLiveChatService
    let onClose: () -> Void

    @State private var planName: String = ""
    @State private var focus: String = ""
    @State private var exercises: [(name: String, sets: String, reps: String)] = [("", "3", "10")]
    @State private var sending: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            Text("Training Plan")
                                .font(.title3.weight(.bold))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Plan name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    TextField("e.g. Push Day", text: $planName)
                                        .textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Focus").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    TextField("e.g. Strength", text: $focus)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Exercises")
                                .font(.subheadline.weight(.bold))
                            ForEach(exercises.indices, id: \.self) { i in
                                HStack(spacing: 8) {
                                    TextField("Exercise", text: Binding(
                                        get: { exercises[i].name },
                                        set: { exercises[i].name = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)

                                    TextField("Sets", text: Binding(
                                        get: { exercises[i].sets },
                                        set: { exercises[i].sets = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .keyboardType(.numberPad)

                                    TextField("Reps", text: Binding(
                                        get: { exercises[i].reps },
                                        set: { exercises[i].reps = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)

                                    if exercises.count > 1 {
                                        Button {
                                            exercises.remove(at: i)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            Button {
                                exercises.append(("", "3", "10"))
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add exercise")
                                }
                                .foregroundStyle(.green)
                                .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            Task { await sendPlan() }
                        } label: {
                            HStack {
                                if sending { ProgressView().tint(.white) }
                                Image(systemName: "paperplane.fill")
                                Text("Send to Room")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.green, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(sending)

                        Text("Viewers can save this plan to their Whisper with one tap.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Coach Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose(); dismiss() }
                }
            }
        }
    }

    private func sendPlan() async {
        let clean = exercises.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !planName.trimmingCharacters(in: .whitespaces).isEmpty, !clean.isEmpty else { return }
        sending = true
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "displayName": planName.trimmingCharacters(in: .whitespaces),
            "focus": focus.trimmingCharacters(in: .whitespaces).isEmpty ? "General" : focus.trimmingCharacters(in: .whitespaces),
            "durationSeconds": clean.count * 180,
            "calories": clean.count * 50,
            "exerciseNames": clean.map { $0.name.trimmingCharacters(in: .whitespaces) },
            "totalSets": clean.reduce(0) { $0 + (Int($1.sets) ?? 1) },
            "date": Date().timeIntervalSince1970,
        ]
        let embed = "::whisper-workout-v1::\(WhisperWorkoutEmbed.encodePayload(payload))"
        do {
            try await chatService.sendMessage(roomID: roomID, userID: userID, username: username, body: embed, isHost: false)
            onClose()
            dismiss()
        } catch {
            print("[CoachTools] send error: \(error)")
        }
        sending = false
    }
}

// MARK: - Creator tools sheet

struct CreatorToolsSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void

    private let reactions = ["❤️", "🔥", "👏", "🤯", "💯", "🎉"]

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(.purple)
                            Text("Creator Tools")
                                .font(.title3.weight(.bold))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Send floating reaction")
                                .font(.subheadline.weight(.bold))
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                                ForEach(reactions, id: \.self) { emoji in
                                    Button {
                                        Haptics.tap()
                                        WhisperLiveRTCService.shared.sendReaction(emoji)
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 32))
                                            .frame(width: 64, height: 64)
                                            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Screen Share", systemImage: "display")
                                .font(.subheadline.weight(.bold))
                            Text("Use the screen-share button in the live controls to broadcast your screen into the stage.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Q&A Mode", systemImage: "questionmark.bubble")
                                .font(.subheadline.weight(.bold))
                            Text("Coming soon — pin a question and highlight viewer answers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Creator Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose(); dismiss() }
                }
            }
        }
    }
}

// MARK: - Recruiter tools sheet

struct RecruiterToolsSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let roomID: String
    let speakers: [WhisperLiveSpeaker]
    let listenerCount: Int
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "target")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            Text("Recruiting Tools")
                                .font(.title3.weight(.bold))
                        }

                        // Live stats
                        HStack(spacing: 12) {
                            statCard(value: "\(listenerCount)", label: "Listeners")
                            statCard(value: "\(speakers.count)", label: "On Stage")
                            statCard(value: "\(pendingRequests)", label: "Requests")
                        }

                        // Talent spotlight with roles
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                Text("Talent Spotlight")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.secondary)

                            ForEach(speakers.prefix(5), id: \.user_id) { speaker in
                                talentCard(speaker)
                            }

                            if speakers.isEmpty {
                                Text("No speakers yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            }
                        }

                        // Quick invite button
                        Button {
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                Text("Invite from Audience")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.orange, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        // Evaluation notes
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Evaluation Notes", systemImage: "clipboard")
                                .font(.subheadline.weight(.bold))
                            Text("Rate talent with private notes and star ratings. Tap a speaker above to open their evaluation form.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Recruiting Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose(); dismiss() }
                }
            }
        }
    }

    private var pendingRequests: Int {
        // Placeholder — the real count comes from the parent view.
        0
    }

    private func talentCard(_ speaker: WhisperLiveSpeaker) -> some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: speaker.user_id, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(speaker.user_id.prefix(8)) + "...")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    if speaker.is_host {
                        rolePill("Host", color: .green)
                    }
                    if speaker.is_cohost {
                        rolePill("Co-host", color: .blue)
                    }
                }
            }
            Spacer()
            // Star rating
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.3))
                }
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 12))
    }

    private func rolePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.85), in: Capsule())
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.weight(.black))
                .foregroundStyle(.orange)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Flow layout helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}
