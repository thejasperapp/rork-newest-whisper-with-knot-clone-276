import Testing
import Foundation
@testable import Whisper

struct WhisperMeetingInvitationTests {
    @Test func preservesPublicIdentitiesAcrossLegacyAndNewLinks() throws {
        for identity in ["ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456", "wsp-Ab12-Cd34"] {
            for host in ["www.mydailywhisper.com", "mydailywhisper.com", "meet.mydailywhisper.com"] {
                let url = try #require(URL(string: "https://\(host)/meet/\(identity)?token=discard&autoJoin=1#access_token=discard"))
                let target = try #require(WhisperMeetingLinkRouter.parse(url))
                #expect(target.idOrCode == identity)
                #expect(target.webURL?.absoluteString == "https://meet.mydailywhisper.com/meet/\(identity)")
                #expect(target.appURL?.absoluteString == "whisperworkspace://meet/\(identity)")
                #expect(!target.isSocial)
                #expect(WhisperMeetingInvitation.fromText("Join my meeting: \(url.absoluteString)")?.idOrCode == identity)
                #expect(WhisperMeetingService.link(for: identity) == "https://meet.mydailywhisper.com/meet/\(identity)")
            }
        }
    }

    @Test func excludesUnrelatedURLsAndStructuredInvitations() {
        for value in ["https://evil.example/meet/wsp-ab12-cd34", "https://www.mydailywhisper.com.evil.example/meet/wsp-ab12-cd34", "https://www.mydailywhisper.com/meet/wsp-ab12-cd34/extra", "https://user:secret@www.mydailywhisper.com/meet/wsp-ab12-cd34", "wsp-ab12-cd345", "::whisper-date-invite-v1::{\"meetCode\":\"wsp-ab12-cd34\"}", "::whisper-calendar-v1::{\"link\":\"https://www.mydailywhisper.com/meet/wsp-ab12-cd34\"}"] {
            #expect(WhisperMeetingInvitation.fromText(value) == nil)
        }
    }

    @Test func datingAndCallLinksStaySocial() throws {
        for suffix in ["?sd=1", "?call=alex&mode=audio", "?groupCall=1"] {
            let target = try #require(WhisperMeetingInvitation.fromText("https://www.mydailywhisper.com/meet/wsp-Ab12-Cd34\(suffix)"))
            #expect(target.isSocial)
            #expect(target.idOrCode == "wsp-Ab12-Cd34")
        }
        #expect(WhisperMeetingInvitation.fromText("Started a group audio call — join here: https://www.mydailywhisper.com/meet/ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456")?.socialCall == true)
    }

    @MainActor @Test func successfulOperatingSystemOpenDoesNotLaunchBrowser() async {
        var opened: [String] = []
        let result = await WhisperMeetHandoff.open(.init(idOrCode: "wsp-Ab12-Cd34"), using: { url in
            opened.append(url.absoluteString)
            return true
        })
        #expect(result)
        #expect(opened == ["whisperworkspace://meet/wsp-Ab12-Cd34"])
    }

    @MainActor @Test func unavailableAppFallsBackToExactHTTPSIdentity() async {
        var opened: [String] = []
        let result = await WhisperMeetHandoff.open(.init(idOrCode: "ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456"), using: { url in
            opened.append(url.absoluteString)
            return url.scheme == "https"
        })
        #expect(result)
        #expect(opened == ["whisperworkspace://meet/ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456", "https://meet.mydailywhisper.com/meet/ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456"])
    }

    @MainActor @Test func openingFailureRemainsRetryableAndSocialNeverHandsOff() async {
        var opened: [URL] = []
        let failure = await WhisperMeetHandoff.open(.init(idOrCode: "wsp-ab12-cd34"), using: { url in opened.append(url); return false })
        #expect(!failure)
        #expect(opened.count == 2)
        opened = []
        let social = await WhisperMeetHandoff.open(.init(idOrCode: "wsp-ab12-cd34", speedDate: true), using: { url in opened.append(url); return true })
        #expect(!social)
        #expect(opened.isEmpty)
    }
}
