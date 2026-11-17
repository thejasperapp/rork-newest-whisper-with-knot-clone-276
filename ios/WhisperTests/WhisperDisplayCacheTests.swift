import Testing
import Foundation
@testable import Whisper

struct WhisperDisplayCacheTests {
    @Test func snapshotRejectsOtherOwnersExpiredFutureAndUnsupportedVersions() throws {
        let owner = "11111111-1111-4111-8111-111111111111"
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = WhisperLocalDisplaySnapshot(version: 1, owner: owner, savedAt: now, value: ["cached"])
        #expect(snapshot.isValid(for: owner.uppercased(), now: now, maxAge: 60))
        #expect(!snapshot.isValid(for: "22222222-2222-4222-8222-222222222222", now: now, maxAge: 60))
        #expect(!snapshot.isValid(for: owner, now: now.addingTimeInterval(60), maxAge: 60))
        #expect(!snapshot.isValid(for: owner, now: now.addingTimeInterval(-1), maxAge: 60))
        let unknown = WhisperLocalDisplaySnapshot(version: 2, owner: owner, savedAt: now, value: [String]())
        #expect(!unknown.isValid(for: owner, now: now, maxAge: 60))
        let guest = WhisperLocalDisplaySnapshot(version: 1, owner: "guest", savedAt: now, value: [String]())
        #expect(!guest.isValid(for: "guest", now: now, maxAge: 60))
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WhisperLocalDisplaySnapshot<[String]>.self, from: encoded)
        #expect(decoded.value == ["cached"])
    }

    @Test func displayProfileNeverPersistsEntitlementsPrivacyOrOnboarding() throws {
        let profile = WhisperUserRow(user_id: "11111111-1111-4111-8111-111111111111", username: "tester",
            display_name: "Test", bio: "My bio", interests: ["Photography"], profile_image_url: nil,
            onboarded_at: "2026-09-22T00:00:00Z", is_private: true,
            professional_category: "Photographer", account_type: "business", is_plus: true)
        let display = WhisperProfileDisplay(profile)
        let data = try JSONEncoder().encode(display)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["is_plus"] == nil)
        #expect(json["account_type"] == nil)
        #expect(json["is_private"] == nil)
        #expect(json["onboarded_at"] == nil)
        #expect(display.interests == ["Photography"])
        #expect(display.username == "tester")
    }
}
