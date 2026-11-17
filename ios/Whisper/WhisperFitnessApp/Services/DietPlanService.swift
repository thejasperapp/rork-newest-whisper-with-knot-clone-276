import Foundation

@Observable
class DietPlanService {
    var savedPlans: [WeeklyDietPlan] = []
    var isGenerating: Bool = false
    var generationError: String?
    var surveyResult: MacroSurveyResult?

    private let plansKey = "jasper_diet_plans"
    private let surveyKey = "jasper_macro_survey"


    init() {
        loadPlans()
        loadSurvey()
    }

    func generateDietPlan(survey: MacroSurveyResult) async -> WeeklyDietPlan? {
        isGenerating = true
        generationError = nil

        let allergiesText = survey.allergies.isEmpty ? "None" : survey.allergies.joined(separator: ", ")
        let notesText = survey.additionalNotes.isEmpty ? "None" : survey.additionalNotes

        let prompt = """
        You are a certified nutritionist AI. Create a detailed 7-day meal plan that PRECISELY hits these macronutrient targets. This must be scientifically accurate.

        TARGET MACROS (per day):
        - Calories: \(survey.targetCalories) kcal
        - Protein: \(Int(survey.targetProtein))g
        - Carbs: \(Int(survey.targetCarbs))g
        - Fat: \(Int(survey.targetFat))g

        USER PROFILE:
        - Age: \(survey.age), Gender: \(survey.gender.rawValue)
        - Weight: \(Int(survey.weightLbs)) lbs, Height: \(Int(survey.heightInches)) inches
        - Activity: \(survey.activityLevel.rawValue)
        - Goal: \(survey.goal.rawValue)
        - Diet: \(survey.dietaryPreference.rawValue)
        - Meals per day: \(survey.mealsPerDay)
        - Allergies: \(allergiesText)
        - Notes: \(notesText)

        CRITICAL RULES:
        1. Each day MUST have exactly \(survey.mealsPerDay) meals
        2. Daily totals MUST be within 50 calories of \(survey.targetCalories)
        3. Daily protein MUST be within 5g of \(Int(survey.targetProtein))g
        4. Daily carbs MUST be within 10g of \(Int(survey.targetCarbs))g
        5. Daily fat MUST be within 5g of \(Int(survey.targetFat))g
        6. Use real, common foods with accurate nutrition data
        7. Include variety — don't repeat the same meals across days
        8. Each meal needs realistic portion sizes and practical ingredients
        9. Include prep time estimates
        10. Respect dietary preference and allergies strictly

        Respond ONLY with a JSON object (no markdown, no code fences):
        {
          "planName": "descriptive plan name",
          "days": [
            {
              "day": "Monday",
              "meals": [
                {
                  "mealType": "Breakfast",
                  "name": "meal name",
                  "description": "brief appetizing description",
                  "ingredients": ["ingredient 1 with amount", "ingredient 2 with amount"],
                  "calories": 500,
                  "protein": 35.0,
                  "carbs": 45.0,
                  "fat": 18.0,
                  "prepTime": "10 min"
                }
              ]
            }
          ]
        }
        All number values must be numbers. 7 days required: Monday through Sunday.
        """

        var request = RorkAIProxy.chatRequest(timeout: 120)

        let body = OpenAIChatRequest(
            model: RorkAIProxy.chatModel,
            messages: [
                OpenAIChatMessage(role: "system", content: "You are a precise nutritionist. Always respond with valid JSON only. No markdown. No extra text."),
                OpenAIChatMessage(role: "user", content: prompt)
            ],
            max_tokens: 8000
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, httpResponse) = try await URLSession.shared.data(for: request)

            if let http = httpResponse as? HTTPURLResponse, http.statusCode != 200 {
                generationError = "Jasper couldn't generate your plan right now. Try again in a moment."
                isGenerating = false
                return nil
            }

            let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            guard let content = response.choices?.first?.message.content, !content.isEmpty else {
                generationError = "Empty response from Jasper. Please try again."
                isGenerating = false
                return nil
            }

            var cleaned = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let startIdx = cleaned.firstIndex(of: "{"),
               let endIdx = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[startIdx...endIdx])
            }

            guard let jsonData = cleaned.data(using: .utf8) else {
                generationError = "Failed to parse diet plan. Please try again."
                isGenerating = false
                return nil
            }

            let parsed = try JSONDecoder().decode(DietPlanAPIResponse.self, from: jsonData)

            let days = (parsed.days ?? []).map { dayResp in
                let meals = (dayResp.meals ?? []).map { m in
                    DietMeal(
                        mealType: m.mealType ?? "Meal",
                        name: m.name ?? "Untitled",
                        description: m.description ?? "",
                        ingredients: m.ingredients ?? [],
                        calories: m.calories ?? 0,
                        protein: m.protein ?? 0,
                        carbs: m.carbs ?? 0,
                        fat: m.fat ?? 0,
                        prepTime: m.prepTime ?? ""
                    )
                }
                return DailyDietPlan(dayName: dayResp.day ?? "Day", meals: meals)
            }

            let plan = WeeklyDietPlan(
                name: parsed.planName ?? "\(survey.goal.rawValue) Plan",
                targetCalories: survey.targetCalories,
                targetProtein: survey.targetProtein,
                targetCarbs: survey.targetCarbs,
                targetFat: survey.targetFat,
                dietaryPreference: survey.dietaryPreference,
                goal: survey.goal,
                days: days
            )

            isGenerating = false
            return plan
        } catch {
            generationError = "Something went wrong generating your plan. Please try again."
            isGenerating = false
            return nil
        }
    }

    func savePlan(_ plan: WeeklyDietPlan, changeNote: String? = nil) {
        // Replace any existing plan with the same id (edit) or insert new.
        if let idx = savedPlans.firstIndex(where: { $0.id == plan.id }) {
            savedPlans[idx] = plan
        } else {
            savedPlans.insert(plan, at: 0)
        }
        // Snapshot a version for Google Docs–style history. Skipped
        // automatically when the payload is byte-identical to the latest.
        PlanVersionHistoryService.shared.snapshot(
            plan: plan,
            planID: plan.id,
            kind: "diet",
            title: plan.name.isEmpty ? "Diet Plan" : plan.name,
            changeNote: changeNote
        )
        persistPlans()
    }

    /// Revert a plan in place to a previous snapshot. Used by the version
    /// history UI when the user taps "Revert to this version".
    func revertPlan(to snapshot: PlanVersionSnapshot) {
        guard let restored = PlanVersionHistoryService.shared.decode(snapshot, as: WeeklyDietPlan.self) else { return }
        if let idx = savedPlans.firstIndex(where: { $0.id == restored.id }) {
            savedPlans[idx] = restored
        } else {
            savedPlans.insert(restored, at: 0)
        }
        // Re-snapshot so the revert itself appears in history.
        PlanVersionHistoryService.shared.snapshot(
            plan: restored,
            planID: restored.id,
            kind: "diet",
            title: restored.name.isEmpty ? "Diet Plan" : restored.name,
            changeNote: "Reverted to \(snapshot.label)"
        )
        persistPlans()
    }

    func deletePlan(_ plan: WeeklyDietPlan) {
        savedPlans.removeAll { $0.id == plan.id }
        persistPlans()
    }

    func saveSurvey(_ survey: MacroSurveyResult) {
        surveyResult = survey
        if let data = try? JSONEncoder().encode(survey) {
            AccountStorage.set(data, forKey: surveyKey)
        }
        syncToCloud()
    }

    private func persistPlans() {
        if let data = try? JSONEncoder().encode(savedPlans) {
            AccountStorage.set(data, forKey: plansKey)
        }
        syncToCloud()
    }

    private func syncToCloud() {
        let userID = AccountStorage.currentUserID
        guard userID != "guest" else { return }
        Task {
            await CloudKitService.shared.saveUserDataBlob(userID: userID, key: "dietPlans", storageKey: plansKey)
            await CloudKitService.shared.saveUserDataBlob(userID: userID, key: "macroSurvey", storageKey: surveyKey)
        }
    }

    private func loadPlans() {
        if let data = AccountStorage.data(forKey: plansKey),
           let decoded = try? JSONDecoder().decode([WeeklyDietPlan].self, from: data) {
            savedPlans = decoded
        }
    }

    private func loadSurvey() {
        if let data = AccountStorage.data(forKey: surveyKey),
           let decoded = try? JSONDecoder().decode(MacroSurveyResult.self, from: data) {
            surveyResult = decoded
        }
    }
}
