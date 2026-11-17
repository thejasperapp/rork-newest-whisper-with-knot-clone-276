import SwiftUI
import CoreImage

/// The Looks tool: three color families previewed on the footage, a strength
/// dial for the chosen look, and an Adjust family with exposure, contrast,
/// color and warmth on the same dial.
struct WhisperWaveLookControls: View {
    @Binding var filter: SnapFilter
    @Binding var adjustments: WhisperWaveColorAdjustments
    let thumbnail: UIImage?
    @State private var family: String = "Essentials"
    @State private var control: String = "Exposure"
    @State private var previews: [SnapFilter: UIImage] = [:]

    private struct Control: Identifiable {
        let name: String
        let symbol: String
        var id: String { name }
    }

    private static let families: [String] = ["Essentials", "Film", "Mono", "Adjust"]
    private static let controls: [Control] = [
        Control(name: "Exposure", symbol: "sun.max"),
        Control(name: "Contrast", symbol: "circle.lefthalf.filled"),
        Control(name: "Color", symbol: "drop"),
        Control(name: "Warmth", symbol: "thermometer.sun")
    ]

    private var filters: [SnapFilter] {
        switch family {
        case "Film": return [.none, .film, .fade, .instant, .transfer, .vhs]
        case "Mono": return [.none, .mono, .noir, .process]
        default: return [.none, .pop, .ember, .frost, .ghost, .dream, .midnight, .chrome, .vivid]
        }
    }

    private var isDefault: Bool { filter == .none && adjustments == WhisperWaveColorAdjustments() }

    private var value: Binding<Double> {
        switch control {
        case "Contrast": return $adjustments.contrast
        case "Color": return $adjustments.saturation
        case "Warmth": return $adjustments.warmth
        default: return $adjustments.exposure
        }
    }

    private var range: ClosedRange<Double> {
        switch control {
        case "Contrast": return 0.5...1.5
        case "Color": return 0...2
        case "Warmth": return -1...1
        default: return -2...2
        }
    }

    private var defaultValue: Double {
        switch control {
        case "Contrast", "Color": return 1
        default: return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            familyRow
            if family == "Adjust" { adjustTiles } else { lookStrip }
            dial
        }
        .foregroundStyle(.white)
        .task(id: thumbnail) { await renderPreviews() }
    }

    private var familyRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.families, id: \.self) { name in
                        WhisperWavePanelChip(title: name, systemImage: name == "Adjust" ? "slider.horizontal.3" : nil, selected: family == name) {
                            family = name
                        }
                    }
                }
            }
            if !isDefault {
                WhisperWavePanelChip(title: "Reset", systemImage: "arrow.counterclockwise", selected: false) {
                    filter = .none
                    adjustments = WhisperWaveColorAdjustments()
                }
                .accessibilityLabel("Reset look and adjustments")
            }
        }
        .frame(height: 28)
    }

    private var lookStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { look in
                    WhisperWavePreviewTile(title: look.name, image: previews[look] ?? thumbnail, selected: filter == look) {
                        filter = look
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 84)
    }

    private var adjustTiles: some View {
        HStack(spacing: 8) {
            ForEach(Self.controls) { item in
                WhisperWavePreviewTile(title: item.name, image: nil, selected: control == item.name, systemImage: item.symbol) {
                    control = item.name
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 84)
    }

    @ViewBuilder private var dial: some View {
        if family == "Adjust" {
            let baseline = defaultValue
            WhisperWaveRuler(value: value, range: range, defaultValue: baseline, tick: 0.05, detents: [baseline], pointsPerUnit: control == "Exposure" ? 120 : 220, label: control, format: { Self.percent($0 - baseline) })
                .frame(height: 44)
        } else if filter == .none {
            Text("Pick a look · dial its strength here")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: 44, alignment: .leading)
        } else {
            WhisperWaveRuler(value: $adjustments.intensity, range: 0...1, defaultValue: 1, tick: 0.05, detents: [0.5, 1], pointsPerUnit: 220, label: "\(filter.name) strength")
                .frame(height: 44)
        }
    }

    private static func percent(_ v: Double) -> String {
        String(format: "%+.0f", v * 100)
    }

    private func renderPreviews() async {
        guard let thumbnail else { return }
        let looks = SnapFilter.all
        let images = await Task.detached(priority: .utility) { () -> [SnapFilter: UIImage] in
            guard let cg = thumbnail.cgImage else { return [:] }
            let context = CIContext(options: [.cacheIntermediates: false])
            let source = CIImage(cgImage: cg)
            var result: [SnapFilter: UIImage] = [:]
            for look in looks {
                if Task.isCancelled { break }
                let output = look.process(source)
                if let image = context.createCGImage(output, from: source.extent) {
                    result[look] = UIImage(cgImage: image)
                }
            }
            return result
        }.value
        guard !Task.isCancelled else { return }
        previews = images
    }
}
