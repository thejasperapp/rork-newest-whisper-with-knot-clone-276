import SwiftUI

// MARK: - Recipes — one shared library with Jasper (Nutrition → Recipes)

/// Browse, save, and delete recipes through `GET/POST/DELETE /v1/recipes`.
/// A recipe saved here appears inside Jasper under Nutrition → Recipes
/// instantly (the worker builds the decode-safe app payload server-side),
/// and the user's own Jasper recipes read back the other way. Per-serving
/// macros are DERIVED live (totals ÷ servings) — never a stored number.
struct JasperRecipesSheet: View {
    /// Pre-filled draft (Jasper Intelligence `recipe` action, DM recipe
    /// cards) — opens straight into the save editor.
    var initialDraft: JasperRecipeDraft? = nil
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Mode: Equatable {
        case list
        case detail(JasperRecipe)
        case compose(JasperRecipeDraft)
    }

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var mode: Mode
    @State private var phase: Phase = .loading
    @State private var recipes: [JasperRecipe] = []
    @State private var banner: String?
    @State private var confirmDelete: JasperRecipe?
    @State private var deleting = false
    @State private var confirmBack: Bool = false
    @State private var closeAfterConfirm: Bool = false

    init(initialDraft: JasperRecipeDraft? = nil, onClose: (() -> Void)? = nil) {
        self.initialDraft = initialDraft
        self.onClose = onClose
        _mode = State(initialValue: initialDraft.map { .compose($0) } ?? .list)
    }

