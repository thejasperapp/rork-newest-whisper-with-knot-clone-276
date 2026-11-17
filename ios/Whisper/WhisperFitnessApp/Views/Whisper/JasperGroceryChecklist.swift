import SwiftUI

// MARK: - Canonical model (WHISPER_CONNECT.md Aug 16 2026 — the grocery protocol)

/// The grocery checklist Jasper renders in-app, carried VERBATIM on every
/// `diet_plans` read as `payload.groceryList`:
///
///     { planName, itemCount, categories: [{ name, items: [{ name, quantity, usedInMeals }] }] }
///
/// Contract: render it as-is — never re-derive groceries from ingredients.
/// The only sanctioned fallback is a third-party row that omitted the list
/// entirely (`derived` flags that case so the UI can say so).
nonisolated struct JasperGroceryList: Equatable {
    nonisolated struct Item: Equatable, Identifiable {
        let name: String
        let quantity: String
        let usedInMeals: Int
        var id: String { name.lowercased() }
    }

    nonisolated struct Category: Equatable, Identifiable {
        let name: String
        let items: [Item]
        var id: String { name.lowercased() }
    }

    let planName: String
    let categories: [Category]
    /// True when the row omitted `groceryList` (third-party writer) and the
    /// list was assembled from `payload.days` ingredients instead.
    var derived: Bool = false

    var itemCount: Int { categories.reduce(0) { $0 + $1.items.count } }

    /// Jasper's canonical aisle order (§8 fact 9).
    nonisolated static let aisleOrder = [
        "Proteins", "Dairy & Eggs", "Fruits & Vegetables", "Grains & Bread",
        "Pantry", "Oils & Condiments", "Beverages", "Other",
    ]

    // MARK: Canonical decode

    /// Decodes `payload.groceryList` exactly as published. Lenient on value
    /// types (numbers-as-quantity etc.), strict on structure.
    static func parse(payload: [String: Any]?, fallbackName: String) -> JasperGroceryList? {
        guard let grocery = payload?["groceryList"] as? [String: Any],
              let rawCategories = grocery["categories"] as? [[String: Any]] else { return nil }
        let categories: [Category] = rawCategories.compactMap { cat in
            guard let name = cat["name"] as? String else { return nil }
            let items: [Item] = ((cat["items"] as? [[String: Any]]) ?? []).compactMap { raw in
                guard let itemName = raw["name"] as? String, !itemName.isEmpty else { return nil }
                let quantity = (raw["quantity"] as? String)
                    ?? (raw["quantity"] as? NSNumber).map { "\($0)" }
                    ?? ""
                let used = (raw["usedInMeals"] as? Int)
                    ?? (raw["usedInMeals"] as? NSNumber)?.intValue
                    ?? 1
                return Item(name: itemName, quantity: quantity, usedInMeals: used)
            }
            return items.isEmpty ? nil : Category(name: name, items: items)
        }
        guard !categories.isEmpty else { return nil }
        return JasperGroceryList(
            planName: (grocery["planName"] as? String) ?? fallbackName,
            categories: categories
        )
    }

    /// §4 fallback — ONLY for rows that omitted `groceryList`: assemble from
    /// `payload.days[].meals[].ingredients` with a compact quantity parse +
    /// aisle keywords. Marked `derived` so the UI labels it honestly.
    static func derive(payload: [String: Any]?, fallbackName: String) -> JasperGroceryList? {
        guard let days = payload?["days"] as? [[String: Any]], !days.isEmpty else { return nil }
        var map: [String: (quantity: String, count: Int, aisle: String)] = [:]
        for day in days {
            for meal in (day["meals"] as? [[String: Any]]) ?? [] {
                for ingredient in (meal["ingredients"] as? [String]) ?? [] {
                    let (name, quantity) = splitQuantity(ingredient)
                    let key = name.lowercased()
                    guard !key.isEmpty else { continue }
                    if let existing = map[key] {
                        map[key] = (existing.quantity, existing.count + 1, existing.aisle)
                    } else {
                        map[key] = (quantity, 1, aisle(for: key))
                    }
                }
            }
        }
        guard !map.isEmpty else { return nil }
        var grouped: [String: [Item]] = [:]
        for (key, value) in map {
            grouped[value.aisle, default: []].append(
                Item(name: key.capitalized, quantity: value.quantity, usedInMeals: value.count))
        }
        let categories: [Category] = aisleOrder.compactMap { name in
            guard let items = grouped[name], !items.isEmpty else { return nil }
            return Category(name: name, items: items.sorted { $0.name < $1.name })
        }
        guard !categories.isEmpty else { return nil }
        return JasperGroceryList(planName: fallbackName, categories: categories, derived: true)
    }

    /// Picks the best `diet_plans` row (active first, then newest) and
    /// returns its grocery list — canonical preferred, derivation only when
    /// the row omitted it.
    static func fromRows(_ rows: [[String: Any]]) -> JasperGroceryList? {
        let sorted = rows.sorted { a, b in
            let activeA = (a["is_active"] as? Bool) ?? false
            let activeB = (b["is_active"] as? Bool) ?? false
            if activeA != activeB { return activeA }
            let dateA = jasperConnectDate(a["recorded_on"]) ?? .distantPast
            let dateB = jasperConnectDate(b["recorded_on"]) ?? .distantPast
            return dateA > dateB
        }
        for row in sorted {
            let name = (row["name"] as? String) ?? "Diet plan"
            let payload = row["payload"] as? [String: Any]
            if let list = parse(payload: payload, fallbackName: name) { return list }
            if let list = derive(payload: payload, fallbackName: name) { return list }
        }
        return nil
    }

    // MARK: Compact ingredient helpers (fallback path only)

    nonisolated private static func splitQuantity(_ raw: String) -> (name: String, quantity: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let pattern = /^([\d\/\.]+\s*(?:oz|g|kg|ml|l|cup|cups|tbsp|tsp|lb|lbs|slices?|pieces?|cloves?|stalks?|scoops?|medium|large|small|bunch|can|cans)?\.?\s*)/
        if let match = trimmed.firstMatch(of: pattern) {
            let quantity = String(match.1).trimmingCharacters(in: .whitespaces)
            let name = String(trimmed[match.range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? trimmed : name, quantity)
        }
        return (trimmed, "")
    }

    nonisolated private static func aisle(for name: String) -> String {
        let n = name.lowercased()
        let proteins = ["chicken", "turkey", "beef", "pork", "salmon", "tuna", "shrimp", "fish", "steak", "lamb", "tofu", "tempeh", "protein", "sausage", "bacon", "ham"]
        let dairy = ["milk", "cheese", "yogurt", "butter", "cream", "egg", "whey", "cottage", "mozzarella", "cheddar", "parmesan"]
        let produce = ["apple", "banana", "berry", "spinach", "kale", "broccoli", "tomato", "onion", "garlic", "pepper", "lettuce", "avocado", "potato", "carrot", "celery", "cucumber", "zucchini", "mushroom", "lemon", "lime", "orange", "mango", "pineapple", "corn", "peas", "beans", "asparagus"]
        let grains = ["rice", "bread", "oat", "pasta", "tortilla", "quinoa", "cereal", "flour", "wrap", "bagel", "noodle", "couscous", "barley", "pita"]
        let oils = ["oil", "olive", "vinegar", "sauce", "dressing", "mayo", "mustard", "ketchup", "honey", "syrup", "salsa"]
        let beverages = ["water", "juice", "coffee", "tea", "smoothie", "shake"]
        if proteins.contains(where: { n.contains($0) }) { return "Proteins" }
        if dairy.contains(where: { n.contains($0) }) { return "Dairy & Eggs" }
        if produce.contains(where: { n.contains($0) }) { return "Fruits & Vegetables" }
        if grains.contains(where: { n.contains($0) }) { return "Grains & Bread" }
        if oils.contains(where: { n.contains($0) }) { return "Oils & Condiments" }
        if beverages.contains(where: { n.contains($0) }) { return "Beverages" }
        if ["nut", "seed", "almond", "peanut", "salt", "spice", "cinnamon", "cocoa"].contains(where: { n.contains($0) }) { return "Pantry" }
        return "Other"
    }
}

// MARK: - Sheet (Jasper glow language, adaptive light/dark)

/// The grocery checklist drawn exactly like a Jasper moment: glow stage,
/// ember-glow aisle boxes, brand type — ink stage in dark mode, cream in
/// light. Own-account use is interactive (check-offs persist per plan); the
/// coach view is read-only — it's the client's list.
struct JasperGroceryListSheet: View {
    enum Source {
        /// Already-loaded list (coach dashboard — read through the client's token).
        case preloaded(JasperGroceryList, note: String?)
        /// Self-loading through the user's OWN Connect token.
        case ownConnect
        /// A coach reading an accepted client through the coach-held token.
        case coachClient(uid: String, username: String)
    }

    let source: Source
    /// Overlay presentations (Jasper action modals) pass a custom close;
    /// sheet presentations fall back to `dismiss`.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: Phase = .loading
    @State private var checked: Set<String> = []
    /// Aug 17 2026 grocery sync: the live shared state off GET /v1/grocery_list
    /// — stable item ids + checked flags, the SAME rows Jasper's in-app
    /// checklist reads and writes. When present, checks POST straight back.
    @State private var shared: JasperSharedGrocery?
    @State private var coachCanWrite = false
    @State private var syncError: String?

    private enum Phase: Equatable {
        case loading
        case list(JasperGroceryList)
        case shared
        case empty(String)
        case failed(String)
    }

    private var isInteractive: Bool {
        switch source {
        case .ownConnect: return true
        case .coachClient: return shared != nil && coachCanWrite
        case .preloaded: return false
        }
    }

    private var note: String? {
        switch source {
        case .preloaded(_, let note):
            return note
        case .ownConnect:
            return "From your active Jasper diet plan — the exact checklist Jasper renders in-app."
        case .coachClient(_, let username):
            return "Read live through @\(username)'s coach token."
        }
    }

    /// Change-feed pulse for the coach view — a fresh journal event forces a
    /// silent re-read so app-side check-offs land here without reopening.
    private var coachPulse: Date? {
        if case .coachClient(let uid, _) = source { return JasperEventPush.shared.pulses[uid] }
        return nil
    }

    private var headerPlanName: String? {
        if let shared { return shared.planName }
        if case .list(let list) = phase { return list.planName }
        return nil
    }

    var body: some View {
        ZStack {
            JasperGlowStage()
            VStack(spacing: 0) {
                header
                switch phase {
                case .loading:
                    ScrollView { loadingBody }
                        .scrollIndicators(.hidden)
                case .failed(let message):
                    statusBody(icon: "wifi.exclamationmark", title: "Couldn't load the list", message: message, retry: true)
                case .empty(let message):
                    ScrollView { WhisperEmptyState(icon: "cart", title: "No grocery list yet", message: message, isCard: false) }
                case .list(let list):
                    checklist(list)
                case .shared:
                    if let shared { sharedChecklist(shared) }
                }
            }
        }
        .task { await load() }
        .onChange(of: coachPulse) { _, _ in
            Task { await refreshShared() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                JasperKicker(text: "Grocery list")
                if let planName = headerPlanName {
                    Text(planName)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                        .lineLimit(2)
                }
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
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close grocery list")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: Checklist

    private func checklist(_ list: JasperGroceryList) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryRow(list)
                ForEach(list.categories) { category in
                    aisleSection(category)
                }
                Text(list.derived
                     ? "This plan predates Jasper's grocery protocol — the list was assembled from its ingredients."
                     : "Carried on the plan itself, straight from Jasper — never re-derived from ingredients.")
                    .font(.caption2)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                    .padding(.top, 2)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func summaryRow(_ list: JasperGroceryList) -> some View {
        HStack(spacing: 8) {
            summaryChip(icon: "cart.fill", text: "\(list.itemCount) items")
            summaryChip(icon: "square.grid.2x2.fill", text: "\(list.categories.count) aisles")
            if isInteractive {
                let done = checked.count
                summaryChip(icon: "checkmark.circle.fill",
                            text: done == 0 ? "Tap to check off" : "\(done) of \(list.itemCount) in the cart",
                            emphasized: done > 0)
            }
            Spacer()
        }
    }

    private func summaryChip(icon: String, text: String, emphasized: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(emphasized ? JasperBrand.ink : JasperBrand.text(colorScheme).opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if emphasized {
                Capsule().fill(JasperBrand.emberGradient)
            } else {
                Capsule().fill(JasperBrand.chip(colorScheme))
            }
        }
    }

    private func aisleSection(_ category: JasperGroceryList.Category) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: Self.aisleSymbol(category.name))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(JasperBrand.kicker(colorScheme))
                Text(category.name.uppercased())
                    .font(.system(size: 10.5, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                Spacer()
                Text("\(category.items.count)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
            }
            JasperGlowBox(cornerRadius: 18, glow: 0.4) {
                VStack(spacing: 0) {
                    ForEach(Array(category.items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item, key: "\(category.id)::\(item.id)")
                        if index < category.items.count - 1 {
                            Rectangle()
                                .fill(JasperBrand.divider(colorScheme))
                                .frame(height: 0.7)
                                .padding(.leading, 46)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: JasperGroceryList.Item, key: String) -> some View {
        let isChecked = checked.contains(key)
        Button {
            guard isInteractive else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isChecked { checked.remove(key) } else { checked.insert(key) }
            }
            persistChecks()
        } label: {
            HStack(spacing: 12) {
                // WHISPER_PLANS.md §4.6 — 22pt check circle: unchecked = 1pt
                // hairline; checked = teal fill + white bold checkmark.
                ZStack {
                    if isChecked {
                        Circle()
                            .fill(JasperBrand.teal)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .strokeBorder(JasperBrand.text(colorScheme).opacity(isInteractive ? 0.25 : 0.16),
                                          lineWidth: 1)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(isChecked ? 0.45 : 1))
                        .strikethrough(isChecked, color: JasperBrand.text(colorScheme).opacity(0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !item.quantity.isEmpty {
                        Text(item.quantity)
                            .font(.system(size: 11))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if item.usedInMeals > 1 {
                    Text("×\(item.usedInMeals) meals")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(JasperBrand.kicker(colorScheme))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(JasperBrand.ember.opacity(0.14), in: .capsule)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityLabel("\(item.name), \(item.quantity)\(isChecked ? ", checked" : "")")
    }

    // MARK: Shared checklist (live state — checks converge with Jasper)

    private func sharedChecklist(_ list: JasperSharedGrocery) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sharedSummaryRow(list)
                ForEach(list.categories) { category in
                    sharedAisleSection(category)
                }
                if let syncError {
                    Text(syncError)
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.ember)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(sharedFootnote)
                    .font(.caption2)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var sharedFootnote: String {
        switch source {
        case .ownConnect:
            return "One shared checklist — a check here is checked in Jasper too, and Jasper's own check-offs flow back (grocery.updated on the live feed)."
        case .coachClient(_, let username):
            return coachCanWrite
                ? "Shared state through the coach token — a check here shows up in @\(username)'s Jasper instantly, and their own checks land here."
                : "@\(username)'s live shared checklist — view-only on this read-only grant (their choice), their own check-offs still show."
        case .preloaded:
            return ""
        }
    }

    private func sharedSummaryRow(_ list: JasperSharedGrocery) -> some View {
        HStack(spacing: 8) {
            summaryChip(icon: "cart.fill", text: "\(list.itemCount) items")
            summaryChip(icon: "dot.radiowaves.up.forward", text: "LIVE · synced with Jasper")
            let done = list.checkedCount
            if done > 0 || isInteractive {
                summaryChip(icon: "checkmark.circle.fill",
                            text: done == 0 ? "Tap to check off" : "\(done) of \(list.itemCount) in the cart",
                            emphasized: done > 0)
            }
            Spacer()
        }
    }

    private func sharedAisleSection(_ category: JasperSharedGrocery.Category) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: Self.aisleSymbol(category.name))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(JasperBrand.kicker(colorScheme))
                Text(category.name.uppercased())
                    .font(.system(size: 10.5, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                Spacer()
                Text("\(category.items.count)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
            }
            JasperGlowBox(cornerRadius: 18, glow: 0.4) {
                VStack(spacing: 0) {
                    ForEach(Array(category.items.enumerated()), id: \.element.id) { index, item in
                        sharedItemRow(item, categoryID: category.id)
                        if index < category.items.count - 1 {
                            Rectangle()
                                .fill(JasperBrand.divider(colorScheme))
                                .frame(height: 0.7)
                                .padding(.leading, 46)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func sharedItemRow(_ item: JasperSharedGrocery.Item, categoryID: String) -> some View {
        Button {
            toggleShared(categoryID: categoryID, itemID: item.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if item.checked {
                        Circle()
                            .fill(JasperBrand.teal)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .strokeBorder(JasperBrand.text(colorScheme).opacity(isInteractive ? 0.25 : 0.16),
                                          lineWidth: 1)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(item.checked ? 0.45 : 1))
                        .strikethrough(item.checked, color: JasperBrand.text(colorScheme).opacity(0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !item.quantity.isEmpty {
                        Text(item.quantity)
                            .font(.system(size: 11))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if item.usedInMeals > 1 {
                    Text("×\(item.usedInMeals) meals")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(JasperBrand.kicker(colorScheme))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(JasperBrand.ember.opacity(0.14), in: .capsule)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityLabel("\(item.name), \(item.quantity)\(item.checked ? ", checked" : "")")
    }

    /// Optimistic toggle → POST /v1/grocery_list; a failed write reverts and
    /// says so — the UI never pretends a check reached Jasper when it didn't.
    private func toggleShared(categoryID: String, itemID: String) {
        guard isInteractive, var next = shared,
              let ci = next.categories.firstIndex(where: { $0.id == categoryID }),
              let ii = next.categories[ci].items.firstIndex(where: { $0.id == itemID }) else { return }
        Haptics.tap()
        let newValue = !next.categories[ci].items[ii].checked
        next.categories[ci].items[ii].checked = newValue
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { shared = next }
        syncError = nil
        let planID = next.planID
        Task {
            do {
                switch source {
                case .ownConnect:
                    try await JasperConnectClient.shared.setGroceryChecks(
                        planID: planID, changes: [(itemID, newValue)])
                case .coachClient(let uid, _):
                    try await JasperCoachConnect.shared.setGroceryChecks(
                        forClient: uid, planID: planID, changes: [(itemID, newValue)])
                case .preloaded:
                    break
                }
            } catch {
                if var revert = shared,
                   let rci = revert.categories.firstIndex(where: { $0.id == categoryID }),
                   let rii = revert.categories[rci].items.firstIndex(where: { $0.id == itemID }) {
                    revert.categories[rci].items[rii].checked = !newValue
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { shared = revert }
                }
                Haptics.warning()
                syncError = "That check didn't reach Jasper — \((error as? JasperConnectError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }

    /// Silent re-read of the shared state (change-feed pulse / reopen) — folds
    /// in Jasper-side check-offs without a loading flash.
    private func refreshShared() async {
        guard case .shared = phase else { return }
        switch source {
        case .ownConnect:
            if let live = try? await JasperConnectClient.shared.sharedGroceryList(planID: shared?.planID) {
                withAnimation(.spring(duration: 0.3)) { shared = live }
            }
        case .coachClient(let uid, _):
            if let live = try? await JasperCoachConnect.shared.sharedGroceryList(forClient: uid) {
                withAnimation(.spring(duration: 0.3)) { shared = live }
            }
        case .preloaded:
            break
        }
    }

    // MARK: Loading / status

    private var loadingBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(JasperBrand.text(colorScheme).opacity(0.16))
                        .frame(width: 110, height: 10)
                    JasperGlowBox(cornerRadius: 18, glow: 0.3) {
                        VStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(JasperBrand.text(colorScheme).opacity(0.12))
                                        .frame(width: 22, height: 22)
                                    Capsule()
                                        .fill(JasperBrand.text(colorScheme).opacity(0.16))
                                        .frame(width: 140, height: 11)
                                    Spacer()
                                }
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .phaseAnimator([0.9, 0.45]) { view, phaseValue in
            view.opacity(phaseValue)
        } animation: { _ in .easeInOut(duration: 0.7) }
    }

    private func statusBody(icon: String, title: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(JasperBrand.kicker(colorScheme))
            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(JasperBrand.text(colorScheme))
            Text(message)
                .font(.footnote)
                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if retry {
                Button {
                    Haptics.tap()
                    phase = .loading
                    Task { await load() }
                } label: {
                    Text("Try again")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(JasperBrand.ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(JasperBrand.emberGradient, in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Load

    private func load() async {
        switch source {
        case .preloaded(let list, _):
            phase = .list(list)
            restoreChecks(for: list)
        case .ownConnect:
            guard case .loading = phase else { return }
            // Shared state first (Aug 17 grocery sync) — stable ids + checked
            // flags that converge with Jasper's own checklist.
            do {
                if let live = try await JasperConnectClient.shared.sharedGroceryList() {
                    withAnimation(.spring(duration: 0.35)) {
                        shared = live
                        phase = .shared
                    }
                    return
                }
            } catch JasperConnectError.revoked {
                phase = .failed("This connection was revoked — reconnect Jasper in Settings and try again.")
                return
            } catch {
                // Fall back to the verbatim payload read below — older plans
                // and transient failures still get the honest checklist.
            }
            do {
                let data = try await JasperConnectClient.shared.read("diet_plans", limit: 20)
                apply(data: data,
                      emptyRows: "No diet plan in Jasper yet — create one and its grocery checklist appears here.",
                      emptyList: "Your plan doesn't carry a grocery list yet — open it in Jasper once to generate one.")
            } catch {
                applyError(error)
            }
        case .coachClient(let uid, let username):
            guard case .loading = phase else { return }
            coachCanWrite = (try? await JasperCoachConnect.shared.access(forClient: uid))?.canWrite == true
            do {
                if let live = try await JasperCoachConnect.shared.sharedGroceryList(forClient: uid) {
                    withAnimation(.spring(duration: 0.35)) {
                        shared = live
                        phase = .shared
                    }
                    return
                }
            } catch {
                // Fall back to the verbatim diet_plans payload below.
            }
            do {
                let data = try await JasperCoachConnect.shared.read(forClient: uid, "diet_plans", limit: 20)
                apply(data: data,
                      emptyRows: "@\(username) has no diet plan in Jasper yet.",
                      emptyList: "Their plan doesn't carry a grocery list yet — it generates when they open it in Jasper.")
            } catch {
                applyError(error)
            }
        }
    }

    private func apply(data: Data, emptyRows: String, emptyList: String) {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let rows = (body?["data"] as? [[String: Any]]) ?? []
        if let list = JasperGroceryList.fromRows(rows) {
            restoreChecks(for: list)
            withAnimation(.spring(duration: 0.35)) { phase = .list(list) }
        } else {
            phase = .empty(rows.isEmpty ? emptyRows : emptyList)
        }
    }

    private func applyError(_ error: Error) {
        if case JasperConnectError.revoked = error {
            phase = .failed("This connection was revoked — reconnect Jasper in Settings and try again.")
            return
        }
        let message = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        if message.lowercased().contains("missing_scope") || message.lowercased().contains("missing scope") {
            phase = .empty("Nutrition isn't shared on this token — that's a consent choice made on the Jasper side, not an error.")
        } else {
            phase = .failed(message)
        }
    }

    // MARK: Check-off persistence (own list only)

    private var storageKey: String? {
        guard isInteractive, case .list(let list) = phase else { return nil }
        return "jasper_grocery_checked_v1::" + list.planName.lowercased()
    }

    private func restoreChecks(for list: JasperGroceryList) {
        guard isInteractive else { return }
        let key = "jasper_grocery_checked_v1::" + list.planName.lowercased()
        checked = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private func persistChecks() {
        guard let key = storageKey else { return }
        UserDefaults.standard.set(Array(checked), forKey: key)
    }

    // MARK: Aisle symbols

    nonisolated static func aisleSymbol(_ name: String) -> String {
        switch name.lowercased() {
        case "proteins": return "fish.fill"
        case "dairy & eggs": return "cup.and.saucer.fill"
        case "fruits & vegetables": return "carrot.fill"
        case "grains & bread": return "circle.hexagongrid.fill"
        case "pantry": return "archivebox.fill"
        case "oils & condiments": return "drop.fill"
        case "beverages": return "waterbottle.fill"
        default: return "basket.fill"
        }
    }
}
