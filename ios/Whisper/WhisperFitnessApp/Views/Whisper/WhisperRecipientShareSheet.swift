import SwiftUI

/// Shared compact recipient tray. Selection never sends until the explicit Send action.
struct WhisperRecipientShareSheet<Actions: View>: View {
    let payload: String
    var hasActions: Bool = false
    var isBusy: Bool = false
    var sendingDisabledReason: String? = nil
    var directOnly: Bool = false
    var deliverPayload: ((String, String, UUID) async -> Bool)? = nil
    /// Optional plain-language reason for the most recent payload failure.
    var payloadFailureReason: (() -> String?)? = nil
    var onSent: () -> Void = {}
    @ViewBuilder let actions: () -> Actions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var backend = WhisperBackendService.shared
    @State private var groups = WhisperGroupChatService.shared
    @State private var suggestions: [WhisperUserRow] = []
    @State private var ranked: [Recipient] = []
    @State private var searchResults: [WhisperUserRow] = []
    @State private var searching: Bool = false
    @State private var searchFailed: Bool = false
    @State private var query: String = ""
    @State private var selected: [Recipient] = []
    @State private var note: String = ""
    @State private var sending: Bool = false
    @State private var loaded: Bool = false
    @State private var failure: String?
    @State private var sentRecipients: Set<String> = []
    @State private var payloadDelivered: Set<String> = []
    @State private var groupReceipts: [String: Set<String>] = [:]
    @State private var deliveryIDs: [String: UUID] = [:]
    @State private var frozenNote: String?
    @State private var frozenPayload: String?
    @State private var generation: UUID = AccountStorage.generation
    @State private var isClosed: Bool = false
    @State private var confirmClose: Bool = false
    @State private var searchAttempt: Int = 0
    @State private var detent: PresentationDetent = .height(320)
    @FocusState private var searchFocused: Bool
    @FocusState private var noteFocused: Bool

    init(payload: String, hasActions: Bool = false, isBusy: Bool = false, sendingDisabledReason: String? = nil,
         directOnly: Bool = false, deliverPayload: ((String, String, UUID) async -> Bool)? = nil,
         payloadFailureReason: (() -> String?)? = nil,
         onSent: @escaping () -> Void = {}, @ViewBuilder actions: @escaping () -> Actions) {
        self.payload = payload
        self.hasActions = hasActions
        self.isBusy = isBusy
        self.sendingDisabledReason = sendingDisabledReason
        self.directOnly = directOnly
        self.deliverPayload = deliverPayload
        self.payloadFailureReason = payloadFailureReason
        self.onSent = onSent
        self.actions = actions
        _detent = State(initialValue: .height(hasActions ? 320 : 220))
    }

    private struct Recipient: Identifiable {
        let userID: String
        let username: String
        var group: WhisperGroup? = nil
        var kind: WhisperConversationKind = .direct
        var id: String { group != nil ? userID : kind.localKey(peer: userID) }
    }

