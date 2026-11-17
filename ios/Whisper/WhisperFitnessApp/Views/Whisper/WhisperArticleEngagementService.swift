import Foundation
import SwiftUI

/// Local persistence for article engagement (likes and saves) until a backend
/// table is wired. Keeps the reader buttons working offline and consistent
/// across the same device.
@MainActor
@Observable
final class WhisperArticleEngagementService {
    static let shared = WhisperArticleEngagementService()

    private let likedKey = "whisper.article.likedIDs"
    private let savedKey = "whisper.article.savedIDs"

    private(set) var likedIDs: Set<String> = []
    private(set) var savedIDs: Set<String> = []

    private init() {
        likedIDs = Set(UserDefaults.standard.stringArray(forKey: likedKey) ?? [])
        savedIDs = Set(UserDefaults.standard.stringArray(forKey: savedKey) ?? [])
    }

    func isLiked(articleID: String) -> Bool {
        likedIDs.contains(articleID)
    }

    func isSaved(articleID: String) -> Bool {
        savedIDs.contains(articleID)
    }

    @discardableResult
    func toggleLike(articleID: String) -> Bool {
        let liked = likedIDs.contains(articleID)
        if liked {
            likedIDs.remove(articleID)
        } else {
            likedIDs.insert(articleID)
        }
        UserDefaults.standard.set(Array(likedIDs), forKey: likedKey)
        return !liked
    }

    @discardableResult
    func toggleSave(articleID: String) -> Bool {
        let saved = savedIDs.contains(articleID)
        if saved {
            savedIDs.remove(articleID)
        } else {
            savedIDs.insert(articleID)
        }
        UserDefaults.standard.set(Array(savedIDs), forKey: savedKey)
        return !saved
    }
}
