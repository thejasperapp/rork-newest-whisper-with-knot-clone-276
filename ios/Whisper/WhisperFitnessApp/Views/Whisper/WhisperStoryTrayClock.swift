import SwiftUI

/// A flip-clock preview using the real local time, rather than a fixed reference time.
struct WhisperStoryTrayClock: View {
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            TimelineView(.everyMinute) { context in
                GeometryReader { geometry in
                    let hour = Calendar.current.component(.hour, from: context.date)
                    let minute = Calendar.current.component(.minute, from: context.date)
                    HStack(spacing: 3) {
                        tile(hour >= 12 ? "PM" : "AM", small: true)
                        tile(String(hour % 12 == 0 ? 12 : hour % 12))
                        tile(String(minute / 10))
                        tile(String(minute % 10))
                    }
                    .frame(width: 90, height: 36)
                    .scaleEffect(min(1.2, geometry.size.width / 90))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            .frame(minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add current time")
    }

    private func tile(_ value: String, small: Bool = false) -> some View {
        Text(value)
            .font(.system(size: small ? 6 : 31, weight: .medium, design: .rounded).width(.condensed))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: small ? .bottom : .center)
            .padding(.bottom, small ? 4 : 0)
            .background(Color(white: 0.32), in: .rect(cornerRadius: 2))
            .overlay { Rectangle().fill(.black.opacity(0.4)).frame(height: 0.7) }
    }
}
