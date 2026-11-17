import SwiftUI
import PhotosUI
import CoreImage

/// One photo inside the grid composer. Identified so reordering, deleting,
/// and the pager keep stable identity (index-keyed ForEach broke animations).
private struct GridDraftPhoto: Identifiable, Equatable {
    let id: UUID
    let data: Data
    let image: UIImage
    /// The kit filter picked for THIS photo — baked into the upload at publish.
    var filter: WhisperGridFilter = .normal

    init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        self.id = UUID()
        self.data = data
        self.image = image
    }
}

/// The 9-filter rack from the web composer's Edit step — CIFilter
/// approximations of the same looks, baked at publish so every platform
/// sees the identical photo.
nonisolated enum WhisperGridFilter: String, CaseIterable, Sendable {
    case normal = "Normal"
    case clarendon = "Clarendon"
    case gingham = "Gingham"
    case moon = "Moon"
    case lark = "Lark"
    case reyes = "Reyes"
    case juno = "Juno"
    case slumber = "Slumber"
    case aden = "Aden"

    nonisolated(unsafe) private static let context = CIContext()

    /// Applies the filter chain and returns a baked UIImage (original on
    /// any failure — publishing never blocks on a filter).
    func bake(_ image: UIImage) -> UIImage { rendered(image) ?? image }

    /// Failure-reporting path for editors that must not claim a look was applied.
    func rendered(_ image: UIImage) -> UIImage? {
        if self == .normal { return image }
        guard let base = CIImage(image: image) else { return nil }
        var img = base

        func colorControls(saturation: Double, brightness: Double, contrast: Double) {
            guard let f = CIFilter(name: "CIColorControls") else { return }
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(saturation, forKey: kCIInputSaturationKey)
            f.setValue(brightness, forKey: kCIInputBrightnessKey)
            f.setValue(contrast, forKey: kCIInputContrastKey)
            img = f.outputImage ?? img
        }
        func sepia(_ intensity: Double) {
            guard let f = CIFilter(name: "CISepiaTone") else { return }
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(intensity, forKey: kCIInputIntensityKey)
            img = f.outputImage ?? img
        }
        func temperature(_ targetKelvin: CGFloat) {
            guard let f = CIFilter(name: "CITemperatureAndTint") else { return }
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: targetKelvin, y: 0), forKey: "inputTargetNeutral")
            img = f.outputImage ?? img
        }

        switch self {
        case .normal:
            break
        case .clarendon:
            colorControls(saturation: 1.35, brightness: 0.02, contrast: 1.18)
        case .gingham:
            colorControls(saturation: 0.88, brightness: 0.05, contrast: 0.94)
        case .moon:
            colorControls(saturation: 0.0, brightness: 0.06, contrast: 1.1)
        case .lark:
            colorControls(saturation: 1.08, brightness: 0.08, contrast: 0.93)
            temperature(7200)
        case .reyes:
            sepia(0.22)
            colorControls(saturation: 0.78, brightness: 0.1, contrast: 0.86)
        case .juno:
            colorControls(saturation: 1.38, brightness: 0.02, contrast: 1.12)
            temperature(5600)
        case .slumber:
            sepia(0.18)
            colorControls(saturation: 0.68, brightness: 0.05, contrast: 0.96)
        case .aden:
            colorControls(saturation: 0.85, brightness: 0.09, contrast: 0.9)
            temperature(5400)
        }

        guard let cg = Self.context.createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}

/// Instagram-grade grid post composer for creators. A big 4:5 stage up top,
/// a draggable film strip to reorder (first frame = cover), a caption card
/// with a live counter, and a pinned share bar. The photo picker opens
/// itself on first launch so the flow starts in the library — exactly like
/// the reference composers.
struct WhisperGridComposerView: View {
    var embedded: Bool = false
    var isActive: Bool = true
    var onBusyChanged: ((Bool) -> Void)? = nil
    var onPosted: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onDirtyChanged: ((Bool) -> Void)? = nil
    @State private var accountGeneration = AccountStorage.generation
    @State private var importing = false
    @State private var publishError: String?
    @State private var confirmExit = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var photos: [GridDraftPhoto] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showPicker: Bool = false
    @State private var didAutoOpenPicker: Bool = false
    @State private var selectedID: UUID?
    @State private var draggingID: UUID?
    @State private var caption: String = ""
    @State private var posting: Bool = false
    @FocusState private var captionFocused: Bool
    /// Filter rack thumbnails for the SELECTED photo — one tiny render per
    /// filter, recomputed when the selection changes.
    @State private var rackThumbs: [String: UIImage] = [:]
    /// Baked mid-size previews so the hero shows the filtered look.
    @State private var filteredPreviews: [String: UIImage] = [:]
    // Advanced share options — the web composer's Share-step fields, riding
    // the SAME caption meta wire (altText · commentsOff · hideCounts).
    @State private var altText: String = ""
    @State private var commentsOff: Bool = false
    @State private var hideCounts: Bool = false

