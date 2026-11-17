import SwiftUI

/// Jasper's public plan marketplace (Aug 17 2026) rendered in the Jasper
/// glow language — browse coach-published program & diet-plan templates,
/// preview the full plan_shapes payload, import into an accepted client's
/// Jasper (their token, coach attribution, upsert-by-template-id) or into
/// your own, and manage your own listings. Browse/preview are public; the
/// list is live off `GET /v1/marketplace` every time this opens.
struct JasperMarketplaceSheet: View {
    /// Preselected import target (opened from a client dashboard).
    var importClientUID: String? = nil
    var importClientUsername: String? = nil
    var initialQuery: String = ""
    /// Chat-modal presentations pass a close handler; sheet presentations
    /// use the environment dismiss.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var market = JasperMarketplace.shared
    @State private var searchText: String = ""
    @State private var kindFilter: String? = nil     // nil = all, "program", "diet_plan"
    @State private var results: [JasperMarketTemplate] = []
    @State private var loading = false
    @State private var searchTask: Task<Void, Never>?

    // Detail (in-place — the sheet may live inside the chat modal overlay,
    // so no nested presentation).
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var detail: JasperMarketTemplate?
    @State private var detailLoading = false

    // Import / unpublish state
    @State private var importBusyKey: String?
    @State private var importReceipt: String?
    @State private var importError: String?
    @State private var unpublishBusy = false

    private var clients: [WhisperCoachRequestRow] { WhisperCoachRequestService.shared.myClients }
    private var ownConnected: Bool { JasperConnectClient.shared.connection != nil }

