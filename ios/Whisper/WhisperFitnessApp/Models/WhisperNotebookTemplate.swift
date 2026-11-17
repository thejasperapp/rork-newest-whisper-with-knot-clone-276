import Foundation

nonisolated enum WhisperNotebookTemplate: String, CaseIterable, Identifiable, Sendable {
    case general, oneOnOne = "one-on-one", project, client, interview
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "Meeting"
        case .oneOnOne: "1:1"
        case .project: "Project"
        case .client: "Client"
        case .interview: "Interview"
        }
    }
    var outline: String {
        switch self {
        case .general: "Summary, decisions, open questions"
        case .oneOnOne: "Progress, feedback, support needed"
        case .project: "Updates, blockers, decisions"
        case .client: "Goals, constraints, agreements"
        case .interview: "Experience, evidence, open questions"
        }
    }
}
