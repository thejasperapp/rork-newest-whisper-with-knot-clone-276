import SwiftUI

nonisolated enum WhisperKnotBrowserError: Error { case server(String) }
nonisolated struct WhisperKnotBrowserState: Decodable, Sendable {
    let live: Bool
    var url: String?
    var title: String?
    var profile_persists: Bool?
    var outcomeUncertain: Bool?
    var operationPending: Bool?
    var agentRunning: Bool?
    var humanDriving: Bool?
    var can_go_back: Bool?
    var can_go_forward: Bool?
}
private nonisolated struct BrowserFindReceipt: Decodable { let count: Int }
private nonisolated struct BrowserDownloadReceipt: Decodable { let path: String }
nonisolated struct WhisperKnotBrowserTabs: Decodable, Sendable {
    nonisolated struct Tab: Decodable, Sendable, Identifiable, Equatable {
        let id: String
        var url: String?
        var title: String?
        var active: Bool?
        var label: String {
            if let title, !title.isEmpty { return title }
            if let url, let host = URL(string: url)?.host() { return host.replacingOccurrences(of: "www.", with: "") }
            return "New tab"
        }
    }
    var live: Bool?
    var active_id: String?
    var tabs: [Tab]?
}

/// Real provider frames with serialized input and a durable exclusive driver
/// gate. A human takeover discards queued agent actions on handback.
struct WhisperKnotBrowserView: View {
    let bot: WhisperKnotBot
    let conversationID: UUID
    var compact = false
    var enabled = true
    var showWhileBrowsing = false
    var onPresentationChange: ((Bool) -> Void)? = nil
    var open: (() -> Void)? = nil
    var onStopTask: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var browserState: WhisperKnotBrowserState?
    @State private var tabs: [WhisperKnotBrowserTabs.Tab] = []
    @State private var activeTabID: String?
    @State private var image: UIImage?
    @State private var capturedAt: Date?
    @State private var issue: String?
    @State private var frameIssue: String?
    @State private var stopping = false
    @State private var readingFrame = false
    @State private var address = ""
    @State private var text = ""
    @State private var expanded = false
    @State private var controls = false
    @State private var keyboardVisible = false
    @State private var addressVisible = false
    @State private var privacyVisible = false
    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat = 1
    @State private var dragSent: CGFloat = 0
    @State private var pendingScroll: Double = 0
    @State private var findText = ""
    @State private var finding = false
    @State private var utilityResult: String?
    @State private var busy = false
    @State private var invalidated = false
    @State private var refreshID = UUID()
    @State private var mutation: Task<Void, Never>?
    @State private var mutationEpoch = UUID()
    @State private var generation = AccountStorage.generation
    @FocusState private var textFocused: Bool

