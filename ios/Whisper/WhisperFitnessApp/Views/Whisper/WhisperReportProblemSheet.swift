import Supabase
import SwiftUI
import UIKit

/// Settings → "Report a problem" — an IN-APP report (never an email hand-off).
/// Category tiles, what happened, and one Send that writes the report through
/// `whisper_submit_report` (supabase/reports.sql). Reports about a person go
/// through the dating/safety report sheet; this one is for bugs, content,
/// account, payments, safety, and anything else.
struct WhisperReportProblemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private struct Category: Identifiable {
        let id: String
        let label: String
        let icon: String
        let hint: String
    }

    private static let categories: [Category] = [
        Category(id: "bug", label: "Something's broken", icon: "ladybug.fill", hint: "A screen, button, or feature isn't working."),
        Category(id: "content", label: "A post or message", icon: "text.bubble.fill", hint: "Content that shouldn't be on Whisper."),
        Category(id: "account", label: "My account", icon: "person.crop.circle.badge.exclamationmark", hint: "Login, badges, roles, or profile trouble."),
        Category(id: "payment", label: "A payment", icon: "creditcard.fill", hint: "A charge, refund, or payout question."),
        Category(id: "safety", label: "Safety", icon: "shield.lefthalf.filled", hint: "Harassment, threats, or someone at risk."),
        Category(id: "other", label: "Something else", icon: "ellipsis.circle.fill", hint: "Anything that doesn't fit above."),
    ]

    @State private var category: String = "bug"
    @State private var details: String = ""
    @State private var includeDevice: Bool = true
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var failed: Bool = false
    @State private var copiedSupport: Bool = false

    private let mint: Color = Color(red: 0.16, green: 0.72, blue: 0.45)
    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var canSend: Bool {
        details.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 && !sending
    }
    private var currentHint: String {
        Self.categories.first(where: { $0.id == category })?.hint ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    if sent {
                        sentState
                    } else {
                        form
                    }
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What's going on?")
                .font(.title3.weight(.heavy))
                .foregroundStyle(ink)

            categoryGrid

            Text(currentHint)
                .font(.footnote)
                .foregroundStyle(muted)

            detailsField

            deviceToggle

            if failed {
                failureNote
            }

            sendButton

            Text("Reports go straight to the Whisper team inside the app. Safety reports are read first.")
                .font(.caption2)
                .foregroundStyle(muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(18)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Self.categories) { item in
                categoryTile(item)
            }
        }
    }

    private func categoryTile(_ item: Category) -> some View {
        let selected = category == item.id
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            Haptics.tap()
            category = item.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(selected ? Color.white : mint)
                Text(item.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? Color.white : ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(shape.fill(selected ? mint : WhisperTheme.card(colorScheme)))
            .overlay(shape.strokeBorder(selected ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var detailsField: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return TextField("Tell us what happened — the more detail, the faster we can fix it.", text: $details, axis: .vertical)
            .lineLimit(4...9)
            .font(.subheadline)
            .padding(12)
            .background(WhisperTheme.card(colorScheme), in: shape)
            .overlay(shape.strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1))
    }

    private var deviceToggle: some View {
        Toggle(isOn: $includeDevice) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include app & device info")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text("App version, iOS version, and device model — nothing personal.")
                    .font(.caption)
                    .foregroundStyle(muted)
            }
        }
        .tint(mint)
    }

    private var failureNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't send the report. Check your connection and try again.")
                .font(.caption)
                .foregroundStyle(.red)
            Button {
                UIPasteboard.general.string = "support@mydailywhisper.com"
                copiedSupport = true
                Haptics.success()
            } label: {
                Text(copiedSupport ? "Support address copied" : "Copy the support address instead")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(mint)
            }
            .buttonStyle(.plain)
        }
    }

    private var sendButton: some View {
        Button {
            Haptics.tap()
            send()
        } label: {
            HStack(spacing: 8) {
                if sending { ProgressView().tint(.white) }
                Text("Send report")
                    .font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(canSend ? mint : mint.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private var sentState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42))
                .foregroundStyle(mint)
            Text("Thanks — we've got it")
                .font(.title3.weight(.heavy))
                .foregroundStyle(ink)
            Text("The team reads every report. If we need more, we'll message you in Whisper.")
                .font(.footnote)
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Send

    private func send() {
        sending = true
        failed = false
        let context: [String: String] = includeDevice ? Self.deviceContext() : [:]
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = category
        Task {
            let ok = await WhisperProblemReports.submit(kind: kind, details: text, context: context)
            await MainActor.run {
                sending = false
                failed = !ok
                if ok {
                    Haptics.success()
                    withAnimation(.spring(response: 0.3)) { sent = true }
                }
            }
        }
    }

    private static func deviceContext() -> [String: String] {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return [
            "app": "ios \(version) (\(build))",
            "os": "iOS \(UIDevice.current.systemVersion)",
            "device": UIDevice.current.model,
        ]
    }
}

/// The in-app problem report rail — `whisper_submit_report` (supabase/reports.sql).
enum WhisperProblemReports {
    @MainActor
    static func submit(kind: String, details: String, context: [String: String]) async -> Bool {
        nonisolated struct Params: Encodable, Sendable {
            let p_kind: String
            let p_reason: String
            let p_details: String?
            let p_target_username: String?
            let p_target_id: String?
            let p_context: [String: String]
        }
        do {
            let generation = AccountStorage.generation
            let receipt: UUID = try await SupabaseService.shared.client.rpc(
                "whisper_submit_report",
                params: Params(
                    p_kind: kind,
                    p_reason: kind,
                    p_details: details.isEmpty ? nil : details,
                    p_target_username: nil,
                    p_target_id: context["adId"],
                    p_context: context
                )
            ).execute().value
            guard generation == AccountStorage.generation else { return false }
            _ = receipt
            return true
        } catch {
            return false
        }
    }
}
