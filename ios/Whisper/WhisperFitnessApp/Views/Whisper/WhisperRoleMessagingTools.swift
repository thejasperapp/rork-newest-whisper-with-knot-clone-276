import SwiftUI

/// The roles that get a dedicated messaging toolkit inside the briefcase.
/// Each role ships with its own seeded quick-reply templates tuned to how
/// that role actually talks — coaches nudging clients, creators handling
/// collab inquiries, athletes replying to scouts, brands running outreach.
enum WhisperMessagingRole: String, CaseIterable, Identifiable {
    case coach, creator, athlete, brand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: return "Coach messaging"
        case .creator: return "Creator messaging"
        case .athlete: return "Athlete messaging"
        case .brand: return "Brand messaging"
        }
    }

    var icon: String {
        switch self {
        case .coach: return "person.2.fill"
        case .creator: return "chart.line.uptrend.xyaxis"
        case .athlete: return "trophy.fill"
        case .brand: return "briefcase.fill"
        }
    }

    var blurb: String {
        switch self {
        case .coach: return "Templates for check-ins, plan follow-ups, and payment nudges — send in two taps."
        case .creator: return "Ready replies for collab inquiries, sponsorship terms, and fan messages."
        case .athlete: return "Quick responses for scouts, meet updates, and sponsorship conversations."
        case .brand: return "Outreach and deal-flow templates for messaging creators and athletes."
        }
    }

    /// Starter templates seeded the first time the toolkit opens.
    var seededReplies: [String] {
        switch self {
        case .coach:
            return [
                "Hey! Checking in — how did this week's sessions go? Anything feel too easy or too heavy?",
                "Great work this week. I've reviewed your log and I'm adjusting next week's plan tonight.",
                "Friendly reminder — your monthly coaching payment is due this week. Let me know if anything's up.",
                "Send me a quick form-check video of your top set when you get a chance.",
            ]
        case .creator:
            return [
                "Thanks for reaching out! I'd love to hear more — what's the deliverable, timeline, and budget?",
                "Appreciate the offer! My sponsored-post rate starts at the terms on my profile. Open to discussing scope.",
                "Thank you so much for the support — it genuinely means a lot!",
                "I only promote products I've actually used. Happy to test it first and go from there.",
            ]
        case .athlete:
            return [
                "Thanks for the interest! Here's my athlete card — happy to share meet results and PRs.",
                "My next competition is coming up — I'll send results right after.",
                "I'm open to sponsorship conversations. What terms did you have in mind?",
                "Appreciate you following my journey — more training updates coming this week.",
            ]
        case .brand:
            return [
                "Hi! We love your content and think you'd be a great fit for our brand. Open to a sponsorship?",
                "Thanks for applying! We're reviewing your profile and will follow up with terms shortly.",
                "Quick reminder — your deliverable is due this week. Let us know if you need anything.",
                "Payment has been released from escrow — thanks for a great collaboration!",
            ]
        }
    }
}

/// Per-role quick-reply templates, persisted on device. Seeds each role's
/// starter set on first read; edits/deletes/additions stick across
/// launches.
@Observable
@MainActor
final class WhisperQuickReplyStore {
    static let shared = WhisperQuickReplyStore()

    private static let key = "whisper.roleQuickReplies.v2"
    private var storage: [String: [String]]

    private init() {
        let raw = AccountStorage.data(forKey: Self.key)
        storage = raw.flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
    }

    func reloadForCurrentAccount() {
        // Legacy device-wide templates have no reliable owner. Leave them
        // untouched rather than assigning private text to a new account.
        storage = AccountStorage.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
    }

    func replies(for role: WhisperMessagingRole) -> [String] {
        if let existing = storage[role.rawValue] { return existing }
        return role.seededReplies
    }

