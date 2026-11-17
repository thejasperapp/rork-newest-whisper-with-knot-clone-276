import SwiftUI
import UIKit

/// A dedicated presenter can place an invitation above the current chat or
/// sheet. It never borrows human CallKit/PushKit signaling or starts audio.
struct WhisperKnotContactPresentation: ViewModifier {
    @State private var service = WhisperKnotContactService.shared
    func body(content: Content) -> some View {
        content.background {
            WhisperKnotContactPresenter(target: service.presentation) { id in
                if service.presentation?.id == id { service.presentation = nil }
            }.frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }
}
private struct WhisperKnotContactPresenter: UIViewControllerRepresentable {
    let target: WhisperKnotContactTarget?
    let onDismiss: (UUID) -> Void
    @Environment(\.scenePhase) private var scenePhase
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> Anchor {
        let anchor = Anchor(); anchor.view.backgroundColor = .clear; anchor.view.isUserInteractionEnabled = false
        return anchor
    }
    func updateUIViewController(_ controller: Anchor, context: Context) {
        context.coordinator.update(target, phase: scenePhase, from: controller, onDismiss: onDismiss)
        controller.ready = { [weak coordinator = context.coordinator, weak controller] in
            guard let controller else { return }; coordinator?.update(target, phase: scenePhase, from: controller, onDismiss: onDismiss)
        }
    }
    static func dismantleUIViewController(_ controller: Anchor, coordinator: Coordinator) { coordinator.close(); controller.ready = nil }
    final class Anchor: UIViewController {
        var ready: (() -> Void)?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); ready?() }
    }
    final class Hosting: UIHostingController<AnyView> {
        var didClose: (() -> Void)?
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isBeingDismissed || presentingViewController == nil { didClose?() }
        }
    }
    @MainActor final class Coordinator {
        private var hosting: Hosting?
        private var targetID: UUID?
        private var attempt: Task<Void, Never>?
        private var phase: ScenePhase = .inactive
        func close() {
            attempt?.cancel(); attempt = nil
            hosting?.didClose = nil; hosting?.dismiss(animated: false); hosting = nil; targetID = nil
        }
        private func destination(_ target: WhisperKnotContactTarget, onDismiss: @escaping (UUID) -> Void) -> AnyView {
            AnyView(WhisperKnotContactDestination(target: target, close: { [weak self] in
                guard let self, self.targetID == target.id, let host = self.hosting else { return }
                host.didClose = nil
                host.dismiss(animated: true) { [weak self, weak host] in
                    guard let self, let host, self.targetID == target.id, self.hosting === host else { return }
                    self.close(); onDismiss(target.id)
                }
            }).environment(\.scenePhase, phase))
        }
        func update(_ target: WhisperKnotContactTarget?, phase: ScenePhase, from anchor: Anchor, onDismiss: @escaping (UUID) -> Void) {
            guard let target else { close(); return }
            if targetID == target.id {
                if self.phase != phase {
                    self.phase = phase
                    // This independently hosted SwiftUI root must receive the
                    // real scene lifecycle rather than an initial default value.
                    hosting?.rootView = destination(target, onDismiss: onDismiss)
                }
                return
            }
            close(); targetID = target.id; self.phase = phase
            attempt = Task { @MainActor [weak self, weak anchor] in
                for _ in 0..<40 {
                    guard let self, let anchor, !Task.isCancelled, self.targetID == target.id else { return }
                    if let root = anchor.view.window?.rootViewController {
                        // An optional welcome never takes ownership over an
                        // existing sheet, alert, permission flow or human call.
                        if target.welcome != nil && root.presentedViewController != nil { onDismiss(target.id); return }
                        var top = root
                        while let presented = top.presentedViewController { top = presented }
                        if !top.isBeingDismissed && !top.isBeingPresented && !(top is UIAlertController) {
                            let host = Hosting(rootView: self.destination(target, onDismiss: onDismiss))
                            host.modalPresentationStyle = .fullScreen
                            host.didClose = { [weak self, weak host] in
                                guard let host, self?.targetID == target.id, self?.hosting === host else { return }
                                self?.hosting = nil; self?.targetID = nil; onDismiss(target.id)
                            }
                            self.hosting = host; top.present(host, animated: true); return
                        }
                    }
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
                onDismiss(target.id)
            }
        }
    }
}

