import SwiftUI
import PhotosUI
import UIKit

/// "Imagine" — drop yourself into a scene. Presents a grid of curated
/// scene tiles (Beach, Mountains, Cyberpunk, Gym, Snow Peak…). Tapping
/// a tile prompts the user to pick a photo of themselves; we then send
/// the photo + scene prompt to OpenAI's `/v1/images/edits` endpoint
/// (`gpt-image-1`) and return the transformed image back to the caller.
struct WhisperImagineSceneSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// Called with the generated image bytes once a scene transformation
    /// succeeds. Caller is responsible for routing the result into the
    /// story editor (or other surface).
    let onGenerated: (UIImage) -> Void

    @State private var selectedScene: ImagineScene?
    @State private var pendingScene: ImagineScene?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var generated: UIImage?
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?
    @State private var customPrompt: String = ""
    @State private var showCustom: Bool = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        sourcePhotoRow
                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }
                        Text("Pick a scene")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ImagineScene.catalog) { scene in
                                sceneTile(scene)
                            }
                            customTile
                        }
                        .padding(.horizontal, 16)
                        Color.clear.frame(height: 24)
                    }
                    .padding(.top, 8)
                }
                if isGenerating {
                    generatingOverlay
                }
            }
            .navigationTitle("Imagine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                guard let item = newItem else { return }
                Task { await loadPickedPhoto(item) }
            }
            .sheet(isPresented: $showCustom) {
                customPromptSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .whisperSheetBorder()
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("Put yourself in the scene")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text("Pick a photo of yourself, then choose a scene. Jasper reimagines you inside it.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [Color(red: 1, green: 0.4, blue: 0.2), Color(red: 0.85, green: 0.2, blue: 0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(.rect(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    // MARK: - Source photo

    private var sourcePhotoRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: 64, height: 64)
                if let img = sourceImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 14))
                } else {
                    Image(systemName: "person.crop.square")
                        .font(.title2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sourceImage == nil ? "Add your photo" : "Your photo")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(sourceImage == nil ? "Tap to pick a photo of yourself" : "Tap to swap photo")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer(minLength: 0)
            PhotosPicker(selection: $photoPickerItem, matching: .images, preferredItemEncoding: .compatible) {
                Text(sourceImage == nil ? "Pick" : "Change")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Tiles

    private func sceneTile(_ scene: ImagineScene) -> some View {
        Button {
            Haptics.tap()
            triggerScene(scene)
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: scene.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: scene.symbol)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(scene.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(scene.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(height: 150)
            .clipShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var customTile: some View {
        Button {
            Haptics.tap()
            showCustom = true
        } label: {
            ZStack {
                WhisperTheme.card(colorScheme)
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Custom prompt")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Describe your own scene")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 150)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom prompt sheet

    private var customPromptSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.title3.weight(.bold))
                Text("Custom scene")
                    .font(.title3.weight(.bold))
                Spacer()
            }
            Text("Describe the scene you want to be placed in.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("e.g. me surfing a massive Pipeline wave at sunset", text: $customPrompt, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            Button {
                showCustom = false
                let p = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !p.isEmpty else { return }
                let scene = ImagineScene(
                    id: "custom",
                    title: "Custom",
                    subtitle: p,
                    symbol: "wand.and.stars",
                    gradient: [Color(red: 1, green: 0.4, blue: 0.2), Color(red: 0.85, green: 0.2, blue: 0.55)],
                    prompt: p
                )
                triggerScene(scene)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Imagine")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Color(red: 1, green: 0.4, blue: 0.2), Color(red: 0.85, green: 0.2, blue: 0.55)], startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    // MARK: - Generating overlay

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Imagining…")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                if let scene = pendingScene {
                    Text(scene.title)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(28)
            .background(.ultraThinMaterial.opacity(0.85), in: .rect(cornerRadius: 18))
        }
        .allowsHitTesting(true)
    }

    // MARK: - Flow

    private func triggerScene(_ scene: ImagineScene) {
        pendingScene = scene
        guard sourceImage != nil else {
            errorMessage = "Pick a photo of yourself first."
            return
        }
        errorMessage = nil
        Task { await runImagine(for: scene) }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                await MainActor.run {
                    self.sourceImage = img
                    self.photoPickerItem = nil
                }
                if let scene = pendingScene {
                    await runImagine(for: scene)
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Couldn't load that photo."
                self.photoPickerItem = nil
            }
        }
    }

    private func runImagine(for scene: ImagineScene) async {
        guard let source = sourceImage else { return }
        guard let png = source.pngData() ?? source.jpegData(compressionQuality: 0.85) else { return }
        await MainActor.run {
            self.isGenerating = true
            self.errorMessage = nil
        }
        defer {
            Task { @MainActor in self.isGenerating = false }
        }
        do {
            let prompt = "Place the person from the provided photo into this scene: \(scene.prompt). Keep their face, hair, and body proportions recognizable. Photoreal lighting that matches the scene. Cinematic, social-media ready."
            let data = try await OpenAIService().editImage(imageData: png, prompt: prompt)
            if let img = UIImage(data: data) {
                await MainActor.run {
                    self.generated = img
                    self.pendingScene = nil
                    onGenerated(img)
                    dismiss()
                }
            } else {
                await MainActor.run { self.errorMessage = "Couldn't decode the result." }
            }
        } catch {
            await MainActor.run { self.errorMessage = "Imagine failed. Try a different scene or photo." }
        }
    }
}

// MARK: - Scene catalog

nonisolated struct ImagineScene: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let gradient: [Color]
    let prompt: String

    static func == (lhs: ImagineScene, rhs: ImagineScene) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let catalog: [ImagineScene] = [
        .init(id: "beach", title: "Tropical beach", subtitle: "Golden hour, palm trees", symbol: "beach.umbrella.fill",
              gradient: [Color(red: 1.0, green: 0.78, blue: 0.45), Color(red: 0.95, green: 0.4, blue: 0.45)],
              prompt: "a sun-drenched tropical beach at golden hour with turquoise water, palm trees, and warm orange skies"),
        .init(id: "mountains", title: "Alpine summit", subtitle: "Snowy peaks at sunrise", symbol: "mountain.2.fill",
              gradient: [Color(red: 0.32, green: 0.55, blue: 0.78), Color(red: 0.78, green: 0.86, blue: 0.95)],
              prompt: "the snowy summit of an alpine mountain at sunrise with dramatic clouds and a sea of peaks below"),
        .init(id: "cyberpunk", title: "Cyberpunk city", subtitle: "Neon Tokyo at night", symbol: "building.2.fill",
              gradient: [Color(red: 0.18, green: 0.05, blue: 0.42), Color(red: 0.95, green: 0.18, blue: 0.55)],
              prompt: "a neon-lit cyberpunk Tokyo street at night, glowing signs, rain-slick pavement, dramatic cinematic lighting"),
        .init(id: "space", title: "Outer space", subtitle: "Floating among stars", symbol: "sparkles",
              gradient: [Color(red: 0.05, green: 0.08, blue: 0.25), Color(red: 0.35, green: 0.18, blue: 0.7)],
              prompt: "floating in outer space among stars and galaxies, Earth visible in the background, photoreal astronaut style"),
        .init(id: "gym", title: "Gym power shot", subtitle: "Studio lighting, chrome", symbol: "dumbbell.fill",
              gradient: [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.4, green: 0.4, blue: 0.46)],
              prompt: "a dramatic dark gym scene with rim lighting, chalk dust, chrome dumbbells, photoreal magazine cover style"),
        .init(id: "track", title: "Olympic track", subtitle: "Sprinting under stadium lights", symbol: "figure.run",
              gradient: [Color(red: 0.86, green: 0.25, blue: 0.18), Color(red: 1.0, green: 0.65, blue: 0.2)],
              prompt: "an olympic running track under blazing stadium floodlights at night, crowd blurred in the background"),
        .init(id: "forest", title: "Misty forest", subtitle: "Cinematic morning fog", symbol: "tree.fill",
              gradient: [Color(red: 0.16, green: 0.42, blue: 0.32), Color(red: 0.6, green: 0.78, blue: 0.55)],
              prompt: "a misty old-growth forest at dawn with shafts of sunlight cutting through tall trees, cinematic colors"),
        .init(id: "concert", title: "Concert stage", subtitle: "Spotlight, crowd, lasers", symbol: "music.mic",
              gradient: [Color(red: 0.55, green: 0.1, blue: 0.85), Color(red: 0.95, green: 0.2, blue: 0.6)],
              prompt: "headlining a massive concert stage with spotlights, lasers, smoke, and a sea of fans"),
        .init(id: "f1", title: "F1 pit lane", subtitle: "Carbon fiber, fast", symbol: "flag.checkered",
              gradient: [Color(red: 0.85, green: 0.05, blue: 0.1), Color(red: 0.15, green: 0.15, blue: 0.18)],
              prompt: "standing on an F1 pit lane next to a race car, carbon fiber details, motion blur, photoreal sports photography"),
        .init(id: "fashion", title: "Fashion runway", subtitle: "High-fashion editorial", symbol: "sparkle",
              gradient: [Color(red: 0.95, green: 0.85, blue: 0.78), Color(red: 0.45, green: 0.18, blue: 0.32)],
              prompt: "walking a high-fashion Paris runway with editorial lighting, magazine-cover composition"),
        .init(id: "snow", title: "Aurora ridge", subtitle: "Northern lights overhead", symbol: "snowflake",
              gradient: [Color(red: 0.18, green: 0.3, blue: 0.55), Color(red: 0.45, green: 0.85, blue: 0.78)],
              prompt: "on a snowy ridge in iceland under a vivid green northern lights display, photoreal night sky"),
        .init(id: "desert", title: "Desert dunes", subtitle: "Sahara sunset, warm tones", symbol: "sun.max.fill",
              gradient: [Color(red: 0.95, green: 0.6, blue: 0.18), Color(red: 0.78, green: 0.28, blue: 0.18)],
              prompt: "atop a Sahara sand dune at sunset, long shadows, warm orange tones, cinematic landscape"),
    ]
}
