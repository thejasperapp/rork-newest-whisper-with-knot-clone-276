import SwiftUI

/// A personal reply mixer, visually related to Discover/Waves without sharing their data.
struct WhisperJasperTuningView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: WhisperJasperTuningViewModel = WhisperJasperTuningViewModel()
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var addTarget: AddTarget?
    @State private var addText: String = ""
    @State private var confirmReset: Bool = false

    private enum AddTarget: Identifiable {
        case more, less
        var id: String { self == .more ? "more" : "less" }
    }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }
    private let moreSuggestions: [String] = ["Practical steps", "Deeper explanations", "Creative ideas", "Encouragement", "Real examples", "Concise answers"]
    private let lessSuggestions: [String] = ["Jargon", "Long answers", "Follow-up questions", "Repeated advice"]

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { header }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    strengthCard
                    heroCard
                    mixerCard(less: false)
                    suggestions
                    mixerCard(less: true)
                    footer
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Tune your Knot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset", systemImage: "arrow.counterclockwise") { confirmReset = true }
                }
            }
        }
        .foregroundStyle(ink)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .whisperEdgeBack(isEnabled: !embedded, controller: backTransition) { close() }
        .accessibilityAction(.escape) { close() }
        .disabled(!model.isCurrentAccount)
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
            model.invalidate(); addText = ""; addTarget = nil
            dismiss()
        }
        .alert(addTarget == .less ? "Turn down" : "Turn up", isPresented: Binding(
            get: { addTarget != nil }, set: { if !$0 { addTarget = nil; addText = "" } }
        )) {
            TextField("Response style or topic", text: $addText)
            Button("Add") {
                model.add(addText, less: addTarget == .less)
                addTarget = nil; addText = ""
                Haptics.selection()
            }
            .disabled(addText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { addTarget = nil; addText = "" }
        } message: {
            Text("Guide how Knot answers you. Up to 8 choices per list, 80 characters each. This won't change your feed.")
        }
        .onChange(of: addText) { _, value in
            if value.count > WhisperJasperTuning.maxTermLength {
                addText = String(value.prefix(WhisperJasperTuning.maxTermLength))
            }
        }
        .confirmationDialog("Reset your Knot tuning?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset tuning", role: .destructive) { model.reset(); Haptics.selection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores balanced Knot replies. Your chats, drafts, connected data and feed tuning stay untouched.")
        }
        .alert("Change not saved", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "Please try again.") }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { close() } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain).accessibilityLabel("Back to Knot")
            VStack(alignment: .leading, spacing: 2) {
                Text("Tune your Knot").font(.headline)
                Text("Your intelligence, your way").font(.caption).foregroundStyle(muted)
            }
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Menu {
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Reset your tuning", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Image(systemName: "ellipsis").font(.headline)
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .accessibilityLabel("Knot tuning options")
        }
        .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 8)
    }

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tuning strength").font(.headline)
                Spacer()
                Text(model.preferences.strength, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().foregroundStyle(muted)
            }
            Slider(value: Binding(get: { model.preferences.strength }, set: { model.setStrength($0) }), in: 0...1, step: 0.05)
                .tint(.blue).accessibilityLabel("Knot tuning strength")
                .accessibilityIdentifier("jasper.tuning.strength")
            Text("How strongly your choices guide new replies. Zero pauses tuning without forgetting your choices.")
                .font(.caption).foregroundStyle(muted)
        }
        .modifier(WhisperKnotPanel())
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YOUR KNOT").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(muted)
                Spacer()
                WhisperEmberMascot(size: 42, expression: .attentive, usesIntelligenceStyle: true)
                    .frame(width: 46, height: 46)
            }
            Text(model.preferences.summary)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Label(model.preferences.strength == 0 ? "Tuning paused" : "Guided by your choices", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.medium)).foregroundStyle(muted)
        }
        .modifier(WhisperKnotPanel())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.preferences.summary)
    }

    private func mixerCard(less: Bool) -> some View {
        let terms = less ? model.preferences.lessOf : model.preferences.moreOf
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: less ? "arrow.down.right" : "arrow.up.right")
                    .foregroundStyle(less ? muted : Color.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(less ? "Turn down" : "Turn up").font(.headline)
                    Text(less ? "Less of what gets in your way." : "More of what makes an answer useful.")
                        .font(.caption).foregroundStyle(muted)
                }
            }
            .padding(16)
            if terms.isEmpty {
                Text(less ? "Nothing turned down yet." : "Start with a suggestion or add your own.")
                    .font(.subheadline).foregroundStyle(muted)
                    .padding(.horizontal, 16).padding(.bottom, 14)
            }
            ForEach(terms, id: \.self) { term in
                HStack(spacing: 12) {
                    Circle().fill(less ? AnyShapeStyle(muted) : AnyShapeStyle(Color.blue))
                        .frame(width: 8, height: 8)
                    Text(term).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Menu {
                        Button { model.add(term, less: !less); Haptics.selection() } label: {
                            Label(less ? "Turn up instead" : "Turn down instead", systemImage: less ? "arrow.up.right" : "arrow.down.right")
                        }
                        .disabled((less ? model.preferences.moreOf : model.preferences.lessOf).count >= WhisperJasperTuning.maxTerms)
                        Button(role: .destructive) { model.remove(term, less: less); Haptics.selection() } label: {
                            Label("Remove", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(.rect)
                    }
                    .accessibilityLabel("Options for \(term)")
                }
                .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 4)
            }
            Divider()
            Button {
                addText = ""; addTarget = less ? .less : .more
                Haptics.tap()
            } label: {
                Label(terms.count >= WhisperJasperTuning.maxTerms ? "8 choices added" : (less ? "Turn something down" : "Turn something up"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 16).contentShape(.rect)
            }
            .buttonStyle(.plain).disabled(terms.count >= WhisperJasperTuning.maxTerms)
        }
        .background(card, in: .rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5) }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Make it yours").font(.subheadline.weight(.bold))
            Text("A few ideas to get you started — not guesses about you.").font(.caption).foregroundStyle(muted)
            suggestionGrid(moreSuggestions, less: false)
            suggestionGrid(lessSuggestions, less: true)
        }
        .padding(.vertical, 2)
    }

    private func suggestionGrid(_ choices: [String], less: Bool) -> some View {
        let chosen = Set((model.preferences.moreOf + model.preferences.lessOf).map { $0.lowercased() })
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
            ForEach(choices.filter { !chosen.contains($0.lowercased()) }, id: \.self) { choice in
                Button {
                    model.add(choice, less: less); Haptics.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: less ? "minus" : "plus").font(.caption.weight(.bold))
                        Text(choice).font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
                    .background(card, in: .rect(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(hairline, lineWidth: 0.75) }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled((less ? model.preferences.lessOf : model.preferences.moreOf).count >= WhisperJasperTuning.maxTerms)
                .accessibilityLabel("\(less ? "Turn down" : "Turn up") \(choice)")
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Just your Knot", systemImage: "lock").font(.caption.weight(.semibold))
            Text("Saved automatically for this account on this device. Your choices are sent with new Knot chats and voice sessions to guide replies. They don't change Discover, Waves or Meet, and don't grant access to more data.")
                .font(.caption).foregroundStyle(muted)
            Text("Tuning is guidance, not a guarantee. Your current question, accuracy and safety still come first.")
                .font(.caption).foregroundStyle(muted)
        }
        .padding(.horizontal, 4)
    }

    private func close() { Haptics.tap(); backTransition.perform { dismiss() } }
}
