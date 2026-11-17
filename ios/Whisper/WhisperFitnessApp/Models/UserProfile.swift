import Foundation
import CloudKit

nonisolated struct UserProfile: Codable, Sendable {
    var userID: String
    var email: String?
    var displayName: String?
    var givenName: String?
    var familyName: String?
    var authProvider: AuthProvider
    var isProUser: Bool
    var joinDate: Date
    var lastSyncDate: Date?
    var gender: Gender?
    var weightLbs: Double?
    var heightInches: Double?
    var dateOfBirth: Date?
    var fitnessGoal: FitnessGoal?
    var activityLevel: ActivityLevel?
    var profileImageURL: String?
    var hasCompletedProfileSetup: Bool = false
    /// The user's chosen handle. Picked once during sign-up, stored on the
    /// profile row (and mirrored in `public.usernames` for uniqueness checks).
    var username: String?
    /// Blue checkmark — toggled manually from the Supabase dashboard.
    var isVerified: Bool = false
    /// Gold checkmark — toggled manually from the Supabase dashboard.
    var isModerator: Bool = false
    /// Gradient checkmark — owner / founder. Toggled manually from Supabase.
    var isOwner: Bool = false
    /// Apple StoreKit product identifier of the active subscription (e.g.
    /// `jaspermax` or `jaspermax_yearly`). Nil when the user is on the free tier.
    var activeSubscriptionProductID: String?
    /// Expiry of the active subscription, in epoch seconds. Synced from
    /// StoreKit `Transaction.expirationDate`.
    var subscriptionExpiresAt: Date?
    var profileImageInitial: String {
        if let first = displayName?.first ?? givenName?.first {
            return String(first).uppercased()
        }
        return "J"
    }

    var formattedName: String {
        if let name = displayName, !name.isEmpty {
            return name
        }
        if let given = givenName {
            if let family = familyName {
                return "\(given) \(family)"
            }
            return given
        }
        return "Whisper User"
    }

    nonisolated enum AuthProvider: String, Codable, Sendable {
        case apple
        case google
        case email
        case none
    }

    nonisolated enum Gender: String, Codable, Sendable, CaseIterable {
        case male = "Male"
        case female = "Female"
    }

    nonisolated enum FitnessGoal: String, Codable, Sendable, CaseIterable {
        case loseWeight = "Lose Weight"
        case buildMuscle = "Build Muscle"
        case improveEndurance = "Improve Endurance"
        case stayActive = "Stay Active"
        case flexibility = "Flexibility & Recovery"
    }

    nonisolated enum ActivityLevel: String, Codable, Sendable, CaseIterable {
        case sedentary = "Sedentary"
        case lightlyActive = "Lightly Active"
        case moderatelyActive = "Moderately Active"
        case veryActive = "Very Active"
    }

    var isFemale: Bool {
        gender == .female
    }

    static let guest = UserProfile(
        userID: "guest",
        email: nil,
        displayName: nil,
        givenName: nil,
        familyName: nil,
        authProvider: .none,
        isProUser: true,
        joinDate: Date(),
        gender: nil,
        weightLbs: nil,
        heightInches: nil,
        dateOfBirth: nil,
        fitnessGoal: nil,
        activityLevel: nil,
        profileImageURL: nil,
        hasCompletedProfileSetup: false,
        username: nil,
        isVerified: false,
        isModerator: false,
        isOwner: false,
        activeSubscriptionProductID: nil,
        subscriptionExpiresAt: nil
    )
}

extension UserProfile {
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "UserProfile")
        record["userID"] = userID as CKRecordValue
        record["email"] = (email ?? "") as CKRecordValue
        record["displayName"] = (displayName ?? "") as CKRecordValue
        record["givenName"] = (givenName ?? "") as CKRecordValue
        record["familyName"] = (familyName ?? "") as CKRecordValue
        record["authProvider"] = authProvider.rawValue as CKRecordValue
        record["isProUser"] = (isProUser ? 1 : 0) as CKRecordValue
        record["joinDate"] = joinDate as CKRecordValue
        return record
    }

    static func from(record: CKRecord) -> UserProfile? {
        guard let userID = record["userID"] as? String else { return nil }
        let genderRaw = record["gender"] as? String ?? ""
        let goalRaw = record["fitnessGoal"] as? String ?? ""
        let activityRaw = record["activityLevel"] as? String ?? ""
        let weight = record["weightLbs"] as? Double
        let height = record["heightInches"] as? Double
        let imgURL = record["profileImageURL"] as? String
        return UserProfile(
            userID: userID,
            email: record["email"] as? String,
            displayName: record["displayName"] as? String,
            givenName: record["givenName"] as? String,
            familyName: record["familyName"] as? String,
            authProvider: AuthProvider(rawValue: record["authProvider"] as? String ?? "none") ?? .none,
            isProUser: (record["isProUser"] as? Int ?? 0) == 1,
            joinDate: record["joinDate"] as? Date ?? Date(),
            lastSyncDate: record.modificationDate,
            gender: genderRaw.isEmpty ? nil : Gender(rawValue: genderRaw),
            weightLbs: (weight ?? 0) > 0 ? weight : nil,
            heightInches: (height ?? 0) > 0 ? height : nil,
            dateOfBirth: record["dateOfBirth"] as? Date,
            fitnessGoal: goalRaw.isEmpty ? nil : FitnessGoal(rawValue: goalRaw),
            activityLevel: activityRaw.isEmpty ? nil : ActivityLevel(rawValue: activityRaw),
            profileImageURL: (imgURL?.isEmpty == false) ? imgURL : nil,
            hasCompletedProfileSetup: (record["hasCompletedProfileSetup"] as? Int ?? 0) == 1
        )
    }

    var hasCompletedOnboardingFromCloud: Bool {
        hasCompletedProfileSetup
    }
}