    var body: some View {
        ZStack {
            JasperGlowStage()
            VStack(spacing: 0) {
                header
                switch mode {
                case .list:
                    listBody
                case .detail(let recipe):
                    JasperRecipeDetailView(
                        recipe: recipe,
                        onEdit: {
                            Haptics.tap()
                            withAnimation(.spring(duration: 0.3)) { mode = .compose(JasperRecipeDraft(recipe: recipe)) }
                        },
                        onDelete: { confirmDelete = recipe })
                case .compose(let draft):
                    JasperRecipeComposerView(
                        draft: draft,
                        onSaved: { name in
                            banner = "\"\(name)\" saved to Jasper — it's in Nutrition → Recipes now."
                            Haptics.success()
                            withAnimation(.spring(duration: 0.3)) { mode = .list }
                            Task { await load(silent: true) }
                        })
                }
            }
        }
        .whisperEdgeBack(isEnabled: !deleting, requiresDecision: mode != .list, revealPresentation: mode == .list, controller: backTransition) { requestBack(close: mode == .list) }
        .confirmationDialog("Discard this recipe draft?", isPresented: $confirmBack, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { finishBack() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Use Save in the recipe editor to keep your changes.") }
        .interactiveDismissDisabled(isComposing)
        .task { await load() }
        .confirmationDialog("Remove this recipe from Jasper?",
                            isPresented: Binding(get: { confirmDelete != nil },
                                                 set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) {
                if let recipe = confirmDelete { Task { await delete(recipe) } }
            }
            Button("Keep it", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Deletes it from the shared library — it disappears from Jasper too.")
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if mode != .list {
                Button {
                    Haptics.tap()
                    requestBack(close: false)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.75))
                        .frame(width: 32, height: 32)
                        .background(JasperBrand.chip(colorScheme), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to recipes")
            }
            VStack(alignment: .leading, spacing: 3) {
                JasperKicker(text: headerKicker)
                Text(headerTitle)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Button {
                Haptics.tap()
                requestBack(close: true)
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
            .accessibilityLabel("Close recipes")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var isComposing: Bool { if case .compose = mode { return true }; return false }
    private func requestBack(close: Bool) {
        guard !deleting else { return }
        closeAfterConfirm = close
        if isComposing { confirmBack = true } else { finishBack() }
    }
    private func finishBack() {
        backTransition.perform {
            if closeAfterConfirm { if let onClose { onClose() } else { dismiss() } }
            else { mode = .list }
        }
    }

    private var headerKicker: String {
        switch mode {
        case .list: return "Recipes"
        case .detail: return "Recipe"
        case .compose: return "Save to Jasper"
        }
    }

    private var headerTitle: String {
        switch mode {
        case .list: return "Shared with Jasper"
        case .detail(let recipe): return recipe.name
        case .compose(let draft): return draft.upsertID == nil ? "New recipe" : "Edit recipe"
        }
    }

    // MARK: List

    private var listBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let banner {
                    JasperGlowBox(cornerRadius: 14, glow: 0.4) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.36, green: 0.86, blue: 0.72))
                            Text(banner)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                    }
                }
                newRecipeButton
                switch phase {
                case .loading:
                    loadingRows
                case .failed(let message):
                    statusCard(icon: "wifi.exclamationmark", title: "Couldn't read your recipes", message: message, retry: true)
                case .ready:
                    if recipes.isEmpty {
                        WhisperEmptyState(icon: "book.closed", title: "No recipes yet",
                            message: "Save one here — or ask Knot for a recipe and tap \"Save recipe to Jasper\". Recipes made inside Jasper appear here too.", isCard: false)
                    } else {
                        ForEach(recipes) { recipe in
                            recipeRow(recipe)
                        }
                    }
                }
                Text("One shared library — a recipe saved here appears inside Jasper under Nutrition → Recipes instantly, and Jasper's own recipes read back. Per-serving macros are always derived live from the ingredients, never stored.")
                    .font(.caption2)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var newRecipeButton: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.3)) { mode = .compose(JasperRecipeDraft()) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New recipe")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text("POST /v1/recipes")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.35))
            }
            .foregroundStyle(JasperBrand.ember)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(JasperBrand.ember.opacity(colorScheme == .dark ? 0.13 : 0.09), in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func recipeRow(_ recipe: JasperRecipe) -> some View {
        let macros = recipe.perServing()
        return Button {
            Haptics.tap()
            backTransition.captureLocalPredecessor()
            withAnimation(.smooth(duration: 0.3)) { mode = .detail(recipe) }
        } label: {
            JasperGlowBox(cornerRadius: 16, glow: 0.4) {
                HStack(spacing: 12) {
                    Text(recipe.emoji.isEmpty ? "🍽️" : recipe.emoji)
                        .font(.system(size: 24))
                        .frame(width: 44, height: 44)
                        .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.name)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("\(recipe.servings) servings · \(Int(macros.kcal)) kcal/serving · P \(Int(macros.protein)) · C \(Int(macros.carbs)) · F \(Int(macros.fat))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if recipe.sourceApp?.lowercased().contains("whisper") == true {
                            Text("SAVED FROM WHISPER")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(1.0)
                                .foregroundStyle(JasperBrand.kicker(colorScheme))
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.35))
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
    }

    private var loadingRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                JasperGlowBox(cornerRadius: 16, glow: 0.3) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(JasperBrand.text(colorScheme).opacity(0.12))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(JasperBrand.text(colorScheme).opacity(0.16))
                                .frame(width: 150, height: 11)
                            Capsule().fill(JasperBrand.text(colorScheme).opacity(0.10))
                                .frame(width: 200, height: 9)
                        }
                        Spacer()
                    }
                    .padding(12)
                }
            }
        }
        .phaseAnimator([0.9, 0.45]) { view, value in
            view.opacity(value)
        } animation: { _ in .easeInOut(duration: 0.7) }
    }

    private func statusCard(icon: String, title: String, message: String, retry: Bool) -> some View {
        JasperGlowBox(cornerRadius: 16, glow: 0.4) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(JasperBrand.kicker(colorScheme))
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(JasperBrand.text(colorScheme))
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                    .multilineTextAlignment(.center)
                if retry {
                    Button {
                        Haptics.tap()
                        phase = .loading
                        Task { await load() }
                    } label: {
                        Text("Try again")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(JasperBrand.ink)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(JasperBrand.emberGradient, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)
        }
    }

    // MARK: Data

    private func load(silent: Bool = false) async {
        if !silent { phase = .loading }
        do {
            let library = try await JasperConnectClient.shared.recipeLibrary()
            withAnimation(.spring(duration: 0.3)) {
                recipes = library
                phase = .ready
            }
        } catch JasperConnectError.notConnected {
            phase = .failed("Connect Jasper first — Settings → Sync with Jasper, one tap.")
        } catch {
            let message = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
            if message.lowercased().contains("missing_scope") {
                phase = .failed("Nutrition isn't shared on this token — that's a consent choice made on the Jasper side.")
            } else if !silent {
                phase = .failed(message)
            }
        }
    }

    private func delete(_ recipe: JasperRecipe) async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await JasperConnectClient.shared.deleteRow(resource: "recipes", id: recipe.id)
            Haptics.success()
            banner = "\"\(recipe.name)\" deleted — gone from Jasper too."
            withAnimation(.spring(duration: 0.3)) {
                recipes.removeAll { $0.id == recipe.id }
                mode = .list
            }
        } catch {
            Haptics.warning()
            banner = "Couldn't delete: \((error as? JasperConnectError)?.errorDescription ?? error.localizedDescription)"
        }
        confirmDelete = nil
    }
}

