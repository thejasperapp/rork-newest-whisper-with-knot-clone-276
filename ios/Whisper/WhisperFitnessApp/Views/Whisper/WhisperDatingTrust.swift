import SwiftUI
import AVFoundation
import Vision
import Supabase
import UserNotifications
import UIKit

// MARK: - Verification ("Verified dater 💘")

/// Photo verification state + the verified-usernames cache. iOS verifies
/// ON DEVICE: a live front-camera face is tracked through a random head-turn
/// prompt (Vision), the selfie uploads, and the RPC marks the dater
/// verified. Anyone can ask "which of these people are verified" — only the
/// boolean leaks, never the selfie. Mirrors web `lib/datingTrust.ts`.
@MainActor
@Observable
final class WhisperDatingVerificationService {
    static let shared = WhisperDatingVerificationService()
    /// pending | verified | rejected | nil (never submitted / unknown)
    var status: String? = nil
    var verifiedUsernames: Set<String> = []
    private var lookedUp: Set<String> = []
    private var loaded: Bool = false

    private var client: SupabaseClient { SupabaseService.shared.client }

    var isVerified: Bool { status == "verified" }

    func refreshMine() async {
        let uid = AccountStorage.currentUserID.lowercased()
        guard !uid.isEmpty else { return }
        struct Row: Decodable, Sendable { let status: String? }
        let rows: [Row]? = try? await client
            .from("whisper_dating_verifications")
            .select("status")
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value
        status = rows?.first?.status
        loaded = true
        if status == "verified", let me = LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username {
            verifiedUsernames.insert(me.lowercased())
        }
    }

    /// Upload the selfie + submit. Returns the resulting status or nil.
    func submit(selfie: UIImage, livenessPassed: Bool) async -> String? {
        let uid = AccountStorage.currentUserID.lowercased()
        guard !uid.isEmpty, let data = selfie.jpegData(compressionQuality: 0.8) else { return nil }
        let path = "\(uid)/dating-verification/\(UUID().uuidString).jpg"
        do {
            _ = try await client.storage.from("whisper-media").upload(
                path, data: data,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
            )
            let url = try client.storage.from("whisper-media").getPublicURL(path: path).absoluteString
            struct Params: Encodable, Sendable {
                let p_selfie_url: String
                let p_method: String
                let p_liveness_passed: Bool
                let p_username: String?
            }
            struct Reply: Decodable, Sendable { let status: String? }
            let reply: Reply = try await client.rpc(
                "whisper_dating_verification_submit",
                params: Params(
                    p_selfie_url: url,
                    p_method: livenessPassed ? "liveness" : "selfie",
                    p_liveness_passed: livenessPassed,
                    p_username: LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username
                )
            ).execute().value
            status = reply.status
            if status == "verified", let me = LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username {
                verifiedUsernames.insert(me.lowercased())
            }
            return status
        } catch {
            return nil
        }
    }

    /// Resolve which of these usernames are verified (cached per session).
    func lookup(_ usernames: [String]) async {
        let fresh = usernames.map { $0.lowercased() }.filter { !$0.isEmpty && !lookedUp.contains($0) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { lookedUp.insert($0) }
        struct Params: Encodable, Sendable { let p_usernames: [String] }
        let hits: [String]? = try? await client
            .rpc("whisper_dating_verified", params: Params(p_usernames: Array(fresh.prefix(200))))
            .execute()
            .value
        for h in hits ?? [] { verifiedUsernames.insert(h.lowercased()) }
    }

    func isVerified(_ username: String) -> Bool {
        verifiedUsernames.contains(username.lowercased())
    }
}

/// The rose "Verified dater" chip — sits next to a name wherever daters meet.
struct WhisperVerifiedDaterBadge: View {
    var compact: Bool = false
    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: compact ? 10 : 11, weight: .bold))
            if !compact {
                Text("Verified dater")
                    .font(.system(size: 10, weight: .heavy))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(rose, in: Capsule())
        .accessibilityLabel("Verified dater")
    }
}

/// The on-device liveness flow. Front camera → Vision tracks the face →
/// three beats: center your face · turn your head (random side) · look
/// straight and hold → the selfie is captured and submitted as `liveness`.
struct WhisperDatingVerifyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var onVerified: (() -> Void)? = nil

    @State private var engine = WhisperLivenessEngine()
    @State private var submitting: Bool = false
    @State private var result: String? = nil
    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if engine.isAvailable {
                    SnapCameraPreview(session: engine.session)
                        .ignoresSafeArea()
                        .overlay {
                            // Soft oval mask so the face sits where Vision expects it.
                            Color.black.opacity(0.55)
                                .mask {
                                    Rectangle()
                                        .overlay {
                                            Ellipse()
                                                .frame(width: 250, height: 340)
                                                .blendMode(.destinationOut)
                                        }
                                        .compositingGroup()
                                }
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                            Ellipse()
                                .strokeBorder(engine.faceInFrame ? rose : .white.opacity(0.6), lineWidth: 3)
                                .frame(width: 250, height: 340)
                                .animation(.easeOut(duration: 0.2), value: engine.faceInFrame)
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.7))
                        Text("A camera is needed to verify").font(.headline).foregroundStyle(.white)
                        Text("Install the app on your iPhone via the Rork App and try again.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                }

                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        if let result {
                            Text(result == "verified" ? "You're a verified dater 💘" : "Sent for review")
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(.white)
                            Text(result == "verified"
                                 ? "Your badge shows on the Dating hub, in the queue, and on every blind date."
                                 : "A moderator will confirm it shortly — your badge appears the moment they do.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                            Button {
                                Haptics.tap()
                                onVerified?()
                                dismiss()
                            } label: {
                                Text("Done")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(.white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { i in
                                    Capsule()
                                        .fill(i < engine.stepIndex ? rose : (i == engine.stepIndex ? .white : .white.opacity(0.3)))
                                        .frame(height: 4)
                                }
                            }
                            Text(engine.prompt)
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .contentTransition(.numericText())
                            Text(engine.hint)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                            if submitting {
                                ProgressView().tint(.white)
                            }
                        }
                    }
                    .padding(18)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 26)
                }
            }
            .navigationTitle("Photo verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .task {
            engine.start()
        }
        .onDisappear { engine.stop() }
        .onChange(of: engine.capturedSelfie != nil) { _, done in
            guard done, !submitting, result == nil, let selfie = engine.capturedSelfie else { return }
            submitting = true
            Task {
                let status = await WhisperDatingVerificationService.shared.submit(selfie: selfie, livenessPassed: true)
                await MainActor.run {
                    submitting = false
                    if status != nil { Haptics.success() } else { Haptics.warning() }
                    result = status ?? "pending"
                }
            }
        }
    }
}

