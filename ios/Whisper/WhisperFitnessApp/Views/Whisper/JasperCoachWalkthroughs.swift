import SwiftUI

// MARK: - Coach side — the moment a client's live pipe opens

/// Full-screen glow walkthrough for the COACH, shown automatically the first
/// time a client's live Jasper pipe opens (and reopenable from the
/// dashboard's "What I can see" button): the confirmation moment with live
/// counts, then pages for reads, coach tools (or the read-only truth), and
/// the fair-play rules.
struct JasperCoachAccessWalkthrough: View {
    let clientUsername: String
    let access: JasperCoachAccess
    let snapshot: JasperLiveSnapshot?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        JasperGlowWalkthrough(slides: slides, onDone: { dismiss() }) {
            JasperLinkConfirmation(
                title: "Coach access granted",
                subtitle: "@\(clientUsername) · \(accessLine) · revocable"
            ) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(JasperBrand.stage(colorScheme))
                    .frame(width: 52, height: 52)
                    .background(JasperBrand.text(colorScheme), in: .rect(cornerRadius: 14))
            } below: {
                VStack(spacing: 12) {
                    accessPill
                    if let snap = snapshot {
                        JasperGlowCountsGrid(resources: snap.resources)
                        Text(snap.windowDays > 0
                             ? "Live counts from the last \(snap.windowDays) days — read through @\(clientUsername)'s own token."
                             : "Live counts from one dashboard call — read through @\(clientUsername)'s own token.")
                            .font(.caption2)
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }

    private var accessLine: String {
        access.canWrite == true ? "read & write" : "scoped reads"
    }

    private var accessPill: some View {
        HStack(spacing: 5) {
            Image(systemName: access.canWrite == true ? "wand.and.stars" : "eye.fill")
                .font(.system(size: 10, weight: .bold))
            Text(access.canWrite == true ? "Coach tools unlocked" : "Read-only grant")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(access.canWrite == true ? JasperBrand.ink : JasperBrand.text(colorScheme).opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            if access.canWrite == true {
                Capsule().fill(JasperBrand.emberGradient)
            } else {
                Capsule().fill(JasperBrand.chip(colorScheme))
            }
        }
    }

    private var slides: [JasperWalkthroughSlide] {
        var out: [JasperWalkthroughSlide] = [
            JasperWalkthroughSlide(
                id: "reads",
                kicker: "What you can see",
                title: "Their last 30 days, live",
                rows: [
                    JasperWalkthroughRow(icon: "antenna.radiowaves.left.and.right",
                                         title: "Straight from the Jasper API",
                                         detail: "Workouts, meals, water, the full diet plan (daily meals, targets, and Jasper's grocery checklist — both on this dashboard), sleep, readiness, weight, steps, PRs, goals, and preferences — read through @\(clientUsername)'s own token."),
                    JasperWalkthroughRow(icon: "sparkles.rectangle.stack",
                                         title: "Jasper's native looks",
                                         detail: "The readiness recovery ring and the sleep night-view render on this dashboard exactly like Jasper draws them."),
                    JasperWalkthroughRow(icon: "clock.fill",
                                         title: "Honest freshness",
                                         detail: "Reads refresh with the dashboard; when Jasper says no, the panel states the real reason."),
                ]
            ),
        ]
        if access.canWrite == true {
            out.append(JasperWalkthroughSlide(
                id: "tools",
                kicker: "Coach tools",
                title: "You can act, not just look",
                rows: [
                    JasperWalkthroughRow(icon: "figure.strengthtraining.traditional",
                                         title: "Assign programs",
                                         detail: "Send a training program straight into their Jasper — name, goal, weeks, and days per week."),
                    JasperWalkthroughRow(icon: "fork.knife",
                                         title: "Log corrections",
                                         detail: "Add a meal or water entry on their behalf — every write has one-tap Undo."),
                    JasperWalkthroughRow(icon: "tray.and.arrow.down.fill",
                                         title: "Send to their inbox",
                                         detail: "Drop a note card into their Jasper \"Shared with you\" inbox."),
                ],
                footnote: "Writes cover training, nutrition, and goals — never their body metrics, blood, or preferences."
            ))
        } else {
            out.append(JasperWalkthroughSlide(
                id: "readonly",
                kicker: "Read-only grant",
                title: "Looking is on, acting is off",
                rows: [
                    JasperWalkthroughRow(icon: "eye.fill",
                                         title: "Reads only",
                                         detail: "@\(clientUsername) chose view-only coaching at consent — you see their data, writes stay locked."),
                    JasperWalkthroughRow(icon: "arrow.up.circle.fill",
                                         title: "Want coach tools?",
                                         detail: "Ask them to switch coach access to read & write in Jasper — program assignment, meal logging, and inbox cards unlock automatically."),
                ]
            ))
        }
        out.append(JasperWalkthroughSlide(
            id: "rules",
            kicker: "Ground rules",
            title: "Fair, visible, revocable",
            rows: [
                JasperWalkthroughRow(icon: "person.fill.viewfinder",
                                     title: "They see this token",
                                     detail: "Your access is listed in their Jasper settings under your handle — they can revoke it any time."),
                JasperWalkthroughRow(icon: "bolt.shield.fill",
                                     title: "Re-verified every call",
                                     detail: "Jasper checks the coaching grant on every single request — ending coaching kills access instantly."),
                JasperWalkthroughRow(icon: "drop.fill",
                                     title: "Never blood, never photo files",
                                     detail: "Blood panels never ride coach access, and progress photos stay in Jasper's private storage — metadata only."),
                JasperWalkthroughRow(icon: "slider.horizontal.3",
                                     title: "Consent is granular",
                                     detail: "Clients pick the level — invites can be accepted view-only and scopes trimmed. \"Not shared\" is a choice Whisper respects, never an error."),
            ],
            footnote: "One distinct token per client · deleted the moment coaching ends."
        ))
        return out
    }
}

// MARK: - Client side — what your coach sees

/// The mirror image, for the CLIENT: shown once when a coach token first
/// appears on their Jasper account (and any time from the settings card).
/// Names the coach, lists exactly what they read, what they can never see,
/// and every way to revoke.
struct JasperClientCoachVisibilityWalkthrough: View {
    let coachUsername: String?
    let appName: String?
    let scopes: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var canWrite: Bool { scopes.contains { $0 == "all" || $0.hasPrefix("write:") } }
    private var coachHandle: String { coachUsername.map { "@\($0)" } ?? "Your coach" }

    var body: some View {
        JasperGlowWalkthrough(slides: slides, onDone: { dismiss() }) {
            JasperLinkConfirmation(
                title: "Your coach is connected",
                subtitle: "\(coachHandle) reads your Jasper through Whisper — here's exactly what that means."
            ) {
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(JasperBrand.stage(colorScheme))
                    .frame(width: 52, height: 52)
                    .background(JasperBrand.text(colorScheme), in: .rect(cornerRadius: 14))
            } below: {
                VStack(spacing: 10) {
                    accessPill
                    if let appName {
                        Text("Listed in Jasper → Settings → Connect as \"\(appName)\"")
                            .font(.caption2)
                            .foregroundStyle(JasperBrand.text(colorScheme).opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
    }

    private var accessPill: some View {
        HStack(spacing: 5) {
            Image(systemName: canWrite ? "wand.and.stars" : "eye.fill")
                .font(.system(size: 10, weight: .bold))
            Text(canWrite ? "Reads + coach tools" : "Reads only")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(canWrite ? JasperBrand.ink : JasperBrand.text(colorScheme).opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            if canWrite {
                Capsule().fill(JasperBrand.emberGradient)
            } else {
                Capsule().fill(JasperBrand.chip(colorScheme))
            }
        }
    }

    private var slides: [JasperWalkthroughSlide] {
        var seeRows: [JasperWalkthroughRow] = [
            JasperWalkthroughRow(icon: "figure.strengthtraining.traditional",
                                 title: "Training",
                                 detail: "Workouts, programs, personal records, and weight from your last 30 days."),
            JasperWalkthroughRow(icon: "fork.knife",
                                 title: "Nutrition",
                                 detail: "Meals with macros, water, diet plans with their grocery checklist, goals, and your preferences (read-only)."),
            JasperWalkthroughRow(icon: "moon.zzz.fill",
                                 title: "Sleep & recovery",
                                 detail: "Sleep stages, readiness, heart rate, steps, and energy — drawn in Jasper's own looks."),
            JasperWalkthroughRow(icon: "waveform.path.ecg",
                                 title: "Biological age",
                                 detail: "Your bio-age history, display-only — nobody can write it from outside Jasper."),
        ]
        if canWrite {
            seeRows.append(JasperWalkthroughRow(icon: "square.and.pencil",
                                                title: "They can also act",
                                                detail: "You granted read & write — your coach can assign programs, log meals or water for you (always undoable), and send cards to your Jasper inbox."))
        }
        return [
            JasperWalkthroughSlide(
                id: "sees",
                kicker: "What they see",
                title: "Exactly this, nothing more",
                rows: seeRows
            ),
            JasperWalkthroughSlide(
                id: "never",
                kicker: "What they never see",
                title: "Off-limits by design",
                rows: [
                    JasperWalkthroughRow(icon: "drop.fill",
                                         title: "Blood panels",
                                         detail: "Never included in coach access — even \"full access\" coach tokens exclude blood on Jasper's side."),
                    JasperWalkthroughRow(icon: "photo.fill",
                                         title: "Your photo files",
                                         detail: "Progress photo images stay in Jasper's private storage — a coach token sees metadata only."),
                    JasperWalkthroughRow(icon: "lock.fill",
                                         title: "Your account",
                                         detail: "Coaches read through their own token — they never hold your password or your session."),
                ]
            ),
            JasperWalkthroughSlide(
                id: "controls",
                kicker: "Your controls",
                title: "Revocable in one tap, always",
                rows: [
                    JasperWalkthroughRow(icon: "eye.fill",
                                         title: "See it in Jasper",
                                         detail: "Jasper → Settings → Connect lists this access under your coach's handle."),
                    JasperWalkthroughRow(icon: "hand.raised.fill",
                                         title: "Revoke anytime",
                                         detail: "Kill it from Jasper settings, or end coaching in Whisper — access dies instantly either way."),
                    JasperWalkthroughRow(icon: "bolt.shield.fill",
                                         title: "Checked every call",
                                         detail: "Jasper re-verifies the coaching grant on every single request — a revoked grant can't read one more row."),
                ],
                footnote: "You chose the level at consent — invites can be accepted view-only, and downgrading later locks coach writes immediately while reads keep working."
            ),
        ]
    }
}