// MARK: - Detail (render contract: WHISPER_RECIPES.md §3)

private struct JasperRecipeDetailView: View {
    let recipe: JasperRecipe
    var onEdit: () -> Void
    var onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var servings: Int

    init(recipe: JasperRecipe, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.recipe = recipe
        self.onEdit = onEdit
        self.onDelete = onDelete
        _servings = State(initialValue: recipe.servings)
    }

    var body: some View {
        let macros = recipe.perServing(servings)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header card: emoji, per-serving macro line, time chips.
                JasperGlowBox(cornerRadius: 18, glow: 0.5) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text(recipe.emoji.isEmpty ? "🍽️" : recipe.emoji)
                                .font(.system(size: 34))
                                .frame(width: 56, height: 56)
                                .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Int(macros.kcal)) kcal / serving")
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundStyle(JasperBrand.text(colorScheme))
                                    .contentTransition(.numericText())
                                Text("P \(Int(macros.protein))g · C \(Int(macros.carbs))g · F \(Int(macros.fat))g")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.6))
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                        }
                        // Servings stepper — re-derives live, never stored.
                        HStack(spacing: 10) {
                            Text("SERVINGS")
                                .font(.system(size: 9.5, weight: .heavy))
                                .tracking(1.4)
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                            stepButton("minus") { if servings > 1 { servings -= 1 } }
                            Text("\(servings)")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(JasperBrand.text(colorScheme))
                                .frame(minWidth: 24)
                                .contentTransition(.numericText())
                            stepButton("plus") { servings += 1 }
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            if let prep = recipe.prepTime, !prep.isEmpty { timeChip("Prep \(prep)") }
                            if let cook = recipe.cookTime, !cook.isEmpty { timeChip("Cook \(cook)") }
                            if let source = recipe.sourceURL, let url = URL(string: source) {
                                Link(destination: url) {
                                    timeChip("View source")
                                }
                            }
                        }
                        if !recipe.note.isEmpty {
                            Text(recipe.note)
                                .font(.system(size: 11.5))
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                }

                // Ingredients — each row: name, amount, total contribution.
                VStack(alignment: .leading, spacing: 8) {
                    JasperKicker(text: "Ingredients · \(recipe.ingredients.count)")
                    JasperGlowBox(cornerRadius: 16, glow: 0.4) {
                        VStack(spacing: 0) {
                            ForEach(Array(recipe.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                                HStack(spacing: 10) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 5))
                                        .foregroundStyle(JasperBrand.ember.opacity(0.7))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ingredient.name)
                                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(JasperBrand.text(colorScheme))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                        Text(ingredient.amountLabel)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                                    }
                                    Spacer()
                                    Text("\(Int(ingredient.totalCalories)) kcal")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.55))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                if index < recipe.ingredients.count - 1 {
                                    Rectangle()
                                        .fill(JasperBrand.divider(colorScheme))
                                        .frame(height: 0.7)
                                        .padding(.leading, 27)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Steps — numbered, hidden when empty.
                if !recipe.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        JasperKicker(text: "Steps")
                        JasperGlowBox(cornerRadius: 16, glow: 0.4) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                                            .foregroundStyle(JasperBrand.ink)
                                            .frame(width: 20, height: 20)
                                            .background(JasperBrand.emberGradient, in: .circle)
                                        Text(step)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.85))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(14)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        onEdit()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11, weight: .bold))
                            Text("Edit & re-save")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(JasperBrand.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(JasperBrand.emberGradient, in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Haptics.tap()
                        onDelete()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .bold))
                            Text("Delete")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(JasperBrand.ember)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(JasperBrand.ember.opacity(0.13), in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                Text("Editing re-POSTs the same recipe id, so Jasper updates in place — deleting removes it from both apps (recipe.deleted on the events feed).")
                    .font(.caption2)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func timeChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(JasperBrand.chip(colorScheme), in: .capsule)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.25)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(JasperBrand.ember)
                .frame(width: 28, height: 28)
                .background(JasperBrand.chip(colorScheme), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Composer (write_fields exactly; payload built server-side)

private struct JasperRecipeComposerView: View {
    var onSaved: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: JasperRecipeDraft
    @State private var stepRows: [StepRow]
    @State private var saving = false
    @State private var saveError: String?

    private struct StepRow: Identifiable {
        let id = UUID()
        var text: String
    }

    init(draft: JasperRecipeDraft, onSaved: @escaping (String) -> Void) {
        self.onSaved = onSaved
        _draft = State(initialValue: draft)
        _stepRows = State(initialValue: draft.steps.isEmpty
                          ? [StepRow(text: "")]
                          : draft.steps.map { StepRow(text: $0) })
    }

    var body: some View {
        let perServing = currentDraft.perServing
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Live per-serving preview — derived, never stored.
                JasperGlowBox(cornerRadius: 16, glow: 0.5) {
                    HStack(spacing: 8) {
                        Image(systemName: "sum")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(JasperBrand.ember)
                        Text("\(Int(perServing.kcal)) kcal · P \(Int(perServing.protein)) · C \(Int(perServing.carbs)) · F \(Int(perServing.fat)) per serving")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .contentTransition(.numericText())
                        Spacer()
                    }
                    .padding(12)
                }

                JasperGlowBox(cornerRadius: 18, glow: 0.5) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            field("Recipe name", text: $draft.name, placeholder: "Protein overnight oats")
                            VStack(alignment: .leading, spacing: 5) {
                                label("Emoji")
                                TextField("", text: $draft.emoji,
                                          prompt: Text("🥣").foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                                    .font(.system(size: 18))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 52, height: 44)
                                    .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 12))
                            }
                        }
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                label("Servings")
                                HStack(spacing: 8) {
                                    stepButton("minus") { if draft.servings > 1 { draft.servings -= 1 } }
                                    Text("\(draft.servings)")
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                        .foregroundStyle(JasperBrand.text(colorScheme))
                                        .frame(minWidth: 22)
                                        .contentTransition(.numericText())
                                    stepButton("plus") { draft.servings += 1 }
                                }
                            }
                            field("Prep time", text: $draft.prepTime, placeholder: "5 min")
                            field("Cook time", text: $draft.cookTime, placeholder: "20 min")
                        }
                        field("Note", text: $draft.note, placeholder: "Optional — a line about the dish")
                    }
                    .padding(14)
                }

                // Ingredients editor.
                VStack(alignment: .leading, spacing: 8) {
                    JasperKicker(text: "Ingredients — macros are per ONE serving of the ingredient")
                    ForEach($draft.ingredients) { $ingredient in
                        ingredientEditor($ingredient)
                    }
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(duration: 0.3)) {
                            draft.ingredients.append(JasperRecipeDraft.Ingredient())
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("Add ingredient")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(JasperBrand.ember)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(JasperBrand.ember.opacity(0.12), in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }

                // Steps editor.
                VStack(alignment: .leading, spacing: 8) {
                    JasperKicker(text: "Steps")
                    JasperGlowBox(cornerRadius: 16, glow: 0.4) {
                        VStack(spacing: 8) {
                            ForEach($stepRows) { $row in
                                HStack(spacing: 8) {
                                    Text("\((stepRows.firstIndex(where: { $0.id == row.id }) ?? 0) + 1)")
                                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                                        .foregroundStyle(JasperBrand.ember)
                                        .frame(width: 18)
                                    TextField("", text: $row.text,
                                              prompt: Text("Mix everything…")
                                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(JasperBrand.text(colorScheme))
                                        .tint(JasperBrand.ember)
                                    Button {
                                        Haptics.tap()
                                        withAnimation(.spring(duration: 0.25)) {
                                            stepRows.removeAll { $0.id == row.id }
                                            if stepRows.isEmpty { stepRows = [StepRow(text: "")] }
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                                            .frame(width: 22, height: 22)
                                            .background(JasperBrand.chip(colorScheme), in: .circle)
                                            .contentShape(.circle)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove step")
                                }
                            }
                            Button {
                                Haptics.tap()
                                withAnimation(.spring(duration: 0.3)) { stepRows.append(StepRow(text: "")) }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Add step")
                                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(JasperBrand.ember)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                    }
                }

                if let saveError {
                    Text(saveError)
                        .font(.caption2)
                        .foregroundStyle(JasperBrand.ember)
                        .fixedSize(horizontal: false, vertical: true)
                }

                saveButton

                Text(draft.upsertID == nil
                     ? "One POST — it appears inside Jasper under Nutrition → Recipes instantly, per-serving macros computed server-side."
                     : "Re-saves the SAME recipe id, so Jasper updates this recipe in place.")
                    .font(.caption2)
                    .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var currentDraft: JasperRecipeDraft {
        var d = draft
        d.steps = stepRows.map(\.text)
        return d
    }

    private var saveButton: some View {
        Button {
            Haptics.tap()
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if saving {
                    ProgressView().tint(JasperBrand.ink).controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(saving ? "Saving to Jasper…" : "Save to Jasper")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(JasperBrand.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(JasperBrand.emberGradient, in: .capsule)
            .opacity(currentDraft.isSendable && !saving ? 1 : 0.45)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!currentDraft.isSendable || saving)
    }

    private func ingredientEditor(_ ingredient: Binding<JasperRecipeDraft.Ingredient>) -> some View {
        JasperGlowBox(cornerRadius: 14, glow: 0.35) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("", text: ingredient.name,
                              prompt: Text("Rolled oats…")
                                .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(JasperBrand.text(colorScheme))
                        .tint(JasperBrand.ember)
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(duration: 0.25)) {
                            draft.ingredients.removeAll { $0.id == ingredient.wrappedValue.id }
                            if draft.ingredients.isEmpty {
                                draft.ingredients = [JasperRecipeDraft.Ingredient()]
                            }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.4))
                            .frame(width: 22, height: 22)
                            .background(JasperBrand.chip(colorScheme), in: .circle)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove ingredient")
                }
                HStack(spacing: 6) {
                    miniField("kcal", text: ingredient.calories)
                    miniField("P g", text: ingredient.protein)
                    miniField("C g", text: ingredient.carbs)
                    miniField("F g", text: ingredient.fat)
                }
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        label("Unit")
                        TextField("", text: ingredient.servingUnit,
                                  prompt: Text("cup").foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(JasperBrand.text(colorScheme))
                            .tint(JasperBrand.ember)
                            .padding(.horizontal, 8)
                            .frame(height: 30)
                            .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 8))
                    }
                    miniField("× used", text: ingredient.numberOfServings)
                    Spacer()
                }
            }
            .padding(11)
        }
    }

    private func miniField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label(title)
            TextField("", text: text,
                      prompt: Text("0").foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(JasperBrand.text(colorScheme))
                .tint(JasperBrand.ember)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 8)
                .frame(width: 56, height: 30)
                .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 8))
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            label(title)
            TextField("", text: text,
                      prompt: Text(placeholder).foregroundStyle(JasperBrand.text(colorScheme).opacity(0.3)))
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(JasperBrand.text(colorScheme))
                .tint(JasperBrand.ember)
                .padding(.horizontal, 11)
                .frame(height: 44)
                .background(JasperBrand.chip(colorScheme), in: .rect(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }

    private func label(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.3)
            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.25)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(JasperBrand.ember)
                .frame(width: 28, height: 28)
                .background(JasperBrand.chip(colorScheme), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        let final = currentDraft
        guard final.isSendable, !saving else { return }
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            _ = try await JasperConnectClient.shared.saveRecipe(final)
            onSaved(final.name.trimmingCharacters(in: .whitespaces))
        } catch JasperConnectError.notConnected {
            saveError = "Connect Jasper first — Settings → Sync with Jasper, one tap."
        } catch {
            Haptics.warning()
            saveError = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
        }
    }
}
