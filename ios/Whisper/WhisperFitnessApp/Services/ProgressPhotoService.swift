import Foundation
import SwiftUI

@Observable
class ProgressPhotoService {
    static let shared = ProgressPhotoService()

    var photos: [ProgressPhoto] = []

    private let storageKey = "progressPhotos"

    private init() {
        loadPhotos()
    }

    var photosByPose: [PhotoPose: [ProgressPhoto]] {
        Dictionary(grouping: photos, by: \.pose)
    }

    var latestByPose: [PhotoPose: ProgressPhoto] {
        var result: [PhotoPose: ProgressPhoto] = [:]
        for pose in PhotoPose.allCases {
            result[pose] = photos.filter { $0.pose == pose }.sorted { $0.date > $1.date }.first
        }
        return result
    }

    var uniqueDates: [Date] {
        let calendar = Calendar.current
        let days = Set(photos.map { calendar.startOfDay(for: $0.date) })
        return days.sorted(by: >)
    }

    func photosForDate(_ date: Date) -> [ProgressPhoto] {
        let calendar = Calendar.current
        return photos.filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.pose.rawValue < $1.pose.rawValue }
    }

    func addPhoto(_ photo: ProgressPhoto) {
        photos.append(photo)
        photos.sort { $0.date > $1.date }
        savePhotos()
    }

    func deletePhoto(_ photo: ProgressPhoto) {
        photos.removeAll { $0.id == photo.id }
        savePhotos()
    }

    func photoCount(for pose: PhotoPose) -> Int {
        photos.filter { $0.pose == pose }.count
    }

    var totalPhotoSets: Int {
        uniqueDates.count
    }

    var daysSinceFirstPhoto: Int? {
        guard let first = photos.sorted(by: { $0.date < $1.date }).first else { return nil }
        return Calendar.current.dateComponents([.day], from: first.date, to: Date()).day
    }

    private func savePhotos() {
        if let data = try? JSONEncoder().encode(photos) {
            AccountStorage.set(data, forKey: storageKey)
        }
    }

    private func loadPhotos() {
        guard let data = AccountStorage.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([ProgressPhoto].self, from: data) else {
            photos = []
            return
        }
        photos = saved.sorted { $0.date > $1.date }
    }

    /// Re-reads photos from `AccountStorage` for the currently signed-in
    /// user. Required because the singleton is created with `currentUserID =
    /// "guest"` at app launch — once a real account becomes active, callers
    /// must trigger a reload so the user-scoped photo set is hydrated.
    func reload() {
        loadPhotos()
    }
}
