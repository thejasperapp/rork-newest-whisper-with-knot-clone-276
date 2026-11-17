import Foundation

/// This clone's verified Knot-only authority in both Debug and Release.
/// Authentication, billing, social data and generated configuration are unchanged.
nonisolated enum WhisperKnotBackend {
    static let identity = "mayokn2749ag072e3uvbh"
    static let origin = "https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app"
    // History sync separately gates retained snapshots at an authority change.
    static let syncRetainedHistory = true
}