/// Front-camera session + Vision face tracking driving the three liveness beats.
@Observable
final class WhisperLivenessEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated let session = AVCaptureSession()
    var isAvailable: Bool = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    var faceInFrame: Bool = false
    var stepIndex: Int = 0
    var prompt: String = "Center your face in the oval"
    var hint: String = "Good light, no hat or sunglasses."
    var capturedSelfie: UIImage? = nil

    private let queue = DispatchQueue(label: "whisper.liveness")
    private let output = AVCaptureVideoDataOutput()
    private var configured: Bool = false
    nonisolated(unsafe) private var frameCount: Int = 0
    nonisolated(unsafe) private var turnDirectionLeft: Bool = Bool.random()
    nonisolated(unsafe) private var centeredFrames: Int = 0
    nonisolated(unsafe) private var turnedFrames: Int = 0
    nonisolated(unsafe) private var straightFrames: Int = 0
    nonisolated(unsafe) private var step: Int = 0
    nonisolated(unsafe) private var finished: Bool = false

    func start() {
        guard isAvailable, !configured else { return }
        configured = true
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.output.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            if let conn = self.output.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                }
                if conn.isVideoMirroringSupported {
                    conn.automaticallyAdjustsVideoMirroring = false
                    conn.isVideoMirrored = true
                }
            }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
        Task { @MainActor in
            self.prompt = "Center your face in the oval"
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !finished else { return }
        frameCount &+= 1
        guard frameCount % 4 == 0, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
        try? handler.perform([request])
        guard let face = (request.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }) else {
            Task { @MainActor in self.faceInFrame = false }
            return
        }
        let box = face.boundingBox
        let centered = box.width > 0.28 && abs(box.midX - 0.5) < 0.18 && abs(box.midY - 0.5) < 0.2
        let yaw = Double(truncating: face.yaw ?? 0)
        Task { @MainActor in self.faceInFrame = centered }

        switch step {
        case 0:
            centeredFrames = centered ? centeredFrames + 1 : 0
            if centeredFrames >= 6 {
                step = 1
                let dir = turnDirectionLeft ? "LEFT" : "RIGHT"
                Task { @MainActor in
                    self.stepIndex = 1
                    self.prompt = "Slowly turn your head \(dir)"
                    self.hint = "Keep your face in the oval while you turn."
                }
            }
        case 1:
            // Mirrored preview: turning your head left shows a negative yaw.
            let turned = turnDirectionLeft ? yaw < -0.30 : yaw > 0.30
            turnedFrames = turned ? turnedFrames + 1 : max(0, turnedFrames - 1)
            if turnedFrames >= 3 {
                step = 2
                Task { @MainActor in
                    self.stepIndex = 2
                    self.prompt = "Now look straight and hold still"
                    self.hint = "Capturing your selfie…"
                }
            }
        default:
            let straight = centered && abs(yaw) < 0.12
            straightFrames = straight ? straightFrames + 1 : 0
            if straightFrames >= 8 {
                finished = true
                let ci = CIImage(cvPixelBuffer: pixel)
                let ctx = CIContext()
                if let cg = ctx.createCGImage(ci, from: ci.extent) {
                    let img = UIImage(cgImage: cg, scale: 1, orientation: .up)
                    Task { @MainActor in
                        self.stepIndex = 3
                        self.prompt = "Got it"
                        self.hint = "Submitting…"
                        self.capturedSelfie = img
                    }
                } else {
                    finished = false
                    straightFrames = 0
                }
            }
        }
    }
}

// MARK: - Safety (report + block in one move)

enum WhisperDatingSafety {
    static let reasons: [(id: String, label: String)] = [
        ("fake", "Fake profile or photos"),
        ("harassment", "Harassment or hate"),
        ("inappropriate", "Inappropriate behavior"),
        ("underage", "Seems underage"),
        ("scam", "Scam or spam"),
        ("other", "Something else")
    ]

    /// Writes the report and (by default) the platform-wide block, then
    /// mirrors the block into the local block service so the hub, queue,
    /// and inbox filter them out immediately.
    @MainActor
    static func report(username: String, reason: String, details: String?, roomCode: String?, block: Bool) async -> Bool {
        struct Params: Encodable, Sendable {
            let p_reported_username: String
            let p_reason: String
            let p_details: String?
            let p_room_code: String?
            let p_block: Bool
        }
        do {
            _ = try await SupabaseService.shared.client.rpc(
                "whisper_dating_report",
                params: Params(p_reported_username: username, p_reason: reason, p_details: details, p_room_code: roomCode, p_block: block)
            ).execute()
            if block {
                if let row = await WhisperUserService.shared.fetchByUsername(username) {
                    _ = await WhisperBlockService.shared.block(userID: row.user_id, username: row.username)
                }
            }
            return true
        } catch {
            return false
        }
    }
}