    private var ink: Color { WhisperTheme.ink(scheme) }
    private var muted: Color { WhisperTheme.muted(scheme) }
    private var isCurrent: Bool { !isClosed && generation == AccountStorage.generation && !Task.isCancelled }
    private var expanded: Bool { searchFocused || !query.isEmpty || detent == .large }
    private var idleHeight: CGFloat { hasActions ? 320 : 220 }
    private var compactHeight: CGFloat { selected.isEmpty ? idleHeight : 400 }
    private var needsCloseDecision: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || failure != nil }
    private var selectionLocked: Bool { sending || isBusy || failure != nil }
    private var sheetDetents: Set<PresentationDetent> {
        typeSize.isAccessibilitySize ? [.large] : [.height(idleHeight), .height(400), .large]
    }

    private var people: [Recipient] {
        var seen: Set<String> = []
        let candidates = ranked + (searchResults + suggestions).map {
            Recipient(userID: $0.user_id.lowercased(), username: $0.username)
        }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { recipient in
            (!directOnly || recipient.group == nil && recipient.kind == .direct) && seen.insert(recipient.id).inserted &&
            (term.isEmpty || WhisperUserSearch.matches(term, username: recipient.username, displayName: actualName(recipient)))
        }
    }

    private func actualName(_ recipient: Recipient) -> String? {
        (searchResults + suggestions).first { $0.user_id.lowercased() == recipient.userID.lowercased() }?.display_name
            ?? backend.threadProfiles[recipient.userID.lowercased()]?.display_name
    }

    private func subtitle(_ recipient: Recipient) -> String {
        if recipient.kind == .dating { return "Dating" }
        if recipient.group != nil { return "Group" }
        return actualName(recipient) ?? "Whisper"
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            ScrollView {
                VStack(spacing: 12) {
                    if expanded { recipientList } else { recipientRail }
                    if let sendingDisabledReason {
                        Text(sendingDisabledReason).font(.footnote).foregroundStyle(muted).padding(.horizontal, 16)
                    }
                    if let failure {
                        Text(failure).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
                    }
                    if hasActions && selected.isEmpty {
                        Divider()
                        actions().padding(.bottom, 12).disabled(isBusy)
                    }
                }.padding(.top, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            if !selected.isEmpty { sendFooter }
        }
        .foregroundStyle(ink)
        .presentationBackground(WhisperTheme.surface(scheme))
        .presentationCornerRadius(30)
        .presentationDetents(sheetDetents, selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(sending || isBusy || needsCloseDecision)
        .confirmationDialog("Close sharing?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Close without finishing", role: .destructive) { close() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(failure == nil ? "Your unsent message will be discarded." : "Some deliveries may already have arrived. Closing ends this retry session; reopening and sending again may create duplicates.")
        }
        .onAppear { if detent != .large { detent = typeSize.isAccessibilitySize ? .large : .height(compactHeight) } }
        .onChange(of: typeSize) { _, value in if value.isAccessibilitySize { detent = .large } }
        .onChange(of: selected.isEmpty) { _, _ in if detent != .large { detent = .height(compactHeight) } }
        .onChange(of: searchFocused) { _, focused in if focused { detent = .large } }
        .onChange(of: noteFocused) { _, focused in if focused { detent = .large } }
        .task {
            rebuildRanking()
            await backend.fetchThreads()
            guard isCurrent else { return }
            rebuildRanking()
        }
        .task {
            guard !directOnly else { return }
            await groups.syncRegistry()
            guard isCurrent, !Task.isCancelled else { return }
            rebuildRanking()
        }
        .task {
            let users = await WhisperUserService.shared.suggestions(limit: 24)
            guard isCurrent, !Task.isCancelled else { return }
            suggestions = users; loaded = true
        }
        .task(id: "\(query)|\(searchAttempt)") { await search() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            isClosed = true; selected = []; ranked = []; suggestions = []; searchResults = []; note = ""
            frozenPayload = nil; frozenNote = nil; deliveryIDs = [:]; groupReceipts = [:]; dismiss()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(muted)
                TextField(directOnly ? "Search friends" : "Search people and groups", text: $query).font(.subheadline)
                    .focused($searchFocused).autocorrectionDisabled().textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(WhisperTheme.card(scheme), in: .capsule)
            if expanded && !typeSize.isAccessibilitySize {
                Button {
                    query = ""; searchFocused = false; noteFocused = false; detent = .height(compactHeight)
                } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                .accessibilityLabel("Collapse sharing")
            }
            Button {
                if needsCloseDecision { confirmClose = true } else { close() }
            } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
                    .background(WhisperTheme.card(scheme), in: .circle)
            }.accessibilityLabel("Close sharing")
        }
        .buttonStyle(.plain).disabled(sending || isBusy)
        .padding(.horizontal, 16).padding(.top, 24)
    }

    @ViewBuilder private var recipientRail: some View {
        if people.isEmpty { emptyRecipients }
        else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(people) { person in
                        Button { select(person) } label: {
                            VStack(spacing: 5) {
                                avatar(person, size: 58)
                                Text(person.username).font(.caption).lineLimit(1)
                                Text(subtitle(person)).font(.caption2).foregroundStyle(muted).lineLimit(1)
                            }.frame(width: 76).padding(.vertical, 3).contentShape(.rect)
                        }
                        .buttonStyle(.plain).disabled(selectionLocked || sentRecipients.contains(person.id))
                        .accessibilityLabel(recipientLabel(person))
                        .accessibilityAddTraits(selected.contains(where: { $0.id == person.id }) ? [.isSelected] : [])
                    }
                    Button { detent = .large } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "person.2").font(.title3).frame(width: 58, height: 58)
                                .background(WhisperTheme.card(scheme), in: .circle)
                            Text("See all").font(.caption)
                        }.frame(width: 76).padding(.vertical, 3)
                    }.buttonStyle(.plain).disabled(sending || isBusy)
                }
            }.contentMargins(.horizontal, 16).scrollIndicators(.hidden).frame(minHeight: 112)
        }
    }

    private var recipientList: some View {
        LazyVStack(spacing: 4) {
            if searching { ProgressView().controlSize(.small).padding(8) }
            if searchFailed {
                HStack {
                    Text("Couldn't search.").font(.footnote).foregroundStyle(muted)
                    Button("Try again") { searchAttempt += 1 }.font(.footnote.weight(.semibold)).frame(minHeight: 44)
                }
            }
            if people.isEmpty && !searching && !searchFailed { emptyRecipients }
            ForEach(people) { person in
                Button { select(person) } label: {
                    HStack(spacing: 12) {
                        avatar(person, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.username).font(.subheadline.weight(.semibold))
                            Text(subtitle(person)).font(.caption).foregroundStyle(muted)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: selected.contains(where: { $0.id == person.id }) || sentRecipients.contains(person.id) ? "checkmark.circle.fill" : "circle")
                    }.frame(minHeight: 60).contentShape(.rect)
                }
                .buttonStyle(.plain).disabled(selectionLocked || sentRecipients.contains(person.id))
                .accessibilityLabel(recipientLabel(person))
                .accessibilityAddTraits(selected.contains(where: { $0.id == person.id }) ? [.isSelected] : [])
            }
        }.padding(.horizontal, 16)
    }

    private var emptyRecipients: some View {
        VStack(spacing: 8) {
            if !loaded { ProgressView().controlSize(.small) }
            Text(!loaded ? "Loading recipients…" : query.isEmpty ? "Search for someone to share with." : "No matching recipients.")
                .font(.footnote).foregroundStyle(muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, minHeight: 100).padding(.horizontal, 16)
    }

    private func avatar(_ person: Recipient, size: CGFloat) -> some View {
        let checked = selected.contains { $0.id == person.id } || sentRecipients.contains(person.id)
        return Group {
            if person.group != nil {
                Image(systemName: "person.2.fill").font(.title3).frame(width: size, height: size)
                    .background(WhisperTheme.card(scheme), in: .circle)
            } else { WhisperAvatar(username: person.username, size: size, ring: false) }
        }.overlay(alignment: .bottomTrailing) {
            if checked {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22, weight: .semibold))
                    .background(WhisperTheme.surface(scheme), in: .circle)
            }
        }
    }

    private func recipientLabel(_ person: Recipient) -> String {
        let state = sentRecipients.contains(person.id) ? "Sent to" : selected.contains(where: { $0.id == person.id }) ? "Deselect" : "Select"
        return "\(state) \(person.username), \(subtitle(person))"
    }

    private func select(_ person: Recipient) {
        guard isCurrent, !selectionLocked, !sentRecipients.contains(person.id) else { return }
        Haptics.soft()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            if let index = selected.firstIndex(where: { $0.id == person.id }) { selected.remove(at: index) }
            else { selected.append(person) }
        }
    }

    private var sendFooter: some View {
        VStack(spacing: 8) {
            Divider()
            Text("To: " + selected.map { $0.username + ($0.kind == .dating ? " (Dating)" : $0.group != nil ? " (Group)" : "") }.joined(separator: ", "))
                .font(.caption).foregroundStyle(muted).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            TextField("Add a message…", text: $note, axis: .vertical)
                .font(.subheadline).lineLimit(1...3).focused($noteFocused)
                .padding(12).background(WhisperTheme.card(scheme), in: .rect(cornerRadius: 16))
                .disabled(sending || frozenNote != nil || isBusy)
            Button { Task { await send() } } label: {
                HStack(spacing: 8) {
                    if sending { ProgressView().tint(WhisperTheme.surface(scheme)) }
                    Text(sending ? "Sending…" : failure != nil ? "Retry remaining" : selected.count > 1 ? "Send separately" : "Send")
                        .font(.body.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(WhisperTheme.surface(scheme)).background(ink, in: .capsule)
            }.buttonStyle(.plain).disabled(sending || isBusy || sendingDisabledReason != nil)
        }.padding(.horizontal, 16).padding(.bottom, 12)
    }

    private func search() async {
        guard isCurrent else { return }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchResults = []; searchFailed = false; searching = false
        guard !term.isEmpty else { return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(250))
            let results = try await WhisperUserService.shared.mentionSuggestions(term, limit: 30, matchingNames: true)
            guard isCurrent, query.trimmingCharacters(in: .whitespacesAndNewlines) == term else { return }
            searchResults = results; searching = false
        } catch {
            guard isCurrent, query.trimmingCharacters(in: .whitespacesAndNewlines) == term else { return }
            searching = false; searchFailed = true
        }
    }

    private func rebuildRanking() {
        guard isCurrent else { return }
        let now = Date()
        var scored: [(Recipient, Double)] = []
        var seen: Set<String> = []
        for (index, thread) in backend.threads.enumerated() {
            let person = Recipient(userID: thread.otherUserID.lowercased(), username: thread.otherUsername, kind: thread.kind)
            guard seen.insert(person.id).inserted else { continue }
            scored.append((person, Self.interactionScore(backend.directMessages(with: thread.otherUserID, kind: thread.kind), now: now) + max(0, 6 - Double(index)) * 0.4))
        }
        for group in groups.visibleGroups {
            let person = Recipient(userID: "group:\(group.id.uuidString.lowercased())", username: group.name, group: group)
            guard seen.insert(person.id).inserted else { continue }
            scored.append((person, Self.interactionScore(groups.messages(forGroup: group), now: now)))
        }
        ranked = scored.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }.map(\.0)
    }

    nonisolated private static func interactionScore(_ rows: [WhisperMessageRow], now: Date) -> Double {
        rows.reduce(0) { score, row in
            guard let date = WhisperBackendService.parseISO(row.created_at) else { return score + 0.2 }
            let days = now.timeIntervalSince(date) / 86_400
            return score + (days <= 7 ? 1.6 : days <= 30 ? 1 : days <= 60 ? 0.6 : 0.1)
        }
    }

    private func send() async {
        guard isCurrent, !selected.isEmpty, !sending, !isBusy, sendingDisabledReason == nil else { return }
        sending = true
        defer { if generation == AccountStorage.generation { sending = false } }
        searchFocused = false; noteFocused = false; failure = nil
        let recipients = selected
        let body = frozenPayload ?? payload
        let text = frozenNote ?? note.trimmingCharacters(in: .whitespacesAndNewlines)
        frozenPayload = body; frozenNote = text
        for recipient in recipients {
            guard isCurrent else { return }
            var posted = payloadDelivered.contains(recipient.id)
            if !posted {
                posted = await deliver(body, to: recipient, stage: "payload")
                guard isCurrent else { return }
                if posted { payloadDelivered.insert(recipient.id) }
            }
            guard posted else { continue }
            let noteOK = text.isEmpty ? true : await deliver(text, to: recipient, stage: "note")
            guard isCurrent else { return }
            if noteOK { sentRecipients.insert(recipient.id) }
        }
        guard isCurrent else { return }
        selected.removeAll { sentRecipients.contains($0.id) }
        if selected.isEmpty {
            Haptics.success(); onSent(); close()
        } else {
            let generic = "Some shares couldn't finish. Retry the remaining recipients; confirmed deliveries are skipped in this session."
            failure = payloadFailureReason?().map { $0 + " " + generic } ?? generic
            detent = .large
        }
    }

    private func deliver(_ body: String, to recipient: Recipient, stage: String) async -> Bool {
        guard isCurrent else { return false }
        if stage == "payload", let deliverPayload {
            guard recipient.group == nil, recipient.kind == .direct else { return false }
            return await deliverPayload(recipient.userID, recipient.username, deliveryID(recipient.id + ":" + stage))
        }
        if let group = recipient.group {
            let key = recipient.id + ":" + stage
            let result = await groups.sendShare(toGroup: group, body: body, delivered: groupReceipts[key] ?? [],
                                               messageIDForMember: { deliveryID(key + ":" + $0.lowercased()) })
            guard isCurrent else { return false }
            groupReceipts[key] = result.delivered
            return result.complete
        }
        return await backend.sendMessage(toUserID: recipient.userID, toUsername: recipient.username, body: body, conversationKind: recipient.kind, requiresConfirmedDelivery: true,
                                         messageID: deliveryID(recipient.id + ":" + stage))
    }

    private func deliveryID(_ key: String) -> UUID {
        if let existing = deliveryIDs[key] { return existing }
        let id = UUID()
        deliveryIDs[key] = id
        return id
    }

    private func close() { isClosed = true; searchFocused = false; noteFocused = false; dismiss() }
}
