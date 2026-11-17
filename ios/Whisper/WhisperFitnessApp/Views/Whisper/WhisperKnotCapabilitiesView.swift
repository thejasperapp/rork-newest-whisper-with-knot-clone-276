import SwiftUI

enum WhisperKnotCapabilitySelection {
    case prompt(String)
    case photo, file, voice, tuning
}

/// Skill shortcuts create drafts; tool descriptions never confer permissions.
struct WhisperKnotCapabilitiesView: View {
    var embedded = false
    var bot: WhisperKnotBot = .main
    let onSelect: (WhisperKnotCapabilitySelection) -> Void
    @Environment(\.dismiss) private var dismiss

    private struct Skill: Identifiable {
        let title: String
        let icon: String
        let detail: String
        let prompt: String
        var id: String { title }
    }
    private var writing: [Skill] { [
        .init(title: "Draft something", icon: "square.and.pencil", detail: "Posts, captions, bios, articles and announcements", prompt: "Help me write something. Ask what it is and who it is for, then give me a usable draft."),
        .init(title: "Edit in my voice", icon: "text.cursor", detail: "Clarity, rhythm and tone without losing your meaning", prompt: "Edit my writing without changing my meaning or inventing facts. Ask me to paste the text."),
        .init(title: "Find the right reply", icon: "bubble.left.and.bubble.right", detail: "Thoughtful replies, introductions and outreach", prompt: "Help me write a thoughtful reply. Ask me to paste the message and tell you what I want to say.")
    ] }
    private var research: [Skill] { [
        .init(title: "Investigate a question", icon: "magnifyingglass", detail: "Evidence, real sources and what is still uncertain", prompt: "Research a question with live sources where needed. Ask for my question first. Distinguish evidence from inference and don't invent citations."),
        .init(title: "Compare my options", icon: "arrow.left.arrow.right", detail: "Trade-offs based on what matters to you", prompt: "Help me compare my options. Ask what I am deciding and my most important constraints."),
        .init(title: "Explain it clearly", icon: "text.book.closed", detail: "Make a difficult topic understandable", prompt: "Explain a topic clearly, with a useful example. Ask what topic and how familiar I am with it.")
    ] }
    private var planning: [Skill] { [
        .init(title: "Build a practical plan", icon: "list.bullet.clipboard", detail: "Priorities, dependencies and a realistic next step", prompt: "Turn my goal into a realistic plan with priorities, dependencies and a next step. Ask for my goal and constraints."),
        .init(title: "Plan my week", icon: "calendar", detail: "Balance time, commitments and priorities", prompt: "Help me plan my week from the commitments I provide. Ask for priorities, available time and my time zone. Don't imply calendar access."),
        .init(title: "Break down a project", icon: "square.stack.3d.up", detail: "Milestones, effort and what could get in the way", prompt: "Break my project into milestones and actionable steps. Ask about the outcome, deadline and constraints.")
    ] }
    private var community: [Skill] { [
        .init(title: "Find my communities", icon: "person.3", detail: "Matches from Whisper’s real public catalog", prompt: "Help me find real Whisper communities for my interests. Ask what I care about, then use only the supplied community catalog."),
        .init(title: "Start a conversation", icon: "bubble.left", detail: "Welcomes, discussion starters and introductions", prompt: "Help me start a thoughtful community conversation. Ask about the community and what I want people to discuss."),
        .init(title: "Bring people together", icon: "person.2", detail: "Community ideas, events and respectful outreach", prompt: "Help me bring people together around a shared interest. Ask about the people, goal and constraints; don't invent members or send messages."),
        .init(title: "Find & share posts", icon: "square.on.square", detail: "Matches from posts already loaded on this device", prompt: "Help me find posts among the available loaded Whisper posts. Ask what topic I want. Don't claim a global search.")
    ] }
    private var focusSkills: [Skill] {
        switch bot {
        case .main: [writing[0], research[0], planning[0], community[0]]
        case .writer: writing
        case .researcher: research
        case .planner: planning
        case .social: community
        }
    }
    private var allSkills: [Skill] { writing + research + planning + community }