/// The report sheet — reason picker, optional details, "Also block" toggle.
struct WhisperDatingReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let username: String
    var roomCode: String? = nil
    var onDone: ((Bool) -> Void)? = nil

    @State private var reason: String = "fake"
    @State private var details: String = ""
    @State private var block: Bool = true
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var failed: Bool = false
    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if sent {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(rose)
                                Text("Thanks — we've got it")
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text(block ? "@\(username) is blocked. They can't message you, be paired with you, or appear in your Dating hub." : "Our team will review this report.")
                                    .font(.footnote)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                        } else {
                            Text("What happened with @\(username)?")
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            VStack(spacing: 0) {
                                ForEach(WhisperDatingSafety.reasons, id: \.id) { r in
                                    Button {
                                        Haptics.tap()
                                        reason = r.id
                                    } label: {
                                        HStack {
                                            Text(r.label)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                            Spacer()
                                            Image(systemName: reason == r.id ? "largecircle.fill.circle" : "circle")
                                                .foregroundStyle(reason == r.id ? rose : WhisperTheme.muted(colorScheme))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    if r.id != WhisperDatingSafety.reasons.last?.id {
                                        Divider().padding(.leading, 14)
                                    }
                                }
                            }
                            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }

                            TextField("Anything else we should know? (optional)", text: $details, axis: .vertical)
                                .lineLimit(2...5)
                                .font(.subheadline)
                                .padding(12)
                                .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }

                            Toggle(isOn: $block) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Also block @\(username)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    Text("Removes them from your hub, the queue, and your messages — permanently.")
                                        .font(.caption)
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                }
                            }
                            .tint(rose)

                            if failed {
                                Text("Couldn't send the report. Check your connection and try again.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Button {
                                Haptics.tap()
                                sending = true
                                Task {
                                    let ok = await WhisperDatingSafety.report(
                                        username: username, reason: reason,
                                        details: details.isEmpty ? nil : details,
                                        roomCode: roomCode, block: block
                                    )
                                    await MainActor.run {
                                        sending = false
                                        failed = !ok
                                        if ok {
                                            Haptics.success()
                                            withAnimation(.spring(response: 0.3)) { sent = true }
                                            onDone?(block)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if sending { ProgressView().tint(.white) }
                                    Text(block ? "Report & block" : "Send report")
                                        .font(.subheadline.weight(.heavy))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(rose, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(sending)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Dating hours ("Tonight at 8")

/// Scheduled dating hours concentrate the queue: every night 8–9pm in the
/// dater's local time, plus Sunday brunch at 11. RSVPs are keyed by the
/// instant of that local 8pm, so everyone in a time zone shares one count.
@MainActor
@Observable
final class WhisperDatingEventsService {
    static let shared = WhisperDatingEventsService()

    struct Event: Identifiable, Equatable {
        let key: String
        let startsAt: Date
        let endsAt: Date
        let title: String
        var going: Int
        var me: Bool
        var id: String { key }
        var isLive: Bool { Date() >= startsAt && Date() < endsAt }
        var isTonight: Bool { Calendar.current.isDateInToday(startsAt) }
    }

    var events: [Event] = []
    var available: Bool = true

    private static let keyFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// The next three nights (8pm local) + the next Sunday brunch (11am).
    static func upcomingSlots(now: Date = Date()) -> [(key: String, start: Date, end: Date, title: String)] {
        let cal = Calendar.current
        var out: [(String, Date, Date, String)] = []
        for dayOffset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now),
                  let start = cal.date(bySettingHour: 20, minute: 0, second: 0, of: day),
                  let end = cal.date(byAdding: .hour, value: 1, to: start) else { continue }
            if end < now { continue }
            let title = dayOffset == 0 ? "Tonight at 8" : (dayOffset == 1 ? "Tomorrow at 8" : "\(day.formatted(.dateTime.weekday(.wide))) at 8")
            out.append((keyFormatter.string(from: start), start, end, title))
        }
        // Next Sunday brunch.
        var probe = now
        for _ in 0..<8 {
            if cal.component(.weekday, from: probe) == 1,
               let start = cal.date(bySettingHour: 11, minute: 0, second: 0, of: probe),
               let end = cal.date(byAdding: .hour, value: 1, to: start), end > now {
                out.append((keyFormatter.string(from: start), start, end, "Sunday brunch at 11"))
                break
            }
            probe = cal.date(byAdding: .day, value: 1, to: probe) ?? probe
        }
        return out.sorted { $0.1 < $1.1 }.map { (key: $0.0, start: $0.1, end: $0.2, title: $0.3) }
    }

    func refresh() async {
        let slots = Self.upcomingSlots()
        struct Params: Encodable, Sendable { let p_keys: [String] }
        struct Row: Decodable, Sendable { let event_key: String; let going: Int?; let me: Bool? }
        let rows: [Row]? = try? await SupabaseService.shared.client
            .rpc("whisper_dating_event_counts", params: Params(p_keys: slots.map(\.key)))
            .execute()
            .value
        available = rows != nil
        let byKey = Dictionary(uniqueKeysWithValues: (rows ?? []).map { ($0.event_key, $0) })
        events = slots.map { s in
            Event(key: s.key, startsAt: s.start, endsAt: s.end, title: s.title,
                  going: byKey[s.key]?.going ?? 0, me: byKey[s.key]?.me ?? false)
        }
    }

    func toggle(_ event: Event) async {
        guard let idx = events.firstIndex(where: { $0.key == event.key }) else { return }
        let going = !events[idx].me
        events[idx].me = going
        events[idx].going = max(0, events[idx].going + (going ? 1 : -1))
        struct Params: Encodable, Sendable { let p_event_key: String; let p_going: Bool; let p_username: String }
        struct Reply: Decodable, Sendable { let going: Int? }
        let reply: Reply? = try? await SupabaseService.shared.client
            .rpc("whisper_dating_event_toggle", params: Params(
                p_event_key: event.key, p_going: going,
                p_username: LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username ?? "someone"))
            .execute()
            .value
        if let n = reply?.going, let i = events.firstIndex(where: { $0.key == event.key }) {
            events[i].going = n
        }
        if going { Self.scheduleReminder(for: event) } else { Self.cancelReminder(for: event) }
    }

    /// A local nudge 10 minutes before the hour.
    static func scheduleReminder(for event: Event) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let fire = event.startsAt.addingTimeInterval(-600)
            guard fire > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Blind dating starts in 10 minutes 💘"
            content.body = "\(event.going) people said they're coming. Hop in the queue at 8."
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "dating-event-\(event.key)", content: content, trigger: trigger))
        }
    }

    static func cancelReminder(for event: Event) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["dating-event-\(event.key)"])
    }
}

