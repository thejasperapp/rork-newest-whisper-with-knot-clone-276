import SwiftUI

private nonisolated struct InsideMeetingNotebookKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var whisperInsideMeetingNotebook: Bool {
        get { self[InsideMeetingNotebookKey.self] }
        set { self[InsideMeetingNotebookKey.self] = newValue }
    }
}
