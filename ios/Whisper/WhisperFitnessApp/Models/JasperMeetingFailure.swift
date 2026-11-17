import Foundation

nonisolated struct JasperMeetingFailure: LocalizedError {
    let code: String
    var errorDescription: String? {
        switch code {
        case "workspace_access_denied": "This workspace item is not available to your account. Ask the owner to review your invitation or team access."
        case "invalid_work": "Check required fields, date format (YYYY-MM-DD), field lengths and HTTPS links."
        case "work_person_missing": "No exact Whisper username matched. Check the spelling with the person you want to invite."
        case "invalid_transition": "This step is not available. Refresh and check the assigned owner, required dates and current version."
        case "work_limit": "This workspace reached its supported capacity. Existing records are unchanged."
        case "confirmation_required": "Review this content and who can see it before saving."
        case "revision_conflict": "This saved item changed on another device. Reload before retrying; your draft has not overwritten it."
        case "client_access_denied": "This private person is not available to your account."
        case "team_access_denied": "Your team access is no longer available. Refresh your teams."
        case "invalid_client": "Check email, dates and field lengths, then retry."
        case "client_save_failed": "The update could not be confirmed. Refresh before retrying."
        case "client_limit": "This workspace reached its supported client or team-card limit."
        case "invalid_meeting_scope": "Choose between one and eight meetings without combining other scopes."
        case "meeting_access_denied": "You no longer have access to one of these meetings. Refresh your library."
        case "meeting_read_failed": "The saved transcript could not load. Reconnect and retry."
        case "narrow_search": "There are too many matches to verify. Choose a folder or ask a more specific question."
        case "transcript_too_long": "This transcript is too long for one scan. It has not been shortened or sent to AI."
        case "google_setup_required": "Google Calendar needs the app’s Google authorization setup before it can connect."
        case "google_reconnect": "Connect Google Calendar again to restore access."
        case "sign_in_required": "Sign in again to use your Jasper."
        case "ai_not_configured": "Jasper’s AI connection needs server setup. Your meetings are unchanged."
        case "answer_expired": "This temporary answer expired. Ask again before saving it."
        case "invalid_answer", "incomplete_answer": "Jasper’s answer could not be verified. Try a narrower question."
        case "try_again_shortly": "Please wait a moment before asking again."
        default: "Jasper could not finish. Your original meetings are unchanged. Please try again."
        }
    }
}
