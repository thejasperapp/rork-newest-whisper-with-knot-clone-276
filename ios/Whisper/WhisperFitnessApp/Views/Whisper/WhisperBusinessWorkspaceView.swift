import SwiftUI

/// Native Business+ company, roster and business-scoped agenda.
struct WhisperBusinessWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var service: WhisperBusinessWorkspaceService = .shared
    @State private var tab: String = "Team"
    @State private var editor: WhisperBusinessEditorView.Kind?
    @State private var removingMember: WhisperBusinessModels.Member?
    @State private var removingEvent: WhisperBusinessModels.Event?
    @State private var busy: Bool = false
    @State private var error: String?
    @State private var showMeetings: Bool = false
    @State private var showSponsorships: Bool = false
    @State private var showBrandEditor: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let business = service.context {
                        header(business)
                        if service.plans.count > 1 {
                            Menu {
                                ForEach(service.plans) { plan in
                                    Button(plan.displayName) { Task { await service.select(plan.user_id) } }
                                }
                            } label: { Label("Switch business", systemImage: "arrow.triangle.2.circlepath").font(.subheadline.weight(.semibold)) }
                                .disabled(service.isLoading || busy)
                        }
                        Button { showMeetings = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "video").font(.title3).foregroundStyle(WhisperBrandGradient.linear)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Meet with your team").font(.subheadline.weight(.semibold))
                                    Text("Rooms, links and your meeting library").font(.caption).foregroundStyle(WhisperTheme.muted(scheme))
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.padding(16).background(WhisperTheme.card(scheme), in: .rect(cornerRadius: 18))
                        }.buttonStyle(.plain)
                        Picker("Business tools", selection: $tab) {
                            Text("Team").tag("Team")
                            Text("Agenda").tag("Agenda")
                        }.pickerStyle(.segmented)
                        if let message = (tab == "Team" ? service.teamError : service.agendaError) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(message).font(.footnote)
                                Button("Try again") { Task { await service.load() } }.disabled(service.isLoading).frame(minHeight: 44)
                            }
                        }
                        if tab == "Team" { teamSection } else { agendaSection }
                    } else if service.isLoading {
                        ProgressView("Opening your workspace…").frame(maxWidth: .infinity).padding(.top, 70)
                    } else {
                        ContentUnavailableView {
                            Label("Set up your team", systemImage: "person.2")
                        } description: {
                            Text(service.accessError ?? "Teams use your existing Business+ membership. To establish a team, open Workspace → Teams on Whisper web and set up Business+. Then return here to name your team and add people. To join an existing team, ask its owner to add your exact Whisper username; members do not need a separate plan.")
                        } actions: {
                            Button("Check again") { Task { await service.load() } }
                        }
                    }
                    marketplaceSection
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(WhisperTheme.surface(scheme))
            .foregroundStyle(WhisperTheme.ink(scheme))
            .navigationTitle("Teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if service.isLoading { ProgressView() }
                }
            }
            .whisperRefreshable { await service.load() }
            .task { await service.load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await service.load() } } }
            .onChange(of: service.contextVersion) { _, _ in
                editor = nil
                removingMember = nil
                removingEvent = nil
                error = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .whisperAccountSwitched)) { _ in
                showMeetings = false
                showSponsorships = false
                showBrandEditor = false
                Task { await service.load() }
            }
            .sheet(item: $editor) { kind in
                WhisperBusinessEditorView(kind: kind, service: service)
            }
            .fullScreenCover(isPresented: $showMeetings) { WhisperMeetingsView() }
            .fullScreenCover(isPresented: $showSponsorships) { WhisperBrandDashboardView() }
            .fullScreenCover(isPresented: $showBrandEditor) { WhisperBrandEditorView() }
            .confirmationDialog("Remove team member?", isPresented: Binding(get: { removingMember != nil }, set: { if !$0 { removingMember = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let member = removingMember { perform { try await service.removeMember(member) } }
                }
            } message: { Text("They will lose access to this Business+ workspace. Existing chats and group memberships are not changed.") }
            .confirmationDialog("Delete this event?", isPresented: Binding(get: { removingEvent != nil }, set: { if !$0 { removingEvent = nil } }), titleVisibility: .visible) {
                Button("Delete event", role: .destructive) {
                    if let event = removingEvent { perform { try await service.deleteEvent(event) } }
                }
            } message: { Text("This removes the event from the calendar, not its meeting room.") }
            .alert("Couldn't complete that", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "Please try again.") }
        }
    }

    private var marketplaceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your brand on Whisper").font(.title3.weight(.semibold))
            Text("These tools manage your signed-in account's brand, not another business's team seat.")
                .font(.footnote).foregroundStyle(WhisperTheme.muted(scheme))
            Button { showSponsorships = true } label: {
                HStack { Label("Applications, agreements & escrow", systemImage: "person.2.badge.gearshape"); Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: 48)
            }.buttonStyle(.plain)
            Divider()
            Button { showBrandEditor = true } label: {
                HStack { Label("Edit marketplace listing", systemImage: "building.2"); Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: 48)
            }.buttonStyle(.plain)
        }.padding(16).background(WhisperTheme.card(scheme), in: .rect(cornerRadius: 18))
    }

    private func header(_ business: WhisperBusinessModels.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WhisperBusinessPlusMark().stroke(WhisperBrandGradient.linear, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 48, height: 48).accessibilityLabel("Business Plus")
                Spacer()
                Text(service.isOwner ? "OWNER" : "TEAM MEMBER").font(.caption2.weight(.bold)).tracking(1)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(WhisperTheme.card(scheme), in: .capsule)
            }
            HStack(alignment: .top) {
                Text(business.displayName).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if service.isOwner {
                    Button { editor = .company(business.displayName) } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                        .disabled(busy || service.isLoading).accessibilityLabel("Edit company name")
                }
            }
            Text("One place for your people and what's next.").font(.subheadline).foregroundStyle(WhisperTheme.muted(scheme))
            Rectangle().fill(WhisperBrandGradient.linear).frame(height: 2)
        }
    }

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your people").font(.title3.weight(.semibold))
                Spacer()
                if service.isOwner { addButton("Add person", icon: "person.badge.plus") { editor = .member(nil) } }
            }
            Text("The owner is included automatically. Only the owner can add people or edit roles. Role titles do not grant owner permissions. Private notes, recordings and Jasper conversations stay private.")
                .font(.footnote).foregroundStyle(WhisperTheme.muted(scheme))
            if service.members.isEmpty && service.teamError == nil && !service.isLoading {
                WhisperEmptyState(icon: "person.2", title: "Build your team", message: service.isOwner ? "Add people by their Whisper username, then give each person a role." : "The owner can add teammates here.", isCard: false)
            }
            ForEach(service.members) { member in
                HStack(spacing: 12) {
                    Text(String(member.username.prefix(1)).uppercased()).font(.headline)
                        .frame(width: 44, height: 44).background(WhisperTheme.card(scheme), in: .circle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("@\(member.username)").font(.subheadline.weight(.semibold))
                        Text(member.role_title).font(.footnote).foregroundStyle(WhisperTheme.muted(scheme))
                    }
                    Spacer(minLength: 8)
                    if service.isOwner {
                        Menu {
                            Button("Edit role", systemImage: "pencil") { editor = .member(member) }
                            Button("Remove from team", systemImage: "person.badge.minus", role: .destructive) { removingMember = member }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .disabled(busy).accessibilityLabel("Options for \(member.username)")
                    }
                }
                Divider().overlay(WhisperTheme.hairline(scheme))
            }
        }
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Business agenda").font(.title3.weight(.semibold))
                Spacer()
                addButton("New", icon: "plus") { editor = .event }
            }
            Text("These events are grouped for your business, but the current shared calendar is not private. Do not add confidential details.")
                .font(.footnote).foregroundStyle(WhisperTheme.muted(scheme))
            if service.events.isEmpty && service.agendaError == nil && !service.isLoading {
                WhisperEmptyState(icon: "calendar", title: "Make time for the team", message: "Add your next meeting and attach a join link. It will appear on web too.", isCard: false)
            }
            ForEach(service.events) { event in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let date = event.start {
                                Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                                    .font(.caption.weight(.semibold)).foregroundStyle(WhisperBrandGradient.accent)
                            }
                            Text(event.title).font(.headline)
                        }
                        Spacer()
                        if event.created_by.lowercased() == AccountStorage.currentUserID.lowercased() {
                            Button(role: .destructive) { removingEvent = event } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                                .disabled(busy).accessibilityLabel("Delete \(event.title)")
                        }
                    }
                    if let details = event.description, !details.isEmpty { Text(details).font(.subheadline) }
                    if let url = WhisperServedAd.webURL(event.meeting_link) {
                        Button {
                            if !WhisperMeetingLinkRouter.handle(url) { openURL(url) }
                        } label: { Label("Join meeting", systemImage: "video").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WhisperTheme.card(scheme), in: .rect(cornerRadius: 18))
            }
        }
    }

    private func addButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(WhisperTheme.surface(scheme)).background(WhisperTheme.ink(scheme), in: .capsule)
        }.buttonStyle(.plain).disabled(busy || service.isLoading)
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        let version = service.contextVersion
        Task {
            defer { busy = false }
            guard service.contextVersion == version else { return }
            do {
                try await action()
                guard service.contextVersion == version else { return }
                Haptics.tap()
            } catch {
                guard service.contextVersion == version else { return }
                self.error = (error as? WhisperBusinessModels.Failure)?.errorDescription ?? "The change wasn't saved. Check your connection and try again."
            }
        }
    }
}
