import Foundation
import CoreLocation
import Realtime

@Observable
class RaceViewModel {
    var currentRace: Race?
    var currentParticipant: RaceParticipant?
    var participants: [RaceParticipant] = []
    var runnerPositions: [String: RunnerPosition] = [:]
    var isLoading: Bool = false
    var errorMessage: String?
    var raceElapsedTime: TimeInterval = 0
    var isRaceActive: Bool = false
    var useMiles: Bool = false
    var canRetry: Bool = false
    private var pendingRetry: RetryAction?

    private let supabase = SupabaseService.shared
    let locationService = RaceLocationService()
    private var channel: RealtimeChannelV2?
    /// Retains the broadcast observation — the token deregisters its callback
    /// when deallocated, so discarding it makes the channel receive nothing.
    private var positionSubscription: RealtimeSubscription?
    private var broadcastTimer: Timer?
    private var raceTimer: Timer?
    private var raceStartTime: Date?
    private var statusPollTimer: Timer?
    private var positionPollTimer: Timer?
    private var isChannelSubscribed: Bool = false

    nonisolated enum RetryAction {
        case createRace(name: String, distance: Double, startDate: Date, organizerName: String, startCoord: CLLocationCoordinate2D?, finishCoord: CLLocationCoordinate2D?)
        case joinRace(code: String, displayName: String, role: ParticipantRole)
        case startRace
        case startRunning
        case finishRun
    }

    private let raceIdKey = "activeRaceId"
    private let participantIdKey = "activeParticipantId"
    private let raceActiveKey = "isRaceActive"

    var sortedResults: [RaceParticipant] {
        participants
            .filter { $0.participantRole == .runner }
            .sorted { a, b in
                if let aTime = a.finishTimeSeconds, let bTime = b.finishTimeSeconds {
                    return aTime < bTime
                }
                if a.finishTimeSeconds != nil { return true }
                if b.finishTimeSeconds != nil { return false }
                return a.displayName < b.displayName
            }
    }