    var body: some View {
        WhisperKnotNavigationContainer(embedded: embedded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        WhisperKnotProfilePortrait(size: 56, tint: bot.portraitTint)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(bot.displayName).font(.headline)
                            Text(bot.job).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.modifier(WhisperKnotPanel())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bot == .main ? "Everyday ideas" : "Specialist ideas").font(.headline).padding(.bottom, 10)
                        ForEach(focusSkills) { item in
                            skill(item.title, icon: item.icon, detail: item.detail, prompt: item.prompt)
                            if item.id != focusSkills.last?.id { Divider() }
                        }
                    }.modifier(WhisperKnotPanel())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Communication · built in").font(.headline).padding(.bottom, 10)
                        skill("Emoji & tone", icon: "face.smiling", detail: "Natural chat, with sparse emoji when it fits", prompt: "Help me write a natural message in my voice. Use emoji only if it fits; ask who it is for and what I want to say.")
                        Divider()
                        skill("Message reactions", icon: "bubble.left.and.bubble.right", detail: "An occasional reaction to your message—not answer feedback", prompt: "Explain how you use message reactions and how I can ask for no reactions or emoji.")
                        Text("These communication skills work automatically when appropriate. You can ask for no emoji or reactions. They do not read workspace guides or approve actions.").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                    }.modifier(WhisperKnotPanel())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tools").font(.headline).padding(.bottom, 10)
                        skill("Live web search", icon: "globe", detail: "Sources when the search service returns evidence", prompt: "Search the live web for my question and cite only returned sources. Ask for my question first.")
                        Divider()
                        skill("Calculator", icon: "plus.forwardslash.minus", detail: "Arithmetic evaluated by the live Knot service", prompt: "Calculate an expression using the calculator tool. Ask me for the expression first. Don't claim tool execution if the service is unavailable.")
                        Divider()
                        tool("Look at a photo", icon: "photo", detail: "Analyze an image you deliberately attach", selection: .photo)
                        Divider()
                        tool("Read a file", icon: "doc.text", detail: "Extract text from a supported document", selection: .file)
                        Divider()
                        tool("Voice conversation", icon: "waveform", detail: "Talk with \(bot.displayName); no actions run from voice", selection: .voice)
                        Divider()
                        WhisperKnotLiveCapabilitiesPanel().padding(.vertical, 10)
                        Text("Search and calculations run only on the live connection. Voice, shared replies, fallback and Responsibilities never run shell commands. Files remain in the isolated workspace; no download link is created.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                    }.modifier(WhisperKnotPanel())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actions · your approval").font(.headline).padding(.bottom, 10)
                        skill("Publish a post", icon: "square.and.pencil", detail: "Review the exact caption and destination", prompt: "Help me publish a plain-text post. Ask for its text and destination, then propose it for native approval. Don't publish automatically.")
                        Divider()
                        skill("Set a reminder", icon: "bell.badge", detail: "One notification on this device", prompt: "Help me set a one-time reminder on this device. Ask for its title, exact time and time zone, then show an approval card.")
                        Divider()
                        skill("Schedule a meeting", icon: "calendar.badge.plus", detail: "Exact date and time; invitations need review", prompt: "Help me schedule a Whisper meeting. Ask for its title, exact date, time and time zone, then propose it for approval.")
                        Divider()
                        skill("Join a community", icon: "person.3", detail: "A canonical Whisper community", prompt: "Help me join a real Whisper community. Verify the catalog community, then ask for native approval.")
                        Divider()
                        skill("Follow someone", icon: "person.badge.plus", detail: "Verify the exact handle and approve first", prompt: "Help me follow someone on Whisper. Ask for the exact handle, then show an approval card.")
                        Text("Allow applies once to that exact request. Deny runs nothing. Only these documented actions are available to Knot; existing privacy and account access always apply.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                    }.modifier(WhisperKnotPanel())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Responsibilities").font(.headline).padding(.bottom, 10)
                        skill("Watch my performance", icon: "chart.line.uptrend.xyaxis", detail: "Your Whisper post metrics, with a separate read approval", prompt: "I'd like you to take responsibility for my Whisper creator score and how my posts are performing. Help me agree the schedule, quiet hours and end date one question at a time, then show the exact creator_performance approval. Don't claim you've read my metrics before an approved check.")
                        Divider()
                        skill("Keep an eye on something", icon: "checklist", detail: "Public-topic tracking or scheduled goal check-ins", prompt: "I'd like to assign you a recurring responsibility. Ask what I want you to keep an eye on, then agree the schedule and boundaries one question at a time. Show a native approval draft; don't schedule anything automatically.")
                    }.modifier(WhisperKnotPanel())
                    DisclosureGroup("Other ideas") {
                        ForEach(allSkills.filter { item in !focusSkills.contains { $0.id == item.id } }) { item in
                            skill(item.title, icon: item.icon, detail: item.detail, prompt: item.prompt)
                        }
                    }.modifier(WhisperKnotPanel())
                    NavigationLink { WhisperJasperTuningView(embedded: true) } label: {
                        Label("Tune \(bot.displayName)’s replies", systemImage: "slider.horizontal.3").frame(minHeight: 44)
                    }.modifier(WhisperKnotPanel())
                    Text("Shortcuts only fill your draft; nothing is sent automatically. Knot can make mistakes.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6)
                }.frame(maxWidth: 620).padding(20).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Skills & tools").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !embedded { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        }
    }

    private func skill(_ title: String, icon: String, detail: String, prompt: String) -> some View {
        tool(title, icon: icon, detail: detail, selection: .prompt(prompt))
    }
    private func tool(_ title: String, icon: String, detail: String, selection: WhisperKnotCapabilitySelection) -> some View {
        Button { Haptics.tap(); onSelect(selection) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(.primary).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }.foregroundStyle(.primary).padding(.vertical, 10).frame(minHeight: 44).contentShape(.rect)
        }.buttonStyle(.plain)
    }
}
