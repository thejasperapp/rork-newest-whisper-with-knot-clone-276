import SwiftUI

/// Reference-composed catalogue; selecting a supported tool uses the existing dismissal handoff.
struct WhisperStoryAttachmentTray: View {
    var photo: UIImage? = nil
    let onTool: (String) -> Void
    let onSticker: (WhisperStorySticker) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query: String = ""
    @State private var unavailableTool: WhisperStoryTrayTool?
    @State private var showsWeatherNotice: Bool = false
    @FocusState private var searching: Bool
    @ScaledMetric(relativeTo: .body) private var searchFont: CGFloat = 16

    private let words: [String] = ["GOOD\nENERGY", "on my\nway", "little\nwins", "TODAY", "OFFLINE", "YES!", "MEMORIES", "a good\nday", "weekend", "LIVE\nA LITTLE", "thank\nyou", "KEEP\nGOING"]
    private let characters: [String] = ["ember", "ember_headphones", "ghost_crown", "ghost_king", "ghost_bolt", "ghost_boost", "ghost_send", "ghost_trophy", "ghost_beach", "jasper_beachball", "ghost_couple", "ghost_home", "ghost_sleepy", "ghost_sad", "ghost_cookie", "ghost_book", "ghost_dragon", "ghost_kraken"]
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func matches(_ value: String) -> Bool {
        cleanQuery.isEmpty || value.replacingOccurrences(of: "\n", with: " ").localizedStandardContains(cleanQuery)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(440, geometry.size.width)
            let scale = width / 390
            let isReferenceLayout = width >= 350 && typeSize <= .large && cleanQuery.isEmpty
            VStack(spacing: 0) {
                Capsule().fill(.white.opacity(0.75))
                    .frame(width: 31 * scale, height: 3.5)
                    .frame(height: 16 * scale)
                    .accessibilityHidden(true)
                searchBar(scale: scale)
                    .padding(.horizontal, 9 * scale)
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(spacing: 0) {
                        toolRows(scale: scale, referenceLayout: isReferenceLayout)
                            .padding(.horizontal, 16 * scale)
                            .padding(.top, 12 * scale)
                        artworkGallery(scale: scale)
                            .padding(.top, 18 * scale)
                        retainedTools(scale: scale)
                            .padding(.horizontal, 16)
                            .padding(.top, 28)
                        retainedArtwork(scale: scale)
                            .padding(.top, 24)
                        Button("Close attachments") { dismiss() }
                            .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                            .frame(minHeight: 44).padding(.top, 16)
                        }.padding(.bottom, 20).id("story.tray.catalogue")
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: cleanQuery) { _, _ in
                        scroll.scrollTo("story.tray.catalogue", anchor: .top)
                    }
                }
            }
            .frame(width: width, height: geometry.size.height, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .accessibilityAction(.escape) { dismiss() }
        .alert(unavailableTool?.rawValue ?? "Not available", isPresented: Binding(get: { unavailableTool != nil }, set: { if !$0 { unavailableTool = nil } })) {
            Button("OK", role: .cancel) { unavailableTool = nil }
        } message: {
            Text(unavailableTool?.unavailableMessage ?? "This feature isn't available yet.")
        }
        .alert("Weather stickers aren't connected", isPresented: $showsWeatherNotice) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Whisper doesn't currently fetch local weather for Stories. No temperature has been added.")
        }
    }

    private func searchBar(scale: CGFloat) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 7 * scale) {
                Image(systemName: "magnifyingglass").font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(.white)
                TextField("", text: $query, prompt: Text("Search").foregroundStyle(.white.opacity(0.77)))
                    .font(.system(size: max(16 * scale, searchFont)))
                    .foregroundStyle(.white).tint(.white)
                    .focused($searching).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { searching = false }
                    .accessibilityLabel("Search attachments")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, 10 * scale).padding(.trailing, query.isEmpty ? 10 * scale : 0)
            .frame(minHeight: 44)
            .background {
                Capsule().fill(Color(white: 0.33).opacity(0.96))
                    .frame(height: max(32 * scale, searchFont + 14))
            }
            if searching {
                Button("Cancel") { searching = false; query = "" }
                    .font(.subheadline).foregroundStyle(.white).frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder private func toolRows(scale: CGFloat, referenceLayout: Bool) -> some View {
        if referenceLayout {
            VStack(spacing: 0) {
                ForEach(WhisperStoryTrayTool.referenceRows, id: \.self) { row in
                    HStack(spacing: (row.contains(.poll) ? 9 : 10) * scale) {
                        ForEach(row) { tool in
                            toolButton(tool, scale: scale, referenceWidth: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, row.contains(.questions) || row.contains(.poll) ? 4 * scale : 0)
                }
            }
        } else {
            WhisperStoryAttachmentFlow(spacing: 10) {
                ForEach(WhisperStoryTrayTool.referenceRows.flatMap { $0 }.filter { matches($0.rawValue) }) { tool in
                    toolButton(tool, scale: 1, referenceWidth: false)
                }
            }
        }
    }

    private func toolButton(_ tool: WhisperStoryTrayTool, scale: CGFloat, referenceWidth: Bool) -> some View {
        WhisperStoryTrayToolButton(tool: tool, photo: photo, scale: scale, usesReferenceWidth: referenceWidth) {
            Haptics.tap()
            if tool.unavailableMessage != nil { unavailableTool = tool }
            else { searching = false; onTool(tool.rawValue) }
        }
    }

    private func artworkGallery(scale: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16 * scale), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 18 * scale) {
            if matches("weather temperature") {
                Button { showsWeatherNotice = true } label: {
                    Text("—°F").font(.system(size: 34 * scale, weight: .light, design: .rounded))
                        .tracking(-2 * scale).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 76 * scale)
                }.accessibilityLabel("Temperature sticker, not available yet")
            }
            if matches("time clock") {
                WhisperStoryTrayClock(onSelect: { addTime() }).frame(height: 76 * scale)
            }
            artButton(.vote, scale: scale)
            if matches("heart reaction love") {
                Button { onTool("Reaction") } label: {
                    Image(systemName: "heart.fill").font(.system(size: 25 * scale)).foregroundStyle(.white)
                        .frame(width: 72 * scale, height: 46 * scale)
                        .background(Color(red: 0.97, green: 0.15, blue: 0.20), in: .capsule)
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.97, green: 0.15, blue: 0.20))
                                .frame(width: 12 * scale, height: 12 * scale).rotationEffect(.degrees(45)).offset(y: 5 * scale)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76 * scale).contentShape(.rect)
                }.accessibilityLabel("Choose a reaction").accessibilityHint("Opens the reaction sticker editor")
            }
            ForEach(WhisperStoryTrayArtwork.illustratedRow) { artwork in artButton(artwork, scale: scale) }
            if matches("date today day") { dayStamp(scale: scale) }
            ForEach(WhisperStoryTrayArtwork.remainingRows) { artwork in artButton(artwork, scale: scale) }
        }.padding(.horizontal, 20 * scale)
    }

    @ViewBuilder private func artButton(_ artwork: WhisperStoryTrayArtwork, scale: CGFloat) -> some View {
        if matches(artwork.title) {
            Button {
                onSticker(WhisperStorySticker(kind: .sticker, imageURL: artwork.url))
            } label: {
                Color.clear.frame(height: 76 * scale)
                    .overlay { Image(artwork.assetName).resizable().scaledToFit().allowsHitTesting(false) }
                    .contentShape(.rect)
            }.accessibilityLabel("Add \(artwork.title) sticker")
        }
    }

    private func retainedTools(scale: CGFloat) -> some View {
        VStack(spacing: 10) {
            if cleanQuery.isEmpty {
                Text("More tools").font(.subheadline).foregroundStyle(.white.opacity(0.6))
            }
            WhisperStoryAttachmentFlow(spacing: 10) {
                ForEach(WhisperStoryTrayTool.extraTools.filter { matches($0.rawValue) }) { tool in
                    toolButton(tool, scale: scale, referenceWidth: false)
                }
            }
            if matches("pin my template") {
                Button { onTool("My template") } label: {
                    Label("Pin your own template", systemImage: "pin").frame(minHeight: 44)
                }.font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            if !cleanQuery.isEmpty {
                Button { onTool("GIF") } label: {
                    Label("Search animated GIFs", systemImage: "magnifyingglass").frame(minHeight: 44)
                }.font(.subheadline).foregroundStyle(.white)
            }
        }
    }

    private func retainedArtwork(scale: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16 * scale), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 18 * scale) {
            ForEach(Array(words.enumerated()).filter { matches($0.element) }, id: \.element) { index, text in
                Button { onSticker(wordSticker(text, index: index)) } label: {
                    Text(text).font(WhisperStoryTypography.font(index % 3 == 0 ? "rounded" : "editorial", size: 23 * scale))
                        .multilineTextAlignment(.center).foregroundStyle(tint(index))
                        .lineLimit(text.contains("\n") ? 2 : 1).minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, minHeight: 76 * scale).contentShape(.rect)
                }.accessibilityLabel("Add \(text.replacingOccurrences(of: "\n", with: " ")) sticker")
            }
            ForEach(characters.filter { matches($0.replacingOccurrences(of: "_", with: " ")) || matches("Jasper") }, id: \.self) { name in
                Button { onSticker(WhisperStorySticker(kind: .sticker, imageURL: "jasper-sticker://\(name)")) } label: {
                    Color.clear.frame(height: 76 * scale)
                        .overlay { Image("WhisperSticker_\(name)").resizable().scaledToFit().allowsHitTesting(false) }
                        .contentShape(.rect)
                }.accessibilityLabel("Add \(name.replacingOccurrences(of: "_", with: " ")) sticker")
            }
        }.padding(.horizontal, 20 * scale)
    }

    private func dayStamp(scale: CGFloat) -> some View {
        Button {
            var layer = WhisperStorySticker(kind: .text, text: Date.now.formatted(.dateTime.weekday(.wide)).uppercased(), color: "#F08A36", style: 0)
            layer.fontName = "typewriter"; layer.fontSize = 28; onSticker(layer)
        } label: {
            Text(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: 18 * scale, weight: .medium, design: .monospaced).width(.condensed))
                .foregroundStyle(Color.orange).shadow(color: .purple, radius: 0, x: -1, y: 1)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 76 * scale).contentShape(.rect)
        }.accessibilityLabel("Add today's day")
    }

    private func addTime() {
        var layer = WhisperStorySticker(kind: .text, text: Date.now.formatted(date: .omitted, time: .shortened), color: "#FFFFFF", style: 0)
        layer.fontName = "typewriter"; layer.fontSize = 36; onSticker(layer)
    }

    private func tint(_ index: Int) -> Color { [Color.yellow, .mint, .pink, .white, .orange, .cyan][index % 6] }
    private func wordSticker(_ text: String, index: Int) -> WhisperStorySticker {
        var layer = WhisperStorySticker(kind: .text, rotation: index % 2 == 0 ? -0.12 : 0.09, text: text, color: tint(index).toHex(), style: 0)
        layer.fontName = index % 3 == 0 ? "rounded" : "editorial"; layer.fontSize = 36
        return layer
    }
}
