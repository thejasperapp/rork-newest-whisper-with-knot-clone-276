import SwiftUI

struct WhisperChatThemePicker: View {
    @Binding var selection: WhisperChatAppearance
    let thread: String
    var sharedStore: WhisperGroupThemeStore? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var draft: WhisperChatAppearance? = nil
    @State private var showWallpaper: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    @State private var generated: WhisperChatThemeDesign? = nil
    @State private var prompt: String = ""
    @State private var busy: Bool = false
    @State private var error: String? = nil
    @State private var work: Task<Void, Never>? = nil
    @State private var expectedRevision: Int? = nil
    @State private var operationID: UUID = UUID()
    private var preview: WhisperChatAppearance { generated?.appearance ?? draft ?? selection }
    private var previewDesign: WhisperChatThemeDesign? {
        generated ?? (draft == nil ? sharedStore?.design : nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Set the mood.").font(.largeTitle.weight(.bold))
                        Text("A place that feels like your conversation.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        WhisperChatThemePreview(theme: preview, design: previewDesign).frame(height: 250)
                        HStack {
                            Text(previewDesign?.title ?? preview.title).font(.headline)
                            Spacer()
                            Text("PREVIEW").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                        }
                        Text(preview.mood).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button("Create a personal AI wallpaper", systemImage: "sparkles.rectangle.stack") { showWallpaper = true }
                        .frame(minHeight: 44).disabled(busy)
                    if sharedStore != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Design with AI", systemImage: "sparkles").font(.headline)
                            Text("Describe a mood. AI combines a pattern with a custom palette; nothing changes until you apply it.").font(.footnote).foregroundStyle(.secondary)
                            TextField("Sea glass, warm sand, a quiet coast…", text: $prompt, axis: .vertical)
                                .lineLimit(2...4).padding(12).background(WhisperTheme.card(scheme), in: .rect(cornerRadius: 12))
                                .onChange(of: prompt) { _, value in if value.count > 400 { prompt = String(value.prefix(400)) } }
                            Button("Generate preview", systemImage: "wand.and.stars") { generate() }
                                .frame(minHeight: 44).disabled(busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sharedStore?.isReady != true)
                        }
                    }
                    if busy { ProgressView("Working…") }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if let sharedStore, !sharedStore.isReady {
                        Text(sharedStore.error ?? "Loading shared theme…").font(.footnote).foregroundStyle(.secondary)
                        Button("Refresh") { work = Task { await sharedStore.refresh(); expectedRevision = sharedStore.revision } }.frame(minHeight: 44)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 18) {
                        ForEach(WhisperChatAppearance.allCases) { theme in
                            Button {
                                generated = nil; draft = theme; operationID = UUID()
                                Haptics.selection()
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    WhisperChatThemePreview(theme: theme, compact: true)
                                        .frame(height: 145)
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(preview == theme ? WhisperTheme.ink(scheme) : WhisperTheme.hairline(scheme), lineWidth: preview == theme ? 2 : 0.75))
                                        .overlay(alignment: .bottomTrailing) {
                                            if preview == theme {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(WhisperTheme.surface(scheme), WhisperTheme.ink(scheme))
                                                    .font(.title3).padding(7)
                                            }
                                        }
                                    Text(theme.title).font(.caption.weight(.medium))
                                }
                            }.buttonStyle(.plain)
                                .accessibilityLabel(theme.title)
                                .accessibilityAddTraits(preview == theme ? .isSelected : [])
                        }
                    }
                    .disabled(busy)
                    Text(sharedStore == nil ? "Only you see this theme. Saved for this conversation on this device." : "Applying changes the theme for everyone in this group. Everyone keeps their own light or dark mode.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(16)
            }
            .background(WhisperTheme.surface(scheme))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    guard generation == AccountStorage.generation else { dismiss(); return }
                    apply()
                } label: {
                    Text(sharedStore == nil ? "Apply \(preview.title)" : "Apply for everyone").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(WhisperTheme.surface(scheme))
                        .background(WhisperTheme.ink(scheme), in: Capsule())
                }.disabled(busy || (sharedStore != nil && (sharedStore?.isReady != true || expectedRevision == nil)))
                    .buttonStyle(.plain).padding(16).background(WhisperTheme.surface(scheme))
            }
            .navigationTitle("Chat themes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }.whisperFlatToolbar() }
        }
        .sheet(isPresented: $showWallpaper) { WhisperWallpaperEditor(thread: thread) }
        .foregroundStyle(WhisperTheme.ink(scheme))
        .task {
            if let sharedStore { await sharedStore.refresh(); expectedRevision = sharedStore.revision }
        }
        .onDisappear { work?.cancel() }
        .interactiveDismissDisabled(busy)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
    }

    private func generate() {
        guard !busy, let sharedStore, sharedStore.isReady else { return }
        busy = true; error = nil
        let brief = prompt
        work = Task {
            defer { busy = false }
            do {
                let next = try await WhisperAIThemeService.generate(prompt: brief, operationID: UUID())
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                generated = next; draft = nil; operationID = UUID()
            } catch {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                self.error = (error as? WhisperThemeFailure)?.errorDescription ?? WhisperThemeFailure.generation.errorDescription
            }
        }
    }

    private func apply() {
        guard !busy else { return }
        guard let sharedStore else {
            preview.save(thread: thread); selection = preview; Haptics.selection(); dismiss(); return
        }
        guard let expectedRevision else { return }
        let design = previewDesign ?? .init(theme: preview)
        busy = true; error = nil
        work = Task {
            defer { busy = false }
            do {
                try await sharedStore.apply(design, expectedRevision: expectedRevision, operationID: operationID)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                selection = sharedStore.design.appearance; Haptics.success(); dismiss()
            } catch {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                if case WhisperThemeFailure.conflict = error {
                    self.expectedRevision = sharedStore.revision; operationID = UUID()
                }
                self.error = (error as? WhisperThemeFailure)?.errorDescription ?? "Couldn't save for the group. Your preview is still here; try again."
            }
        }
    }
}
