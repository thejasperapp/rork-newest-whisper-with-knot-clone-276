import SwiftUI

/// Coach-only screen: list of programs I've built, plus a builder to create
/// or edit one. Tapping a program lets the coach send it to a client in DM.
struct WhisperCoachProgramsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var service = WhisperCoachProgramService.shared
    @State private var editing: WhisperCoachProgram?
    @State private var sharing: WhisperCoachProgram?
    @State private var jasperPrograms: [GeneratedProgram] = []

    // Live off the coach's OWN Jasper (GET /v1/programs / /v1/diet_plans).
    @State private var studioSection: StudioSection = .training
    @State private var apiPrograms: [JasperOwnPlanRow] = []
    @State private var apiDietPlans: [JasperOwnPlanRow] = []
    @State private var apiPhase: APIPhase = .loading
    @State private var apiLoadedAt: Date?
    @State private var apiOperation = UUID()
    @State private var publishBusyID: String?
    @State private var publishedIDs: Set<String> = []
    @State private var publishNote: String?
    @State private var showDietBuilder = false
    @State private var viewingProgram: JasperOwnPlanRow?
    @State private var viewingDiet: JasperOwnPlanRow?

    private enum StudioSection: String, CaseIterable {
        case training = "Training"
        case diet = "Diet"
    }

    private enum APIPhase: Equatable {
        case loading, ready
        case failed(String)
    }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var cardBG: Color { WhisperTheme.card(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        hero
                        sectionPicker
                        if let publishNote {
                            Text(publishNote)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.likeRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        switch studioSection {
                        case .training: trainingSection
                        case .diet: dietSection
                        }
                        if let err = service.lastError {
                            Text(err).font(.caption).foregroundStyle(WhisperTheme.likeRed)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                    .whisperPadContent()
                }
                .whisperRefreshable {
                    await loadStudio(force: true)
                }
            }
            .navigationTitle("Programs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        if studioSection == .diet {
                            showDietBuilder = true
                        } else {
                            editing = service.makeBlankProgram()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .foregroundStyle(ink)
                    }
                }
            }
            .task(id: AccountStorage.generation) { await loadStudio(force: false) }
            .onDisappear { apiOperation = UUID() }
            .onChange(of: JasperConnectClient.shared.connection?.tokenID) { _, _ in
                apiOperation = UUID(); apiLoadedAt = nil; apiPrograms = []; apiDietPlans = []
                apiPhase = .failed("Jasper access changed. Reopen your studio after reviewing the connection.")
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                apiOperation = UUID(); apiLoadedAt = nil; apiPrograms = []; apiDietPlans = []; jasperPrograms = []
                editing = nil; sharing = nil; viewingProgram = nil; viewingDiet = nil; showDietBuilder = false; publishedIDs = []
                dismiss()
            }
            .fullScreenCover(item: $editing) { program in
                WhisperProgramBuilderView(program: program) { updated in
                    Task {
                        _ = await service.saveProgram(updated)
                        editing = nil
                    }
                } onShare: { p in
                    editing = nil
                    sharing = p
                }
            }
            .fullScreenCover(isPresented: $showDietBuilder) {
                JasperOwnDietBuilderView {
                    Task { await loadFromJasper(force: true) }
                }
            }
            .sheet(item: $sharing) { p in
                WhisperPickRecipientSheet(payload: WhisperProgramEmbed.encode(p)) {
                    sharing = nil
                }
            }
            .sheet(item: $viewingProgram) { row in
                JasperProgramDetailSheet(
                    plan: JasperPlanShape.parse(row.payload, fallbackTitle: row.name, fallbackGoal: row.goal))
            }
            .sheet(item: $viewingDiet) { row in
                JasperDietPlanSheet(source: .preloaded(
                    JasperDietPlan.parse(row: row.rawRow),
                    note: "Read live off your Jasper — the studio renders the exact payload."))
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                WhisperCoachBadge(size: 18)
                Text("COACH STUDIO")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(WhisperTheme.coachAccent)
            }
            Text("Your Jasper studio — live.")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(ink)
            Text("Training programs and diet plans read straight off your Jasper over the API. Publish any of them to the marketplace, keep Whisper-only drafts to sell in DMs, or generate a diet plan with Jasper's own engine.")
                .font(.caption)
                .foregroundStyle(muted)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            WhisperMeetDoodle(symbol: "rectangle.stack", height: 120)
            Text("No programs yet")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ink)
            Text("Tap + to build your first program.")
                .font(.caption)
                .foregroundStyle(muted)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, style: StrokeStyle(lineWidth: 0.75, dash: [5]))
        }
    }

    private func programCard(_ p: WhisperCoachProgram) -> some View {
        JasperGlowBox(cornerRadius: 22, glow: 0.5) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    EmberGlowIcon(systemName: "rectangle.stack.fill", size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        JasperKicker(text: p.focus.isEmpty ? "Workout plan — draft" : "\(p.focus) — draft")
                        Text(p.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if p.isPaid {
                        Text(WhisperBillingService.formatCents(p.priceCents))
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(JasperBrand.emberGradient, in: .capsule)
                    }
                }
                if !p.summary.isEmpty {
                    Text(p.summary)
                        .font(.caption)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.58))
                        .lineLimit(2)
                }
                HStack(spacing: 14) {
                    stat("\(p.weeks)", "wks")
                    stat("\(p.sessionsPerWeek)", "x/wk")
                    stat("\(p.days.count)", "days")
                    stat("\(p.totalExercises)", "lifts")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stat(_ v: String, _ u: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(v).font(.subheadline.weight(.heavy))
                .foregroundStyle(JasperBrand.text(colorScheme))
            Text(u).font(.caption2.weight(.semibold))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
        }
    }

    // MARK: - Live from the Jasper API

    private var sectionPicker: some View {
        HStack(spacing: 8) {
            ForEach(StudioSection.allCases, id: \.self) { s in
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) { studioSection = s }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s == .training ? "figure.strengthtraining.traditional" : "leaf.fill")
                            .font(.caption.weight(.bold))
                        Text(s.rawValue)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(studioSection == s ? WhisperTheme.surface(colorScheme) : ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(studioSection == s ? ink : cardBG, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(hairline, lineWidth: studioSection == s ? 0 : 0.75)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var trainingSection: some View {
        sectionHeader("In your Jasper — live", systemImage: "bolt.horizontal.circle.fill")
        apiRows(apiPrograms,
                empty: "No programs in your Jasper yet. Import one from the marketplace or assign one through Coach tools — it lands here instantly.")
        if !jasperPrograms.isEmpty { jasperSection }
        if service.isLoading && service.myPrograms.isEmpty {
            ProgressView().padding(.top, 8)
        } else if !service.myPrograms.isEmpty {
            sectionHeader("Whisper drafts — sell & send in DMs", systemImage: "rectangle.stack.fill")
            ForEach(service.myPrograms) { p in
                Button {
                    Haptics.tap()
                    editing = p
                } label: {
                    programCard(p)
                }
                .buttonStyle(.plain)
            }
        } else if apiPrograms.isEmpty && jasperPrograms.isEmpty && apiPhase == .ready {
            emptyState
        }
    }

    @ViewBuilder
    private var dietSection: some View {
        generateCard
        sectionHeader("Diet plans in your Jasper — live", systemImage: "leaf.circle.fill")
        apiRows(apiDietPlans,
                empty: "No diet plans in your Jasper yet. Generate one with Jasper above — it saves straight into your account.")
        Text("Grocery checklists ride every plan and stay in sync with Jasper — a check-off in either app shows up in both.")
            .font(.caption2)
            .foregroundStyle(muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generateCard: some View {
        Button {
            Haptics.tap()
            showDietBuilder = true
        } label: {
            JasperGlowBox(cornerRadius: 22, glow: 0.5) {
                HStack(spacing: 12) {
                    EmberGlowIcon(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 3) {
                        JasperKicker(text: "Native review required")
                        Text("Review in Jasper")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                        Text("Connected meal generation is paused. Review nutrition in Jasper. Saved cloud plans remain readable with your permission.")
                            .font(.caption)
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func apiRows(_ rows: [JasperOwnPlanRow], empty: String) -> some View {
        switch apiPhase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading your Jasper…")
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(cardBG, in: .rect(cornerRadius: 20))
        case .failed(let message):
            VStack(spacing: 8) {
                Text("Couldn't read your Jasper")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
                Button {
                    Haptics.tap()
                    Task { await loadFromJasper(force: true) }
                } label: {
                    Text("Try again")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(cardBG, in: .rect(cornerRadius: 20))
            ForEach(rows) { row in apiRow(row) }
        case .ready:
            if rows.isEmpty {
                Text(empty)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(cardBG, in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(hairline, style: StrokeStyle(lineWidth: 0.75, dash: [5]))
                    }
            } else {
                ForEach(rows) { row in
                    apiRow(row)
                }
            }
        }
    }

    /// WHISPER_PLANS.md §3/§4 — every live Jasper plan renders as the ember
    /// glow box, locked in place in the vertical stack (glow 0.5, stacked).
    @ViewBuilder
    private func apiRow(_ row: JasperOwnPlanRow) -> some View {
        if row.isProgram {
            JasperWorkoutPlanGlowCard(
                plan: JasperPlanShape.parse(row.payload, fallbackTitle: row.name, fallbackGoal: row.goal),
                glow: 0.5,
                live: true,
                chips: row.chips,
                primaryLabel: "View program",
                onPrimary: { viewingProgram = row },
                publishState: publishState(row),
                onPublish: { Task { await publish(row) } })
                .jasperPlanEntrance()
        } else {
            JasperDietPlanGlowCard(
                name: row.name,
                metaLine: row.detail,
                kcal: row.kcal, protein: row.proteinG, carbs: row.carbsG, fat: row.fatG,
                glow: 0.5,
                live: true,
                groceryCount: row.groceryCount,
                primaryLabel: "View plan",
                onPrimary: { viewingDiet = row },
                publishState: publishState(row),
                onPublish: { Task { await publish(row) } })
                .jasperPlanEntrance()
        }
    }

    private func publishState(_ row: JasperOwnPlanRow) -> JasperPlanPublishState {
        if row.payload.isEmpty { return .hidden }
        if publishedIDs.contains(row.id) { return .published }
        return .publishable(busy: publishBusyID == row.id)
    }

    private func loadStudio(force: Bool) async {
        let generation = AccountStorage.generation
        async let plans: Void = loadFromJasper(force: force)
        await service.fetchMyPrograms()
        if generation == AccountStorage.generation, !Task.isCancelled {
            jasperPrograms = service.loadSavedWhisperPrograms()
        }
        _ = await plans
    }

    /// Reads programs + diet plans off the coach's OWN Jasper token.
    private func loadFromJasper(force: Bool) async {
        if !force, let at = apiLoadedAt, Date().timeIntervalSince(at) < 60 { return }
        let generation = AccountStorage.generation, operation = UUID()
        let tokenID = JasperConnectClient.shared.connection?.tokenID
        apiOperation = operation
        if apiPrograms.isEmpty && apiDietPlans.isEmpty { apiPhase = .loading }
        do {
            async let programsData = JasperConnectClient.shared.read("programs", limit: 50)
            async let dietData = JasperConnectClient.shared.read("diet_plans", limit: 50)
            let (pData, dData) = try await (programsData, dietData)
            guard !Task.isCancelled, generation == AccountStorage.generation, apiOperation == operation,
                  JasperConnectClient.shared.connection?.tokenID == tokenID else { return }
            func rows(_ data: Data) throws -> [[String: Any]] {
                guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = body["data"] as? [[String: Any]] else { throw URLError(.cannotDecodeContentData) }
                return rows
            }
            let programs = try rows(pData).compactMap { JasperOwnPlanRow.parse($0, isProgram: true) }
            let diets = try rows(dData).compactMap { JasperOwnPlanRow.parse($0, isProgram: false) }
            withAnimation(.whisperSnappy) {
                apiPrograms = programs
                apiDietPlans = diets
                apiPhase = .ready
            }
            apiLoadedAt = Date()
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, apiOperation == operation else { return }
            if JasperConnectClient.shared.connection == nil {
                apiPrograms = []; apiDietPlans = []; apiLoadedAt = nil
                apiPhase = .failed("Connect Jasper in Settings to see your saved programs and diet plans.")
            } else {
                apiPhase = .failed("Your plans couldn’t load just now. Please try again.")
            }
        }
    }

    /// Publishes the row's verbatim plan_shapes payload to the marketplace.
    private func publish(_ row: JasperOwnPlanRow) async {
        guard publishBusyID == nil else { return }
        let generation = AccountStorage.generation
        let tokenID = JasperConnectClient.shared.connection?.tokenID
        publishBusyID = row.id
        publishNote = nil
        defer { if generation == AccountStorage.generation { publishBusyID = nil } }
        do {
            _ = try await JasperMarketplace.shared.publish(
                kind: row.isProgram ? "program" : "diet_plan",
                title: row.name,
                summary: row.detail,
                goal: row.goal.isEmpty ? (row.isProgram ? "General Fitness" : "Maintain Weight") : row.goal,
                topLevel: row.topLevel,
                payload: row.payload)
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  JasperConnectClient.shared.connection?.tokenID == tokenID else { return }
            withAnimation(.whisperSnappy) { _ = publishedIDs.insert(row.id) }
            Haptics.success()
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            Haptics.warning()
            publishNote = "Publishing couldn’t be confirmed. Refresh the marketplace before trying again."
        }
    }

    // MARK: - Whisper saved programs

    private var jasperSection: some View {
        VStack(spacing: 10) {
            sectionHeader("From your Whisper library", systemImage: "square.and.arrow.up.on.square.fill")
            ForEach(jasperPrograms) { gp in
                Button {
                    Haptics.tap()
                    sharing = service.bridge(gp)
                } label: {
                    jasperProgramCard(gp)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.6)
            Spacer()
        }
        .foregroundStyle(muted)
        .padding(.top, 4)
    }

    private func jasperProgramCard(_ g: GeneratedProgram) -> some View {
        let exerciseCount = g.workoutDays.reduce(0) { $0 + $1.exercises.count }
        return JasperGlowBox(cornerRadius: 22, glow: 0.5) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    EmberGlowIcon(systemName: g.goal.icon, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        JasperKicker(text: g.goal.rawValue)
                        Text(g.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "paperplane.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                }
                if !g.overview.isEmpty {
                    Text(g.overview)
                        .font(.caption)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.58))
                        .lineLimit(2)
                }
                HStack(spacing: 14) {
                    stat("\(g.weeks)", "wks")
                    stat("\(g.daysPerWeek)", "x/wk")
                    stat("\(g.workoutDays.count)", "days")
                    stat("\(exerciseCount)", "lifts")
                    Spacer()
                    Text("Send")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(JasperBrand.emberGradient, in: .capsule)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Builder

/// Themed program builder — replaces the old system Form with the same
/// monochrome card language as the rest of the studio.
struct WhisperProgramBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State var program: WhisperCoachProgram
    let onSave: (WhisperCoachProgram) -> Void
    let onShare: (WhisperCoachProgram) -> Void

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var cardBG: Color { WhisperTheme.card(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        detailsCard
                        ForEach($program.days) { $day in
                            dayCard($day)
                        }
                        addDayButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                    .whisperPadContent(640)
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle("Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ink)
                }
            }
        }
    }

    // MARK: - Program details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            builderHeader("Program")
            labeledField("Title", text: $program.title, prompt: "e.g. 8-Week Strength Block")
            labeledField("Focus", text: $program.focus, prompt: "e.g. Hypertrophy")
            stepperRow("Weeks", value: $program.weeks, range: 1...52)
            stepperRow("Sessions per week", value: $program.sessionsPerWeek, range: 1...7)
            stepperRow(
                "Price",
                value: Binding(
                    get: { program.priceCents / 100 },
                    set: { program.priceCents = max(0, min(2000, $0)) * 100 }
                ),
                range: 0...2000,
                step: 5,
                prefix: "$"
            )
            Text(program.priceCents > 0
                 ? "Clients pay \(WhisperBillingService.formatCents(program.priceCents)) in-app before the full plan opens — the sale lands in your earnings."
                 : "Free — anyone you send it to can open it. Set a price to sell it.")
                .font(.caption2)
                .foregroundStyle(muted)
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Summary")
                TextField("What this program is about", text: $program.summary, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.footnote)
                    .foregroundStyle(ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(ink.opacity(0.045), in: .rect(cornerRadius: 12))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    // MARK: - Day card

    private func dayCard(_ day: Binding<WhisperProgramDay>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                builderHeader(day.wrappedValue.name.isEmpty ? "Day" : day.wrappedValue.name)
                Spacer()
                Button {
                    Haptics.warning()
                    withAnimation(.whisperSnappy) {
                        program.days.removeAll { $0.id == day.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(muted)
                        .frame(width: 30, height: 30)
                        .background(ink.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
            }
            labeledField("Day name", text: day.name, prompt: "e.g. Push A")
            labeledField("Focus", text: day.focus, prompt: "e.g. Chest & triceps")

            ForEach(day.exercises) { $ex in
                exerciseEditor($ex, day: day)
            }

            Button {
                Haptics.tap()
                withAnimation(.whisperSnappy) {
                    day.wrappedValue.exercises.append(WhisperProgramExercise(
                        name: "",
                        sets: 3,
                        reps: "8-10",
                        restSeconds: 90,
                        note: nil
                    ))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.footnote.weight(.bold))
                    Text("Add exercise")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(ink.opacity(0.05), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(hairline, lineWidth: 0.75)
        }
    }

    private func exerciseEditor(
        _ ex: Binding<WhisperProgramExercise>,
        day: Binding<WhisperProgramDay>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Exercise name", text: ex.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(ink.opacity(0.045), in: .rect(cornerRadius: 10))
                Button {
                    Haptics.warning()
                    withAnimation(.whisperSnappy) {
                        day.wrappedValue.exercises.removeAll { $0.id == ex.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(muted)
                        .frame(width: 26, height: 26)
                        .background(ink.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
            }
            stepperRow("Sets", value: ex.sets, range: 1...10)
            HStack(spacing: 8) {
                fieldLabel("Reps")
                Spacer()
                TextField("6-8", text: ex.reps)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .frame(width: 88)
                    .padding(.vertical, 7)
                    .background(ink.opacity(0.045), in: Capsule())
            }
            stepperRow("Rest", value: ex.restSeconds, range: 0...600, step: 15, suffix: "s")
        }
        .padding(12)
        .background(ink.opacity(0.03), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hairline, lineWidth: 0.5)
        }
    }

    private var addDayButton: some View {
        Button {
            Haptics.tap()
            withAnimation(.whisperSnappy) {
                program.days.append(WhisperProgramDay(
                    name: "Day \(program.days.count + 1)",
                    focus: "Full body",
                    exercises: []
                ))
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.footnote.weight(.bold))
                Text("Add day")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(cardBG, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(hairline, style: StrokeStyle(lineWidth: 0.75, dash: [5]))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save bar

    private var saveBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                onSave(program)
            } label: {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(hairline, lineWidth: 0.75) }
            }
            .buttonStyle(.plain)
            Button {
                Haptics.tap()
                onSave(program)
                onShare(program)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.footnote.weight(.bold))
                    Text("Save & send")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(WhisperTheme.surface(colorScheme))
        .overlay(alignment: .top) {
            Rectangle().fill(hairline).frame(height: 0.5)
        }
    }

    // MARK: - Field helpers

    private func builderHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.black))
            .tracking(1.6)
            .foregroundStyle(muted)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(muted)
    }

    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            TextField(prompt, text: text)
                .font(.footnote)
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(ink.opacity(0.045), in: .rect(cornerRadius: 12))
        }
    }

    private func stepperRow(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = "",
        prefix: String = ""
    ) -> some View {
        HStack {
            fieldLabel(label)
            Spacer()
            HStack(spacing: 0) {
                Button {
                    Haptics.tap()
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ink)
                        .frame(width: 34, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Text("\(prefix)\(value.wrappedValue)\(suffix)")
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                Button {
                    Haptics.tap()
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ink)
                        .frame(width: 34, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .background(ink.opacity(0.05), in: Capsule())
        }
    }
}

// MARK: - Inline DM card

/// Premium coach-sent program card. Matches the Coach Macros / Diet Plan
/// inline card layout — avatar header, columnar stat tiles, accent CTA.
struct WhisperProgramInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperProgramEmbed.Payload
    let mine: Bool
    var saved: Bool = false
    /// Paid program the viewer hasn't bought yet — the footer becomes an
    /// "Unlock" CTA and tapping starts in-app checkout.
    var locked: Bool = false
    /// True while checkout for THIS card is in flight.
    var buying: Bool = false

    // WHISPER_PLANS.md / WHISPER_BRIDGE.md — program chat embeds render as the
    // ember glow box in BOTH directions, light and dark; never gray glass.
    private var fg: Color { JasperBrand.text(colorScheme) }

    private var totalLifts: Int {
        payload.days.reduce(0) { $0 + $1.exercises.count }
    }

    var body: some View {
        JasperGlowBox(cornerRadius: 20, glow: 0.5) {
            VStack(alignment: .leading, spacing: 0) {
                header
                title
                statRow
                if !payload.focus.isEmpty || !payload.summary.isEmpty { chipsRow }
                footer
            }
            .frame(width: 264, alignment: .leading)
            .foregroundStyle(fg)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            WhisperAvatar(username: payload.coachUsername, size: 32, ring: false)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("@\(payload.coachUsername)")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    WhisperCoachBadge(size: 10)
                }
                Text(payload.isPaid
                     ? "Training program · \(WhisperBillingService.formatCents(payload.priceCents ?? 0))"
                     : "Training program")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            EmberGlowIcon(systemName: locked ? "lock.fill" : "figure.strengthtraining.traditional", size: 26)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var title: some View {
        Text(payload.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            statTile("\(payload.weeks)", "weeks", isLast: false)
            statTile("\(payload.sessionsPerWeek)", "per wk", isLast: false)
            statTile("\(payload.days.count)", "days", isLast: false)
            statTile("\(totalLifts)", "lifts", isLast: true)
        }
        .padding(.vertical, 10)
        .background(JasperBrand.inset(colorScheme), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    private func statTile(_ v: String, _ u: String, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 1) {
                Text(v)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(u)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            if !isLast {
                Rectangle()
                    .fill(fg.opacity(0.10))
                    .frame(width: 0.5, height: 22)
            }
        }
    }

    private var chipsRow: some View {
        HStack(spacing: 5) {
            if !payload.focus.isEmpty {
                Text(payload.focus)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(fg.opacity(0.08), in: Capsule())
            }
            if !payload.summary.isEmpty {
                Text(payload.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if buying {
                ProgressView()
                    .controlSize(.small)
                Text("Opening secure checkout…")
                    .font(.footnote.weight(.medium))
            } else if locked {
                Image(systemName: "lock.open.fill")
                    .font(.footnote)
                Text("Unlock for \(WhisperBillingService.formatCents(payload.priceCents ?? 0)) · one-time")
                    .font(.footnote.weight(.semibold))
            } else {
                Image(systemName: saved ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    .font(.footnote)
                Text(saved ? "Added to your programs" : "Tap to save to Whisper")
                    .font(.footnote.weight(.medium))
            }
            Spacer(minLength: 0)
            if !saved && !buying {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(saved ? JasperBrand.teal : JasperBrand.kicker(colorScheme))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

// MARK: - A row straight off the coach's own Jasper

/// One plan read live off the coach's OWN Jasper (`GET /v1/programs` /
/// `GET /v1/diet_plans`). Carries the verbatim plan_shapes payload so a
/// marketplace publish re-uses the exact bytes Jasper stores.
private struct JasperOwnPlanRow: Identifiable {
    let id: String
    let name: String
    let goal: String
    let detail: String
    let daysCount: Int
    let topLevel: [String: Any]
    let payload: [String: Any]
    let rawRow: [String: Any]
    let isProgram: Bool
    let chips: [String]
    let kcal: Int?
    let proteinG: Int?
    let carbsG: Int?
    let fatG: Int?
    let groceryCount: Int

    static func parse(_ row: [String: Any], isProgram: Bool) -> JasperOwnPlanRow? {
        let payload = (row["payload"] as? [String: Any]) ?? [:]
        let name = (row["name"] as? String) ?? (payload["name"] as? String) ?? (payload["title"] as? String)
        guard let name, !name.isEmpty else { return nil }
        let id = (row["id"] as? String)
            ?? (row["client_id"] as? String)
            ?? (payload["id"] as? String)
            ?? UUID().uuidString
        let goal = (row["goal"] as? String) ?? (payload["goal"] as? String) ?? ""
        // plan_shapes.programs carries `workoutDays`; diet plans carry `days`.
        let days = (payload["workoutDays"] as? [[String: Any]])
            ?? (payload["days"] as? [[String: Any]])
            ?? []

        func intVal(_ key: String, of dict: [String: Any]) -> Int? {
            (dict[key] as? NSNumber)?.intValue
        }

        let coachAssigned = ((row["source"] as? String) ?? (payload["source"] as? String)) == "coach"
        var top: [String: Any] = [:]
        var detailParts: [String] = []
        var chips: [String] = []
        var kcal: Int?
        var proteinG: Int?
        var carbsG: Int?
        var fatG: Int?
        var groceryCount = 0

        if isProgram {
            let weeks = intVal("weeks", of: row) ?? intVal("weeks", of: payload)
            let perWeek = intVal("days_per_week", of: row)
                ?? intVal("daysPerWeek", of: payload)
            if !goal.isEmpty {
                top["goal"] = goal
                chips.append(goal)
            }
            if let weeks {
                top["weeks"] = weeks
                detailParts.append("\(weeks) wks")
                chips.append("\(weeks) weeks")
            }
            if let perWeek { top["days_per_week"] = perWeek }
            detailParts.append("\(days.count) day\(days.count == 1 ? "" : "s")")
            let lifts = days.reduce(0) { $0 + (($1["exercises"] as? [[String: Any]])?.count ?? 0) }
            if lifts > 0 { detailParts.append("\(lifts) lifts") }
            chips.append(coachAssigned ? "Coach-built" : "Saved cloud plan")
        } else {
            let pref = (row["dietary_preference"] as? String) ?? (payload["dietaryPreference"] as? String)
            kcal = intVal("target_calories", of: row) ?? intVal("targetCalories", of: payload)
            proteinG = intVal("target_protein_g", of: row) ?? intVal("target_protein", of: row)
            carbsG = intVal("target_carbs_g", of: row) ?? intVal("target_carbs", of: row)
            fatG = intVal("target_fat_g", of: row) ?? intVal("target_fat", of: row)
            let mealsPerDay = intVal("meals_per_day", of: row) ?? intVal("mealsPerDay", of: payload)
            if !goal.isEmpty { top["goal"] = goal }
            if let kcal { top["target_calories"] = kcal }
            if let pref { top["dietary_preference"] = pref }
            for key in ["target_protein_g", "target_carbs_g", "target_fat_g"] {
                if let v = intVal(key, of: row) { top[key] = v }
            }
            // §4 meta line: "7 days · {meals_per_day} meals/day · {goal}".
            detailParts.append("\(days.count) day\(days.count == 1 ? "" : "s")")
            if let mealsPerDay { detailParts.append("\(mealsPerDay) meals/day") }
            if !goal.isEmpty { detailParts.append(goal) }
            groceryCount = ((payload["groceryList"] as? [String: Any])?["categories"] as? [[String: Any]])?
                .reduce(0) { $0 + (($1["items"] as? [[String: Any]])?.count ?? 0) } ?? 0
        }
        if coachAssigned { detailParts.append("coach-assigned") }
        return JasperOwnPlanRow(id: id, name: name, goal: goal,
                                detail: detailParts.joined(separator: " · "),
                                daysCount: days.count, topLevel: top,
                                payload: payload, rawRow: row, isProgram: isProgram,
                                chips: chips, kcal: kcal, proteinG: proteinG,
                                carbsG: carbsG, fatG: fatG, groceryCount: groceryCount)
    }
}