    // Share-step extras — tag people, location, music (web parity, same wire).
    @State private var tagged: [String] = []
    @State private var tagInput: String = ""
    @State private var locationText: String = ""
    @State private var pickedMusic: WhisperStoryMusic? = nil
    @State private var showMusicPicker: Bool = false

    @State private var backend = WhisperBackendService.shared

    private let maxPhotos: Int = 10
    private let captionLimit: Int = 2_200

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var card: Color { WhisperTheme.card(colorScheme) }

    private var selectedIndex: Int {
        guard let selectedID else { return 0 }
        return photos.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    private var displayUsername: String {
        WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private var hasEdits: Bool {
        !photos.isEmpty || !caption.isEmpty || !altText.isEmpty || !tagged.isEmpty
            || !locationText.isEmpty || pickedMusic != nil || commentsOff || hideCounts
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            if photos.isEmpty {
                                emptyStage
                            } else {
                                heroStage
                                filmStrip
                                filterRack
                            }
                            captionCard
                            if !photos.isEmpty { detailsCard }
                            if !photos.isEmpty { advancedCard }
                        }
                        .padding(16)
                        .padding(.bottom, 8)
                    }

                    shareBar
                }
                .disabled(posting || importing)

                if importing { ProgressView("Preparing photos…").padding(20).background(.regularMaterial, in: .rect(cornerRadius: 18)) }
                if posting { postingOverlay }
            }
            .navigationTitle("New grid post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if let onCancel { onCancel() }
                        else if !hasEdits { dismiss() }
                        else { confirmExit = true }
                    }
                        .disabled(posting || importing)
                        .foregroundStyle(ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showPicker = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(photos.count >= maxPhotos ? muted : ink)
                    }
                    .disabled(photos.count >= maxPhotos || posting || importing)
                }
            }
        }
        .photosPicker(
            isPresented: $showPicker,
            selection: $photoPickerItems,
            maxSelectionCount: maxPhotos - photos.count,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty, !importing, !posting else { return }
            importing = true
            Task { await loadPhotos(items) }
        }
        .onAppear {
            // Start in the library like Instagram — but only once, so
            // cancelling the picker doesn't loop it back open.
            if !embedded && photos.isEmpty && !didAutoOpenPicker {
                didAutoOpenPicker = true
                showPicker = true
            }
        }
        .interactiveDismissDisabled(posting || importing || hasEdits)
        .onChange(of: hasEdits, initial: true) { _, dirty in onDirtyChanged?(dirty) }
        .onChange(of: posting || importing, initial: true) { _, busy in onBusyChanged?(busy) }
        .onChange(of: isActive) { _, active in if !active { captionFocused = false } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in dismiss() }
        .confirmationDialog("Discard grid post edits?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Discard edits", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        }
        .alert("Grid post update", isPresented: Binding(get: { publishError != nil }, set: { if !$0 { publishError = nil } })) {
            Button("Keep editing", role: .cancel) { publishError = nil }
        } message: { Text(publishError ?? "") }
        .sheet(isPresented: $showMusicPicker) {
            WhisperThoughtMusicSheet { picked in
                pickedMusic = picked
                showMusicPicker = false
                Haptics.success()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Empty stage

    private var emptyStage: some View {
        VStack(spacing: 18) {
            ZStack {
                // A fanned stack of frames — the grid-post idea at a glance.
                RoundedRectangle(cornerRadius: 18)
                    .fill(card)
                    .frame(width: 132, height: 165)
                    .rotationEffect(.degrees(-7))
                    .offset(x: -26, y: 6)
                RoundedRectangle(cornerRadius: 18)
                    .fill(card)
                    .frame(width: 132, height: 165)
                    .rotationEffect(.degrees(6))
                    .offset(x: 26, y: 2)
                RoundedRectangle(cornerRadius: 18)
                    .fill(card)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(ink)
                            Text("Up to 10 photos")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(muted)
                        }
                    }
                    .frame(width: 148, height: 185)
                    .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
            }
            .padding(.top, 26)

            VStack(spacing: 4) {
                Text("Build your grid")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(ink)
                Text("Pick photos — viewers swipe through them\nas one post on your wall.")
                    .font(.footnote)
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
            }

            Button {
                Haptics.tap()
                showPicker = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Choose photos")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .padding(.horizontal, 26)
                .padding(.vertical, 13)
                .background(ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero stage (4:5 pager)

    private var heroStage: some View {
        TabView(selection: $selectedID) {
            ForEach(photos) { photo in
                Color.clear
                    .overlay {
                        Image(uiImage: filteredPreviews["\(photo.id)-\(photo.filter.rawValue)"] ?? photo.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipped()
                    .tag(Optional(photo.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .background(card)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
        .overlay(alignment: .topLeading) {
            if selectedIndex == 0 {
                Text("COVER")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if photos.count > 1 {
                Text("\(selectedIndex + 1)/\(photos.count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                Haptics.tap()
                removeSelected()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .overlay(alignment: .bottom) {
            if photos.count > 1 { pageDots.padding(.bottom, 10) }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(photos) { photo in
                Circle()
                    .fill(photo.id == photos[selectedIndex].id ? .white : .white.opacity(0.45))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.35), in: Capsule())
    }

    // MARK: - Film strip (drag to reorder)

    private var filmStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drag to reorder — first frame is your cover")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(muted)
                Spacer()
                Text("\(photos.count)/\(maxPhotos)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(muted)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            stripThumb(photo)
                                .id(photo.id)
                        }
                        if photos.count < maxPhotos { addTile }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Filter rack (the web Edit step, per photo)

    @ViewBuilder
    private var filterRack: some View {
        if photos.indices.contains(selectedIndex) {
            let photo = photos[selectedIndex]
            VStack(alignment: .leading, spacing: 8) {
                Text("Filter — photo \(selectedIndex + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(WhisperGridFilter.allCases, id: \.rawValue) { f in
                            filterTile(f, photo: photo)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .task(id: selectedID) { await buildRackThumbs() }
        }
    }

    private func filterTile(_ f: WhisperGridFilter, photo: GridDraftPhoto) -> some View {
        let isOn = photo.filter == f
        return Button {
            Haptics.tap()
            applyFilter(f)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let thumb = rackThumbs[f.rawValue] {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color(.secondarySystemBackground)
                    }
                }
                .frame(width: 62, height: 62)
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isOn ? ink : WhisperTheme.hairline(colorScheme), lineWidth: isOn ? 2 : 1)
                }
                Text(f.rawValue)
                    .font(.system(size: 10, weight: isOn ? .bold : .semibold))
                    .foregroundStyle(isOn ? ink : muted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.rawValue) filter")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Applies a filter to the selected photo and refreshes its hero preview.
    private func applyFilter(_ f: WhisperGridFilter) {
        guard photos.indices.contains(selectedIndex) else { return }
        photos[selectedIndex].filter = f
        let photo = photos[selectedIndex]
        guard f != .normal else { return }
        let key = "\(photo.id)-\(f.rawValue)"
        guard filteredPreviews[key] == nil else { return }
        let source = photo.image
        Task.detached(priority: .userInitiated) {
            let scaled = Self.downscale(source, maxSide: 1200)
            let baked = f.bake(scaled)
            await MainActor.run {
                filteredPreviews[key] = baked
                // Keep the cache small — previews are throwaway.
                if filteredPreviews.count > 24 { filteredPreviews.removeAll(keepingCapacity: true); filteredPreviews[key] = baked }
            }
        }
    }

    /// Renders the 9 rack thumbnails for the selected photo off-main.
    private func buildRackThumbs() async {
        guard photos.indices.contains(selectedIndex) else { return }
        let source = photos[selectedIndex].image
        let thumbs: [String: UIImage] = await Task.detached(priority: .userInitiated) {
            let base = Self.downscale(source, maxSide: 120)
            var out: [String: UIImage] = [:]
            for f in WhisperGridFilter.allCases {
                out[f.rawValue] = f.bake(base)
            }
            return out
        }.value
        await MainActor.run { rackThumbs = thumbs }
    }

    private nonisolated static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private func stripThumb(_ photo: GridDraftPhoto) -> some View {
        let isSelected = photo.id == selectedID || (selectedID == nil && photos.first?.id == photo.id)
        let isCover = photos.first?.id == photo.id
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectedID = photo.id }
        } label: {
            Color.clear
                .frame(width: 66, height: 66)
                .overlay {
                    Image(uiImage: photo.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? ink : .clear, lineWidth: 2)
                }
                .overlay(alignment: .bottomLeading) {
                    if isCover {
                        Text("COVER")
                            .font(.system(size: 6.5, weight: .black))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(3)
                    }
                }
                .opacity(draggingID == photo.id ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .draggable(photo.id.uuidString) {
            Image(uiImage: photo.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 66, height: 66)
                .clipShape(.rect(cornerRadius: 12))
                .onAppear { draggingID = photo.id }
        }
        .dropDestination(for: String.self) { items, _ in
            draggingID = nil
            guard let idString = items.first,
                  let from = photos.firstIndex(where: { $0.id.uuidString == idString }),
                  let to = photos.firstIndex(where: { $0.id == photo.id }),
                  from != to
            else { return false }
            Haptics.tap()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                let moved = photos.remove(at: from)
                photos.insert(moved, at: to)
            }
            return true
        } isTargeted: { targeted in
            if targeted { Haptics.tap() }
        }
        .contextMenu {
            if photos.first?.id != photo.id {
                Button {
                    makeCover(photo.id)
                } label: {
                    Label("Make cover", systemImage: "star")
                }
            }
            Button(role: .destructive) {
                remove(photo.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var addTile: some View {
        Button {
            Haptics.tap()
            showPicker = true
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1, dash: [5]))
                .frame(width: 66, height: 66)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(muted)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Caption

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                WhisperAvatar(username: displayUsername, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayUsername)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ink)
                    TextField("Write a caption…", text: $caption, axis: .vertical)
                        .lineLimit(1...8)
                        .focused($captionFocused)
                        .font(.body)
                        .foregroundStyle(ink)
                        .onChange(of: caption) { _, value in
                            if value.count > captionLimit {
                                caption = String(value.prefix(captionLimit))
                            }
                        }
                }
                Spacer(minLength: 0)
            }
            .padding(12)

            if captionFocused || !caption.isEmpty {
                HStack {
                    Spacer()
                    Text("\(caption.count)/\(captionLimit)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(muted)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(card, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    // MARK: - Advanced (the web Share step's fields, same meta wire)

    // MARK: - Details card (tag people · location · music — web parity)

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Tag people — chips + @username input, max 20 like web.
            VStack(alignment: .leading, spacing: 8) {
                Text("Tag people")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ink)
                if !tagged.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                        ForEach(tagged, id: \.self) { name in
                            HStack(spacing: 4) {
                                Text("@\(name)")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Button {
                                    Haptics.tap()
                                    tagged.removeAll { $0 == name }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(ink.opacity(0.08)))
                            .foregroundStyle(ink)
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("@username", text: $tagInput)
                        .font(.footnote)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { addTag() }
                    Button {
                        Haptics.tap()
                        addTag()
                    } label: {
                        Text("Add")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tagInput.trimmingCharacters(in: .whitespaces).isEmpty ? muted : ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty || tagged.count >= 20)
                }
            }
            Divider().background(WhisperTheme.hairline(colorScheme))
            // Location — free text like web.
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(muted)
                TextField("Add location", text: $locationText)
                    .font(.footnote)
                if !locationText.isEmpty {
                    Button {
                        Haptics.tap()
                        locationText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().background(WhisperTheme.hairline(colorScheme))
            // Music — the iTunes search picker; the pick plays on the post.
            Button {
                Haptics.tap()
                if pickedMusic == nil {
                    showMusicPicker = true
                } else {
                    pickedMusic = nil
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pickedMusic == nil ? muted : ink)
                    if let m = pickedMusic {
                        Text("\(m.title) · \(m.artist)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(muted)
                    } else {
                        Text("Add music")
                            .font(.footnote)
                            .foregroundStyle(ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(muted)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(card, in: .rect(cornerRadius: 18))
    }

    /// Appends the typed @username to the tag list (deduped, max 20).
    private func addTag() {
        var name = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("@") { name.removeFirst() }
        guard !name.isEmpty, tagged.count < 20, !tagged.contains(name) else { return }
        tagged.append(name)
        tagInput = ""
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Accessibility")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ink)
                TextField("Describe your photos for screen readers…", text: $altText, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.footnote)
                    .foregroundStyle(ink)
            }
            Divider().background(WhisperTheme.hairline(colorScheme))
            Toggle(isOn: $hideCounts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide like and view counts")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ink)
                    Text("Only you see the totals on this post.")
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
            }
            .tint(ink)
            Toggle(isOn: $commentsOff) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn off commenting")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ink)
                    Text("Nobody can comment on this post.")
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
            }
            .tint(ink)
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    // MARK: - Share bar

    private var shareBar: some View {
        VStack(spacing: 0) {
            Divider().background(WhisperTheme.hairline(colorScheme))
            Button {
                Haptics.tap()
                Task { await publish() }
            } label: {
                HStack(spacing: 7) {
                    if posting {
                        ProgressView().tint(WhisperTheme.surface(colorScheme))
                    } else {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(shareLabel)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(photos.isEmpty || posting ? Color.gray.opacity(0.55) : ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(photos.isEmpty || posting)
            .padding(16)
        }
        .background(WhisperTheme.surface(colorScheme))
    }

    private var shareLabel: String {
        if posting { return "Sharing…" }
        if photos.isEmpty { return "Share" }
        return photos.count == 1 ? "Share 1 photo" : "Share \(photos.count) photos"
    }

    /// Full-screen progress veil while the grid post uploads.
    private var postingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Sharing your grid post\u{2026}")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        defer { if accountGeneration == AccountStorage.generation { importing = false } }
        var loaded: [GridDraftPhoto] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let photo = GridDraftPhoto(data: data) {
                loaded.append(photo)
            }
        }
        guard accountGeneration == AccountStorage.generation, !Task.isCancelled else { return }
        if loaded.count != items.count { publishError = "Some photos couldn't be opened. Your other selections are still here; try adding the missing photos again." }
        let newPhotos = loaded
        await MainActor.run {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                photos.append(contentsOf: newPhotos)
                if photos.count > maxPhotos { photos = Array(photos.prefix(maxPhotos)) }
                if selectedID == nil { selectedID = photos.first?.id }
            }
            photoPickerItems = []
        }
    }

    private func remove(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            photos.remove(at: index)
            if selectedID == id {
                selectedID = photos.indices.contains(index) ? photos[index].id : photos.last?.id
            }
        }
    }

    private func removeSelected() {
        if let selectedID { remove(selectedID) } else if let first = photos.first { remove(first.id) }
    }

    /// Promote a photo to the cover slot (front of the array).
    private func makeCover(_ id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }), index != 0 else { return }
        Haptics.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let photo = photos.remove(at: index)
            photos.insert(photo, at: 0)
            selectedID = photo.id
        }
    }

    private func publish() async {
        guard isActive, !photos.isEmpty, !posting, !importing, accountGeneration == AccountStorage.generation,
              caption.count <= captionLimit,
              WhisperAccountAccess.canPostGrid(username: displayUsername) else { return }
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.25)) { posting = true }
        }
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)

        // Bake each photo's filter into the actual upload bytes (web parity —
        // every platform sees the finished photo).
        let snapshot = photos
        let mediaDatas: [Data] = await Task.detached(priority: .userInitiated) {
            snapshot.map { p in
                guard p.filter != .normal else { return p.data }
                let baked = p.filter.bake(p.image)
                return baked.jpegData(compressionQuality: 0.92) ?? p.data
            }
        }.value

        guard accountGeneration == AccountStorage.generation, !Task.isCancelled else { return }
        // Encode the Share-step options onto the shared caption meta wire.
        var meta: [String: Any] = [:]
        let alt = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alt.isEmpty { meta["altText"] = alt }
        if commentsOff { meta["commentsOff"] = true }
        if hideCounts { meta["hideCounts"] = true }
        if !tagged.isEmpty { meta["tagged"] = tagged }
        let loc = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loc.isEmpty { meta["location"] = loc }
        if let m = pickedMusic {
            var music: [String: Any] = ["id": m.id, "title": m.title, "artist": m.artist]
            if let art = m.artworkURL { music["artworkURL"] = art }
            music["previewURL"] = m.previewURL
            meta["music"] = music
        }
        var finalCaption = trimmedCaption
        if !meta.isEmpty,
           let json = try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys]),
           let line = String(data: json, encoding: .utf8) {
            finalCaption = "\(WhisperPostMeta.prefix)\(line)\n\(trimmedCaption)"
        }

        let row = await backend.createPost(
            kind: "grid",
            caption: finalCaption,
            symbol: "square.grid.2x2",
            accentHex: nil,
            mediaCount: photos.count,
            isGhost: false,
            mediaDatas: mediaDatas
        )
        guard accountGeneration == AccountStorage.generation else { return }
        await MainActor.run {
            posting = false
            if row != nil { onPosted?(); dismiss() }
            else { publishError = backend.lastError ?? "Your grid post wasn't confirmed. Your edits are still here; please try again." }
        }
    }
}
