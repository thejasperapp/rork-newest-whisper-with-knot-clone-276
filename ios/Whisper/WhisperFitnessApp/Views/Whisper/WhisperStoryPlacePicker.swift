import SwiftUI
import MapKit

/// Explicit location selection; search does not request the user's position.
struct WhisperStoryPlacePicker: View {
    let onPick: (String, Double?, Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var results: [Place] = []
    @State private var isLoading: Bool = false
    @State private var message: String?
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    @State private var nearbyTask: Task<Void, Never>?
    @State private var requestID: UUID = UUID()
    @State private var activeSearch: MKLocalSearch?
    private struct Place: Identifiable {
        let id: UUID = UUID()
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
    }
    private var valid: Bool { !closed && !Task.isCancelled && generation == AccountStorage.generation }
    var body: some View {
        VStack(spacing: 0) {
            WhisperStoryToolHeader(title: "Location", onCancel: { dismiss() })
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search places", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                        .accessibilityLabel("Clear location search")
                }
            }.padding(.horizontal, 14).frame(minHeight: 48)
                .background(.white.opacity(0.08), in: .capsule).padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Only the place you choose is shared.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                    Button {
                        nearbyTask?.cancel()
                        nearbyTask = Task { await currentLocation() }
                    } label: { Label("Use current location", systemImage: "location").frame(minHeight: 48) }.disabled(isLoading)
                    if isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
                    if let message { Text(message).font(.subheadline).foregroundStyle(.secondary).padding(.vertical) }
                    ForEach(results) { place in
                        Button {
                            guard valid else { return }
                            onPick(place.name, place.latitude, place.longitude)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(place.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(.vertical, 6)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Use “\(String(query.prefix(100)))” as a text label") {
                            guard valid else { return }
                            onPick(String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)), nil, nil)
                        }.font(.subheadline).frame(minHeight: 52)
                    }
                }.padding(.horizontal, 20)
            }.scrollDismissesKeyboard(.interactively)
                .task(id: query) { await search() }
        }.foregroundStyle(.white).tint(.white).buttonStyle(.plain)
            .onDisappear { closed = true; requestID = UUID(); nearbyTask?.cancel(); activeSearch?.cancel() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in closed = true; requestID = UUID(); results = []; nearbyTask?.cancel(); activeSearch?.cancel(); dismiss() }
    }
    private func search() async {
        guard valid else { return }
        let operation = UUID(); requestID = operation
        nearbyTask?.cancel(); activeSearch?.cancel(); activeSearch = nil
        results = []; message = nil; isLoading = false
        let term = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
        guard !term.isEmpty else { isLoading = false; return }
        do {
            try await Task.sleep(for: .milliseconds(350))
            guard valid, requestID == operation else { return }
            isLoading = true
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = term
            let search = MKLocalSearch(request: request); activeSearch = search
            let response = try await search.start()
            guard valid, requestID == operation else { return }
            activeSearch = nil
            results = response.mapItems.prefix(25).map { Place(name: $0.name ?? term, address: $0.placemark.title ?? "", latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude) }
            isLoading = false
            if results.isEmpty { message = "No places found. Try a city or a different name." }
        } catch { guard valid, requestID == operation else { return }; activeSearch = nil; isLoading = false; message = "Couldn't search places. Try again or add a text label." }
    }
    private func currentLocation() async {
        guard valid else { return }
        let operation = UUID(); requestID = operation
        activeSearch?.cancel(); activeSearch = nil
        isLoading = true; message = nil; results = []
        do {
            let location = try await EmberLocationService.shared.requestCurrentContext()
            guard valid, requestID == operation else { return }
            results = [Place(name: location.name ?? location.city ?? "Current location", address: "Select to attach this location", latitude: location.latitude, longitude: location.longitude)]
            isLoading = false
        } catch { guard valid, requestID == operation else { return }; isLoading = false; message = "Location isn't available. You can still search for a place." }
    }
}
