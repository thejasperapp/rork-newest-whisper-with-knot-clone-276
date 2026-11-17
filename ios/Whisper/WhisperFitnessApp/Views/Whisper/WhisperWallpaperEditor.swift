import SwiftUI

struct WhisperWallpaperEditor: View {
    let thread: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var prompt: String = ""
    @State private var preview: Data?
    @State private var busy: Bool = false
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    @State private var generation: UUID = AccountStorage.generation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A world behind your words.").font(.title.bold())
                    Text("Describe a scene, texture or mood. Only this prompt is sent to AI—not your conversation. Your wallpaper is personal and saved on this device.").font(.footnote).foregroundStyle(.secondary)
                    Color(.secondarySystemBackground).frame(height: 280)
                        .overlay {
                            if let preview, let image = UIImage(data: preview) {
                                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false)
                            } else {
                                Image(systemName: "sparkles.rectangle.stack").font(.largeTitle).foregroundStyle(.secondary)
                            }
                        }.clipShape(.rect(cornerRadius: 22))
                        .overlay(alignment: .bottom) {
                            Text("Your messages stay clear.").font(.callout).padding(14).background(.regularMaterial, in: .capsule).padding(16)
                        }
                    TextField("Pearl dunes, sea glass, a moonlit garden…", text: $prompt, axis: .vertical)
                        .lineLimit(2...4).padding(14).background(WhisperTheme.card(scheme), in: .rect(cornerRadius: 16))
                        .onChange(of: prompt) { _, value in if value.count > 400 { prompt = String(value.prefix(400)) } }
                        .disabled(busy)
                    if busy { ProgressView("Creating your wallpaper…") }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button("Generate wallpaper", systemImage: "sparkles") { generate() }.buttonStyle(.bordered).frame(minHeight: 44)
                        .disabled(busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Use this wallpaper") { save(preview) }.buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(busy || preview == nil)
                    Button("Remove personal wallpaper", role: .destructive) { save(nil) }.frame(minHeight: 44).disabled(busy)
                    Text("Group colors remain shared. Generated images are only for you; they aren't uploaded to a public media bucket.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("AI wallpaper").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { work?.cancel(); dismiss() } } }
        }.presentationDetents([.large])
        .onDisappear { work?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in work?.cancel(); dismiss() }
    }

    private func generate() {
        guard !busy, generation == AccountStorage.generation else { return }
        busy = true; error = nil
        let brief = prompt
        work = Task {
            defer { busy = false }
            do {
                let result = try await WhisperWallpaperStore.generate(brief: brief)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                preview = result
            } catch {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                self.error = "Couldn't generate a wallpaper. Your current background hasn't changed. Try again."
            }
        }
    }

    private func save(_ data: Data?) {
        guard !busy, generation == AccountStorage.generation else { return }
        let owner = AccountStorage.currentUserID
        busy = true; error = nil
        work = Task {
            defer { busy = false }
            do {
                try await WhisperWallpaperStore.shared.save(data, owner: owner, thread: thread)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                NotificationCenter.default.post(name: .init("WhisperWallpaperChanged"), object: nil)
                Haptics.success(); dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Couldn't save this wallpaper. Try again."
            }
        }
    }
}
