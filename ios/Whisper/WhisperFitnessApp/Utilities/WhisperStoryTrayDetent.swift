import SwiftUI

/// Leaves a small strip of the actual editor below the status region.
struct WhisperStoryTrayDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        guard !context.dynamicTypeSize.isAccessibilitySize, context.maxDetentValue > 500 else {
            return context.maxDetentValue
        }
        return context.maxDetentValue - 34
    }
}
