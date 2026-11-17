import SwiftUI

/// Jasper's live thinking indicator — ONE line of shimmering text, no box,
/// no chrome. It shows only the CURRENT step (Searching the web → Reading
/// sources → …) and crossfades as the script advances, exactly like Apple
/// Intelligence's inline status line.
///
/// The full step list is never shown while thinking — after the answer
/// lands, the chat renders `WhisperEmberThoughtSummary` ("Thought for Ns")
/// which expands into every step on demand.
///
/// In meetings the line starts on a live "Listening" step when a voice
/// question is being captured, then walks the thinking steps the moment
/// capture ends.
struct WhisperEmberThinkingSteps: View {
    @Environment(\.colorScheme) private var colorScheme

    /// The active personality (kept for API compatibility; tints nothing now).
    var coachMode: WhisperEmberCoachMode = .regular
    /// Once `/interpret` resolves, its real intent label becomes the final step.
    var resolvedLabel: String?
    /// Whether the interpreter actually computed something (drives the step set).
    var isAnalytical: Bool
    /// White-on-glass skin for dark surfaces (the in-meeting Jasper box).
    var onDark: Bool = false
    /// Which script the line walks — the chat pipeline or a private
    /// mid-meeting answer.
    var flavor: Flavor = .chat
    /// Voice-capture step folded in (meetings): `.listening` holds on a live
    /// "Listening" line, `.done`/`.hidden` start straight on the thinking steps.
    var listenState: ListenState = .hidden
    /// The user's actual ask — steps derive honest, specific labels from it.
    var queryHint: String? = nil

    nonisolated enum Flavor {
        case chat
        case meeting
    }

    nonisolated enum ListenState: Equatable {
        case hidden, listening, done
    }

    @State private var activeIndex: Int = 0
    @State private var advanceTimer: Timer?

    private var steps: [String] {
        Self.stepLabels(
            flavor: flavor,
            isAnalytical: isAnalytical,
            queryHint: queryHint,
            resolvedLabel: resolvedLabel,
            includeListening: listenState != .hidden
        )
    }

    /// The honest step script for a given ask — shared by the live line and
    /// the post-answer "Thought for Ns" summary so they always agree.
    nonisolated static func stepLabels(
        flavor: Flavor = .chat,
        isAnalytical: Bool,
        queryHint: String?,
        resolvedLabel: String?,
        includeListening: Bool = false
    ) -> [String] {
        var list: [String] = []
        if includeListening { list.append("Listening") }
        // Keywords and elapsed time do not establish which tools actually ran.
        // Only the interpreter's confirmed label may name a specific operation.
        list.append(resolvedLabel ?? (flavor == .meeting ? "Preparing your private answer" : "Thinking"))
        return list
    }

    private var inkTone: Color { onDark ? .white : WhisperTheme.ink(colorScheme) }

    var body: some View {
        let labels = steps
        let current = labels[min(activeIndex, max(labels.count - 1, 0))]
        return ShimmerLabel(text: current, tone: inkTone)
            .id(current)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: current)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { startScript() }
            .onDisappear { advanceTimer?.invalidate(); advanceTimer = nil }
            .onChange(of: resolvedLabel) { _, newValue in
                // When the real intent lands, jump the line to the final step.
                if newValue != nil {
                    withAnimation(.spring(response: 0.35)) { activeIndex = labels.count - 1 }
                }
            }
            .onChange(of: listenState) { old, new in
                // Voice capture finished → leave the Listening line and start
                // the thinking steps without remounting.
                if old == .listening && new != .listening {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                        activeIndex = max(activeIndex, min(1, labels.count - 1))
                    }
                    scheduleAdvance()
                }
            }
    }

    private func startScript() {
        advanceTimer?.invalidate()
        activeIndex = listenState == .done ? min(1, max(steps.count - 1, 0)) : 0
        scheduleAdvance()
    }

    /// Advances one step every beat — but never while pinned on a live
    /// Listening line (the mic decides when that step ends).
    private func scheduleAdvance() {
        advanceTimer?.invalidate()
        guard steps.count > 1 else { return }
        advanceTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in
            Task { @MainActor in
                guard listenState != .listening else { return }
                guard activeIndex < steps.count - 1 else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { activeIndex += 1 }
            }
        }
    }
}

/// The post-answer receipt: a quiet "Thought for Ns ⌄" line that expands
/// into every step Jasper walked for that answer. Text only — no card.
struct WhisperEmberThoughtSummary: View {
    @Environment(\.colorScheme) private var colorScheme
    let seconds: Int
    let steps: [String]
    var onDark: Bool = false

    @State private var expanded: Bool = false

    private var muted: Color { onDark ? Color.white.opacity(0.55) : WhisperTheme.muted(colorScheme) }
    private var ink: Color { onDark ? .white : WhisperTheme.ink(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text("Thought for \(seconds)s")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(muted)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thought for \(seconds) seconds. \(expanded ? "Hide" : "Show") steps.")

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(muted)
                            Text(step)
                                .font(.caption)
                                .foregroundStyle(ink.opacity(onDark ? 0.85 : 0.75))
                        }
                    }
                }
                .padding(.leading, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// The active step's label with a soft highlight band sweeping through it —
/// the Apple-Intelligence shimmer, driven by TimelineView so it never needs
/// state or timers of its own.
private struct ShimmerLabel: View {
    let text: String
    let tone: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase: CGFloat = reduceMotion ? 0.5 : CGFloat(t.truncatingRemainder(dividingBy: 1.4) / 1.4)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(
                    .linearGradient(
                        stops: [
                            .init(color: tone.opacity(0.35), location: 0),
                            .init(color: tone.opacity(0.35), location: max(0, phase - 0.28)),
                            .init(color: tone, location: phase),
                            .init(color: tone.opacity(0.35), location: min(1, phase + 0.28)),
                            .init(color: tone.opacity(0.35), location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}
