import SwiftUI

/// Shown on both exact approval paths before the new private-data scope leaves
/// the device. Existing public/goal grants never inherit this scope.
struct WhisperKnotCreatorReadDisclosure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Read my Whisper performance").font(.subheadline.weight(.semibold))
            Text("Each approved check reads only your newest 100 authored posts’ IDs, publication times, like/comment counts, and your total follower count. No captions, media, names of followers or people engaging, private chats, calendar, earnings or other accounts are read.")
            Text("These metrics, the monitoring baseline and reporting instructions go through Whisper’s server and Rork AI Cloud (via Vercel AI Gateway) to OpenAI GPT‑4o to prepare a private update. Unchanged metrics stay quiet. Your existing Analytics or Creator Studio access is checked again for every run; this approval does not unlock paid or verified features.")
            Text("For verified creators and staff, a clearly labeled score estimate uses audience change since the first successful check, not the device’s weekly baseline. It may differ from Creator Studio. Other eligible accounts receive basic metrics without a score. Counts are current totals on recent posts—not reach or interactions occurring only within 30 days.")
            Text("The baseline and last finding are private rule details, removed with the rule or 30 days after its end. Pause or delete in Responsibilities, or stop AI sharing to withdraw future checks. Calls, notifications and app changes need separate permission.")
        }.font(.subheadline)
    }
}
