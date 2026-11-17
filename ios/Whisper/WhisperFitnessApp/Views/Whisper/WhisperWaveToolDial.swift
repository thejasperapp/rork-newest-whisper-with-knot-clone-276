import SwiftUI

/// The edge-to-edge tool dial beneath the canvas — the Camera app's mode strip
/// crossed with a physical detent wheel. Tools sit on a ticked rule that slides
/// under a fixed needle; whichever tool rests beneath the needle is the one
/// being edited. Every detent clicks with the system selection haptic, a spun
/// dial settles with a soft bump, and tapping any tool spins to it.
struct WhisperWaveToolDial<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let symbol: (Item) -> String
    let isMarked: (Item) -> Bool
    @State private var position: Item.ID?

    private static var itemWidth: CGFloat { 78 }

    init(items: [Item], selection: Binding<Item>, title: @escaping (Item) -> String, symbol: @escaping (Item) -> String, isMarked: @escaping (Item) -> Bool = { _ in false }) {
        self.items = items
        self._selection = selection
        self.title = title
        self.symbol = symbol
        self.isMarked = isMarked
        self._position = State(initialValue: selection.wrappedValue.id)
    }

    var body: some View {
        GeometryReader { geometry in
            let inset = max(0, (geometry.size.width - Self.itemWidth) / 2)
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        WaveDialItem(title: title(item), symbol: symbol(item), centered: position == item.id, marked: isMarked(item)) {
                            spin(to: item)
                        }
                        .frame(width: Self.itemWidth)
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
                .background(alignment: .top) {
                    WaveDialRule(itemWidth: Self.itemWidth, count: items.count, bleed: inset)
                }
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $position, anchor: .center)
            .safeAreaPadding(.horizontal, inset)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { old, new in
                if new == .idle, old == .decelerating { Haptics.soft() }
            }
            .overlay(alignment: .top) { needle }
        }
        .frame(height: 88)
        .onChange(of: position) { _, id in
            guard let id, let item = items.first(where: { $0.id == id }) else { return }
            Haptics.selection()
            if item != selection { selection = item }
        }
        .onChange(of: selection) { _, item in
            guard position != item.id else { return }
            withAnimation(.snappy(duration: 0.3)) { position = item.id }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editing tools")
    }

    private var needle: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 3, height: 14)
            .shadow(color: .black.opacity(0.6), radius: 2)
            .allowsHitTesting(false)
    }

    private func spin(to item: Item) {
        guard position != item.id else { return }
        withAnimation(.snappy(duration: 0.32)) { position = item.id }
    }
}

/// One detent on the dial: a glyph in a disc (filled white under the needle)
/// with its name beneath, and an accent dot when that tool has a live edit.
private struct WaveDialItem: View {
    let title: String
    let symbol: String
    let centered: Bool
    let marked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                disc
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(centered ? Color.white : Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.top, 18)
            .scaleEffect(centered ? 1 : 0.9)
            .animation(.snappy(duration: 0.25), value: centered)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(centered ? [.isSelected] : [])
    }

    private var disc: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(centered ? Color.black : Color.white)
            .frame(width: 44, height: 44)
            .background(centered ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.10)), in: Circle())
            .overlay(alignment: .topTrailing) {
                if marked {
                    Circle()
                        .fill(WhisperBrandGradient.accent)
                        .frame(width: 8, height: 8)
                        .overlay { Circle().strokeBorder(Color.black, lineWidth: 1.5) }
                        .offset(x: 1, y: -1)
                }
            }
    }
}

/// The ticked rule that scrolls with the tools: a tall tick at each detent,
/// short ticks between, running past both ends so the dial reads edge to edge.
private struct WaveDialRule: View {
    let itemWidth: CGFloat
    let count: Int
    let bleed: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = itemWidth / 6
            let firstCenter = bleed + itemWidth / 2
            let lowest = Int(floor(-firstCenter / spacing))
            let highest = Int(ceil((size.width - firstCenter) / spacing))
            guard highest >= lowest else { return }
            for n in lowest...highest {
                let x = firstCenter + CGFloat(n) * spacing
                let isDetent = n % 6 == 0 && n >= 0 && n / 6 < count
                let height: CGFloat = isDetent ? 10 : 4
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(.white.opacity(isDetent ? 0.55 : 0.22)), lineWidth: isDetent ? 1.5 : 1)
            }
        }
        .frame(height: 12)
        .padding(.horizontal, -bleed)
        .allowsHitTesting(false)
    }
}
