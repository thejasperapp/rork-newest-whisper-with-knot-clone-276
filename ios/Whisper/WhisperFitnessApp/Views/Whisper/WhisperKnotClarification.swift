import SwiftUI

/// Display-only choices. They never carry a command, consent or approval.
nonisolated struct WhisperKnotClarification: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let sourceMessageID: UUID
    let conversationID: UUID
    let bot: String
    let question: String
    let options: [String]

    func belongs(to conversationID: UUID, bot: String, text: String) -> Bool {
        valid && self.conversationID == conversationID && self.bot == bot && question == text
    }

    func composedAnswer(source: String, answer: String) -> String? {
        guard valid, !answer.isEmpty, answer == answer.trimmingCharacters(in: .whitespacesAndNewlines), answer.count <= 500, answer.utf16.count <= 1000 else { return nil }
        let message = "Original request: \(source)\nClarifying question: \(question)\nMy answer: \(answer)"
        return message.utf16.count <= 16000 ? message : nil
    }

    var valid: Bool {
        func plain(_ text: String, limit: Int) -> Bool {
            !text.isEmpty && text == text.trimmingCharacters(in: .whitespacesAndNewlines) && text.utf16.count <= limit &&
                !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) && !text.contains("`")
        }
        let readableQuestion = !question.isEmpty && question == question.trimmingCharacters(in: .whitespacesAndNewlines) && question.utf16.count <= 2400 &&
            !question.unicodeScalars.contains(where: { CharacterSet.controlCharacters.subtracting(.newlines).contains($0) }) && !question.contains("`")
        return readableQuestion && (0...4).contains(options.count) && options.allSatisfy { plain($0, limit: 100) } &&
            Set(options.map { $0.lowercased() }).count == options.count
    }
}

@MainActor final class WhisperKnotClarificationCapture {
    var value: WhisperKnotClarification?
}

struct WhisperKnotClarificationCard: View {
    let clarification: WhisperKnotClarification
    let enabled: Bool
    var savedAnswer: String? = nil
    var answer: (String) -> Bool
    @State private var localSelection: String?
    private var selected: String? { savedAnswer ?? localSelection }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var custom = ""
    @State private var showCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(clarification.options, id: \.self) { option in
                Button {
                    guard enabled, selected == nil else { return }
                    if answer(option) { localSelection = option; Haptics.tap() }
                } label: {
                    HStack(spacing: 12) {
                        Text(option).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if selected == option { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary) }
                    }
                    .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .background(Color.primary.opacity(selected == option ? 0.05 : 0.025), in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(
                            Color.primary.opacity(selected == option ? 0.85 : 0.20),
                            style: StrokeStyle(lineWidth: selected == option ? 1.5 : 1,
                                               dash: selected != nil && selected != option ? [5, 4] : []))
                    }
                    .opacity(selected != nil && selected != option ? 0.45 : 1)
                    .accessibilityAddTraits(selected == option ? .isSelected : [])
                    .contentShape(.rect)
                }.buttonStyle(.plain).disabled(!enabled || selected != nil)
            }
            if let selected, !clarification.options.contains(selected) {
                HStack(spacing: 12) {
                    Text(selected).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.subheadline.weight(.medium)).padding(14)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5) }
                .accessibilityAddTraits(.isSelected)
            }
            if enabled && selected == nil {
                if showCustom {
                    TextField("Your answer", text: $custom, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                        .onChange(of: custom) { _, value in if value.count > 500 { custom = String(value.prefix(500)) } }
                    Button("Send answer") {
                        let value = custom.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, value.count <= 500, selected == nil else { return }
                        if answer(value) { localSelection = value; Haptics.tap() }
                    }.buttonStyle(.borderedProminent).disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Something else…") { showCustom = true }.font(.subheadline).frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: 390, alignment: .leading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: selected)
        .accessibilityElement(children: .contain)
    }
}
