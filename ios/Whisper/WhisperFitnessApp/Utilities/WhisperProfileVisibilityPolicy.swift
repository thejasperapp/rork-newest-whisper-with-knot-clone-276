import Foundation

nonisolated enum WhisperProfileVisibilityPolicy {
    static func canView(viewerID: String, authorID: String, resolved: Bool, isPrivate: Bool?, following: Bool, blocked: Bool) -> Bool {
        guard !blocked else { return false }
        if !viewerID.isEmpty && viewerID.lowercased() == authorID.lowercased() { return true }
        guard resolved else { return false }
        return isPrivate != true || following
    }
}
