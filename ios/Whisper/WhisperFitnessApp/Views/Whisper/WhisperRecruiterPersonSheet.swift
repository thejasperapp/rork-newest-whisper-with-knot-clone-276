import SwiftUI

/// The person sheet — iOS twin of the web Recruiting OS person drawer.
/// The whole relationship in one panel: stage stepper, contact chips,
/// the next-step editor, the 4-criteria scorecard, #tags, the activity
/// timeline (auto-logged stage moves + notes/calls/DMs), and the sign
/// flow that finds their Whisper account and flips the role badge.
struct WhisperRecruiterPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var recruiter = WhisperRecruiterService.shared

    let prospectID: String

    // Next-step editor
    @State private var stepText: String = ""
    @State private var stepDue: Date = Date()
    @State private var stepHasDue: Bool = true
    @State private var savingStep: Bool = false
    @State private var seededStep: Bool = false

    // Tags
    @State private var newTag: String = ""

    // Timeline
    @State private var activities: [WhisperRecruiterService.ActivityRow] = []
    @State private var newActivityKind: String = "note"
    @State private var newActivityBody: String = ""
    @State private var loggingActivity: Bool = false

    // Sign flow
    @State private var showSignDialog: Bool = false
    @State private var signing: Bool = false
    @State private var signError: String?
    @State private var signedRole: String?

    @State private var presentNotesSheet: Bool = false
    @State private var confirmDelete: Bool = false
    @State private var showPrivateRelationship: Bool = false

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var cardBG: Color { WhisperTheme.card(colorScheme) }
    private var hairline: Color { WhisperTheme.hairline(colorScheme) }
    private var hqViolet: Color { Color(red: 0.439, green: 0.349, blue: 0.910) }
    private var good: Color { Color(red: 0.13, green: 0.65, blue: 0.36) }
    private var bad: Color { Color(red: 0.91, green: 0.30, blue: 0.24) }
    private var star: Color { Color(red: 0.96, green: 0.65, blue: 0.14) }

    /// Live row from the service — every edit reflects instantly.
    private var prospect: WhisperRecruiterService.ProspectRow? {
        recruiter.prospects.first { $0.id == prospectID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                if let p = prospect {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header(p)
                            stageStepper(p)
                            Button { showPrivateRelationship = true } label: {
                                Label("Private profile & meeting memory", systemImage: "lock.doc")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered)
                            nextStepCard(p)
                            scorecardCard(p)
                            tagsCard(p)
                            timelineCard(p)
                            actionsCard(p)
                        }
                        .padding(16)
                        .padding(.bottom, 40)
                    }
                } else {
                    // Row was deleted while open.
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.largeTitle)
                            .foregroundStyle(muted)
                        Text("This person left the pipeline")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(muted)
                    }
                }
            }
            .navigationTitle("Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                    .foregroundStyle(ink)
                }
            }
            .task {
                activities = await recruiter.fetchActivities(prospectID: prospectID)
                if !seededStep, let p = prospect {
                    stepText = p.next_action ?? ""
                    if let due = WhisperRecruiterService.parseDueDate(p.next_action_due) {
                        stepDue = due
                        stepHasDue = true
                    } else {
                        stepHasDue = p.next_action == nil
                    }
                    seededStep = true
                }
            }
            .sheet(isPresented: $showPrivateRelationship) {
                if let p = prospect { RecruiterClientProfileView(prospect: p).id(AccountStorage.generation) }
            }
            .sheet(isPresented: $presentNotesSheet) {
                if let p = prospect {
                    WhisperRecruiterProspectNotesSheet(prospect: p)
                        .whisperSheetBorder()
                }
            }
            .confirmationDialog(
                "Sign \(prospect?.prospect_display_name ?? "them") as…",
                isPresented: $showSignDialog,
                titleVisibility: .visible
            ) {
                Button("Coach") { sign(role: "coach") }
                Button("Athlete") { sign(role: "athlete") }
                Button("Creator (verified)") { sign(role: "creator") }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Remove from pipeline?", isPresented: $confirmDelete) {
                Button("Remove", role: .destructive) {
                    if let p = prospect {
                        Task {
                            await recruiter.deleteProspect(p)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the person and their timeline. Passed keeps them in the archive instead.")
            }
        }
    }

    // MARK: - Header

    private func header(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WhisperAvatar(
                    username: p.prospect_username ?? p.prospect_display_name ?? "?",
                    size: 56,
                    imageURL: p.prospect_image_url.flatMap(URL.init(string:)),
                    ring: false
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.prospect_display_name ?? p.prospect_username ?? "Prospect")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let username = p.prospect_username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(muted)
                        }
                        if let loc = p.location, !loc.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 9, weight: .bold))
                                Text(loc)
                                    .font(.caption)
                            }
                            .foregroundStyle(muted)
                        }
                    }
                    .lineLimit(1)
                    if let score = WhisperRecruiterService.compositeScore(p.scorecard) {
                        HStack(spacing: 4) {
                            Image(systemName: "gauge.with.needle.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Composite \(score)/100")
                                .font(.caption2.weight(.black))
                        }
                        .foregroundStyle(hqViolet)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if let ig = cleanInstagram(p.instagram),
                   let url = URL(string: "https://instagram.com/\(ig)") {
                    Link(destination: url) {
                        contactChip(icon: "camera.fill", label: "@\(ig)")
                    }
                }
                if let niche = p.niche, !niche.isEmpty {
                    contactChip(icon: "sparkles", label: niche)
                }
                if let source = p.source, !source.isEmpty {
                    contactChip(icon: "arrow.down.left.circle", label: source)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardBG)
                .overlay {
                    LinearGradient(
                        colors: [hqViolet.opacity(0.10), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(hqViolet.opacity(0.22), lineWidth: 1)
        }
    }

    private func contactChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(ink.opacity(0.8))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(WhisperTheme.surface(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(hairline, lineWidth: 1) }
    }

    private func cleanInstagram(_ raw: String?) -> String? {
        guard var handle = raw?.trimmingCharacters(in: .whitespaces), !handle.isEmpty else { return nil }
        handle = handle.replacingOccurrences(of: "https://instagram.com/", with: "")
        handle = handle.replacingOccurrences(of: "https://www.instagram.com/", with: "")
        if handle.hasPrefix("@") { handle.removeFirst() }
        handle = handle.components(separatedBy: "/").first ?? handle
        return handle.isEmpty ? nil : handle
    }

    // MARK: - Stage stepper

    private func stageStepper(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            kicker("Stage")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(WhisperRecruiterService.stageLabels, id: \.value) { stage in
                        let active = p.status == stage.value
                        let color = WhisperRecruiterService.statusColor(stage.value)
                        Button {
                            guard !active else { return }
                            Haptics.tap()
                            Task { await recruiter.updateProspectStatus(p, status: stage.value) }
                        } label: {
                            Text(stage.label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(active ? .white : ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(active ? color : color.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    let passed = p.status == "passed"
                    Button {
                        guard !passed else { return }
                        Haptics.warning()
                        Task { await recruiter.updateProspectStatus(p, status: "passed") }
                    } label: {
                        Text("Passed")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(passed ? .white : bad)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(passed ? bad : bad.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Next step

    private func nextStepCard(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            kicker("Next step")
            if !recruiter.v4Available {
                Text("Run supabase/recruiting-v4.sql to unlock next steps.")
                    .font(.caption)
                    .foregroundStyle(muted)
            } else {
                HStack(spacing: 6) {
                    ForEach(["Send a DM", "Call them", "Set a meeting", "Follow up"], id: \.self) { preset in
                        Button {
                            Haptics.tap()
                            stepText = preset
                        } label: {
                            Text(preset)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(stepText == preset ? .white : hqViolet)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    stepText == preset ? hqViolet : hqViolet.opacity(0.10),
                                    in: Capsule()
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField("What's the next touch?", text: $stepText)
                    .font(.subheadline)
                    .foregroundStyle(ink)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(hairline, lineWidth: 1)
                    }
                HStack(spacing: 10) {
                    Toggle(isOn: $stepHasDue) {
                        Text("Due")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ink)
                    }
                    .toggleStyle(.switch)
                    .tint(hqViolet)
                    .fixedSize()
                    if stepHasDue {
                        DatePicker("", selection: $stepDue, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Button {
                        Haptics.success()
                        savingStep = true
                        Task {
                            _ = await recruiter.updateNextAction(
                                p,
                                action: stepText.trimmingCharacters(in: .whitespaces),
                                due: stepHasDue ? stepDue : nil
                            )
                            savingStep = false
                        }
                    } label: {
                        Group {
                            if savingStep {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save step")
                                    .font(.caption.weight(.black))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(hqViolet, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(savingStep || stepText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(stepText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    if p.next_action != nil {
                        Button {
                            Haptics.tap()
                            stepText = ""
                            Task { _ = await recruiter.updateNextAction(p, action: nil, due: nil) }
                        } label: {
                            Text("Clear")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(muted)
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(WhisperTheme.surface(colorScheme), in: Capsule())
                                .overlay { Capsule().strokeBorder(hairline, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 1)
        }
    }

    // MARK: - Scorecard

    private func scorecardCard(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                kicker("Scorecard")
                Spacer()
                if let score = WhisperRecruiterService.compositeScore(p.scorecard) {
                    Text("\(score)/100")
                        .font(.caption.weight(.black).monospacedDigit())
                        .foregroundStyle(hqViolet)
                }
            }
            if !recruiter.v4Available {
                Text("Run supabase/recruiting-v4.sql to unlock scorecards.")
                    .font(.caption)
                    .foregroundStyle(muted)
            } else {
                ForEach(WhisperRecruiterService.scorecardCriteria, id: \.id) { criterion in
                    HStack {
                        Text(criterion.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink)
                            .frame(width: 92, alignment: .leading)
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { value in
                                let current = p.scorecard?[criterion.id] ?? 0
                                Button {
                                    Haptics.tap()
                                    var card = p.scorecard ?? [:]
                                    card[criterion.id] = (current == value) ? 0 : value
                                    Task { await recruiter.updateScorecard(p, scorecard: card) }
                                } label: {
                                    Image(systemName: value <= current ? "star.fill" : "star")
                                        .font(.system(size: 15))
                                        .foregroundStyle(value <= current ? star : muted.opacity(0.35))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 1)
        }
    }

    // MARK: - Tags

    private func tagsCard(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            kicker("Tags")
            if !recruiter.v4Available {
                Text("Run supabase/recruiting-v4.sql to unlock tags.")
                    .font(.caption)
                    .foregroundStyle(muted)
            } else {
                let tags = p.tags ?? []
                if !tags.isEmpty {
                    FlowLayoutChips(tags: tags) { tag in
                        Haptics.tap()
                        Task {
                            await recruiter.updateTags(p, tags: tags.filter { $0 != tag })
                        }
                    }
                }
                HStack(spacing: 8) {
                    TextField("Add a tag — powerlifting, campus…", text: $newTag)
                        .font(.caption)
                        .foregroundStyle(ink)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { addTag(p) }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(hairline, lineWidth: 1) }
                    Button {
                        addTag(p)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(hqViolet, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(newTag.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
            }
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 1)
        }
    }

    private func addTag(_ p: WhisperRecruiterService.ProspectRow) {
        let tag = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !tag.isEmpty else { return }
        Haptics.tap()
        newTag = ""
        Task {
            await recruiter.updateTags(p, tags: (p.tags ?? []) + [tag])
        }
    }

    // MARK: - Timeline

    private func timelineCard(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                kicker("Timeline")
                Spacer()
                Button {
                    Haptics.tap()
                    presentNotesSheet = true
                } label: {
                    Text("Notes")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(activityKinds, id: \.0) { kind, label, _ in
                        Button(label) { newActivityKind = kind }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: kindIcon(newActivityKind))
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(hqViolet)
                    .frame(width: 48, height: 36)
                    .background(hqViolet.opacity(0.10), in: Capsule())
                }
                TextField("Log a touch — what happened?", text: $newActivityBody)
                    .font(.caption)
                    .foregroundStyle(ink)
                    .onSubmit { logTouch(p) }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(WhisperTheme.surface(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(hairline, lineWidth: 1) }
                Button {
                    logTouch(p)
                } label: {
                    Group {
                        if loggingActivity {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.caption.weight(.black))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(hqViolet, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(loggingActivity || newActivityBody.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(newActivityBody.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            if activities.isEmpty {
                Text(recruiter.v4Available
                    ? "No touches logged yet — stage moves land here automatically."
                    : "Run supabase/recruiting-v4.sql to unlock the timeline.")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(activities.enumerated()), id: \.element.id) { idx, activity in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                Image(systemName: kindIcon(activity.kind))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(activity.kind == "stage" ? hqViolet : muted)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        (activity.kind == "stage" ? hqViolet : muted).opacity(0.10),
                                        in: Circle()
                                    )
                                if idx < activities.count - 1 {
                                    Rectangle()
                                        .fill(hairline)
                                        .frame(width: 1)
                                        .frame(minHeight: 14)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.body)
                                    .font(.caption)
                                    .foregroundStyle(ink.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let created = activity.created_at {
                                    Text(WhisperMeetingsService.formatWhen(created))
                                        .font(.caption2)
                                        .foregroundStyle(muted)
                                }
                            }
                            .padding(.bottom, 12)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(cardBG, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 1)
        }
    }

    private var activityKinds: [(String, String, String)] {
        [
            ("note", "Note", "note.text"),
            ("call", "Call", "phone.fill"),
            ("dm", "DM", "paperplane.fill"),
            ("email", "Email", "envelope.fill"),
            ("meeting", "Meeting", "video.fill"),
        ]
    }

    private func kindIcon(_ kind: String) -> String {
        switch kind {
        case "call": return "phone.fill"
        case "dm": return "paperplane.fill"
        case "email": return "envelope.fill"
        case "meeting": return "video.fill"
        case "stage": return "arrow.right.circle.fill"
        case "task": return "checkmark.circle.fill"
        default: return "note.text"
        }
    }

    private func logTouch(_ p: WhisperRecruiterService.ProspectRow) {
        let body = newActivityBody.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, !loggingActivity else { return }
        Haptics.tap()
        loggingActivity = true
        Task {
            let ok = await recruiter.logActivity(prospectID: p.id, kind: newActivityKind, body: body)
            if ok {
                newActivityBody = ""
                activities = await recruiter.fetchActivities(prospectID: p.id)
            }
            loggingActivity = false
        }
    }

    // MARK: - Actions (sign / pass / delete)

    private func actionsCard(_ p: WhisperRecruiterService.ProspectRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let signedRole {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(good)
                    Text("Signed as \(signedRole.capitalized) 🎉")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(good)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(good.opacity(0.10), in: .rect(cornerRadius: 14))
            } else {
                Button {
                    Haptics.success()
                    showSignDialog = true
                } label: {
                    Group {
                        if signing {
                            ProgressView().tint(.white)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "signature")
                                    .font(.subheadline.weight(.bold))
                                Text("Sign them")
                                    .font(.subheadline.weight(.black))
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(good, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(signing)
                if let signError {
                    Text(signError)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(bad)
                }
                if (p.prospect_username ?? "").isEmpty && p.prospect_user_id == nil {
                    Text("Signing flips their Whisper badge — add their @username to the profile first (Notes button up top edits details).")
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
            }
            HStack(spacing: 8) {
                if p.status == "passed" {
                    Button {
                        Haptics.tap()
                        Task { await recruiter.updateProspectStatus(p, status: "discovered") }
                    } label: {
                        Text("Bring back")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(hqViolet)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(hqViolet.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Haptics.warning()
                        Task { await recruiter.updateProspectStatus(p, status: "passed") }
                    } label: {
                        Text("Pass")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(WhisperTheme.surface(colorScheme), in: Capsule())
                            .overlay { Capsule().strokeBorder(hairline, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Haptics.warning()
                    confirmDelete = true
                } label: {
                    Text("Remove")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(bad)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(bad.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The sign flow — find their Whisper account (linked id first, then
    /// exact @username match) and flip the role badge via the same promote
    /// rail as the web drawer.
    private func sign(role: String) {
        guard let p = prospect, !signing else { return }
        signing = true
        signError = nil
        Task {
            var userID: String? = p.prospect_user_id
            var username: String = p.prospect_username ?? ""
            if userID == nil {
                let uname = (p.prospect_username ?? "").trimmingCharacters(in: .whitespaces)
                guard !uname.isEmpty else {
                    signing = false
                    signError = "No Whisper @username on file — add it in Notes first."
                    return
                }
                let results = await WhisperUserService.shared.search(uname, limit: 8)
                if let exact = results.first(where: { $0.username.caseInsensitiveCompare(uname) == .orderedSame }) {
                    userID = exact.user_id
                    username = exact.username
                }
            }
            guard let userID else {
                signing = false
                signError = "No Whisper account found for @\(username). They need to sign up first — share your invite code."
                return
            }
            let ok = await recruiter.promote(
                userID: userID,
                username: username.isEmpty ? "member" : username,
                role: role,
                notes: "Signed from Recruiter HQ (iOS)"
            )
            if ok {
                await recruiter.logActivity(
                    prospectID: p.id,
                    kind: "stage",
                    body: "Signed as \(role.capitalized) ✍️"
                )
                Haptics.success()
                signedRole = role
                activities = await recruiter.fetchActivities(prospectID: p.id)
            } else {
                signError = recruiter.lastError ?? "Couldn't sign them — try again."
            }
            signing = false
        }
    }

    private func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.black))
            .tracking(1.4)
            .foregroundStyle(muted)
    }
}

/// Simple wrapping tag chips — removable on tap.
private struct FlowLayoutChips: View {
    @Environment(\.colorScheme) private var colorScheme
    let tags: [String]
    let onRemove: (String) -> Void

    private var hqViolet: Color { Color(red: 0.439, green: 0.349, blue: 0.910) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onRemove(tag)
                } label: {
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .black))
                            .opacity(0.6)
                    }
                    .foregroundStyle(hqViolet)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(hqViolet.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
