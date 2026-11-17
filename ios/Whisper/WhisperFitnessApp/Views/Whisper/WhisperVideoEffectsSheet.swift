import SwiftUI

/// Camera-off participant treatment shared by meetings, video calls and
/// lives: the person's profile photo blurred to fill the tile with the
/// crisp avatar centered on top — instead of a flat dark rectangle.
struct WhisperVideoAvatarBackdrop: View {
    let username: String
    let imageURL: URL?
    var avatarSize: CGFloat = 84

    var body: some View {
        ZStack {
            Color(white: 0.08)
                .overlay {
                    if let imageURL {
                        WhisperCachedAsyncImage(url: imageURL) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .blur(radius: 36, opaque: true)
                                    .saturation(0.9)
                                    .overlay(Color.black.opacity(0.42))
                            } else {
                                Color(white: 0.08)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .clipped()
            WhisperAvatar(username: username, size: avatarSize, imageURL: imageURL, ring: false)
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
        }
    }
}

/// A built-in backdrop look, rendered locally into an image on selection.
private struct WhisperBackdropPreset: Identifiable {
    let id: String
    let name: String
    let colors: [Color]

    static let all: [WhisperBackdropPreset] = [
        .init(id: "studio", name: "Studio", colors: [Color(white: 0.16), Color(white: 0.05)]),
        .init(id: "sunset", name: "Sunset", colors: [Color(red: 0.98, green: 0.53, blue: 0.28), Color(red: 0.55, green: 0.16, blue: 0.42)]),
        .init(id: "ocean", name: "Ocean", colors: [Color(red: 0.12, green: 0.42, blue: 0.72), Color(red: 0.03, green: 0.11, blue: 0.26)]),
        .init(id: "forest", name: "Forest", colors: [Color(red: 0.16, green: 0.45, blue: 0.30), Color(red: 0.03, green: 0.16, blue: 0.10)]),
        .init(id: "neon", name: "Neon", colors: [Color(red: 0.45, green: 0.22, blue: 0.95), Color(red: 0.05, green: 0.65, blue: 0.85)]),
        .init(id: "loft", name: "Loft", colors: [Color(red: 0.62, green: 0.53, blue: 0.44), Color(red: 0.24, green: 0.19, blue: 0.15)])
    ]

    var gradient: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [Color.white.opacity(0.16), .clear],
                center: .init(x: 0.75, y: 0.2),
                startRadius: 10,
                endRadius: 320
            )
        }
    }
}

/// Bundled photographic scenes (office / nature / cozy) — real images that
/// ride the same persisted-backdrop pipeline as generated ones.
private struct WhisperSceneBackdrop: Identifiable {
    let id: String
    let name: String
    let asset: String

    static let all: [WhisperSceneBackdrop] = [
        .init(id: "office", name: "Office", asset: "backdrop_office"),
        .init(id: "nature", name: "Nature", asset: "backdrop_nature"),
        .init(id: "cozy", name: "Cozy", asset: "backdrop_cozy"),
    ]
}

