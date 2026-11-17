import SwiftUI
import PhotosUI

/// Clip-local green screen editing; imported media is copied into the same private draft as the source clips.
struct WhisperWaveBackgroundControls: View {
    @Binding var background: WhisperWaveBackground?
    let pause: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var showPicker: Bool = false
    @State private var isImporting: Bool = false
    @State private var error: String?
    @State private var page: Page = .cutout
    @State private var importID: UUID = UUID()
    private enum Page: String, CaseIterable { case cutout = "Cutout", person = "Person", backdrop = "Backdrop" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if let background {
                Picker("Green screen controls", selection: $page) {
                    ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if page == .cutout { cutout(background) }
                        if page == .person { person }
                        if page == .backdrop { backdrop(background) }
                    }.padding(.vertical, 6)
                }
            } else { introduction }
        }
        .foregroundStyle(.white)
        .photosPicker(isPresented: $showPicker, selection: $item, matching: .any(of: [.images, .videos]))
        .task(id: item) { await importBackground() }
        .onDisappear { importID = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in importID = UUID(); showPicker = false }
        .alert("Background needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "Select the media again.") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Green Screen", systemImage: "person.and.background.dotted").font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            if isImporting { ProgressView().tint(.white) }
            Button(background == nil ? "Add background" : "Replace") { pause(); showPicker = true }
                .font(.caption.weight(.semibold)).frame(minHeight: 44).disabled(isImporting)
            if background != nil {
                Button { pause(); setBackground(nil); Haptics.selection() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                    .accessibilityLabel("Remove background and show original clip")
            }
        }
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle.badge.plus").font(.system(size: 30)).foregroundStyle(WhisperBrandGradient.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your world. Behind you.").font(.headline)
                    Text("Choose a photo or video. Auto person removes the room—no green wall needed.").font(.caption).foregroundStyle(.white.opacity(0.65))
                }
            }
            Text("Color key is also available for green or blue screens. Background videos loop silently; your microphone audio is kept. Settings are saved separately for each take.")
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
        }.frame(maxHeight: .infinity, alignment: .center)
    }
    private func cutout(_ background: WhisperWaveBackground) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Remove background using", selection: Binding(get: { background.removal }, set: { next in update { $0.removal = next } })) {
                ForEach(WhisperWaveBackground.Removal.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if background.removal == .chroma {
                HStack {
                    ColorPicker("Key color", selection: keyColor, supportsOpacity: false).font(.caption)
                    Button("Green") { update { $0.keyRed = 0; $0.keyGreen = 1; $0.keyBlue = 0 } }.frame(minHeight: 44)
                    Button("Blue") { update { $0.keyRed = 0; $0.keyGreen = 0; $0.keyBlue = 1 } }.frame(minHeight: 44)
                }.font(.caption)
                control("Strength", key: \.tolerance, range: 0...1)
                control("Spill reduction", key: \.spill, range: 0...1)
            }
            control("Feather", key: \.feather, range: 0...1)
            control("Edge cleanup", key: \.edge, range: -1...1)
            Text(background.removal == .person ? "Keeps all detected people. Hair, fast movement and low light may need edge adjustment. Review before posting." : "Choose a color from your backdrop. Similar-colored clothing can disappear; adjust strength and edges.")
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
    }
    private var person: some View {
        VStack(spacing: 8) {
            control("Person size", key: \.subjectScale, range: 0.25...1.5)
            control("Move left / right", key: \.subjectX, range: -0.7...0.7)
            control("Move up / down", key: \.subjectY, range: -0.7...0.7)
            Button("Center person") { update { $0.subjectScale = 1; $0.subjectX = 0; $0.subjectY = 0 } }.font(.caption).frame(minHeight: 44)
        }
    }
    private func backdrop(_ background: WhisperWaveBackground) -> some View {
        VStack(spacing: 8) {
            Text(background.media == .video ? "Video background · loops without sound" : "Photo background")
                .font(.caption).foregroundStyle(WhisperBrandGradient.mint)
            control("Background zoom", key: \.zoom, range: 1...3)
            control("Move left / right", key: \.x, range: -1...1)
            control("Move up / down", key: \.y, range: -1...1)
            if background.media == .video { control("Video offset (seconds)", key: \.startTime, range: 0...60) }

        }
    }
    private var keyColor: Binding<Color> {
        Binding(get: { Color(red: background?.keyRed ?? 0, green: background?.keyGreen ?? 1, blue: background?.keyBlue ?? 0) }, set: { color in
            var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let converted = UIColor(color).cgColor.converted(to: space, intent: .relativeColorimetric, options: nil),
                  UIColor(cgColor: converted).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            update { $0.keyRed = r; $0.keyGreen = g; $0.keyBlue = b }
        })
    }
    private func control(_ title: String, key: WritableKeyPath<WhisperWaveBackground, Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.caption).frame(width: 110, alignment: .leading)
            Slider(value: Binding(get: { background?[keyPath: key] ?? range.lowerBound }, set: { value in update { $0[keyPath: key] = value } }), in: range)
                .tint(WhisperBrandGradient.mint).accessibilityLabel(title)
        }.frame(minHeight: 44)
    }
    private func update(_ change: (inout WhisperWaveBackground) -> Void) {
        guard var next = background else { return }
        pause(); change(&next); setBackground(next)
    }
    private func setBackground(_ value: WhisperWaveBackground?) {
        background = value
    }
    private func importBackground() async {
        guard let item else { return }
        let token = UUID(); importID = token
        let owner = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        isImporting = true
        defer { if token == importID { isImporting = false; self.item = nil } }
        do {
            let imported = try await WhisperWaveBackgroundImporter.load(item)
            guard token == importID, !Task.isCancelled, owner == AccountStorage.currentUserID, generation == AccountStorage.generation else {
                try? FileManager.default.removeItem(at: imported.url); return
            }
            var next = background ?? imported
            next.url = imported.url; next.media = imported.media
            setBackground(next); Haptics.success()
        } catch is CancellationError { }
        catch {
            guard token == importID, !Task.isCancelled else { return }
            self.error = "Couldn't open that background. Your previous background and clips are unchanged. Select it again, or check available device storage."
        }
    }
}
