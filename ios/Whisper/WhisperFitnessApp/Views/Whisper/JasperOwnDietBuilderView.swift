import SwiftUI

/// Connected generation is paused by Jasper's September 2026 contract.
struct JasperOwnDietBuilderView: View {
    var onSaved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                JasperNativeNutritionNotice()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Nutrition planning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