    var elapsedFormatted: String {
        let hours = Int(raceElapsedTime) / 3600
        let minutes = (Int(raceElapsedTime) % 3600) / 60
        let seconds = Int(raceElapsedTime) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var distanceUnit: String { useMiles ? "mi" : "km" }
    var paceUnit: String { useMiles ? "/mi" : "/km" }

    func formatDistance(_ meters: Double) -> String {
        if useMiles {
            return String(format: "%.2f", meters / 1609.344)
        }
        return String(format: "%.2f", meters / 1000.0)
    }

    func formatPace(elapsedSeconds: Double, distanceMeters: Double) -> String {
        guard distanceMeters > 50, elapsedSeconds > 0 else { return "--:--" }
        let divisor = useMiles ? 1609.344 : 1000.0
        let paceSecondsPerUnit = elapsedSeconds / (distanceMeters / divisor)
        let mins = Int(paceSecondsPerUnit) / 60
        let secs = Int(paceSecondsPerUnit) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    func formatSpeed(_ metersPerSecond: Double) -> String {
        if useMiles {
            return String(format: "%.1f mph", metersPerSecond * 2.23694)
        }
        return String(format: "%.1f km/h", metersPerSecond * 3.6)
    }

    // MARK: - Persistence

    private func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(currentRace?.id, forKey: raceIdKey)
        defaults.set(currentParticipant?.id, forKey: participantIdKey)
        defaults.set(isRaceActive, forKey: raceActiveKey)
    }

    private func clearState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: raceIdKey)
        defaults.removeObject(forKey: participantIdKey)
        defaults.removeObject(forKey: raceActiveKey)
    }

    func restoreIfNeeded() async {
        let defaults = UserDefaults.standard
        guard let raceId = defaults.string(forKey: raceIdKey),
              let participantId = defaults.string(forKey: participantIdKey) else { return }

        do {
            guard let race = try await supabase.fetchRace(byId: raceId) else {
                clearState()
                return
            }
            currentRace = race

            let allParticipants = try await supabase.fetchParticipants(raceId: raceId)
            participants = allParticipants
            currentParticipant = allParticipants.first { $0.id == participantId }

            guard currentParticipant != nil else {
                clearState()
                currentRace = nil
                return
            }

            if race.raceStatus == .active {
                if let serverStart = race.raceStartedDate {
                    raceStartTime = serverStart
                    raceElapsedTime = Date().timeIntervalSince(serverStart)
                    startRaceTimer()
                }

                let wasActive = defaults.bool(forKey: raceActiveKey)
                if wasActive && currentParticipant?.participantStatus == .running {
                    isRaceActive = true
                    locationService.startTracking()
                    await setupChannel()
                    startBroadcasting()
                }
            }

            await setupChannel()
            startStatusPolling()
            startPositionPolling()
        } catch {
            clearState()
        }
    }

    // MARK: - Race Actions

    func createRace(name: String, distance: Double, startDate: Date, organizerName: String, startCoord: CLLocationCoordinate2D?, finishCoord: CLLocationCoordinate2D?) async {
        isLoading = true
        errorMessage = nil
        canRetry = false
        pendingRetry = nil
        let joinCode = generateJoinCode()
        let formatter = ISO8601DateFormatter()

        let race = Race(
            id: UUID().uuidString,
            name: name,
            distance: distance,
            startDate: formatter.string(from: startDate),
            status: RaceStatus.upcoming.rawValue,
            joinCode: joinCode,
            organizerName: organizerName,
            startLatitude: startCoord?.latitude,
            startLongitude: startCoord?.longitude,
            finishLatitude: finishCoord?.latitude,
            finishLongitude: finishCoord?.longitude
        )

        do {
            try await supabase.createRace(race)
            currentRace = race

            let organizer = RaceParticipant(
                id: UUID().uuidString,
                raceId: race.id,
                displayName: organizerName,
                bibNumber: nil,
                role: ParticipantRole.organizer.rawValue,
                status: ParticipantStatus.registered.rawValue,
                finishTimeSeconds: nil,
                averagePace: nil
            )
            try await supabase.addParticipant(organizer)
            currentParticipant = organizer
            saveState()
            startStatusPolling()
            startPositionPolling()
        } catch {
            errorMessage = "Failed to create race: \(error.localizedDescription)"
            pendingRetry = .createRace(name: name, distance: distance, startDate: startDate, organizerName: organizerName, startCoord: startCoord, finishCoord: finishCoord)
            canRetry = true
        }
        isLoading = false
    }

    func joinRace(code: String, displayName: String, role: ParticipantRole) async {
        isLoading = true
        errorMessage = nil
        canRetry = false
        pendingRetry = nil

        if role == .runner {
            locationService.requestPermission()
        }

        do {
            guard let race = try await supabase.fetchRace(byJoinCode: code) else {
                errorMessage = "No race found with that code."
                isLoading = false
                return
            }
            currentRace = race

            let participant = RaceParticipant(
                id: UUID().uuidString,
                raceId: race.id,
                displayName: displayName,
                bibNumber: role == .runner ? Int.random(in: 100...999) : nil,
                role: role.rawValue,
                status: ParticipantStatus.registered.rawValue,
                finishTimeSeconds: nil,
                averagePace: nil
            )
            try await supabase.addParticipant(participant)
            currentParticipant = participant
            await refreshParticipants()
            saveState()
            startStatusPolling()
            startPositionPolling()
            await setupChannel()

            if race.raceStatus == .active, let serverStart = race.raceStartedDate {
                raceStartTime = serverStart
                raceElapsedTime = Date().timeIntervalSince(serverStart)
                startRaceTimer()
            }
        } catch {
            errorMessage = "Failed to join race: \(error.localizedDescription)"
            pendingRetry = .joinRace(code: code, displayName: displayName, role: role)
            canRetry = true
        }
        isLoading = false
    }

    func refreshParticipants() async {
        guard let race = currentRace else { return }
        do {
            participants = try await supabase.fetchParticipants(raceId: race.id)
        } catch {
            print("Failed to fetch participants: \(error)")
        }
    }

    func refreshRaceStatus() async {
        guard let race = currentRace else { return }
        do {
            guard let updated = try await supabase.fetchRace(byId: race.id) else { return }
            let oldStatus = currentRace?.raceStatus
            currentRace = updated

            if oldStatus != updated.raceStatus {
                if updated.raceStatus == .active, raceStartTime == nil {
                    if let serverStart = updated.raceStartedDate {
                        raceStartTime = serverStart
                        raceElapsedTime = Date().timeIntervalSince(serverStart)
                        startRaceTimer()
                    }
                }
                await refreshParticipants()
            }
        } catch {
            print("Failed to refresh race: \(error)")
        }
    }

    func retryLastAction() async {
        guard let retry = pendingRetry else { return }
        pendingRetry = nil
        canRetry = false
        switch retry {
        case .createRace(let name, let distance, let startDate, let organizerName, let startCoord, let finishCoord):
            await createRace(name: name, distance: distance, startDate: startDate, organizerName: organizerName, startCoord: startCoord, finishCoord: finishCoord)
        case .joinRace(let code, let displayName, let role):
            await joinRace(code: code, displayName: displayName, role: role)
        case .startRace:
            await startRace()
        case .startRunning:
            await startRunning()
        case .finishRun:
            await finishRun()
        }
    }

    func startRace() async {
        guard let race = currentRace else { return }
        guard let participant = currentParticipant else { return }
        errorMessage = nil
        canRetry = false
        pendingRetry = nil
        do {
            try await supabase.updateRaceStatus(raceId: race.id, status: .active)
            currentRace?.status = RaceStatus.active.rawValue
            let now = Date()
            currentRace?.raceStartedAt = ISO8601DateFormatter().string(from: now)
            raceStartTime = now
            startRaceTimer()
            saveState()

            if participant.participantRole == .runner {
                locationService.requestPermission()
                try await supabase.updateParticipantStatus(participantId: participant.id, status: .running)
                isRaceActive = true
                locationService.startTracking()
                await setupChannel()
                startBroadcasting()
            }

            startPositionPolling()
        } catch {
            errorMessage = "Failed to start race: \(error.localizedDescription)"
            pendingRetry = .startRace
            canRetry = true
        }
    }

    func startRunning() async {
        guard let participant = currentParticipant else { return }
        errorMessage = nil
        canRetry = false
        pendingRetry = nil

        locationService.requestPermission()

        do {
            try await supabase.updateParticipantStatus(participantId: participant.id, status: .running)
        } catch {
            errorMessage = "Failed to start: \(error.localizedDescription)"
            pendingRetry = .startRunning
            canRetry = true
            return
        }

        isRaceActive = true

        if let serverStart = currentRace?.raceStartedDate {
            raceStartTime = serverStart
            raceElapsedTime = Date().timeIntervalSince(serverStart)
        } else {
            raceStartTime = Date()
        }
        startRaceTimer()
        locationService.startTracking()

        await setupChannel()
        startBroadcasting()
        saveState()
    }

    func finishRun() async {
        guard let participant = currentParticipant else { return }
        let elapsed = raceElapsedTime
        let distMeters = locationService.totalDistance
        let divisor = useMiles ? 1609.344 : 1000.0
        let avgPace: Double? = distMeters > 0
            ? (elapsed / distMeters) * divisor / 60.0
            : nil

        locationService.stopTracking()
        stopBroadcasting()
        stopRaceTimer()
        isRaceActive = false
        saveState()

        do {
            try await supabase.finishParticipant(participantId: participant.id, timeSeconds: elapsed, avgPace: avgPace)
            await refreshParticipants()
        } catch {
            errorMessage = "Failed to record finish: \(error.localizedDescription)"
            pendingRetry = .finishRun
            canRetry = true
        }
    }

    // MARK: - Realtime Channel

    private func setupChannel() async {
        guard let race = currentRace else { return }
        guard channel == nil else { return }

        do {
            let ch = supabase.createRaceChannel(raceId: race.id)
            channel = ch

            positionSubscription = ch.onBroadcast(event: "position") { [weak self] message in
                Task { @MainActor in
                    guard let self else { return }
                    self.handleBroadcastMessage(message)
                }
            }

            await ch.subscribe()
            isChannelSubscribed = true
        } catch {
            print("Channel setup error: \(error)")
        }
    }

    private func handleBroadcastMessage(_ message: [String: AnyJSON]) {
        let payload: [String: AnyJSON]
        if let p = message["payload"], case .object(let obj) = p {
            payload = obj
        } else {
            payload = message
        }

        let pid = extractString(payload["participant_id"]) ?? ""
        guard !pid.isEmpty else { return }

        let position = RunnerPosition(
            participantId: pid,
            raceId: currentRace?.id,
            displayName: extractString(payload["display_name"]) ?? "",
            latitude: extractDouble(payload["latitude"]) ?? 0,
            longitude: extractDouble(payload["longitude"]) ?? 0,
            speed: extractDouble(payload["speed"]) ?? 0,
            distanceCovered: extractDouble(payload["distance_covered"]) ?? 0,
            timestamp: extractDouble(payload["timestamp"]) ?? 0
        )
        runnerPositions[pid] = position
    }

    private func extractDouble(_ value: AnyJSON?) -> Double? {
        guard let value else { return nil }
        if let d = value.doubleValue { return d }
        if let i = value.intValue { return Double(i) }
        if let s = value.stringValue, let d = Double(s) { return d }
        return nil
    }

    private func extractString(_ value: AnyJSON?) -> String? {
        guard let value else { return nil }
        if let s = value.stringValue { return s }
        return nil
    }

    func unsubscribe() async {
        positionSubscription?.cancel()
        positionSubscription = nil
        if let ch = channel {
            await ch.unsubscribe()
            channel = nil
            isChannelSubscribed = false
        }
        stopBroadcasting()
        stopRaceTimer()
        stopStatusPolling()
        stopPositionPolling()
    }

    func leaveRace() async {
        await unsubscribe()
        locationService.stopTracking()
        currentRace = nil
        currentParticipant = nil
        participants = []
        runnerPositions = [:]
        isRaceActive = false
        raceElapsedTime = 0
        raceStartTime = nil
        pendingRetry = nil
        canRetry = false
        clearState()
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        stopStatusPolling()
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshRaceStatus()
            }
        }
    }

    private func stopStatusPolling() {
        statusPollTimer?.invalidate()
        statusPollTimer = nil
    }

    // MARK: - Position Polling (fallback for realtime)

    private func startPositionPolling() {
        stopPositionPolling()
        positionPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollRunnerPositions()
            }
        }
    }

    private func stopPositionPolling() {
        positionPollTimer?.invalidate()
        positionPollTimer = nil
    }

    private func pollRunnerPositions() async {
        guard let race = currentRace, race.raceStatus == .active else { return }
        do {
            let positions = try await supabase.fetchRunnerPositions(raceId: race.id)
            for pos in positions {
                let existing = runnerPositions[pos.participantId]
                if existing == nil || pos.timestamp > (existing?.timestamp ?? 0) {
                    runnerPositions[pos.participantId] = pos
                }
            }
        } catch {
            print("Position poll error: \(error)")
        }
    }

    // MARK: - Broadcasting

    private func startBroadcasting() {
        stopBroadcasting()
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.broadcastCurrentPosition()
            }
        }
    }

    private func stopBroadcasting() {
        broadcastTimer?.invalidate()
        broadcastTimer = nil
    }

    private func broadcastCurrentPosition() async {
        guard let participant = currentParticipant,
              let race = currentRace,
              let location = locationService.currentLocation else { return }

        let positionData: [String: AnyJSON] = [
            "participant_id": .string(participant.id),
            "display_name": .string(participant.displayName),
            "latitude": .double(location.coordinate.latitude),
            "longitude": .double(location.coordinate.longitude),
            "speed": .double(max(location.speed, 0)),
            "distance_covered": .double(locationService.totalDistance),
            "timestamp": .double(Date().timeIntervalSince1970)
        ]

        if let ch = channel, isChannelSubscribed {
            await ch.broadcast(event: "position", message: positionData)
        }

        let position = RunnerPosition(
            participantId: participant.id,
            raceId: race.id,
            displayName: participant.displayName,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: max(location.speed, 0),
            distanceCovered: locationService.totalDistance,
            timestamp: Date().timeIntervalSince1970
        )

        do {
            try await supabase.upsertRunnerPosition(raceId: race.id, position: position)
        } catch {
            print("Position upsert error: \(error)")
        }

        runnerPositions[participant.id] = position
    }

    // MARK: - Timer

    private func startRaceTimer() {
        stopRaceTimer()
        raceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.raceStartTime else { return }
                self.raceElapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopRaceTimer() {
        raceTimer?.invalidate()
        raceTimer = nil
    }

    private func generateJoinCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
