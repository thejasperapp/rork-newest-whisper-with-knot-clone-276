import SwiftUI

/// The custom speed-date LOBBY — the screen between "Start a speed date"
/// and the meeting room: a living rose stage with cupid Jasper, your date
/// link (already copied), your dating-card status, and the big enter
/// button. Guests joining by link get the matching welcome takeover
/// inside the room; this lobby is the STARTER's custom join screen.
struct WhisperSpeedDateLobbyView: View {
    @Environment(\.dismiss) private var dismiss
    let meeting: WhisperMeetingRow
    let code: String

    @State private var linkCopied: Bool = true
    @State private var showCardEditor: Bool = false
    /// Bumps after the card editor closes so the status chips recompute.
    @State private var cardTick: Int = 0
    @State private var drift: Bool = false

    private let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
    private let ink = Color(red: 0.16, green: 0.07, blue: 0.10)

    /// Short chip labels for the five card prompts.
    private static let shortLabels: [String: String] = [
        "looking": "Looking for",
        "interests": "Interests",
        "dealbreakers": "Non-negotiables",
        "firstDate": "First date",
        "funFact": "Fun fact"
    ]

    var body: some View {
        let card = { _ = cardTick; return WhisperSpeedDating.loadCard() }()
        let answered = WhisperSpeedDating.questions.filter { !(card[$0.id] ?? "").isEmpty }.count
        ZStack {
            // The living pink field — same family as the Dating masthead.
            Color(red: 0.99, green: 0.83, blue: 0.88).ignoresSafeArea()
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.63, blue: 0.76).opacity(0.6))
                    .frame(width: 320, height: 320)
                    .blur(radius: 60)
                    .offset(x: drift ? -110 : 80, y: drift ? -190 : -120)
                Circle()
                    .fill(Color(red: 0.93, green: 0.36, blue: 0.58).opacity(0.35))
                    .frame(width: 280, height: 280)
                    .blur(radius: 66)
                    .offset(x: drift ? 120 : -90, y: drift ? 210 : 150)
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 240, height: 240)
                    .blur(radius: 58)
                    .offset(x: drift ? -30 : 40, y: drift ? 60 : -40)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ink.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.white.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        WhisperJasperInteractiveMascot(size: 84, dating: true)
                        .padding(.top, 12)

                        Text("BLIND DATE")
                            .font(.system(size: 11, weight: .black))
                            .tracking(2.4)
                            .foregroundStyle(rose)
                        Text("Hear them first.\nSee them at the reveal.")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(ink)
                        Text("Share an invitation for five minutes together. Cameras reveal at two minutes, or earlier if you both choose. Jasper brings the icebreakers.")
                            .font(.subheadline)
                            .foregroundStyle(ink.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)

                        // The invite link — already on the clipboard.
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(rose)
                                Text("mydailywhisper.com/meet/\(code)")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                                Button {
                                    Haptics.tap()
                                    UIPasteboard.general.string = "https://mydailywhisper.com/meet/\(code)?sd=1"
                                    withAnimation(.easeOut(duration: 0.2)) { linkCopied = true }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(linkCopied ? "Copied" : "Copy")
                                            .font(.system(size: 11.5, weight: .bold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(rose))
                                }
                                .buttonStyle(.plain)
                            }
                            Text("Send it to your date — they'll drop straight into the room.")
                                .font(.footnote)
                                .foregroundStyle(ink.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.75)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(rose.opacity(0.25), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)

                        // Your card status — the judge reads it, so show it.
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Your conversation starters")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(rose)
                                Spacer()
                                Text("\(answered) of \(WhisperSpeedDating.questions.count) answered")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ink.opacity(0.55))
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(WhisperSpeedDating.questions) { q in
                                        let done = !(card[q.id] ?? "").isEmpty
                                        HStack(spacing: 4) {
                                            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
                                                .font(.system(size: 10, weight: .bold))
                                            Text(Self.shortLabels[q.id] ?? q.label)
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundStyle(done ? .white : rose)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(done ? rose : rose.opacity(0.10)))
                                        .overlay(Capsule().strokeBorder(rose.opacity(done ? 0 : 0.35), lineWidth: 1))
                                    }
                                }
                            }
                            Button {
                                Haptics.tap()
                                showCardEditor = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "pencil.and.outline")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(answered > 0 ? "Edit my card" : "Fill my card")
                                        .font(.system(size: 12.5, weight: .bold))
                                }
                                .foregroundStyle(rose)
                                .padding(.horizontal, 13)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(.white.opacity(0.7)))
                                .overlay(Capsule().strokeBorder(rose.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.55)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(rose.opacity(0.20), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                }

                // The big enter button — pinned under the scroll.
                Button {
                    enterTheDate()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Enter the date 💘")
                            .font(.system(size: 16, weight: .black))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: rose.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
        }
        .sheet(isPresented: $showCardEditor, onDismiss: { cardTick += 1 }) {
            WhisperDatingCardEditorSheet()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    /// Primes speed-date mode and opens the real meeting room.
    private func enterTheDate() {
        Haptics.tap()
        WhisperSpeedDating.pendingRooms.insert(meeting.id.lowercased())
        // Entering from the lobby IS saying "I'm ready" — the room skips the
        // welcome takeover and starts the clock once the guest is ready too.
        WhisperBlindDate.readyRooms.insert(meeting.id.lowercased())
        let row = meeting
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(360))
            WhisperMeetingWindow.shared.present(row)
        }
    }
}
