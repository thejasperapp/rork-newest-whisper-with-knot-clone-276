import SwiftUI

extension ToolbarContent {
    /// Remove iOS 26's shared glass plate without replacing native navigation.
    @ToolbarContentBuilder
    func whisperFlatToolbar() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
