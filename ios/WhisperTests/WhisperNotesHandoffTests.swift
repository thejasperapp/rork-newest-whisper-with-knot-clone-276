import Foundation
import Testing
@testable import Whisper

struct WhisperNotesHandoffTests {
    @Test func sharedDocumentKeepsCanonicalIdentity() throws {
        let url = try #require(URL(string: "https://notes.mydailywhisper.com/shared/20000000-0000-4000-8000-000000000001"))
        let link = try #require(WhisperNotesLink.parse(url))
        #expect(link.appURL?.absoluteString == "whispernotes://shared/20000000-0000-4000-8000-000000000001")
        #expect(link.webURL == url)
        #expect(WhisperNotesLink.parse(try #require(link.appURL)) == link)
    }

    @Test func privateNotebookRetainsOwnerAndTab() throws {
        let url = try #require(URL(string: "https://notes.mydailywhisper.com/d/20000000-0000-4000-8000-000000000001?owner=10000000-0000-4000-8000-000000000001&tab=transcript"))
        let link = try #require(WhisperNotesLink.parse(url))
        #expect(link.appURL?.absoluteString == "whispernotes://document/20000000-0000-4000-8000-000000000001?owner=10000000-0000-4000-8000-000000000001&tab=transcript")
        #expect(link.webURL == url)
        #expect(WhisperNotesLink.parse(try #require(link.appURL)) == link)
    }

    @Test func rejectsAmbiguousOrCredentialBearingLinks() throws {
        let id = "20000000-0000-4000-8000-000000000001"
        let owner = "10000000-0000-4000-8000-000000000001"
        for value in [
            "https://notes.mydailywhisper.com.evil.example/shared/\(id)",
            "http://notes.mydailywhisper.com/shared/\(id)",
            "https://user:secret@notes.mydailywhisper.com/shared/\(id)",
            "https://notes.mydailywhisper.com/shared/\(id)?token=secret",
            "https://notes.mydailywhisper.com/shared/\(id)#secret",
            "https://notes.mydailywhisper.com/shared/\(id)/extra",
            "https://notes.mydailywhisper.com/d/\(id)",
            "https://notes.mydailywhisper.com/d/\(id)?owner=\(owner)&owner=\(owner)",
            "https://notes.mydailywhisper.com/d/\(id)?owner=\(owner)&tab=full&tab=quick",
            "https://notes.mydailywhisper.com/d/\(id)?owner=\(owner)&tab",
            "whisperworkspace://document/\(id)?owner=\(owner)",
            "whispernotes://shared/not-an-id"
        ] {
            #expect(WhisperNotesLink.parse(try #require(URL(string: value))) == nil)
        }
    }

    @MainActor @Test func appSuccessDoesNotOpenWebsite() async throws {
        let url = try #require(URL(string: "https://notes.mydailywhisper.com/shared"))
        let link = try #require(WhisperNotesLink.parse(url))
        var opened: [URL] = []
        let result = await WhisperNotesHandoff.open(link, using: { url in opened.append(url); return true })
        #expect(result)
        #expect(opened.map(\.absoluteString) == ["whispernotes://shared"])
    }

    @MainActor @Test func appFailureFallsBackAndTotalFailureIsReported() async throws {
        let url = try #require(URL(string: "https://notes.mydailywhisper.com/shared/20000000-0000-4000-8000-000000000001"))
        let link = try #require(WhisperNotesLink.parse(url))
        var opened: [URL] = []
        let result = await WhisperNotesHandoff.open(link, using: { url in opened.append(url); return url.scheme == "https" })
        #expect(result)
        #expect(opened == [try #require(link.appURL), try #require(link.webURL)])
        let failure = await WhisperNotesHandoff.open(link, using: { _ in false })
        #expect(!failure)
    }
}