private struct WhisperKnotContactDestination: View {
    let target: WhisperKnotContactTarget
    let close: () -> Void
    @State private var service = WhisperKnotContactService.shared
    @State private var answered: WhisperKnotIncomingAnswer?
    @State private var showUpdate = false
    @State private var busy = false
    @State private var error: String?
    @State private var answerID = UUID().uuidString.lowercased()
    @State private var answerAttempted = false
    @State private var visible = false
    @State private var operation: Task<Void, Never>?
    @State private var generation = AccountStorage.generation
    @State private var revision = WhisperKnotContextPermission.revision
    @Environment(\.scenePhase) private var scenePhase
    private var leaseValid: Bool { visible && generation == AccountStorage.generation && revision == WhisperKnotContextPermission.revision && scenePhase == .active }
    var body: some View {
        Group {
            if let welcome = target.welcome {
                WhisperKnotWelcomeDestination(invitation: welcome, close: close)
            } else if let answered {
                WhisperEmberVoiceScreen(knotBot: target.bot, incoming: answered, onExternalClose: close)
            } else if showUpdate || target.invitation == nil {
                WhisperEmberChatView(initialBot: target.bot, initialConversationID: target.conversationID, onExternalClose: close)
            } else if let original = target.invitation {
                invitation(service.current(original))
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; operation?.cancel() }
        .task {
            if target.invitation != nil { await service.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { operation?.cancel(); close() } }
        .onChange(of: WhisperCameraCallMonitor.shared.callOwnsAudio) { _, owns in if owns { operation?.cancel(); close() } }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in operation?.cancel(); answered = nil; close() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in operation?.cancel(); close() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotVoiceConsentChanged"))) { _ in if !WhisperKnotVoicePreferences.allowed { operation?.cancel(); close() } }
    }
    private func invitation(_ invite: WhisperKnotInvitation) -> some View {
        ZStack {
            Color.black.ignoresSafeArea().overlay {
                WhisperKnotProfilePortrait(size: 720, expression: .calm, tint: target.bot.portraitTint)
                    .environment(\.whisperMediaActive, false).blur(radius: 64, opaque: true).saturation(0.9).overlay(.black.opacity(0.62))
            }.clipped()
            VStack(spacing: 0) {
                HStack {
                    Label("Whisper Audio · AI invitation", systemImage: "phone.arrow.down.left.fill").font(.subheadline.weight(.medium))
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close invitation")
                }.foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 24)
                WhisperKnotProfilePortrait(size: 128, expression: .calm, tint: target.bot.portraitTint).environment(\.whisperMediaActive, false)
                Text(target.bot.displayName).font(.system(size: 32, weight: .semibold)).padding(.top, 24)
                Text(invite.title).font(.title3).multilineTextAlignment(.center).padding(.top, 12)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(invite.state == "invited" && invite.expires > context.date ? "Would you like to talk?" : invite.status)
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75)).padding(.top, 10)
                }
                if let error { Text(error).font(.subheadline).multilineTextAlignment(.center).padding(.top, 18) }
                Spacer(minLength: 24)
                Button("View update") {
                    guard !busy else { return }; busy = true
                    operation = Task { @MainActor in
                        await WhisperKnotBackgroundService.shared.syncMessages()
                        guard leaseValid, !Task.isCancelled else { return }
                        busy = false; showUpdate = true
                    }
                }.font(.subheadline.weight(.medium)).frame(minHeight: 44).padding(.bottom, 24).disabled(busy)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if invite.canAnswer {
                        HStack(spacing: 80) {
                            callControl("Decline", icon: "phone.down.fill", color: .red) { change(invite, action: "decline") }
                            callControl(answerAttempted ? "Retry answer" : "Answer", icon: "phone.fill", color: .green) { change(invite, action: "answer") }
                                .disabled(!WhisperKnotContextPermission.allowed || !WhisperKnotVoicePreferences.allowed)
                        }.disabled(busy)
                    } else if canRetryAnswer(invite) {
                        callControl("Retry answer", icon: "phone.fill", color: .green) { change(invite, action: "answer") }
                            .disabled(busy || !WhisperKnotContextPermission.allowed || !WhisperKnotVoicePreferences.allowed)
                    } else { Button("Done", action: close).buttonStyle(.bordered).tint(.white).controlSize(.large) }
                }
                if busy { ProgressView().tint(.white).padding(.top, 18).accessibilityLabel("Confirming invitation") }
                Text("No microphone until you answer").font(.caption).foregroundStyle(.white.opacity(0.5)).padding(.top, 28)
            }.frame(maxWidth: 520).padding(.horizontal, 24).padding(.vertical, 24)
        }.foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
    private func callControl(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button(action: action) { Image(systemName: icon).font(.system(size: 24, weight: .medium)).frame(width: 64, height: 64).background(color, in: Circle()) }.buttonStyle(.plain).accessibilityLabel(title)
            Text(title).font(.caption)
        }
    }
    private func canRetryAnswer(_ invite: WhisperKnotInvitation) -> Bool {
        answerAttempted && invite.state == "answered" && invite.connectedAt == nil && invite.expires > Date()
    }
    private func change(_ invite: WhisperKnotInvitation, action: String) {
        guard leaseValid, !busy, (invite.canAnswer || (action == "answer" && canRetryAnswer(invite))), !WhisperCameraCallMonitor.shared.callOwnsAudio else { return }
        if action == "answer" {
            guard WhisperKnotContextPermission.allowed, WhisperKnotVoicePreferences.allowed, !WhisperKnotVoiceSession.isBusy else { return }
            answerAttempted = true
        }
        busy = true; error = nil; Haptics.tap()
        operation = Task { @MainActor in
            do {
                let updated = try await service.change(invite, action: action, answerID: answerID)
                guard leaseValid, !Task.isCancelled else { return }
                busy = false
                if action == "answer" { answered = .init(invitation: updated, answerID: answerID) }
                else { close() }
            } catch {
                guard leaseValid, !Task.isCancelled else { return }; busy = false
                self.error = "Couldn’t confirm this invitation. Refresh before trying again."
                await service.refresh()
            }
        }
    }
}