    var body: some View {
        ZStack {
            JasperBrand.stage(colorScheme).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let detail {
                    detailView(detail)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    browseView
                        .transition(.opacity)
                }
            }
        }
        .whisperEdgeBack(isEnabled: importBusyKey == nil && !unpublishBusy, revealPresentation: detail == nil, controller: backTransition) {
            backTransition.perform {
                if detail != nil { detail = nil; importReceipt = nil; importError = nil }
                else { if let onClose { onClose() } else { dismiss() } }
            }
        }
        .presentationBackground(JasperBrand.stage(colorScheme))
        .presentationDragIndicator(.visible)
        .task {
            searchText = initialQuery
            await runSearch()
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            if detail != nil {
                Button {
                    guard importBusyKey == nil, !unpublishBusy else { return }
                    Haptics.tap()
                    backTransition.perform {
                        detail = nil
                        importReceipt = nil
                        importError = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                        .frame(width: 32, height: 32)
                        .background(JasperBrand.chip(colorScheme), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
            } else {
                JasperMarkTile(size: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(detail != nil ? "Template" : "Plan marketplace")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                Text(detail != nil
                     ? "Full payload · exactly what lands in Jasper"
                     : "Coach-published plans · live from Jasper, public")
                    .font(.system(size: 10.5))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            Button {
                Haptics.tap()
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.65))
                    .frame(width: 32, height: 32)
                    .background(JasperBrand.chip(colorScheme), in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close marketplace")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: Browse

    private var browseView: some View {
        VStack(spacing: 0) {
            searchRow
            filterRow
            ScrollView {
                VStack(spacing: 10) {
                    if let target = importClientUsername {
                        importTargetBanner(target)
                    }
                    myListingsBlock
                    if loading && results.isEmpty {
                        loadingBlock
                    } else if results.isEmpty {
                        emptyBlock
                    } else {
                        ForEach(results) { template in
                            templateRow(template)
                        }
                    }
                    Text("Public catalog · GET /v1/marketplace · imports upsert by template id, so sending a plan twice never duplicates it.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
            TextField("", text: $searchText,
                      prompt: Text("Search plans — strength, cut, endurance…")
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(JasperBrand.text(colorScheme))
                .tint(JasperBrand.ember)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { scheduleSearch(immediate: true) }
                .onChange(of: searchText) { _, _ in scheduleSearch(immediate: false) }
            if loading {
                ProgressView().controlSize(.mini).tint(JasperBrand.ember)
            } else if !searchText.isEmpty {
                Button {
                    Haptics.tap()
                    searchText = ""
                    scheduleSearch(immediate: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 13))
        .padding(.horizontal, 18)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            filterChip("All", value: nil)
            filterChip("Programs", value: "program")
            filterChip("Diet plans", value: "diet_plan")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func filterChip(_ label: String, value: String?) -> some View {
        let selected = kindFilter == value
        return Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.3)) { kindFilter = value }
            scheduleSearch(immediate: true)
        } label: {
            Text(label)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? JasperBrand.ink : JasperBrand.text(colorScheme).opacity(0.7))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                    if selected { Capsule().fill(JasperBrand.emberGradient) }
                    else { Capsule().fill(JasperBrand.chip(colorScheme)) }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func importTargetBanner(_ username: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(JasperBrand.ember)
            Text("Importing for @\(username) — pick a plan and it lands in their Jasper under your coach badge.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(JasperBrand.ember.opacity(colorScheme == .dark ? 0.12 : 0.08), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var myListingsBlock: some View {
        let mine = market.myListings
        if !mine.isEmpty, searchText.isEmpty, kindFilter == nil {
            VStack(alignment: .leading, spacing: 8) {
                JasperKicker(text: "Your listings")
                ForEach(mine) { template in
                    templateRow(template, mineBadge: true)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private var loadingBlock: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                JasperGlowBox(cornerRadius: 16, glow: 0.25) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(JasperBrand.chip(colorScheme))
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(JasperBrand.chip(colorScheme))
                                .frame(width: 150, height: 10)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(JasperBrand.chip(colorScheme).opacity(0.7))
                                .frame(width: 100, height: 8)
                        }
                        Spacer()
                    }
                    .padding(12)
                }
            }
            Text("One public call — browsing Jasper's marketplace…")
                .font(.system(size: 10))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
        }
    }

    private var emptyBlock: some View {
        VStack(spacing: 8) {
            if market.lastError == nil { WhisperMeetDoodle(symbol: "storefront", height: 120) }
            Text(market.lastError ?? (searchText.isEmpty
                 ? "No templates published yet — yours could be first."
                 : "Nothing matches “\(searchText)”."))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Coaches publish from Coach tools → Program → “Also publish to the marketplace.”")
                .font(.system(size: 10.5))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private func templateRow(_ template: JasperMarketTemplate, mineBadge: Bool = false) -> some View {
        Button {
            Haptics.tap()
            openDetail(template)
        } label: {
            JasperGlowBox(cornerRadius: 16, glow: 0.35) {
                HStack(spacing: 10) {
                    Image(systemName: template.kindSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(JasperBrand.ember)
                        .frame(width: 34, height: 34)
                        .background(JasperBrand.ember.opacity(colorScheme == .dark ? 0.16 : 0.1),
                                    in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.title)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(rowSubtitle(template))
                            .font(.system(size: 10.5))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(template.priceLabel)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(template.isFree ? Color(red: 0.36, green: 0.86, blue: 0.72) : JasperBrand.ember)
                        if mineBadge {
                            Text("YOURS")
                                .font(.system(size: 7.5, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(JasperBrand.ember)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(JasperBrand.ember.opacity(0.14), in: Capsule())
                        } else if let count = template.importCount, count > 0 {
                            Text("\(count) imports")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.35))
                }
                .padding(12)
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func rowSubtitle(_ template: JasperMarketTemplate) -> String {
        var parts: [String] = [template.kindLabel]
        if let coach = template.coachUsername, !coach.isEmpty { parts.append("by @\(coach)") }
        if let meta = template.metaLine { parts.append(meta) }
        else if let goal = template.goal, !goal.isEmpty { parts.append(goal) }
        return parts.joined(separator: " · ")
    }

    // MARK: Detail

    private func openDetail(_ template: JasperMarketTemplate) {
        backTransition.captureLocalPredecessor()
        let epoch = AccountStorage.generation
        withAnimation(.spring(duration: 0.32)) {
            detail = template
            importReceipt = nil
            importError = nil
        }
        // Browse rows don't carry the payload — pull the full template.
        if template.payload == nil {
            detailLoading = true
            Task {
                if let full = await market.template(id: template.id), epoch == AccountStorage.generation, detail?.id == template.id {
                    withAnimation(.spring(duration: 0.3)) { detail = full }
                }
                detailLoading = false
            }
        }
    }

    private func detailView(_ template: JasperMarketTemplate) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                JasperGlowBox(cornerRadius: 18, glow: 0.5) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: template.kindSymbol)
                                .font(.system(size: 10, weight: .bold))
                            Text(template.kindLabel.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1.2)
                            Spacer()
                            Text(template.priceLabel)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(template.isFree ? Color(red: 0.36, green: 0.86, blue: 0.72) : JasperBrand.ember)
                        }
                        .foregroundStyle(JasperBrand.ember)
                        Text(template.title)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                        if let summary = template.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 12))
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 6) {
                            if let coach = template.coachUsername, !coach.isEmpty {
                                metaChip("@\(coach)", icon: "person.fill")
                            }
                            if let goal = template.goal, !goal.isEmpty { metaChip(goal, icon: "target") }
                            if let meta = template.metaLine { metaChip(meta, icon: "calendar") }
                        }
                    }
                    .padding(14)
                }
                payloadPreview(template)
                importBlock(template)
                if isMine(template) { unpublishBlock(template) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func metaChip(_ label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 9.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.7))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(JasperBrand.chip(colorScheme), in: Capsule())
    }

    // MARK: Payload preview (plan_shapes, rendered verbatim)

    @ViewBuilder
    private func payloadPreview(_ template: JasperMarketTemplate) -> some View {
        if detailLoading && template.payload == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini).tint(JasperBrand.ember)
                Text("Pulling the full payload…")
                    .font(.system(size: 11))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
            }
            .padding(.vertical, 10)
        } else if let payload = template.payload {
            if template.isProgram {
                programPreview(payload)
            } else {
                dietPreview(payload)
            }
        } else if !detailLoading {
            Text("Jasper didn't return the full payload for this template — the import still copies the real thing server-side.")
                .font(.system(size: 10.5))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func programPreview(_ payload: [String: Any]) -> some View {
        let days = (payload["workoutDays"] as? [[String: Any]]) ?? []
        if !days.isEmpty {
            JasperGlowBox(cornerRadius: 18, glow: 0.35) {
                VStack(alignment: .leading, spacing: 10) {
                    JasperKicker(text: "The plan — exactly as it lands")
                    ForEach(Array(days.prefix(7).enumerated()), id: \.offset) { index, day in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text((day["dayName"] as? String) ?? "Day \(index + 1)")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(JasperBrand.ember)
                                if let focus = day["focus"] as? String, !focus.isEmpty {
                                    Text("· \(focus)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.65))
                                }
                                Spacer()
                            }
                            ForEach(Array(((day["exercises"] as? [[String: Any]]) ?? []).prefix(8).enumerated()), id: \.offset) { _, exercise in
                                exerciseLine(exercise)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(JasperBrand.stage(colorScheme).opacity(colorScheme == .dark ? 0.5 : 0.6),
                                    in: .rect(cornerRadius: 11))
                    }
                    if days.count > 7 {
                        Text("+ \(days.count - 7) more days ride the import")
                            .font(.system(size: 10))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                    }
                }
                .padding(14)
            }
        }
    }

    private func exerciseLine(_ exercise: [String: Any]) -> some View {
        HStack(spacing: 6) {
            Circle().fill(JasperBrand.ember.opacity(0.7)).frame(width: 3.5, height: 3.5)
            Text((exercise["name"] as? String) ?? "Exercise")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(JasperBrand.text(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(exerciseMeta(exercise))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
        }
    }

    private func exerciseMeta(_ exercise: [String: Any]) -> String {
        var parts: [String] = []
        let sets = JasperClientDashboard.intAny(exercise["sets"])
        // plan_shapes: reps is ALWAYS a string — render it verbatim.
        let reps = (exercise["reps"] as? String) ?? JasperClientDashboard.intAny(exercise["reps"]).map(String.init)
        if let sets, let reps { parts.append("\(sets)×\(reps)") }
        if let rest = JasperClientDashboard.intAny(exercise["restSeconds"]), rest > 0 { parts.append("\(rest)s rest") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func dietPreview(_ payload: [String: Any]) -> some View {
        let days = (payload["days"] as? [[String: Any]]) ?? []
        if !days.isEmpty {
            JasperGlowBox(cornerRadius: 18, glow: 0.35) {
                VStack(alignment: .leading, spacing: 10) {
                    JasperKicker(text: "The plan — exactly as it lands")
                    ForEach(Array(days.prefix(4).enumerated()), id: \.offset) { index, day in
                        VStack(alignment: .leading, spacing: 5) {
                            Text((day["name"] as? String) ?? (day["dayName"] as? String) ?? "Day \(index + 1)")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(JasperBrand.ember)
                            ForEach(Array(((day["meals"] as? [[String: Any]]) ?? []).prefix(6).enumerated()), id: \.offset) { _, meal in
                                HStack(spacing: 6) {
                                    Circle().fill(JasperBrand.ember.opacity(0.7)).frame(width: 3.5, height: 3.5)
                                    Text((meal["name"] as? String) ?? "Meal")
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(JasperBrand.text(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 4)
                                    if let kcal = JasperClientDashboard.intAny(meal["calories"] ?? meal["calories_kcal"] ?? meal["kcal"]) {
                                        Text("\(kcal) kcal")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(JasperBrand.stage(colorScheme).opacity(colorScheme == .dark ? 0.5 : 0.6),
                                    in: .rect(cornerRadius: 11))
                    }
                    if days.count > 4 {
                        Text("+ \(days.count - 4) more days ride the import")
                            .font(.system(size: 10))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: Import

    private func importBlock(_ template: JasperMarketTemplate) -> some View {
        JasperGlowBox(cornerRadius: 18, glow: 0.5) {
            VStack(alignment: .leading, spacing: 10) {
                JasperKicker(text: "Import")
                if let receipt = importReceipt {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.36, green: 0.86, blue: 0.72))
                        Text(receipt)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                if let importError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(JasperBrand.ember)
                        Text(importError)
                            .font(.system(size: 11))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                if let uid = importClientUID, let name = importClientUsername {
                    importButton(title: "Import into @\(name)'s Jasper", key: uid) {
                        try await JasperCoachConnect.shared.importMarketplaceTemplate(template.id, forClient: uid)
                        return "Live in @\(name)'s Jasper under your coach badge — re-imports update in place."
                    }
                } else {
                    if ownConnected {
                        importButton(title: "Import into my Jasper", key: "self") {
                            try await JasperMarketplace.shared.importForSelf(templateID: template.id)
                            return "Live in your Jasper — open the plan there or ask Knot about it."
                        }
                    }
                    ForEach(clients, id: \.id) { row in
                        importButton(title: "Send to @\(row.client_username)", key: row.client_user_id, filled: false) {
                            try await JasperCoachConnect.shared.importMarketplaceTemplate(template.id, forClient: row.client_user_id)
                            return "Live in @\(row.client_username)'s Jasper under your coach badge — re-imports update in place."
                        }
                    }
                    if !ownConnected && clients.isEmpty {
                        Text("Connect Jasper in Settings → Sync with Jasper (or accept a coaching client) to import this plan.")
                            .font(.system(size: 11))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Imports carry coach attribution and upsert by template id — the server rewrites ids and timestamps, so nothing ever duplicates.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }

    private func importButton(title: String, key: String, filled: Bool = true,
                              action: @escaping () async throws -> String) -> some View {
        Button {
            Haptics.tap()
            guard importBusyKey == nil else { return }
            importBusyKey = key
            importError = nil
            Task {
                do {
                    let receipt = try await action()
                    Haptics.success()
                    withAnimation(.spring(duration: 0.3)) { importReceipt = receipt }
                } catch {
                    Haptics.warning()
                    withAnimation(.spring(duration: 0.3)) {
                        importError = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
                    }
                }
                importBusyKey = nil
            }
        } label: {
            HStack(spacing: 7) {
                if importBusyKey == key {
                    ProgressView().controlSize(.mini)
                        .tint(filled ? JasperBrand.ink : JasperBrand.ember)
                } else {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(filled ? JasperBrand.ink : JasperBrand.ember)
            .padding(.horizontal, 13)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background {
                if filled { RoundedRectangle(cornerRadius: 12).fill(JasperBrand.emberGradient) }
                else { RoundedRectangle(cornerRadius: 12).fill(JasperBrand.ember.opacity(0.13)) }
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(importBusyKey != nil)
    }

    // MARK: Unpublish (own listings)

    private func isMine(_ template: JasperMarketTemplate) -> Bool {
        guard let mine = market.ownUsername()?.lowercased(), !mine.isEmpty else { return false }
        return template.coachUsername?.lowercased() == mine
    }

    private func unpublishBlock(_ template: JasperMarketTemplate) -> some View {
        Button {
            Haptics.warning()
            guard !unpublishBusy else { return }
            unpublishBusy = true
            Task {
                do {
                    try await JasperMarketplace.shared.unpublish(id: template.id)
                    Haptics.success()
                    withAnimation(.spring(duration: 0.3)) {
                        detail = nil
                        results.removeAll { $0.id == template.id }
                    }
                } catch {
                    withAnimation(.spring(duration: 0.3)) {
                        importError = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
                    }
                }
                unpublishBusy = false
            }
        } label: {
            HStack(spacing: 7) {
                if unpublishBusy {
                    ProgressView().controlSize(.mini).tint(.red)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .bold))
                }
                Text("Unpublish from the marketplace")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.red.opacity(colorScheme == .dark ? 0.12 : 0.08), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(unpublishBusy)
    }

    // MARK: Search plumbing

    private func scheduleSearch(immediate: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(420))
                if Task.isCancelled { return }
            }
            await runSearch()
        }
    }

    private func runSearch() async {
        loading = true
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let found = await market.browse(kind: kindFilter, query: query.isEmpty ? nil : query)
        withAnimation(.spring(duration: 0.3)) { results = found }
        loading = false
    }
}
