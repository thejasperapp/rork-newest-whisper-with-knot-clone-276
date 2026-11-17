import SwiftUI

/// Real activity chooses the supplied animation state. A new delivery gets one short
/// celebration; mounting an existing conversation never invents a milestone.
struct WhisperKnotTaskPortrait: View {
    let size: CGFloat
    let creative: Bool
    var thinking = false
    var tint: Color? = nil
    var milestoneID: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.whisperMediaActive) private var mediaActive
    @State private var celebrationStart: Date?
    @State private var consumedMilestoneID: String?

    private var motion: WhisperKnotMascot.Motion {
        if celebrationStart != nil { return .milestone }
        if creative { return .making }
        return thinking ? .working : .idle
    }

    var body: some View {
        Group {
            if let tint {
                // Preserve the established coloured specialist presentation.
                ZStack {
                    Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
                    WhisperKnotMascot(size: size * 0.82, expression: thinking ? .thinking : .calm,
                                      bodyColor: tint, motion: motion, milestoneDate: celebrationStart)
                        .shadow(color: .black.opacity(0.18), radius: size * 0.045, x: 0, y: size * 0.045)
                }
                .overlay { Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
            } else {
                // Use the full portrait diameter: shrinking 64 to 52.48 points
                // both added a ring and fell below the film playback threshold.
                WhisperKnotMascot(size: size, expression: thinking ? .thinking : .calm,
                                  motion: motion, milestoneDate: celebrationStart)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: milestoneID) {
            celebrationStart = nil
            guard let milestoneID, milestoneID != consumedMilestoneID else { return }
            consumedMilestoneID = milestoneID
            guard mediaActive, scenePhase == .active else { return }
            celebrationStart = Date()
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            celebrationStart = nil
        }
        .onChange(of: mediaActive) { _, active in if !active { celebrationStart = nil } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { celebrationStart = nil } }
        .onDisappear { celebrationStart = nil }
    }
}