    func add(_ text: String, for role: WhisperMessagingRole) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = replies(for: role)
        list.insert(trimmed, at: 0)
        storage[role.rawValue] = list
        persist()
    }

    func remove(at index: Int, for role: WhisperMessagingRole) {
        var list = replies(for: role)
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        storage[role.rawValue] = list
        persist()
    }

    func update(at index: Int, text: String, for role: WhisperMessagingRole) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = replies(for: role)
        guard list.indices.contains(index) else { return }
        list[index] = trimmed
        storage[role.rawValue] = list
        persist()
    }

    func resetToDefaults(for role: WhisperMessagingRole) {
        storage[role.rawValue] = nil
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(storage) {
            AccountStorage.set(data, forKey: Self.key)
        }
    }
}

/// Full-screen messaging toolkit for one role — quick-reply templates the
/// user can send straight into a DM (recipient picker), copy, edit,
/// delete, or extend. Opened from the role sections in the briefcase.
struct WhisperRoleMessagingToolsView: View {
    let role: WhisperMessagingRole

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var store = WhisperQuickReplyStore.shared
    @State private var newTemplate: String = ""
    @State private var sendPayload: SendTarget?
    @State private var editing: EditTarget?
    @State private var copiedIndex: Int?
    @FocusState private var composerFocused: Bool

    private struct SendTarget: Identifiable {
        let id = UUID()
        let text: String
    }

    private struct EditTarget: Identifiable {
        let id = UUID()
        let index: Int
        let text: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        addTemplateField
                        templatesList
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(role.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            Haptics.tap()
                            store.resetToDefaults(for: role)
                        } label: {
                            Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                }
            }
            .sheet(item: $sendPayload) { target in
                WhisperPickRecipientSheet(payload: target.text) {
                    sendPayload = nil
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $editing) { target in
                editSheet(target)
                    .presentationDetents([.height(260)])
                    .presentationDragIndicator(.visible)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            newTemplate = ""; sendPayload = nil; editing = nil; copiedIndex = nil
            dismiss()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: role.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 44, height: 44)
                .background(WhisperTheme.card(colorScheme), in: Circle())
            Text(role.blurb)
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.surface(colorScheme))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Add template

    private var addTemplateField: some View {
        HStack(spacing: 10) {
            TextField("Write a new quick reply…", text: $newTemplate, axis: .vertical)
                .focused($composerFocused)
                .font(.subheadline)
                .lineLimit(1...4)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Button {
                Haptics.success()
                store.add(newTemplate, for: role)
                newTemplate = ""
                composerFocused = false
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(width: 32, height: 32)
                    .background(WhisperTheme.ink(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(newTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(newTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
            .accessibilityLabel("Add quick reply")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
    }

    // MARK: - Templates

    private var templatesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick replies")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)
            VStack(spacing: 10) {
                ForEach(Array(store.replies(for: role).enumerated()), id: \.offset) { index, text in
                    templateRow(index: index, text: text)
                }
            }
        }
    }

    private func templateRow(index: Int, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    sendPayload = SendTarget(text: text)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    UIPasteboard.general.string = text
                    withAnimation(.spring(response: 0.3)) { copiedIndex = index }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        await MainActor.run {
                            withAnimation { if copiedIndex == index { copiedIndex = nil } }
                        }
                    }
                } label: {
                    Label(copiedIndex == index ? "Copied" : "Copy", systemImage: copiedIndex == index ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button {
                        Haptics.tap()
                        editing = EditTarget(index: index, text: text)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) {
                            store.remove(at: index, for: role)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 32, height: 28)
                        .contentShape(.rect)
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.surface(colorScheme))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Edit sheet

    private func editSheet(_ target: EditTarget) -> some View {
        EditTemplateSheet(initialText: target.text) { updated in
            store.update(at: target.index, text: updated, for: role)
            editing = nil
        }
    }
}

/// Small edit form for one quick-reply template.
private struct EditTemplateSheet: View {
    let initialText: String
    let onSave: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit quick reply")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.top, 18)
            TextField("Quick reply", text: $text, axis: .vertical)
                .focused($focused)
                .font(.subheadline)
                .lineLimit(3...6)
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            Button {
                Haptics.success()
                onSave(text)
            } label: {
                Text("Save")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .onAppear {
            text = initialText
            focused = true
        }
    }
}
