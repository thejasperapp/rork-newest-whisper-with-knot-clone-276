import SwiftUI
import Supabase
import CoreImage.CIFilterBuiltins
import AVFoundation

/// QR application system for iOS. Recruiters generate a QR code that links
/// to their signup page. Leads scan the code → fill the applicant questionnaire
/// → responses are stored with the recruiter's ID → recruiter sees them in
/// real-time with position matching scores.
///
/// Mirrors the web `ApplicantQuestionnaire.tsx` + `RecruiterApplications.tsx`.
/// Uses the same Supabase tables: `whisper_applicant_questions`,
/// `whisper_applicant_responses`, `whisper_applicant_notes`.
struct WhisperQRApplicantView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var recruiterCode: String = ""
    @State private var qrImage: UIImage? = nil
    @State private var shareURL: String = ""
    @State private var generating: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        qrSection
                        shareSection
                        infoSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Recruiter QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await loadRecruiterCode() }
    }

    // MARK: - QR code section

    @ViewBuilder
    private var qrSection: some View {
        VStack(spacing: 12) {
            if let qr = qrImage {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: 220, height: 220)
                    .overlay {
                        if generating {
                            ProgressView()
                        } else {
                            Image(systemName: "qrcode")
                                .font(.system(size: 48))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
            }

            Text("Scan to apply")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))

            Text("Prospects scan this code with their camera to open your application form.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if !recruiterCode.isEmpty {
                Text("Code: \(recruiterCode)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Share section

    private var shareSection: some View {
        VStack(spacing: 10) {
            Text("Share your link")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))

            HStack {
                Text(shareURL)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(WhisperTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    UIPasteboard.general.string = shareURL
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Copy")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)

                ShareLink(item: shareURL) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Share")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                }
            }
        }
    }

    // MARK: - Info section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                Text("How it works")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }

            ForEach([
                "1. Prospect scans the QR code or opens your link",
                "2. They sign up on Whisper and fill the questionnaire",
                "3. You see their responses in real-time with position match scores",
                "4. Review, leave notes, and reach out to top matches"
            ], id: \.self) { step in
                Text(step)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    // MARK: - Logic

    private func loadRecruiterCode() async {
        guard let userID = SupabaseService.shared.client.auth.currentUser?.id.uuidString else { return }
        generating = true

        // Fetch the recruiter's referral code from whisper_referral_codes
        do {
            let data = try await SupabaseService.shared.client
                .from("whisper_referral_codes")
                .select("code")
                .eq("recruiter_id", value: userID)
                .single()
                .execute()
                .data
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["code"] as? String {
                recruiterCode = code
                shareURL = "https://mydailywhisper.com/auth?mode=signup&code=\(code)"
                qrImage = generateQRCode(from: shareURL)
            }
        } catch {
            print("[WhisperQR] error loading recruiter code: \(error)")
        }
        generating = false
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Applicant questionnaire view (for leads who scanned a code)

struct WhisperApplicantQuestionnaireView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let recruiterCode: String

    @State private var questions: [WhisperApplicantQuestion] = []
    @State private var answers: [String: String] = [:]
    @State private var submitting: Bool = false
    @State private var submitted: Bool = false
    @State private var loading: Bool = true

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()

                if loading {
                    ProgressView()
                        .tint(WhisperTheme.ink(colorScheme))
                } else if submitted {
                    submittedView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            header
                            ForEach(questions) { q in
                                questionCard(q)
                            }
                            submitButton
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task { await loadQuestions() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Application Form")
                .font(.title3.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Code: \(recruiterCode)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(WhisperTheme.card(colorScheme), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func questionCard(_ q: WhisperApplicantQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(q.question + (q.required ? " *" : ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))

            if q.question_type == "textarea" {
                TextField("Your answer", text: binding(for: q.id), axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
            } else if q.question_type == "select", let options = q.options {
                VStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            Haptics.tap()
                            answers[q.id] = option
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.subheadline)
                                Spacer()
                                if answers[q.id] == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(12)
                            .background(answers[q.id] == option ? Color.green.opacity(0.1) : WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(answers[q.id] == option ? Color.green.opacity(0.3) : WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                TextField("Your answer", text: binding(for: q.id))
                    .padding(12)
                    .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var submitButton: some View {
        Button {
            Haptics.tap()
            Task { await submit() }
        } label: {
            HStack {
                if submitting { ProgressView().tint(.white) }
                Text(submitting ? "Submitting…" : "Submit Application")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(allRequiredAnswered ? .green : Color.gray, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!allRequiredAnswered || submitting)
    }

    private var submittedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Application Submitted!")
                .font(.title3.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("The recruiter will review your responses and be in touch.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var allRequiredAnswered: Bool {
        questions.filter { $0.required }.allSatisfy { q in
            !(answers[q.id]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(get: { answers[id] ?? "" }, set: { answers[id] = $0 })
    }

    // MARK: - Data

    private func loadQuestions() async {
        do {
            let data = try await SupabaseService.shared.client
                .from("whisper_applicant_questions")
                .select("*")
                .eq("is_active", value: true)
                .order("display_order", ascending: true)
                .execute()
                .data
            questions = try JSONDecoder().decode([WhisperApplicantQuestion].self, from: data)
        } catch {
            print("[WhisperQR] error loading questions: \(error)")
        }
        loading = false
    }

    private func submit() async {
        await MainActor.run { submitting = true }

        let userID = SupabaseService.shared.client.auth.currentUser?.id.uuidString
        let email = SupabaseService.shared.client.auth.currentUser?.email

        var answerMap: [String: [String: String]] = [:]
        for q in questions {
            if let ans = answers[q.id], !ans.trimmingCharacters(in: .whitespaces).isEmpty {
                answerMap[q.id] = ["question": q.question, "answer": ans]
            }
        }

        var payload: [String: AnyJSON] = [
            "recruiter_code": .string(recruiterCode.uppercased()),
            "answers": AnyJSON.object(answerMap.mapValues { val in
                AnyJSON.object(val.mapValues { AnyJSON.string($0) })
            }),
            "status": .string("submitted")
        ]
        if let userID { payload["applicant_user_id"] = .string(userID) }
        if let email { payload["applicant_email"] = .string(email) }

        // Extract name from answers
        for q in questions {
            if q.question.lowercased().contains("full name"), let ans = answers[q.id] {
                payload["applicant_name"] = .string(ans)
            }
            if q.question.lowercased().contains("email"), let ans = answers[q.id] {
                payload["applicant_email"] = .string(ans)
            }
        }

        // Compute position match scores
        let match = WhisperApplicantScoring.computePositionMatch(answerMap)
        payload["best_position"] = .string(match.bestPosition)
        payload["position_scores"] = AnyJSON.object(match.positionScores.mapValues { AnyJSON.double($0) })
        payload["potential_score"] = .double(Double(match.potentialScore))
        payload["confidence_score"] = .double(Double(match.confidenceScore))

        do {
            _ = try await SupabaseService.shared.client
                .from("whisper_applicant_responses")
                .insert(payload)
                .execute()
            await MainActor.run { submitted = true }
        } catch {
            print("[WhisperQR] submit error: \(error)")
        }
        await MainActor.run { submitting = false }
    }

}

// MARK: - Position matching (mirrors web computePositionMatch; shared with
// the in-meeting live application capture)

nonisolated enum WhisperApplicantScoring {
    struct PositionMatch {
        let bestPosition: String
        let positionScores: [String: Double]
        let potentialScore: Int
        let confidenceScore: Int
    }

    static func computePositionMatch(_ answers: [String: [String: String]]) -> PositionMatch {
        let allText = answers.values
            .map { "\($0["question"] ?? "") \($0["answer"] ?? "")".lowercased() }
            .joined(separator: " ")

        var scores: [String: Double] = ["coach": 0, "athlete": 0, "creator": 0]

        let coachKeywords = ["coach", "train", "teach", "instruct", "certified", "client", "program", "guide", "mentor", "help other"]
        let coachHits = coachKeywords.filter { allText.contains($0) }.count
        scores["coach"] = Double(min(100, 30 + coachHits * 14))

        let athleteKeywords = ["compete", "competition", "sport", "elite", "athlete", "performance", "pr", "personal record", "meet", "race", "championship", "college", "scholarship"]
        let athleteHits = athleteKeywords.filter { allText.contains($0) }.count
        scores["athlete"] = Double(min(100, 25 + athleteHits * 12))

        let creatorKeywords = ["content", "social", "create", "video", "post", "instagram", "tiktok", "youtube", "blog", "photography", "edit", "audience", "follower", "brand"]
        let creatorHits = creatorKeywords.filter { allText.contains($0) }.count
        scores["creator"] = Double(min(100, 28 + creatorHits * 12))

        // Direct role selection boost
        for a in answers.values {
            let ans = (a["answer"] ?? "").lowercased()
            if ans.contains("coach") { scores["coach"]! += 20 }
            if ans.contains("athlete") { scores["athlete"]! += 20 }
            if ans.contains("creator") { scores["creator"]! += 20 }
        }
        for k in scores.keys { scores[k] = min(100, scores[k]!) }

        let sorted = scores.values.sorted(by: >)
        let bestPosition = scores.max(by: { $0.value < $1.value })?.key ?? "general"
        let potentialScore = Int(sorted.first! * 0.65 + sorted.dropFirst().first! * 0.35)
        let gap = sorted.first! - sorted.dropFirst().first!
        let confidenceScore = min(100, Int(40 + gap * 1.2))

        return PositionMatch(
            bestPosition: bestPosition,
            positionScores: scores,
            potentialScore: potentialScore,
            confidenceScore: confidenceScore
        )
    }
}

// MARK: - Models

nonisolated struct WhisperApplicantQuestion: Identifiable, Codable {
    let id: String
    let question: String
    let question_type: String
    let options: [String]?
    let required: Bool
    let display_order: Int
    let is_active: Bool

    enum CodingKeys: String, CodingKey {
        case id, question
        case question_type = "question_type"
        case options, required
        case display_order = "display_order"
        case is_active = "is_active"
    }
}
