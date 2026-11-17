import SwiftUI
import PhotosUI

/// Draft-first profile editing with the reference's single inset identity card.
struct WhisperEditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var auth = AuthenticationService.shared
    @State private var leaderboard = LeaderboardService.shared
    @State private var users = WhisperUserService.shared
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var website: String = ""
    @State private var pronouns: String = ""
    @State private var specialAccount: String = ""
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var cropCandidate: CropCandidate?
    @State private var localPhotoData: Data?
    @State private var isSaving: Bool = false
    @State private var importing: Bool = false
    @State private var coverWorking: Bool = false
    @State private var errorMessage: String?
    @State private var presentSpecial: Bool = false
    @State private var presentLinks: Bool = false
    @State private var generatingBio: Bool = false
    @State private var loaded: Bool = false
    @State private var closed: Bool = false
    @State private var generation: UUID = AccountStorage.generation
    @State private var initialValues: [String] = []
    @State private var confirmDiscard: Bool = false
    @State private var privacyWorking: Bool = false
    @State private var confirmPrivacy: Bool = false
    private var valid: Bool { !closed && generation == AccountStorage.generation && !Task.isCancelled }
    private var values: [String] { [displayName, username, bio, website, pronouns, specialAccount] }
    private var isDirty: Bool { loaded && (values != initialValues || localPhotoData != nil) }
    private var verified: Bool { WhisperVerifiedPerks.isVerified(username: auth.currentUser.username ?? "") }
    private struct CropCandidate: Identifiable { let id: UUID = UUID(); let image: UIImage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    WhisperProfileBannerEditor(uploading: $coverWorking)
                        .disabled(!valid || !WhisperBackendService.shared.isSignedInRemotely)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 18) {
                            field("Name", text: $displayName, placeholder: "Your name")
                            portrait.fixedSize()
                        }.padding(.vertical, 4)
                        line
                        field("Username", text: $username, placeholder: "username", autocap: false)
                        line
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Bio").font(.body.weight(.semibold))
                                Spacer()
                                Button { Task { await generateBio() } } label: {
                                    Image(systemName: "sparkles").font(.subheadline).frame(width: 44, height: 44)
                                }.accessibilityLabel(generatingBio ? "Writing bio" : "Write bio with Knot").disabled(generatingBio)
                            }
                            TextField("Tell people about yourself", text: Binding(get: { bio }, set: { bio = String($0.prefix(max(500, bio.count))) }), axis: .vertical)
                                .lineLimit(1...8).font(.body)
                        }.padding(.vertical, 16)
                        line
                        NavigationLink(value: "interests") {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Interests").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text((users.me?.interests ?? []).isEmpty ? "Add your communities" : (users.me?.interests ?? []).joined(separator: ", "))
                                    .font(.body).foregroundStyle(.blue).multilineTextAlignment(.leading)
                            }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).padding(.vertical, 12)
                        }.buttonStyle(.plain)
                        line
                        if verified {
                            Button { presentLinks = true } label: {
                                navigationRow("Links", value: String(WhisperVerifiedPerksService.shared.links(forUserID: AccountStorage.currentUserID).count))
                            }.buttonStyle(.plain)
                            line
                        }
                        field("Website", text: $website, placeholder: "Add a website", autocap: false)
                        line
                        field("Pronouns", text: $pronouns, placeholder: "Add your pronouns")
                        line
                        Button { confirmPrivacy = true } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                navigationRow("Profile privacy", value: users.me?.is_private == true ? "Private" : users.me?.is_private == false ? "Public" : "Loading…", padded: false)
                                Text("A private profile limits your posts to approved followers. Privacy changes take effect immediately.")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }.padding(.vertical, 18)
                        }.buttonStyle(.plain).disabled(users.me == nil || privacyWorking)
                    }.padding(.horizontal, 16)
                        .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 18))
                        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                    if let errorMessage { Text(errorMessage).font(.subheadline).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                    Button { presentSpecial = true } label: {
                        navigationRow("Whisper Special account", value: specialAccount.isEmpty ? "Set up" : specialAccount)
                    }.buttonStyle(.plain)
                    Text("Cover photo, community membership, featured links and privacy save separately. Your other edits save with Done.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 32).disabled(isSaving)
            }.scrollDismissesKeyboard(.interactively)
                .background(WhisperTheme.card(colorScheme))
                .navigationTitle("Edit profile").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: leave).disabled(isSaving || privacyWorking || coverWorking) }
                    ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Saving…" : "Done") { save() }.fontWeight(.semibold).disabled(isSaving || importing || privacyWorking || coverWorking || generatingBio || !loaded) }
                }
                .tint(WhisperTheme.ink(colorScheme))
                .navigationDestination(for: String.self) { _ in WhisperCommunitiesView() }
                .task { await load() }
                .task(id: pickedPhotoItem) { await preparePhoto() }
                .fullScreenCover(item: $cropCandidate) { candidate in
                    WhisperAvatarCropperSheet(image: candidate.image) { data in guard valid else { return }; localPhotoData = data }
                }
                .sheet(isPresented: $presentSpecial) { WhisperSpecialAccountSheet(selection: $specialAccount).presentationDetents([.medium, .large]) }
                .sheet(isPresented: $presentLinks) { WhisperFeaturedLinksEditorSheet() }
                .confirmationDialog("Discard profile edits?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard edits", role: .destructive) { closed = true; dismiss() }
                    Button("Keep editing", role: .cancel) { }
                }
                .confirmationDialog("Make your profile \(users.me?.is_private == true ? "public" : "private")?", isPresented: $confirmPrivacy, titleVisibility: .visible) {
                    Button("Make \(users.me?.is_private == true ? "public" : "private")") {
                        privacyWorking = true
                        let target = users.me?.is_private != true
                        Task { let ok = await users.setIsPrivate(target); guard valid else { return }; privacyWorking = false; if !ok { errorMessage = "Couldn't update privacy. Please try again." } }
                    }
                    Button("Cancel", role: .cancel) { }
                }
        }.presentationDetents([.large]).presentationDragIndicator(.hidden).presentationCornerRadius(36)
            .interactiveDismissDisabled(isDirty || isSaving || importing || privacyWorking || coverWorking)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                closed = true; bio = ""; localPhotoData = nil; cropCandidate = nil; presentLinks = false; presentSpecial = false; dismiss()
            }
    }
    private var line: some View { Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5) }
    private func field(_ name: String, text: Binding<String>, placeholder: String, autocap: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.body.weight(.semibold))
            TextField(placeholder, text: text).font(.body).textInputAutocapitalization(autocap ? .sentences : .never).autocorrectionDisabled(!autocap)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
    }
    private func navigationRow(_ name: String, value: String, padded: Bool = true) -> some View {
        HStack {
            Text(name).font(.body.weight(.semibold))
            Spacer(minLength: 12)
            Text(value).font(.subheadline).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
        }.foregroundStyle(.primary).frame(minHeight: padded ? 60 : 24)
    }
    private var portrait: some View {
        PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
            Group {
                if let data = localPhotoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(.circle)
                } else { WhisperAvatar(username: auth.currentUser.username ?? "you", size: 52, imageURL: auth.currentUser.profileImageURL.flatMap(URL.init(string:)), ring: false) }
            }.overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil").font(.system(size: 10, weight: .bold)).foregroundStyle(.black).frame(width: 20, height: 20).background(.white, in: .circle)
            }
        }.disabled(importing || isSaving).accessibilityLabel("Edit profile picture")
    }
    private func leave() { guard !isSaving, !coverWorking else { return }; if isDirty { confirmDiscard = true } else { closed = true; dismiss() } }
    private func load() async {
        guard !loaded, valid else { return }
        displayName = auth.currentUser.displayName ?? auth.currentUser.formattedName
        username = leaderboard.savedUsername ?? auth.currentUser.username ?? ""
        bio = users.me?.bio ?? AccountStorage.string(forKey: "whisper.bio") ?? ""
        website = AccountStorage.string(forKey: "whisper.website") ?? ""
        pronouns = AccountStorage.string(forKey: "whisper.pronouns") ?? ""
        specialAccount = AccountStorage.string(forKey: "whisper.specialAccount") ?? ""
        initialValues = values; loaded = true
        let initialBio = bio
        await users.refreshMe()
        guard valid, !isSaving, bio == initialBio else { return }
        if let serverBio = users.me?.bio { bio = serverBio; initialValues[2] = serverBio }
    }
    private func preparePhoto() async {
        guard let item = pickedPhotoItem, valid else { return }
        importing = true
        defer { importing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), valid,
                  let image = WhisperImageCache.decode(data, maxPixelSize: 1600) else { return }
            cropCandidate = CropCandidate(image: image)
        } catch { if valid { errorMessage = "Couldn't read that photo. Try another one." } }
    }
    private func generateBio() async {
        guard !generatingBio, valid else { return }
        generatingBio = true
        let before = bio
        let result = await WhisperEmberService.shared.generateBio(seed: "name: \(displayName), current bio: \(bio)")
        guard valid else { return }
        generatingBio = false
        if bio == before, !result.isEmpty { bio = String(result.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)) }
    }
    private func save() {
        guard valid, !isSaving, !generatingBio, !importing, !privacyWorking, !coverWorking else { return }
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanUsername.range(of: "^[a-z0-9_.]{3,20}$", options: .regularExpression) != nil else { errorMessage = "Use 3–20 letters, numbers, periods or underscores for your username."; return }
        isSaving = true; errorMessage = nil
        Task {
            defer { isSaving = false }
            if cleanUsername != initialValues[1].lowercased() {
                let reserved = await leaderboard.reserveUsername(cleanUsername)
                guard valid else { return }
                guard reserved else { errorMessage = "Couldn't finish saving that username. It may already be reserved to you; retry to finish, or choose another."; return }
                _ = leaderboard.setUsername(cleanUsername)
                await users.refreshMe()
                guard valid else { return }
            }
            var avatarURL: String?
            if let data = localPhotoData {
                do { avatarURL = try await auth.uploadProfileImage(data) }
                catch { if valid { errorMessage = "Couldn't save your picture. Your edits are still here." }; return }
                guard valid else { return }
                localPhotoData = nil
            }
            let ok = await users.updateProfile(bio: bio, displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines), avatarURL: avatarURL)
            guard valid else { return }
            guard ok else { errorMessage = "Couldn't finish saving your profile. Please try again; any saved picture or username is kept."; return }
            auth.currentUser.displayName = displayName; auth.saveCurrentUser()
            AccountStorage.set(bio, forKey: "whisper.bio"); AccountStorage.set(website, forKey: "whisper.website")
            AccountStorage.set(pronouns, forKey: "whisper.pronouns"); AccountStorage.set(specialAccount, forKey: "whisper.specialAccount")
            Haptics.success(); closed = true; dismiss()
        }
    }
}
