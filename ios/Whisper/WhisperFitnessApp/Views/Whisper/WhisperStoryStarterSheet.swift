import SwiftUI

/// Compact browsing shelves, with personal saves clearly separated from public discovery.
struct WhisperStoryStarterSheet: View {
    let onPick: (WhisperStoryStarter) -> Void
    var photo: UIImage? = nil
    var onLayout: ((WhisperStoryPhotoLayout) -> Void)? = nil
    var onPersonal: ((WhisperStorySavedTemplate) -> Void)? = nil
    var onCreate: (() -> Void)? = nil
    var onEffect: ((WhisperWaveCameraEffect) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var saved: Set<String> = []
    @State private var personal: [WhisperStorySavedTemplate] = []
    @State private var savedOnly: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    @State private var closed: Bool = false
    @State private var selected: WhisperStoryStarter?
    private let savedKey: String = "whisper.story.starters.saved.v1"
    private var starters: [WhisperStoryStarter] { WhisperStoryStarter.allCases.filter { !savedOnly || saved.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button { if selected != nil { selected = nil } else { dismiss() } } label: {
                    Image(systemName: selected == nil ? "xmark" : "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel(selected == nil ? "Close templates" : "Back to templates")
                Spacer(minLength: 0)
                if selected == nil {
                    tab("Browse", selected: !savedOnly) { savedOnly = false }
                    tab("Saved", selected: savedOnly) { savedOnly = true }
                } else { Text("Template preview").font(.subheadline.weight(.semibold)) }
                Spacer(minLength: 0)
                if let onCreate {
                    Button { perform(onCreate) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Create a template")
                } else { Color.clear.frame(width: 44, height: 44) }
            }.padding(.horizontal, 12).padding(.vertical, 12)
            if let selected { detail(selected) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !starters.isEmpty {
                            heading(savedOnly ? "Saved templates" : "Start with a look")
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) { ForEach(starters.filter { savedOnly || ($0 != .question && $0 != .poll) }) { starter in poster(starter) } }
                            }.contentMargins(.horizontal, 12)
                        }
                        if savedOnly {
                            if personal.isEmpty && saved.isEmpty {
                                ContentUnavailableView("Your collection starts here", systemImage: "bookmark", description: Text("Save a look or create your own template from the editor."))
                            }
                            if !personal.isEmpty {
                                heading("Made by you · on this device")
                                ForEach(personal) { item in
                                    HStack {
                                        Button { perform { onPersonal?(item) } } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.title).font(.headline)
                                                Text("\(item.stickers.count) reusable layers").font(.caption).foregroundStyle(.secondary)
                                            }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                        }
                                        Button(role: .destructive) {
                                            guard valid else { return }
                                            WhisperStoryTemplateStore.remove(item.id, generation: generation); personal = WhisperStoryTemplateStore.load()
                                        } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Delete \(item.title)")
                                    }.padding(.horizontal, 16)
                                }
                            }
                        } else {
                            if let onLayout {
                                heading("Photo layouts")
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        ForEach(WhisperStoryPhotoLayout.allCases) { layout in
                                            Button { perform { onLayout(layout) } } label: {
                                                VStack(alignment: .leading, spacing: 7) {
                                                    WhisperStoryLayoutPreview(layout: layout, photo: photo).frame(width: 112, height: 170).clipShape(.rect(cornerRadius: 10))
                                                    Text(layout.title).font(.caption.weight(.medium))
                                                }
                                            }
                                        }
                                    }
                                }.contentMargins(.horizontal, 12)
                            }
                            heading("Conversation starters")
                            ViewThatFits {
                                HStack(spacing: 8) { prompt(.question); prompt(.poll) }
                                VStack(spacing: 8) { prompt(.question); prompt(.poll) }
                            }.padding(.horizontal, 12)
                            if let onEffect {
                                heading("Camera effects")
                                ScrollView(.horizontal) {
                                    HStack(spacing: 10) {
                                        ForEach(WhisperWaveCameraEffect.available.filter { $0 != .none }, id: \.rawValue) { effect in
                                            Button { perform { onEffect(effect) } } label: {
                                                VStack(spacing: 7) {
                                                    Image(systemName: effect.symbol)
                                                        .font(.system(size: 26)).frame(width: 76, height: 76).background(.white.opacity(0.09), in: .rect(cornerRadius: 14))
                                                    Text(effect.name).font(.caption)
                                                }
                                            }
                                        }
                                    }
                                }.contentMargins(.horizontal, 12)
                            }
                        }
                    }.padding(.vertical, 12)
                }
            }
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .presentationBackground(Color(white: 0.10)).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(30)
        .environment(\.colorScheme, .dark)
        .onAppear { saved = Set(AccountStorage.object(forKey: savedKey) as? [String] ?? []); personal = WhisperStoryTemplateStore.load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in closed = true; personal = []; saved = []; dismiss() }
    }
    private var valid: Bool { !closed && generation == AccountStorage.generation }
    private func perform(_ action: () -> Void) { guard valid else { return }; Haptics.tap(); action(); dismiss() }
    private func heading(_ title: String) -> some View { Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 14) }
    private func poster(_ starter: WhisperStoryStarter) -> some View {
        Button { guard valid else { return }; selected = starter } label: {
            WhisperStoryStarterPreview(starter: starter, photo: photo).frame(width: 162, height: 288)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) {
                    Text(starter.title).font(.caption.weight(.medium)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.35))
                }.clipShape(.rect(cornerRadius: 10))
        }.accessibilityLabel("Preview \(starter.title)")
    }
    private func prompt(_ starter: WhisperStoryStarter) -> some View {
        Button { guard valid else { return }; selected = starter } label: {
            VStack(spacing: 12) {
                Text(starter == .question ? "What's one thing\nI should try?" : "A night in or\nan adventure?").font(.subheadline.weight(.medium)).multilineTextAlignment(.center).foregroundStyle(.black)
                Label(starter == .question ? "Question" : "Poll", systemImage: starter == .question ? "questionmark.bubble" : "chart.bar")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.35, green: 0.25, blue: 0.7))
            }.frame(maxWidth: .infinity).padding(.vertical, 20).background(.white, in: .rect(cornerRadius: 12))
        }
    }
    private func detail(_ starter: WhisperStoryStarter) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                WhisperStoryStarterPreview(starter: starter, photo: photo).aspectRatio(9.0 / 16.0, contentMode: .fit).frame(maxWidth: 280).clipShape(.rect(cornerRadius: 16))
                Text(starter.title).font(.title3.weight(.semibold))
                Text(starter.subtitle).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { perform { onPick(starter) } } label: { Text("Use template").font(.headline).frame(maxWidth: .infinity, minHeight: 48).background(.white, in: .capsule).foregroundStyle(.black) }
                    Button {
                        guard valid else { return }
                        if saved.contains(starter.id) { saved.remove(starter.id) } else { saved.insert(starter.id) }
                        AccountStorage.set(Array(saved).sorted(), forKey: savedKey); Haptics.tap()
                    } label: { Image(systemName: saved.contains(starter.id) ? "bookmark.fill" : "bookmark").frame(width: 48, height: 48) }
                    .accessibilityLabel(saved.contains(starter.id) ? "Unsave template" : "Save template")
                }
            }.padding(16)
        }
    }
    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.semibold)).frame(minHeight: 44).foregroundStyle(selected ? .white : .gray).overlay(alignment: .bottom) { Capsule().fill(selected ? Color.white : .clear).frame(height: 2) } }.accessibilityAddTraits(selected ? .isSelected : [])
    }
}
