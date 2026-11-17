import SwiftUI

struct JasperNativeNutritionNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review in Jasper", systemImage: "fork.knife")
                .font(.title2.bold())
            Text(JasperConnectClient.nativeReviewMessage)
                .font(.body)
            Text("Saved plans remain readable with your permission. Planned macros are estimates, not logged intake. Cloud storage does not confirm native validation or an active plan.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Link("Jasper connection details", destination: URL(string: "https://www.thejasperapp.com/connect")!)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