/// The rose "Tonight at 8" card for the finder — countdown, RSVP count,
/// I'm in / Going, and a LIVE state while the hour runs.
struct WhisperDatingEventCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var events = WhisperDatingEventsService.shared
    var onJoinQueue: () -> Void
    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.system(size: 11, weight: .bold))
                Text("DATING HOURS").font(.system(size: 11, weight: .heavy)).tracking(1.1)
                Spacer()
                if !events.available {
                    Text("RSVPs need the dating-v2 migration").font(.system(size: 10)).foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .foregroundStyle(rose)
            if let next = events.events.first {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(next.title)
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            if next.isLive {
                                HStack(spacing: 6) {
                                    Circle().fill(.red).frame(width: 7, height: 7)
                                    Text("LIVE NOW · the queue is busiest right now").font(.system(size: 12, weight: .bold)).foregroundStyle(.red)
                                }
                            } else {
                                Text("Starts in \(countdown(to: next.startsAt, now: ctx.date)) · \(next.going) going")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            Text("The queue is fullest when everyone shows up together. RSVP and we'll remind you 10 minutes before.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Button {
                            Haptics.tap()
                            if next.isLive { onJoinQueue() } else { Task { await events.toggle(next) } }
                        } label: {
                            Text(next.isLive ? "Join now 💘" : (next.me ? "Going ✓" : "I'm in"))
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(next.me && !next.isLive ? rose : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(next.me && !next.isLive ? AnyShapeStyle(rose.opacity(0.14)) : AnyShapeStyle(rose), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!events.available && !next.isLive)
                    }
                }
                if events.events.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(events.events.dropFirst()) { e in
                                Button {
                                    Haptics.tap()
                                    Task { await events.toggle(e) }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(e.title).font(.system(size: 11.5, weight: .semibold))
                                        Text("· \(e.going)").font(.system(size: 11)).opacity(0.7)
                                        if e.me { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)) }
                                    }
                                    .foregroundStyle(e.me ? .white : WhisperTheme.ink(colorScheme))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(e.me ? AnyShapeStyle(rose) : AnyShapeStyle(WhisperTheme.hairline(colorScheme).opacity(0.5)), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(!events.available)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(rose.opacity(colorScheme == .dark ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(rose.opacity(0.25), lineWidth: 1) }
        .task { await events.refresh() }
    }

    private func countdown(to date: Date, now: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        if s >= 86_400 { return "\(s / 86_400)d \((s % 86_400) / 3600)h" }
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(max(1, s / 60))m"
    }
}

// MARK: - Voice / video intros

@MainActor
@Observable
final class WhisperDatingIntroService {
    static let shared = WhisperDatingIntroService()

    nonisolated struct Intro: Decodable, Sendable, Equatable {
        let user_id: String
        let username: String?
        let url: String
        let kind: String
        let duration_s: Int?
    }

    var mine: Intro? = nil
    private var cache: [String: Intro] = [:]
    private var misses: Set<String> = []

    func refreshMine() async {
        let uid = AccountStorage.currentUserID.lowercased()
        guard !uid.isEmpty else { return }
        let rows: [Intro]? = try? await SupabaseService.shared.client
            .from("whisper_dating_intros").select().eq("user_id", value: uid).limit(1).execute().value
        mine = rows?.first
    }

    /// Lookup by handle — the blind-date stage only knows the partner's name.
    func fetch(username: String) async -> Intro? {
        let key = "@" + username.lowercased()
        if let c = cache[key] { return c }
        if misses.contains(key) { return nil }
        let rows: [Intro]? = try? await SupabaseService.shared.client
            .from("whisper_dating_intros").select().ilike("username", pattern: username).limit(1).execute().value
        if let r = rows?.first { cache[key] = r; return r }
        misses.insert(key)
        return nil
    }

    func fetch(userID: String) async -> Intro? {
        let key = userID.lowercased()
        if let c = cache[key] { return c }
        if misses.contains(key) { return nil }
        let rows: [Intro]? = try? await SupabaseService.shared.client
            .from("whisper_dating_intros").select().eq("user_id", value: key).limit(1).execute().value
        if let r = rows?.first { cache[key] = r; return r }
        misses.insert(key)
        return nil
    }

    func upload(fileURL: URL, kind: String, duration: Int) async -> Bool {
        let uid = AccountStorage.currentUserID.lowercased()
        guard !uid.isEmpty, let data = try? Data(contentsOf: fileURL) else { return false }
        let ext = kind == "video" ? "mp4" : "m4a"
        let path = "\(uid)/dating-intro/\(UUID().uuidString).\(ext)"
        do {
            _ = try await SupabaseService.shared.client.storage.from("whisper-media").upload(
                path, data: data,
                options: FileOptions(cacheControl: "3600", contentType: kind == "video" ? "video/mp4" : "audio/m4a", upsert: true)
            )
            let url = try SupabaseService.shared.client.storage.from("whisper-media").getPublicURL(path: path).absoluteString
            struct Row: Encodable, Sendable {
                let user_id: String; let username: String?; let url: String; let kind: String; let duration_s: Int; let created_at: String
            }
            _ = try await SupabaseService.shared.client.from("whisper_dating_intros").upsert(Row(
                user_id: uid,
                username: LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username,
                url: url, kind: kind, duration_s: duration, created_at: ISO8601DateFormatter().string(from: Date())
            ), onConflict: "user_id").execute()
            mine = Intro(user_id: uid, username: nil, url: url, kind: kind, duration_s: duration)
            return true
        } catch {
            return false
        }
    }

    func remove() async {
        let uid = AccountStorage.currentUserID.lowercased()
        _ = try? await SupabaseService.shared.client.from("whisper_dating_intros").delete().eq("user_id", value: uid).execute()
        mine = nil
    }
}

/// Record a 15-second voice intro (hold the mic) — the first thing a blind
/// date hears before the reveal. Video intros ride the system camera.
struct WhisperDatingIntroSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var intros = WhisperDatingIntroService.shared
    @State private var recorder: AVAudioRecorder? = nil
    @State private var recordingStartedAt: Date? = nil
    @State private var recordedURL: URL? = nil
    @State private var recordedSeconds: Int = 0
    @State private var uploading: Bool = false
    @State private var meter: Double = 0
    @State private var showVideoPicker: Bool = false
    @State private var error: String? = nil
    @State private var previewPlayer: AVPlayer? = nil
    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
    static let maxSeconds: Int = 15

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 18) {
                    HStack(spacing: 10) {
                        WhisperEmberMascot(size: 44, expression: .curious, palette: .cupidPink, smitten: true)
                        Text("Fifteen seconds of you. Blind dates hear it behind the curtain before the reveal; the hub plays it from your card.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let mine = intros.mine, recordedURL == nil {
                        HStack(spacing: 10) {
                            WhisperDatingIntroPlayButton(intro: mine, name: "you")
                            Spacer()
                            Button("Remove") {
                                Haptics.tap()
                                Task { await intros.remove() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                        }
                        .padding(12)
                        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Meter ring + hold-to-record mic.
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: recordingStartedAt == nil)) { ctx in
                        let elapsed = recordingStartedAt.map { ctx.date.timeIntervalSince($0) } ?? 0
                        ZStack {
                            Circle().strokeBorder(rose.opacity(0.18), lineWidth: 8).frame(width: 150, height: 150)
                            Circle()
                                .trim(from: 0, to: min(1, elapsed / Double(Self.maxSeconds)))
                                .stroke(rose, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 150, height: 150)
                            Circle()
                                .fill(rose.opacity(recordingStartedAt == nil ? 1 : 0.85))
                                .frame(width: 96 + CGFloat(meter) * 22, height: 96 + CGFloat(meter) * 22)
                                .animation(.easeOut(duration: 0.08), value: meter)
                            Image(systemName: recordingStartedAt == nil ? "mic.fill" : "waveform")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .onChange(of: elapsed >= Double(Self.maxSeconds)) { _, hit in
                            if hit { stopRecording() }
                        }
                        .onChange(of: ctx.date) { _, _ in
                            if let r = recorder, r.isRecording {
                                r.updateMeters()
                                let p = r.averagePower(forChannel: 0)
                                meter = max(0, min(1, Double(p + 50) / 50))
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in if recordingStartedAt == nil && !uploading { startRecording() } }
                            .onEnded { _ in stopRecording() }
                    )
                    Text(recordingStartedAt == nil
                         ? (recordedURL == nil ? "Hold to record · up to 15s" : "Recorded \(recordedSeconds)s · hold to redo")
                         : "Recording… release to stop")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))

                    if let recordedURL {
                        HStack(spacing: 10) {
                            Button {
                                Haptics.tap()
                                let p = AVPlayer(url: recordedURL)
                                previewPlayer = p
                                try? AVAudioSession.sharedInstance().setCategory(.playback)
                                p.play()
                            } label: {
                                Label("Play back", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            Button {
                                Haptics.tap()
                                uploading = true
                                Task {
                                    let ok = await intros.upload(fileURL: recordedURL, kind: "voice", duration: recordedSeconds)
                                    await MainActor.run {
                                        uploading = false
                                        if ok { Haptics.success(); dismiss() } else { error = "Upload failed — check your connection." }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if uploading { ProgressView().tint(.white) }
                                    Text("Save my intro 💘").font(.subheadline.weight(.heavy))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(rose, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(uploading)
                        }
                    }

                    Button {
                        Haptics.tap()
                        showVideoPicker = true
                    } label: {
                        Label("Record a video intro instead", systemImage: "video.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(rose)
                    }
                    .buttonStyle(.plain)

                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .navigationTitle("Your intro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .fullScreenCover(isPresented: $showVideoPicker) {
                WhisperIntroVideoPicker { url in
                    showVideoPicker = false
                    guard let url else { return }
                    uploading = true
                    Task {
                        let secs = Int(await WhisperStoryPoster.duration(of: url).rounded())
                        let ok = await intros.upload(fileURL: url, kind: "video", duration: min(secs, 15))
                        await MainActor.run {
                            uploading = false
                            if ok { Haptics.success(); dismiss() } else { error = "Upload failed — check your connection." }
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .task { await intros.refreshMine() }
        }
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            guard granted else { return }
            Task { @MainActor in
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dating-intro-\(UUID().uuidString).m4a")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 44_100,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                    ]
                    let r = try AVAudioRecorder(url: url, settings: settings)
                    r.isMeteringEnabled = true
                    r.record()
                    recorder = r
                    recordingStartedAt = Date()
                    Haptics.tap()
                } catch {
                    self.error = "Couldn't start the microphone."
                }
            }
        }
    }

    private func stopRecording() {
        guard let r = recorder, let started = recordingStartedAt else { return }
        let secs = Int(Date().timeIntervalSince(started).rounded())
        r.stop()
        recorder = nil
        recordingStartedAt = nil
        meter = 0
        if secs < 1 {
            try? FileManager.default.removeItem(at: r.url)
            return
        }
        recordedURL = r.url
        recordedSeconds = min(secs, Self.maxSeconds)
        Haptics.success()
    }
}

/// System camera in movie mode, capped at 15 seconds.
struct WhisperIntroVideoPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void
    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            let host = UIHostingController(rootView: Text("Camera unavailable — install on your iPhone to record a video intro.").padding())
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onPick(nil) }
            return host
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.cameraCaptureMode = .video
        picker.cameraDevice = .front
        picker.videoMaximumDuration = 15
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.mediaURL] as? URL)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onPick(nil) }
    }
}

/// "▶ Hear @name's intro · 0:12" — plays the clip inline (voice) or in a
/// small video sheet.
struct WhisperDatingIntroPlayButton: View {
    let intro: WhisperDatingIntroService.Intro
    let name: String
    @State private var player: AVPlayer? = nil
    @State private var playing: Bool = false
    @State private var showVideo: Bool = false
    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    var body: some View {
        Button {
            Haptics.tap()
            if intro.kind == "video" {
                showVideo = true
                return
            }
            if playing {
                player?.pause()
                playing = false
            } else {
                guard let url = URL(string: intro.url) else { return }
                try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
                let p = AVPlayer(url: url)
                player = p
                p.play()
                playing = true
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
                    Task { @MainActor in playing = false }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: playing ? "pause.fill" : (intro.kind == "video" ? "video.fill" : "play.fill"))
                    .font(.system(size: 11, weight: .heavy))
                Text(name == "you" ? "Your \(intro.kind) intro" : "Hear @\(name)'s intro")
                    .font(.system(size: 12.5, weight: .bold))
                if let d = intro.duration_s, d > 0 {
                    Text(String(format: "0:%02d", d)).font(.system(size: 11, weight: .semibold)).opacity(0.75)
                }
                if playing {
                    EqualizerDots()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(rose, in: Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showVideo) {
            if let url = URL(string: intro.url) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    WhisperStoryViewerVideo(url: url, paused: false, muted: false)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 18))
                        .padding()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct EqualizerDots: View {
    @State private var on: Bool = false
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(.white).frame(width: 2.5, height: on ? CGFloat(6 + i * 3) : 4)
                    .animation(.easeInOut(duration: 0.35).repeatForever().delay(Double(i) * 0.1), value: on)
            }
        }
        .onAppear { on = true }
    }
}

// MARK: - Second date (Jasper's scheduler on the DM wire)

/// A second-date proposal rides the DM rails as a wire token both apps
/// render as a rose card; accepting sends a confirm token + adds the event
/// to each person's calendar. Mirrors web `lib/secondDate.ts` exactly.
enum WhisperSecondDate {
    static let invitePrefix = "::whisper-date-invite-v1::"
    static let confirmPrefix = "::whisper-date-confirm-v1::"

    nonisolated struct Invite: Codable, Sendable, Equatable {
        var id: String
        var slot: String        // ISO8601
        var title: String
        var meetCode: String
        var from: String        // user id
        var fromName: String
    }

    nonisolated struct Slot: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let title: String
        let why: String
    }

    /// Jasper's three proposals: the next free evening, a weekend afternoon,
    /// and a coffee a few days out — always in the future, on the half hour.
    static func proposeSlots(now: Date = Date()) -> [Slot] {
        let cal = Calendar.current
        var out: [Slot] = []
        // 1) Tonight 7:30pm if it's before 5pm, else tomorrow 7:30pm.
        let hour = cal.component(.hour, from: now)
        let eveningDay = hour < 17 ? now : (cal.date(byAdding: .day, value: 1, to: now) ?? now)
        if let evening = cal.date(bySettingHour: 19, minute: 30, second: 0, of: eveningDay) {
            out.append(Slot(date: evening, title: "Dinner & a walk", why: "Soon while the spark's fresh"))
        }
        // 2) Next Saturday 2pm.
        var probe = cal.date(byAdding: .day, value: 1, to: now) ?? now
        for _ in 0..<8 {
            if cal.component(.weekday, from: probe) == 7, let sat = cal.date(bySettingHour: 14, minute: 0, second: 0, of: probe), sat > now {
                out.append(Slot(date: sat, title: "Coffee & a wander", why: "Daylight, low pressure"))
                break
            }
            probe = cal.date(byAdding: .day, value: 1, to: probe) ?? probe
        }
        // 3) Four days out, 6:30pm.
        if let later = cal.date(byAdding: .day, value: 4, to: now), let slot = cal.date(bySettingHour: 18, minute: 30, second: 0, of: later) {
            out.append(Slot(date: slot, title: "Drinks & a game", why: "Room to plan something fun"))
        }
        return out.sorted { $0.date < $1.date }
    }

    static func encodeInvite(_ i: Invite) -> String {
        guard let data = try? JSONEncoder().encode(i), let json = String(data: data, encoding: .utf8) else { return invitePrefix + "{}" }
        return invitePrefix + json
    }

    static func encodeConfirm(_ i: Invite) -> String {
        guard let data = try? JSONEncoder().encode(i), let json = String(data: data, encoding: .utf8) else { return confirmPrefix + "{}" }
        return confirmPrefix + json
    }

    /// Decode either token → (invite, isConfirm).
    static func decode(_ body: String) -> (Invite, Bool)? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let isConfirm: Bool
        let payload: String
        if trimmed.hasPrefix(invitePrefix) {
            isConfirm = false
            payload = String(trimmed.dropFirst(invitePrefix.count))
        } else if trimmed.hasPrefix(confirmPrefix) {
            isConfirm = true
            payload = String(trimmed.dropFirst(confirmPrefix.count))
        } else {
            return nil
        }
        guard let data = payload.data(using: .utf8), let inv = try? JSONDecoder().decode(Invite.self, from: data) else { return nil }
        return (inv, isConfirm)
    }

    static func isToken(_ body: String) -> Bool {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix(invitePrefix) || t.hasPrefix(confirmPrefix)
    }

    /// Friendly inbox/push line for either token.
    static func previewLine(_ body: String) -> String? {
        guard let (inv, confirm) = decode(body) else { return nil }
        let when = ISO8601DateFormatter().date(from: inv.slot).map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? ""
        return confirm ? "Second date confirmed 💘 \(when)" : "Proposed a second date 💘 \(when)"
    }

    static func mintMeetCode() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        func chunk() -> String { String((0..<4).map { _ in alphabet.randomElement() ?? "a" }) }
        return "wsp-\(chunk())-\(chunk())"
    }

    /// Both sides add the confirmed date to their calendar (own row each).
    @MainActor
    static func addToCalendar(_ inv: Invite, partnerName: String) async {
        guard let date = ISO8601DateFormatter().date(from: inv.slot) else { return }
        struct Row: Encodable, Sendable {
            let user_id: String; let title: String; let starts_at: String; let ends_at: String
            let kind: String; let meeting_link: String?; let notes: String?
        }
        let uid = AccountStorage.currentUserID.lowercased()
        guard !uid.isEmpty else { return }
        let f = ISO8601DateFormatter()
        _ = try? await SupabaseService.shared.client.from("whisper_calendar_events").insert(Row(
            user_id: uid,
            title: "Second date with @\(partnerName) — \(inv.title)",
            starts_at: f.string(from: date),
            ends_at: f.string(from: date.addingTimeInterval(3600)),
            kind: "meeting",
            meeting_link: "https://www.mydailywhisper.com/meet/\(inv.meetCode)?sd=1",
            notes: "Planned with Jasper 💘"
        )).execute()
    }
}

/// Jasper proposes three slots; pick one (or set your own) → the invite
/// lands in the DM with a Whisper Meet link ready.
struct WhisperSecondDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let partnerUserID: String
    let partnerName: String
    var onSent: (() -> Void)? = nil

    @State private var slots: [WhisperSecondDate.Slot] = WhisperSecondDate.proposeSlots()
    @State private var picked: UUID? = nil
    @State private var customDate: Date = Date().addingTimeInterval(86_400 * 2)
    @State private var useCustom: Bool = false
    @State private var customTitle: String = "Second date"
    @State private var sending: Bool = false
    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            WhisperEmberMascot(size: 48, expression: .happy, palette: .cupidPink, smitten: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Jasper's picks for you and @\(partnerName)")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text("Pick one — the invite lands in your chat with a Whisper Meet link. Once they accept, it's on both calendars.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        VStack(spacing: 10) {
                            ForEach(slots) { s in
                                Button {
                                    Haptics.tap()
                                    picked = s.id
                                    useCustom = false
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                                                .font(.system(size: 14, weight: .heavy))
                                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                            Text("\(s.title) · \(s.why)")
                                                .font(.system(size: 12))
                                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                        }
                                        Spacer()
                                        Image(systemName: picked == s.id && !useCustom ? "heart.circle.fill" : "circle")
                                            .font(.system(size: 22))
                                            .foregroundStyle(picked == s.id && !useCustom ? rose : WhisperTheme.muted(colorScheme))
                                    }
                                    .padding(14)
                                    .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(picked == s.id && !useCustom ? rose : WhisperTheme.hairline(colorScheme), lineWidth: picked == s.id && !useCustom ? 2 : 1) }
                                }
                                .buttonStyle(.plain)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Set my own", isOn: $useCustom).tint(rose)
                                    .font(.system(size: 14, weight: .semibold))
                                if useCustom {
                                    DatePicker("When", selection: $customDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                        .tint(rose)
                                    TextField("What are we doing?", text: $customTitle)
                                        .font(.subheadline)
                                        .padding(10)
                                        .background(WhisperTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(14)
                            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(useCustom ? rose : WhisperTheme.hairline(colorScheme), lineWidth: useCustom ? 2 : 1) }
                        }
                        Button {
                            Haptics.tap()
                            Task { await send() }
                        } label: {
                            HStack(spacing: 8) {
                                if sending { ProgressView().tint(.white) }
                                Text("Send the invite 💘").font(.subheadline.weight(.heavy))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(rose, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(sending || (picked == nil && !useCustom))
                        .opacity((picked == nil && !useCustom) ? 0.5 : 1)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Plan a second date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let date: Date
        let title: String
        if useCustom {
            date = customDate
            title = customTitle.isEmpty ? "Second date" : customTitle
        } else if let s = slots.first(where: { $0.id == picked }) {
            date = s.date
            title = s.title
        } else { return }
        let me = AccountStorage.currentUserID.lowercased()
        let myName = LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username ?? "someone"
        let invite = WhisperSecondDate.Invite(
            id: UUID().uuidString.lowercased(),
            slot: ISO8601DateFormatter().string(from: date),
            title: title,
            meetCode: WhisperSecondDate.mintMeetCode(),
            from: me,
            fromName: myName
        )
        let ok = await WhisperBackendService.shared.sendMessage(
            toUserID: partnerUserID, toUsername: partnerName, body: WhisperSecondDate.encodeInvite(invite), conversationKind: .dating
        )
        if ok {
            Haptics.success()
            onSent?()
            dismiss()
        } else {
            Haptics.warning()
        }
    }
}

/// The DM card for a second-date invite/confirmation — rose, with the
/// slot, the plan, and Accept (partner) / Join (once confirmed).
struct WhisperSecondDateCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let invite: WhisperSecondDate.Invite
    let isConfirm: Bool
    let isMine: Bool
    let partnerUserID: String
    let partnerName: String
    var onOpenMeet: ((String) -> Void)? = nil
    @State private var accepting: Bool = false
    @State private var accepted: Bool = false
    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)

    private var date: Date? { ISO8601DateFormatter().date(from: invite.slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isConfirm ? "checkmark.seal.fill" : "calendar.badge.plus")
                    .font(.system(size: 12, weight: .bold))
                Text(isConfirm ? "SECOND DATE · CONFIRMED" : "SECOND DATE · PROPOSED")
                    .font(.system(size: 10.5, weight: .heavy)).tracking(1)
            }
            .foregroundStyle(rose)
            Text(date.map { $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()) } ?? invite.slot)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(invite.title)
                .font(.system(size: 13))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            HStack(spacing: 8) {
                if isConfirm || accepted {
                    Button {
                        Haptics.tap()
                        onOpenMeet?(invite.meetCode)
                    } label: {
                        Label("Join on Whisper Meet", systemImage: "video.fill")
                            .font(.system(size: 12.5, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(rose, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("On both calendars 💘")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                } else if !isMine {
                    Button {
                        Haptics.tap()
                        accepting = true
                        Task {
                            let ok = await WhisperBackendService.shared.sendMessage(
                                toUserID: partnerUserID, toUsername: partnerName, body: WhisperSecondDate.encodeConfirm(invite), conversationKind: .dating
                            )
                            if ok { await WhisperSecondDate.addToCalendar(invite, partnerName: partnerName) }
                            await MainActor.run {
                                accepting = false
                                if ok { Haptics.success(); accepted = true }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if accepting { ProgressView().tint(.white) }
                            Text("Accept 💘").font(.system(size: 12.5, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(rose, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(accepting)
                    Text("Adds it to both calendars")
                        .font(.system(size: 11.5))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                } else {
                    Text("Waiting for @\(partnerName) to accept…")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 300, alignment: .leading)
        .background(rose.opacity(colorScheme == .dark ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(rose.opacity(0.3), lineWidth: 1) }
        .task {
            // The proposer adds the date to their own calendar when the
            // confirmation lands (the accepter added theirs on tap).
            if isConfirm && invite.from.lowercased() == AccountStorage.currentUserID.lowercased() {
                let key = "whisper-second-date-cal:\(invite.id)"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    await WhisperSecondDate.addToCalendar(invite, partnerName: partnerName)
                }
            }
        }
    }
}

// MARK: - Match expiry

/// Matches fade after 7 days without a message from either side — the
/// dating inbox shows "Fades in 2d" chips and a nudge, and faded matches
/// drop out of the active list. Same rule on web (`lib/matchExpiry.ts`).
nonisolated enum WhisperMatchExpiry {
    static let days: Int = 7

    struct State: Equatable {
        let daysLeft: Int
        let faded: Bool
        var nudge: Bool { !faded && daysLeft <= 2 }
        var chip: String? {
            if faded { return "Faded 💫" }
            if daysLeft <= 2 { return daysLeft <= 0 ? "Fades today 💫" : "Fades in \(daysLeft)d 💫" }
            return nil
        }
    }

    /// `matchedAt` — when the match landed; `lastMessageAt` — the newest
    /// human message in the thread (tokens don't count).
    static func state(matchedAt: Date, lastMessageAt: Date?, now: Date = Date()) -> State {
        let anchor = max(matchedAt, lastMessageAt ?? matchedAt)
        let elapsedDays = Int(now.timeIntervalSince(anchor) / 86_400)
        let left = days - elapsedDays
        return State(daysLeft: max(0, left), faded: left < 0)
    }
}
