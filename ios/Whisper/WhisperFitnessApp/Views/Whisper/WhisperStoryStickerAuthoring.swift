import SwiftUI

/// Author-only bindings. Viewer replies/votes are deliberately separate.
struct WhisperStoryStickerAuthoring {
    let text: Binding<String>
    var options: Binding<[String]>? = nil
    let focus: FocusState<Bool>.Binding
    var chooseDeadline: (() -> Void)? = nil
}