/// Google Meet-style backgrounds & effects picker for meetings and video
/// calls. Changes apply live to the outgoing camera feed:
/// none / blur / preset backdrops / Jasper-generated backdrops.
struct WhisperVideoEffectsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var mode: WhisperVideoEffectMode = WhisperVideoEffects.shared.mode
    @State private var selectedPath: String? = WhisperVideoEffects.shared.backdropPath
    @State private var savedPaths: [String] = []
    @State private var prompt: String = ""
    @State private var generating: Bool = false
    @State private var generateError: String?
    @State private var cloud = WhisperBackdropCloudService.shared
    @State private var applyingCloudID: String?
    @FocusState private var promptFocused: Bool

    /// Local files that aren't presets and aren't cached cloud copies —
    /// those render in their own "Synced" grid instead.
    private var localOnlyPaths: [String] {
        savedPaths.filter { !$0.contains("preset-") && !$0.contains("cloud-") }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.06).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        modeRow
                        presetSection
                        generateSection
                        if !cloud.items.isEmpty { syncedSection }
                        if !localOnlyPaths.isEmpty { recentsSection }
                        Text("Applies to your camera in meetings, video calls, and lives. Only you need to change it — everyone sees your new background. Generated backdrops sync to your account, so the same library appears on the web app.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 2)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Backgrounds & effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                savedPaths = WhisperVideoEffects.savedBackdropPaths()
                await cloud.refresh()
            }
        }
    }

    // MARK: - Mode row (None / Blur)

    private var modeRow: some View {
        HStack(spacing: 10) {
            modeCard(
                title: "None",
                icon: "person.fill",
                active: mode == .off
            ) {
                WhisperVideoEffects.shared.setMode(.off)
                mode = .off
                selectedPath = nil
            }
            modeCard(
                title: "Blur",
                icon: "person.and.background.dotted",
                active: mode == .blur
            ) {
                WhisperVideoEffects.shared.setMode(.blur)
                mode = .blur
                selectedPath = nil
            }
        }
    }

    private func modeCard(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(active ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(
                active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(active ? 0 : 0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Backdrops")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(WhisperSceneBackdrop.all) { scene in
                    sceneTile(scene)
                }
                ForEach(WhisperBackdropPreset.all) { preset in
                    Button {
                        Haptics.tap()
                        applyPreset(preset)
                    } label: {
                        preset.gradient
                            .frame(height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                Text(preset.name)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.45), in: Capsule())
                                    .padding(6)
                            }
                            .overlay {
                                if isPresetSelected(preset) {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white, lineWidth: 2.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isPresetSelected(_ preset: WhisperBackdropPreset) -> Bool {
        mode == .backdrop && (selectedPath?.contains("preset-\(preset.id)") ?? false)
    }

    // MARK: - Photographic scenes (office / nature / cozy)

    private func sceneTile(_ scene: WhisperSceneBackdrop) -> some View {
        Button {
            Haptics.tap()
            applyScene(scene)
        } label: {
            Color(white: 0.1)
                .frame(height: 72)
                .overlay {
                    Image(scene.asset)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(scene.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .padding(6)
                }
                .overlay {
                    if isSceneSelected(scene) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 2.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func isSceneSelected(_ scene: WhisperSceneBackdrop) -> Bool {
        mode == .backdrop && (selectedPath?.contains("preset-\(scene.id)") ?? false)
    }

    /// Copies the bundled scene image into the backdrop store once, then
    /// applies it — identical pipeline to generated backdrops, so selection
    /// persists across launches.
    private func applyScene(_ scene: WhisperSceneBackdrop) {
        let existing = WhisperVideoEffects.savedBackdropPaths()
            .first { $0.contains("preset-\(scene.id)") }
        if let existing, let image = UIImage(contentsOfFile: existing) {
            WhisperVideoEffects.shared.setBackdrop(image, persistPath: existing)
            mode = .backdrop
            selectedPath = existing
            return
        }
        guard let ui = UIImage(named: scene.asset),
              let data = ui.jpegData(compressionQuality: 0.88) else { return }
        let url = WhisperVideoEffects.backgroundsDirectory()
            .appendingPathComponent("preset-\(scene.id).jpg")
        try? data.write(to: url)
        if let saved = UIImage(contentsOfFile: url.path) {
            WhisperVideoEffects.shared.setBackdrop(saved, persistPath: url.path)
            mode = .backdrop
            selectedPath = url.path
            savedPaths = WhisperVideoEffects.savedBackdropPaths()
        }
    }

    /// Renders the preset gradient into a real image once, saves it, and
    /// applies it — so presets ride the exact same pipeline as generated
    /// backdrops.
    private func applyPreset(_ preset: WhisperBackdropPreset) {
        let existing = WhisperVideoEffects.savedBackdropPaths()
            .first { $0.contains("preset-\(preset.id)") }
        if let existing, let image = UIImage(contentsOfFile: existing) {
            WhisperVideoEffects.shared.setBackdrop(image, persistPath: existing)
            mode = .backdrop
            selectedPath = existing
            return
        }
        let renderer = ImageRenderer(content: preset.gradient.frame(width: 640, height: 360))
        renderer.scale = 2
        guard let ui = renderer.uiImage, let data = ui.jpegData(compressionQuality: 0.9) else { return }
        let url = WhisperVideoEffects.backgroundsDirectory()
            .appendingPathComponent("preset-\(preset.id).jpg")
        try? data.write(to: url)
        if let saved = UIImage(contentsOfFile: url.path) {
            WhisperVideoEffects.shared.setBackdrop(saved, persistPath: url.path)
            mode = .backdrop
            selectedPath = url.path
            savedPaths = WhisperVideoEffects.savedBackdropPaths()
        }
    }

    // MARK: - Generate with Jasper

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Generate with Jasper")
            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $prompt,
                    prompt: Text("A cozy cabin office, warm light\u{2026}").foregroundStyle(.white.opacity(0.35))
                )
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($promptFocused)
                .submitLabel(.go)
                .onSubmit { Task { await generate() } }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

                Button {
                    Haptics.tap()
                    promptFocused = false
                    Task { await generate() }
                } label: {
                    Group {
                        if generating {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(generating || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            if generating {
                Text("Jasper is painting your backdrop\u{2026}")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            if let generateError {
                Text(generateError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
    }

    private func generate() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !generating else { return }
        generating = true
        generateError = nil
        do {
            let data = try await OpenAIService().generateImage(
                prompt: "Video call virtual background, no people, wide 16:9 framing, photographic, softly lit: \(trimmed)"
            )
            guard let path = WhisperVideoEffects.saveBackdrop(data),
                  let image = UIImage(contentsOfFile: path) else {
                throw URLError(.cannotDecodeContentData)
            }
            WhisperVideoEffects.shared.setBackdrop(image, persistPath: path)
            mode = .backdrop
            selectedPath = path
            savedPaths = WhisperVideoEffects.savedBackdropPaths()
            prompt = ""
            // Sync to the shared library so the same backdrop shows on web.
            let uploadData = data
            let uploadPrompt = trimmed
            Task { await WhisperBackdropCloudService.shared.upload(data: uploadData, prompt: uploadPrompt) }
            Haptics.success()
        } catch {
            generateError = "Couldn't generate that backdrop. Try a different prompt."
        }
        generating = false
    }

    // MARK: - Synced backdrops (shared with web)

    private var syncedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Synced backdrops")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(cloud.items) { item in
                    Button {
                        Haptics.tap()
                        applyCloud(item)
                    } label: {
                        Color(white: 0.1)
                            .frame(height: 72)
                            .overlay {
                                WhisperCachedAsyncImage(url: URL(string: item.url)) { phase in
                                    if case .success(let image) = phase {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        Color(white: 0.12)
                                    }
                                }
                                .allowsHitTesting(false)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                if applyingCloudID == item.id {
                                    ProgressView().tint(.white)
                                }
                            }
                            .overlay {
                                if mode == .backdrop, let selectedPath, selectedPath.contains("cloud-\(item.id)") {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white, lineWidth: 2.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await cloud.remove(item) }
                        } label: {
                            Label("Delete everywhere", systemImage: "trash")
                        }
                    }
                }
            }
            Text("Painted on any device — the same library shows up on the web app.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func applyCloud(_ item: WhisperCloudBackdrop) {
        guard applyingCloudID == nil else { return }
        applyingCloudID = item.id
        generateError = nil
        Task {
            let path = await cloud.apply(item)
            applyingCloudID = nil
            if let path {
                mode = .backdrop
                selectedPath = path
            } else {
                generateError = "Couldn't load that backdrop. Try again."
            }
        }
    }

    // MARK: - Recents

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("On this device")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(localOnlyPaths.prefix(9), id: \.self) { path in
                    Button {
                        Haptics.tap()
                        if let image = UIImage(contentsOfFile: path) {
                            WhisperVideoEffects.shared.setBackdrop(image, persistPath: path)
                            mode = .backdrop
                            selectedPath = path
                        }
                    } label: {
                        Color(white: 0.1)
                            .frame(height: 72)
                            .overlay {
                                if let image = UIImage(contentsOfFile: path) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .allowsHitTesting(false)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                if mode == .backdrop && selectedPath == path {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white, lineWidth: 2.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            deleteBackdrop(path)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.62), in: Circle())
                                .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel("Delete backdrop")
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteBackdrop(path)
                        } label: {
                            Label("Delete backdrop", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    /// Removes a saved backdrop; if it was applied, the effect turns off.
    private func deleteBackdrop(_ path: String) {
        Haptics.tap()
        WhisperVideoEffects.deleteBackdrop(atPath: path)
        if selectedPath == path {
            selectedPath = nil
            mode = WhisperVideoEffects.shared.mode
        }
        withAnimation(.easeOut(duration: 0.18)) {
            savedPaths = WhisperVideoEffects.savedBackdropPaths()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .black))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.5))
    }
}
