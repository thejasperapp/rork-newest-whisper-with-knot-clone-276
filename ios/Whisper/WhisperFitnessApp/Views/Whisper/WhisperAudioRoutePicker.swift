import SwiftUI
import AVFoundation

/// Where call / meeting audio should play.
nonisolated enum WhisperAudioRoute: String, CaseIterable, Sendable {
    case speaker
    case receiver
    case bluetooth

    /// SF Symbol for control-bar buttons.
    var controlIcon: String {
        switch self {
        case .speaker: return "speaker.wave.2.fill"
        case .receiver: return "iphone"
        case .bluetooth: return "headphones"
        }
    }

    static let bluetoothPortTypes: Set<AVAudioSession.Port> = [
        .bluetoothHFP, .bluetoothLE, .bluetoothA2DP,
    ]

    /// A connected Bluetooth input (HFP/LE) usable as a call route.
    static func bluetoothInput() -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().availableInputs?
            .first { bluetoothPortTypes.contains($0.portType) }
    }

    /// Name of any connected Bluetooth audio device, nil when none.
    static func connectedBluetoothName() -> String? {
        if let input = bluetoothInput() { return input.portName }
        return AVAudioSession.sharedInstance().currentRoute.outputs
            .first { bluetoothPortTypes.contains($0.portType) }?
            .portName
    }
}

/// Speaker / iPhone / Bluetooth output menu shared by calls, video calls,
/// meetings and the call setup sheet. The Bluetooth row only appears when a
/// device is actually connected, labelled with its real name.
struct WhisperAudioRouteMenu<MenuLabel: View>: View {
    let current: WhisperAudioRoute
    let onSelect: (WhisperAudioRoute) -> Void
    let primaryAction: (() -> Void)?
    @ViewBuilder let label: () -> MenuLabel

    init(
        current: WhisperAudioRoute,
        onSelect: @escaping (WhisperAudioRoute) -> Void,
        primaryAction: (() -> Void)? = nil,
        @ViewBuilder label: @escaping () -> MenuLabel
    ) {
        self.current = current
        self.onSelect = onSelect
        self.primaryAction = primaryAction
        self.label = label
    }

    var body: some View {
        if let primaryAction {
            Menu { routeChoices } label: { label() } primaryAction: { primaryAction() }
        } else {
            Menu { routeChoices } label: { label() }
        }
    }

    private var routeChoices: some View {
            Picker("Audio output", selection: Binding(
                get: { current },
                set: { route in
                    Haptics.tap()
                    onSelect(route)
                }
            )) {
                Label("Speaker", systemImage: "speaker.wave.2.fill")
                    .tag(WhisperAudioRoute.speaker)
                Label("iPhone", systemImage: "iphone")
                    .tag(WhisperAudioRoute.receiver)
                if let name = WhisperAudioRoute.connectedBluetoothName() {
                    Label(name, systemImage: "headphones")
                        .tag(WhisperAudioRoute.bluetooth)
                }
            }
    }
}
