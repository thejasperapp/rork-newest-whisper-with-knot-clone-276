import SwiftUI
import UIKit

/// A surface-specific analysis lens or an existing host tool.
struct JasperDockAction: Identifiable {
    enum Kind { case lens(String), perform(() -> Void) }
    let id: String
    let label: String
    let icon: String
    let kind: Kind
    var isLens: Bool { if case .lens = kind { return true }; return false }
}

/// Dating retains its contextual accent and structured match results.
struct JasperDockCostume {
    let accent: Color
    let softAccent: Color
    let pillFill: Color
    let pillRim: Color
    let ink: Color
    let chipLabel: String
    var pillIconAsset: String? = nil
    var mascotPalette: WhisperEmberMascotPalette? = nil
    var mascotSmitten: Bool = false

    static let datingMatchmaker = JasperDockCostume(
        accent: Color(red: 0.91, green: 0.28, blue: 0.49),
        softAccent: Color(red: 0.98, green: 0.70, blue: 0.79),
        pillFill: Color(red: 0.99, green: 0.965, blue: 0.945),
        pillRim: Color(red: 0.95, green: 0.66, blue: 0.76),
        ink: Color(red: 0.12, green: 0.05, blue: 0.08),
        chipLabel: "MATCHMAKER", pillIconAsset: "WhisperDatingLogo",
        mascotPalette: .cupidPink, mascotSmitten: true)
}

/// One Intelligence entry and reading panel for every contextual analysis tool.
/// Analysis still starts only when opened; the host owns its authorized context.
struct JasperAnalysisDock: View {
    var pillLabel: String = "Knot's read"
    var boxTitle: String = "Knot's read"
    let focus: String
    let buildContext: () -> String?
    var emptyText: String = "Nothing to analyze here yet."
    var actions: [JasperDockAction] = []
    var costume: JasperDockCostume? = nil
    var replyContent: ((String) -> AnyView?)? = nil
    var conversationStyle: Bool = false
    var small: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open: Bool = false
    @State private var busy: Bool = false
    @State private var showIntelligence: Bool = false
    @State private var replies: [String: String] = [:]
    @State private var operation: UUID = UUID()
    @State private var activeLens: String = "read"
    private let mode: WhisperEmberCoachMode = .regular
    private static let defaultLensID = "read"
    private var reply: String? { replies[activeLens] }
    private var ink: Color { WhisperTheme.ink(colorScheme) }

    var body: some View {
        Group {
            if open { box.transition(.opacity) }
            else { pill }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            operation = UUID(); replies = [:]; busy = false; open = false; showIntelligence = false
        }
        .fullScreenCover(isPresented: $showIntelligence) { WhisperEmberChatView() }
    }

    private var pill: some View {
        Button {
            Haptics.tap()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { open = true }
            if reply == nil, !busy { Task { await run(force: false) } }
        } label: {
            WhisperJasperIntelligencePill(working: busy, title: "Knot",
                leadingAsset: costume?.pillIconAsset,
                mascotPalette: costume?.mascotPalette, mascotSmitten: costume?.mascotSmitten ?? false, small: small)
        }
        .buttonStyle(WhisperJasperReactionButtonStyle())
        .accessibilityLabel("Open Knot")
        .accessibilityHint(pillLabel)
        .accessibilityIdentifier("jasper.analysis.open")
    }

    private var box: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                WhisperJasperInteractiveMascot(size: 34, dating: costume?.mascotSmitten ?? false,
                    working: busy, restingExpression: reply == nil ? .calm : .happy)
                VStack(alignment: .leading, spacing: 3) {
                    WhisperKnotWordmark()
                    Text(boxTitle).font(.caption).foregroundStyle(costume?.accent ?? WhisperTheme.muted(colorScheme))
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { open = false }
                } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.medium))
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain).accessibilityLabel("Close Knot analysis")
            }
            .padding(.horizontal, 14).padding(.top, 8)
            Divider().padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if busy {
                        WhisperEmberThinkingSteps(coachMode: mode, isAnalytical: false, onDark: colorScheme == .dark)
                    } else if let reply {
                        if let custom = replyContent?(reply) {
                            custom.padding(12)
                                .background(Color(red: 0.09, green: 0.085, blue: 0.08), in: .rect(cornerRadius: 16))
                        } else {
                            WhisperEmberRichText(text: reply, onDark: colorScheme == .dark, baseSize: 16, inkOverride: ink)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: conversationStyle ? 240 : 280)
            actionRail
            HStack(spacing: 8) {
                Text("Private to you · AI can make mistakes")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { showIntelligence = true } label: {
                    Label("Ask anything", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a new Knot conversation. This analysis is not automatically attached.")
            }
            .padding(.horizontal, 16).padding(.bottom, 4)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: 400)
        .background { WhisperJasperIntelligenceShell(shape: RoundedRectangle(cornerRadius: 26), panel: true, ambientTint: costume?.accent) }
        .padding(.horizontal, 12)
    }

    private var actionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionChip(busy ? "Reading…" : "Re-run", icon: "arrow.clockwise", selected: false) {
                    Task { await run(force: true) }
                }
                .disabled(busy)
                if actions.contains(where: { $0.isLens }) {
                    lensChip(id: Self.defaultLensID, label: "Read", icon: "sparkles")
                }
                ForEach(actions) { action in
                    switch action.kind {
                    case .lens: lensChip(id: action.id, label: action.label, icon: action.icon)
                    case .perform(let go):
                        actionChip(action.label, icon: action.icon, selected: false) {
                            open = false; go()
                        }
                    }
                }
            }
        }
        .contentMargins(.horizontal, 16)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func lensChip(id: String, label: String, icon: String) -> some View {
        actionChip(label, icon: icon, selected: activeLens == id) {
            activeLens = id
            if replies[id] == nil { Task { await run(force: false) } }
        }
        .disabled(busy)
        .accessibilityAddTraits(activeLens == id ? .isSelected : [])
    }

    private func actionChip(_ label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Label(label, systemImage: icon).font(.caption.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(selected ? WhisperTheme.card(colorScheme) : ink)
                .background(selected ? ink : WhisperTheme.surface(colorScheme), in: Capsule())
                .overlay { Capsule().strokeBorder(WhisperBrandGradient.linear.opacity(selected ? 0.7 : 0.2), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func focusText(for lensID: String) -> String {
        guard lensID != Self.defaultLensID else { return focus }
        for action in actions {
            if action.id == lensID, case .lens(let text) = action.kind { return text }
        }
        return focus
    }

    private func run(force: Bool) async {
        guard !busy else { return }
        let lens = activeLens
        let token = UUID(); operation = token
        let epoch = AccountStorage.generation
        busy = true
        defer { if operation == token && epoch == AccountStorage.generation { busy = false } }
        let context = (buildContext() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else { replies[lens] = emptyText; return }
        let text = await WhisperEmberService.shared.quickAnalysis(context: context, focus: focusText(for: lens), force: force)
        guard operation == token, epoch == AccountStorage.generation, !Task.isCancelled else { return }
        replies[lens] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Couldn't complete this read. Tap Re-run to try again." : text
    }
}