    private var live: Bool { browserState?.live == true }
    private var blocked: Bool { busy || invalidated || browserState?.outcomeUncertain == true || browserState?.operationPending == true || browserState?.agentRunning == true && browserState?.humanDriving != true }
    private var pollingKey: String { "\(scenePhase)-\(enabled)-\(expanded)-\(showWhileBrowsing)-\(refreshID)" }
    private var inlinePresented: Bool {
        enabled && !invalidated && scenePhase == .active &&
            showWhileBrowsing && live && image != nil
    }
    private var canRead: Bool { enabled && (!compact || showWhileBrowsing) && !invalidated && scenePhase == .active && generation == AccountStorage.generation && WhisperKnotContextPermission.allowed && !Task.isCancelled }
    private var status: String {
        if invalidated { return "Connection cleared" }
        if stopping { return "Stop requested" }
        if browserState?.outcomeUncertain == true { return "Action unconfirmed · stop before continuing" }
        if frameIssue != nil { return image == nil ? "Reconnecting to browser" : "Reconnecting · last captured frame" }
        if browserState?.humanDriving == true { return browserState?.operationPending == true ? "Taking control · finishing current action" : "You’re driving" }
        if browserState?.agentRunning == true { return "Knot is driving" }
        if busy || browserState?.operationPending == true { return "Updating browser" }
        if live { return "Knot’s browser · ready" }
        if browserState == nil { return issue == nil ? "Checking browser" : "Browser unavailable" }
        return "Browser stopped"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !compact || inlinePresented { browserCard }
        }
        .task(id: pollingKey) { await poll(inExpanded: false) }
        .onChange(of: inlinePresented, initial: true) { _, visible in onPresentationChange?(visible) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { pause() } }
        .onChange(of: enabled) { _, value in if !value { pause() } }
        .onDisappear { if !expanded { pause() } }
        .fullScreenCover(isPresented: $expanded) { expandedBrowser }
        .sheet(isPresented: Binding(get: { privacyVisible && !expanded }, set: { privacyVisible = $0 })) { privacySheet }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in clear() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperKnotContextChanged"))) { _ in clear() }
    }

    private var browserHeader: some View {
        HStack(spacing: 8) {
            WhisperKnotProfilePortrait(size: 24, expression: browserState?.agentRunning == true ? .thinking : .calm, tint: bot.portraitTint)
            Text("\(bot.displayName)’s browser").font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            if browserState?.agentRunning == true {
                Circle().fill(.green).frame(width: 7, height: 7)
                    .accessibilityLabel("Knot is browsing")
            }
        }
    }

    /// Genuine provider tabs only; switching and closing are explicit member
    /// actions and pause while Knot owns an active run.
    @ViewBuilder private func tabStrip(dark: Bool) -> some View {
        if live, !tabs.isEmpty {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tabs) { tab in
                            let selected = tab.id == activeTabID || (activeTabID == nil && tab.active == true)
                            HStack(spacing: 6) {
                                Button { if !selected { Haptics.tap(); perform("tab_activate", fields: ["tabID": .string(tab.id)]) } } label: {
                                    Text(tab.label).font(.caption.weight(selected ? .semibold : .regular)).lineLimit(1)
                                        .frame(maxWidth: 140, alignment: .leading)
                                }.buttonStyle(.plain)
                                if tabs.count > 1 {
                                    Button { perform("tab_close", fields: ["tabID": .string(tab.id)]) } label: {
                                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 22, height: 22)
                                    }.buttonStyle(.plain).accessibilityLabel("Close \(tab.label)")
                                }
                            }
                            .padding(.leading, 12).padding(.trailing, tabs.count > 1 ? 4 : 12).frame(minHeight: 34)
                            .background(selected ? (dark ? Color.white.opacity(0.18) : Color.primary.opacity(0.09)) : (dark ? Color.white.opacity(0.06) : Color.primary.opacity(0.03)), in: Capsule())
                            .id(tab.id)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                        Button { perform("tab_open") } label: {
                            Image(systemName: "plus").font(.caption.weight(.semibold)).frame(width: 34, height: 34)
                        }.buttonStyle(.plain).accessibilityLabel("New tab")
                    }
                }
                .onChange(of: activeTabID) { _, id in if let id { withAnimation(.snappy) { reader.scrollTo(id, anchor: .center) } } }
            }
            .disabled(blocked)
            .animation(.snappy, value: tabs)
        }
    }

    private var browserCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            browserHeader
            tabStrip(dark: false)
            browserStage.aspectRatio(1.6, contentMode: .fit)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        if compact, let open { open() } else { expanded = true }
                    } label: {
                        HStack(spacing: 7) {
                            Text("Open browser").font(.subheadline.weight(.medium))
                            Image(systemName: "arrow.up.right.and.arrow.down.left").font(.subheadline)
                        }.padding(.horizontal, 15).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .modifier(WhisperControlGlass(shape: Capsule()))
                    .disabled(invalidated)
                    .padding(12)
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if busy || browserState?.agentRunning == true { ProgressView().controlSize(.mini) }
                Text(status)
                Spacer(minLength: 0)
                if let capturedAt { Text(capturedAt, style: .time).monospacedDigit() }
            }.font(.caption2).foregroundStyle(.secondary)
            if !compact {
                HStack(spacing: 16) {
                    if !live, browserState?.outcomeUncertain != true {
                        Button("Start browser") { perform("start") }.disabled(blocked || browserState == nil)
                    }
                    if live || busy || browserState?.outcomeUncertain == true || browserState?.agentRunning == true {
                        Button("Stop browser") { stopBrowser() }.disabled(stopping || invalidated)
                    }
                    Spacer(minLength: 0)
                    Button { privacyVisible = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Browser privacy")
                }.font(.subheadline).buttonStyle(.plain)
                if let issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var expandedBrowser: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    browserStage
                        .frame(width: proxy.size.width * zoom, height: max(proxy.size.height, proxy.size.width * zoom / 1.6))
                }.defaultScrollAnchor(.center).scrollIndicators(.hidden)
                    .scrollDisabled(controls && zoom <= 1)
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        zoom = min(4, max(1, pinchStart * value.magnification))
                    }.onEnded { _ in pinchStart = zoom })
            }
            .background(.black)
            .safeAreaInset(edge: .bottom, spacing: 0) { manualDock }
            .foregroundStyle(.white).tint(.white)
            .toolbarBackground(.black, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { expanded = false; textFocused = false; keyboardVisible = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close browser")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 3) {
                        Text(status).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(browserState?.title?.isEmpty == false ? browserState!.title! : "\(bot.displayName) Computer")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { expanded = false; textFocused = false; keyboardVisible = false } label: { Image(systemName: "checkmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Done with browser controls")
                }
            }
            .sheet(isPresented: $privacyVisible) { privacySheet }
            .task(id: pollingKey) { await poll(inExpanded: true) }
            .onDisappear { textFocused = false; if !enabled || invalidated { pause() } }
        }.environment(\.colorScheme, .dark)
    }

    private var browserStage: some View {
        GeometryReader { proxy in
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(.rect)
                    .onTapGesture(count: 2) { zoom = zoom > 1 ? 1 : 2.5; pinchStart = zoom }
                    .onTapGesture { location in
                        guard expanded, controls, !blocked else { return }
                        let scale = min(proxy.size.width / 1280, proxy.size.height / 800)
                        guard scale > 0 else { return }
                        let origin = CGPoint(x: (proxy.size.width - 1280 * scale) / 2, y: (proxy.size.height - 800 * scale) / 2)
                        let point = CGPoint(x: (location.x - origin.x) / scale, y: (location.y - origin.y) / scale)
                        guard point.x >= 0, point.y >= 0, point.x < 1280, point.y < 800 else { return }
                        sendInput(["kind": .string("click"), "x": .number(Double(Int(point.x))), "y": .number(Double(Int(point.y)))])
                        keyboardVisible = true; textFocused = true
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                        guard expanded, controls, zoom <= 1 else { return }
                        let scale = min(proxy.size.width / 1280, proxy.size.height / 800)
                        guard scale > 0 else { return }
                        let delta = -(value.translation.height - dragSent) / scale
                        if abs(delta) >= 45 { dragSent = value.translation.height; enqueueScroll(Double(delta)) }
                    }.onEnded { value in
                        defer { dragSent = 0 }
                        guard expanded, controls, zoom <= 1 else { return }
                        let scale = min(proxy.size.width / 1280, proxy.size.height / 800)
                        guard scale > 0 else { return }
                        let remaining = value.translation.height - dragSent
                        let momentum = (value.predictedEndTranslation.height - value.translation.height) * 0.4
                        enqueueScroll(Double(-(remaining + momentum) / scale))
                    })
                    .accessibilityLabel("Remote browser page. Take control to tap or drag the page. Pinch or double tap to inspect details.")
                    .accessibilityScrollAction { edge in
                        if edge == .bottom { enqueueScroll(600) }
                        if edge == .top { enqueueScroll(-600) }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "globe").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                    Text(status).font(.subheadline.weight(.medium))
                    Text(invalidated ? "Reopen Computer to reconnect." : browserState?.outcomeUncertain == true ? "Choose Stop before continuing." : live || showWhileBrowsing ? "Waiting for a genuine browser frame." : "Ask Knot to visit a public site, or start the browser.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24).frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private var manualDock: some View {
        VStack(spacing: 10) {
            tabStrip(dark: true)
            HStack(spacing: 4) {
                Button { perform("back") } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(blocked || !live || browserState?.can_go_back == false).accessibilityLabel("Back")
                Button { perform("forward") } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(blocked || !live || browserState?.can_go_forward == false).accessibilityLabel("Forward")
                Button {
                    address = browserState?.url ?? ""; addressVisible.toggle()
                } label: {
                    Text(URL(string: browserState?.url ?? "")?.host() ?? "Website address")
                        .font(.subheadline).lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
                }.disabled(blocked || !live).accessibilityLabel("Edit website address")
                Button { if let url = browserState?.url { perform("navigate", fields: ["url": .string(url)]) } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.disabled(blocked || !live).accessibilityLabel("Reopen current address")
            }.buttonStyle(.plain)
            if finding {
                HStack {
                    TextField("Find in page", text: $findText).autocorrectionDisabled().onSubmit { findInPage() }
                    Button("Find") { findInPage() }.disabled(blocked || findText.isEmpty)
                    Button { finding = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close find")
                }.font(.subheadline)
            }
            if let utilityResult { Text(utilityResult).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if addressVisible {
                HStack(spacing: 10) {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                    TextField("Website address", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).onSubmit { navigate() }
                    Button("Go") { navigate() }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(14).background(.white.opacity(0.1), in: .rect(cornerRadius: 20)).disabled(blocked || !live)
            }
            if keyboardVisible {
                HStack(spacing: 10) {
                    TextField("Text for the browser", text: $text).focused($textFocused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.send)
                        .onSubmit { typeText() }
                        .onChange(of: text) { _, value in if value.count > 4000 { text = String(value.prefix(4000)) } }
                    Button(action: typeText) { Image(systemName: "arrow.up.circle.fill").font(.title2).frame(width: 44, height: 44) }
                        .accessibilityLabel("Type text in remote browser").disabled(text.isEmpty)
                }.padding(.leading, 16).padding(.trailing, 6).background(.white.opacity(0.1), in: Capsule()).disabled(blocked || !live)
                Text("Tap a page field, then type here. Only Send forwards this text to the page.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let frameIssue { Text(frameIssue).font(.caption2).foregroundStyle(.secondary) }
            if let issue { Text(issue).font(.caption).foregroundStyle(.yellow.opacity(0.9)) }
            HStack(spacing: 10) {
                Button { perform(controls ? "hand-back" : "take-control") } label: {
                    Text(controls ? "Let Knot continue" : "Take control").font(.subheadline.weight(.medium)).padding(.horizontal, 18).frame(minHeight: 48)
                }.buttonStyle(.plain).background(.white.opacity(0.14), in: Capsule()).disabled(busy || stopping || invalidated || !live)
                HStack(spacing: 0) {
                    Button {
                        keyboardVisible.toggle(); textFocused = keyboardVisible
                    } label: { Image(systemName: "keyboard").frame(width: 48, height: 48) }
                        .accessibilityLabel("Browser keyboard").disabled(blocked || !live)
                    Menu {
                        Button("Website address", systemImage: "globe") { addressVisible.toggle(); if address.isEmpty { address = browserState?.url ?? "" } }
                        Button(zoom > 1 ? "Fit page" : "Enlarge page", systemImage: "arrow.up.left.and.arrow.down.right") { zoom = zoom > 1 ? 1 : 2.5; pinchStart = zoom }
                        Button("Refresh image", systemImage: "arrow.clockwise") { refreshID = UUID() }
                        if live {
                            Button("Back", systemImage: "chevron.backward") { perform("back") }.disabled(blocked)
                            Button("Forward", systemImage: "chevron.forward") { perform("forward") }.disabled(blocked)
                        }
                        if !live { Button("Start browser", systemImage: "play") { perform("start") }.disabled(blocked || browserState == nil) }
                        Button("Home in new tab", systemImage: "house") { perform("tab_open") }.disabled(blocked || !live)
                        Button("Find in page", systemImage: "magnifyingglass") { finding.toggle() }.disabled(blocked || !live)
                        Button("Download current file", systemImage: "arrow.down.to.line") {
                            if let url = browserState?.url { perform("download", fields: ["url": .string(url)]) }
                        }.disabled(blocked || !live)
                        if let url = URL(string: browserState?.url ?? ""), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                            Link(destination: url) { Label("Open in Safari", systemImage: "safari") }
                            ShareLink(item: url) { Label("Share page", systemImage: "square.and.arrow.up") }
                        }
                        Section("Page keyboard") {
                            ForEach(["Enter", "Tab", "Escape", "Backspace", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"], id: \.self) { key in
                                Button(key.replacingOccurrences(of: "Arrow", with: "")) { sendInput(["kind": .string("key"), "key": .string(key)]) }.disabled(blocked || !live)
                            }
                        }
                        Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { keyboardVisible = false; textFocused = false }
                        Button("Stop browser", systemImage: "stop", role: .destructive) { stopBrowser() }.disabled(stopping || invalidated)
                    } label: { Image(systemName: "ellipsis").frame(width: 48, height: 48) }
                        .accessibilityLabel("More browser controls")
                }.buttonStyle(.plain).background(.white.opacity(0.14), in: Capsule())
            }.frame(maxWidth: .infinity)
            if let capturedAt {
                Text("Updated \(capturedAt.formatted(date: .omitted, time: .standard)) · Pinch to inspect · Drag at fit size to scroll")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10).background(.black)
    }

    private var privacySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your remote browser").font(.title2.bold())
                    Text("Pages and input go through Whisper to the operator-managed Knot browser at knot-shell.mydailywhisper.com. While AI sharing is on, Knot can read this page’s visible text and genuine screenshots through Whisper’s live Knot service and Rork AI Cloud (via Vercel AI Gateway) to OpenAI.")
                    Text("Your profile—cookies, sign-ins and site storage—persists in your account’s remote workspace across tasks and bots. The process starts on demand and may stop after 30 idle minutes. Stop closes the process; it does not erase the profile. Images stay in memory only.")
                    Text("Take control pauses new Knot inputs. An action already sent finishes before your input is accepted. Let Knot continue discards any queued action and observes the page anew. Only genuine page images are shown. Pinch to inspect; drag at fit size to scroll.")
                    Text("Personal-account actions keep their separate permissions. Turning off AI sharing clears this viewer and stops new input, but does not erase the profile or close the remote process; use Stop browser first.")
                }.font(.subheadline).padding(24)
            }.navigationTitle("Browser privacy").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { privacyVisible = false } } }
        }
    }
    private func findInPage() {
        guard !findText.isEmpty else { return }
        perform("find", fields: ["text": .string(findText)])
    }
    private func enqueueScroll(_ delta: Double) {
        guard controls, canRead, browserState?.outcomeUncertain != true else { return }
        pendingScroll = min(4800, max(-4800, pendingScroll + delta))
        flushScroll()
    }
    private func flushScroll() {
        guard !blocked, controls, abs(pendingScroll) >= 1 else { return }
        let delta = min(1600, max(-1600, pendingScroll.rounded()))
        pendingScroll -= delta
        sendInput(["kind": .string("scroll"), "dy": .number(delta)])
    }
    private func navigate() {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        textFocused = false; perform("navigate", fields: ["url": .string(value)])
    }
    private func typeText() {
        guard !text.isEmpty else { return }
        sendInput(["kind": .string("type"), "text": .string(text)])
    }
    private func stopBrowser() { onStopTask?(); perform("stop") }
    private func sendInput(_ value: [String: WhisperKnotReceiptJSON]) {
        guard image != nil else { return }
        perform("input", fields: ["input": .object(value)])
    }
    private func perform(_ action: String, fields: [String: WhisperKnotReceiptJSON] = [:]) {
        let driverAction = action == "take-control" || action == "hand-back"
        guard canRead, action == "stop" ? !stopping : driverAction ? !busy && !stopping : !blocked else { return }
        // Stop supersedes a pending local action. Its old response cannot publish
        // frames, clear the Stop state or send another mutation after this epoch.
        mutationEpoch = UUID()
        mutation?.cancel()
        if action != "input" { pendingScroll = 0 }
        if action == "stop" { stopping = true; image = nil; capturedAt = nil; textFocused = false }
        let epoch = mutationEpoch
        busy = true; issue = nil
        mutation = Task { @MainActor in
            defer { if epoch == mutationEpoch { busy = false; stopping = false; refreshID = UUID(); flushScroll() } }
            do {
                let data = try await WhisperKnotShellEvidenceService.fetch(action, bot: bot.rawValue, conversationID: conversationID.uuidString, browser: true, fields: fields)
                guard canRead, epoch == mutationEpoch else { return }
                if action == "stop" { image = nil; capturedAt = nil; controls = false; keyboardVisible = false; browserState = .init(live: false) }
                if driverAction {
                    controls = action == "take-control"; browserState?.humanDriving = controls
                    if !controls { keyboardVisible = false; textFocused = false; text = "" }
                }
                if action == "input", case .object(let input)? = fields["input"], case .string("type")? = input["kind"] { text = "" }
                if action == "find", let result = try? JSONDecoder().decode(BrowserFindReceipt.self, from: data) { utilityResult = "\(result.count) matches on this page" }
                if action == "download", let result = try? JSONDecoder().decode(BrowserDownloadReceipt.self, from: data) { utilityResult = "Saved to \(result.path)" }
                await load()
            } catch {
                guard canRead, epoch == mutationEpoch else { return }
                pendingScroll = 0
                if case WhisperKnotBrowserError.server("invalid_browser_url") = error {
                    issue = "Use a public website address, without sign-in credentials in the address."
                } else if case WhisperKnotBrowserError.server("browser_busy") = error {
                    issue = "Another browser action is still in progress. Refresh before choosing what to do next."
                } else {
                    issue = "This action wasn’t confirmed. It has not been repeated. Refresh to inspect the browser, or explicitly stop it before continuing."
                }
            }
        }
    }
    private func poll(inExpanded: Bool) async {
        guard canRead, expanded == inExpanded else { return }
        await load()
        while canRead, expanded == inExpanded {
            // A stopped process is quiet until a new task remounts the preview
            // or Computer is explicitly refreshed/started by the member.
            if browserState?.live == false && browserState?.agentRunning != true && browserState?.operationPending != true { return }
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            await load()
        }
    }
    private func load() async {
        guard canRead, !stopping, !readingFrame else { return }
        let epoch = mutationEpoch
        readingFrame = true
        defer { readingFrame = false }
        do {
            let data = try await WhisperKnotShellEvidenceService.fetch("state", bot: bot.rawValue, conversationID: conversationID.uuidString, browser: true)
            let value = try JSONDecoder().decode(WhisperKnotBrowserState.self, from: data)
            guard canRead, !stopping, epoch == mutationEpoch else { return }
            browserState = value
            controls = value.humanDriving == true
            if !controls { pendingScroll = 0; keyboardVisible = false; textFocused = false }
            if value.outcomeUncertain == true { image = nil; capturedAt = nil; return }
            if value.live {
                let bytes = try await WhisperKnotShellEvidenceService.fetch("screenshot", bot: bot.rawValue, conversationID: conversationID.uuidString, browser: true)
                guard canRead, !stopping, epoch == mutationEpoch else { return }
                guard let frame = UIImage(data: bytes), frame.size == CGSize(width: 1280, height: 800) else { throw URLError(.cannotDecodeContentData) }
                image = frame; capturedAt = Date(); frameIssue = nil
                // Tabs are optional context; a failure never blocks the frame.
                if let data = try? await WhisperKnotShellEvidenceService.fetch("tabs", bot: bot.rawValue, conversationID: conversationID.uuidString, browser: true),
                   let value = try? JSONDecoder().decode(WhisperKnotBrowserTabs.self, from: data), canRead, !stopping, epoch == mutationEpoch {
                    tabs = value.tabs ?? []; activeTabID = value.active_id
                }
            } else { image = nil; capturedAt = nil; frameIssue = nil; tabs = []; activeTabID = nil }
        } catch {
            guard canRead, !stopping, epoch == mutationEpoch else { return }
            frameIssue = "Live image paused. Reconnecting; no input is repeated."
        }
    }
    private func pause() {
        pendingScroll = 0; dragSent = 0
        mutationEpoch = UUID(); mutation?.cancel(); mutation = nil; busy = false; stopping = false; frameIssue = nil
        image = nil; capturedAt = nil; controls = false; text = ""; keyboardVisible = false; textFocused = false; tabs = []; activeTabID = nil
    }
    private func clear() {
        invalidated = true; expanded = false; privacyVisible = false; pause(); browserState = nil; address = ""; issue = nil
    }
}
