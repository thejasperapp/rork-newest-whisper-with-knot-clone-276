import SwiftUI

/// Reusable abuse-report sheet. Presented from profiles, posts, stories, DMs.
struct WhisperReportSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let kind: WhisperReportTargetKind
    let targetID: String?
    let targetUserID: String?
    let targetUsername: String?

    @State private var blocks = WhisperBlockService.shared
    @State private var selected: WhisperReportReason?
    @State private var details: String = ""
    @State private var submitting: Bool = false
    @State private var submitted: Bool = false
    @State private var submitError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        reasonList
                        if selected != nil {
                            detailsField
                        }
                        if let submitError { Text(submitError).font(.footnote).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                        submitButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                if submitted {
                    confirmation
                        .transition(.opacity)
                }
            }
            .navigationTitle("Report \(kind.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's wrong with this \(kind.label)?")
                .font(.title3.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            if let name = targetUsername {
                Text("@\(name)")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Text("Reports are private to you and authorized reviewers, not anonymous to the moderation team. Add useful context or supporting source links. Review times vary.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    private var reasonList: some View {
        VStack(spacing: 0) {
            ForEach(WhisperReportReason.allCases) { reason in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.25)) { selected = reason }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: reason.icon)
                            .font(.body)
                            .frame(width: 22)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text(reason.label)
                            .font(.body)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Spacer()
                        if selected == reason {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if reason != WhisperReportReason.allCases.last {
                    Rectangle()
                        .fill(WhisperTheme.hairline(colorScheme))
                        .frame(height: 0.5)
                        .padding(.leading, 50)
                }
            }
        }
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var detailsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add context (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            ZStack(alignment: .topLeading) {
                if details.isEmpty {
                    Text("Anything our reviewers should know")
                        .font(.body)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.top, 12)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $details)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(8)
                    .frame(minHeight: 100)
            }
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
        }
    }

    private var submitButton: some View {
        Button {
            guard let reason = selected else { return }
            Task { await submit(reason: reason) }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().tint(WhisperTheme.surface(colorScheme)) }
                Text("Submit report")
                    .font(.body.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                (selected == nil ? WhisperTheme.muted(colorScheme) : WhisperTheme.ink(colorScheme)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(selected == nil || submitting)
    }

    private var confirmation: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Thanks for letting us know")
                .font(.title3.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Your report was received for review. Review times vary.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 32)
        }
        .padding(28)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 32)
    }

    private func submit(reason: WhisperReportReason) async {
        guard !submitting else { return }
        submitting = true
        submitError = nil
        let generation = AccountStorage.generation
        let ok = await blocks.report(
            kind: kind,
            targetID: targetID,
            targetUserID: targetUserID,
            targetUsername: targetUsername,
            reason: reason,
            details: details
        )
        guard generation == AccountStorage.generation, !Task.isCancelled else { return }
        submitting = false
        if ok {
            Haptics.success()
            withAnimation { submitted = true }
            try? await Task.sleep(for: .seconds(1.5))
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            dismiss()
        } else {
            submitError = "Your report wasn’t sent. Your details are still here; please try again."
            Haptics.warning()
        }
    }
}
