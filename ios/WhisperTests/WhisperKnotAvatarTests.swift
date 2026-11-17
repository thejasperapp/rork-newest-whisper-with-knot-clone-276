import XCTest
import AVFoundation
import UIKit
@testable import Whisper

final class WhisperKnotAvatarTests: XCTestCase {
    @MainActor func testPrivateMediaCacheSurvivesNewInstanceAndSeparatesOwners() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = WhisperKnotPersonaMediaCache(root: root, maximumBytes: 12)
        let bytes = Data([1, 2, 3, 4, 5, 6, 7, 8])
        _ = try cache.store(bytes, owner: "one", id: "master")
        let restored = WhisperKnotPersonaMediaCache(root: root, maximumBytes: 12)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.file(owner: "one", id: "master"))), bytes)
        XCTAssertNil(restored.file(owner: "two", id: "master"))
        XCTAssertThrowsError(try cache.store(Data([9]), owner: "one", id: "master"))
        _ = try cache.store(bytes, owner: "one", id: "next")
        XCTAssertNil(cache.file(owner: "one", id: "master"))
        XCTAssertNotNil(cache.file(owner: "one", id: "next"))
        cache.clear(owner: "one")
        XCTAssertNil(restored.file(owner: "one", id: "next"))
    }
    @MainActor func testFilmReconfiguresForStateAndLoopChangesWithoutRestartingUnchangedPlayer() throws {
        let view = KnotAvatarFilm.FilmView()
        let coordinator = KnotAvatarFilm.Coordinator(completed: {})
        defer { coordinator.stop() }
        let url = try XCTUnwrap(KnotAvatarResources.film("idle"))
        coordinator.configure(view, state: "idle", url: url, loops: true, theme: "light")
        let original = try XCTUnwrap(coordinator.player)
        coordinator.configure(view, state: "idle", url: url, loops: true, theme: "light")
        XCTAssertTrue(original === coordinator.player)
        coordinator.configure(view, state: "milestone", url: url, loops: false, theme: "light")
        XCTAssertFalse(original === coordinator.player)
        XCTAssertNil(coordinator.looper)
        XCTAssertNotNil(coordinator.ended)
    }
    @MainActor func testAuthoredActivityCopyIsNotClippedAndClears() {
        let id = UUID().uuidString
        let label = "Preparing your reading guide with the full list of requested sections and checking the complete reading schedule"
        WhisperKnotServerActivity.shared.set(label, for: id)
        XCTAssertEqual(WhisperKnotServerActivity.shared.label(for: UUID(uuidString: id)), label)
        WhisperKnotServerActivity.shared.set(nil, for: id)
        XCTAssertNil(WhisperKnotServerActivity.shared.label(for: UUID(uuidString: id)))
    }

    @MainActor func testAllSuppliedStateFilmsAreBundledPlayableAndSilent() async throws {
        XCTAssertEqual(KnotAvatarResources.states, ["waking", "idle", "working", "making-something", "milestone"])
        for state in KnotAvatarResources.states {
            let url = try XCTUnwrap(KnotAvatarResources.film(state), "Missing supplied clip: \(state)")
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertTrue(playable, state)
            // Current LightV5 kit contains five-second films; V4 used eight.
            XCTAssertEqual(duration.seconds, 5, accuracy: 0.2, state)
            XCTAssertTrue(audio.isEmpty, "Supplied state clips must not alter call or music audio: \(state)")
        }
    }

    @MainActor func testSuppliedPostersRemainAvailableWithoutVideo() throws {
        for name in ["master", "darkmode"] + KnotAvatarResources.states {
            let image = try XCTUnwrap(UIImage(named: "KnotV4-" + name), "Missing master/poster: \(name)")
            XCTAssertGreaterThan(image.size.width * image.scale, 700)
            XCTAssertEqual(image.size.width, image.size.height, accuracy: 1)
        }
    }

    @MainActor func testOnlyTheActualSuppliedDanceIsAddressable() async throws {
        let url = try XCTUnwrap(KnotAvatarResources.film("dance-6"))
        let playable = try await AVURLAsset(url: url).load(.isPlayable)
        XCTAssertTrue(playable)
        XCTAssertNil(KnotAvatarResources.film("dance-1"))
        XCTAssertNil(KnotAvatarResources.film("call-dark"))
        XCTAssertNil(KnotAvatarResources.film("../anim-idle"))
    }
}
