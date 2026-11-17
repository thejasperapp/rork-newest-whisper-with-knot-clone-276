import Foundation
import HealthKit
import WidgetKit

@Observable
@MainActor
class HealthKitService {
    var isAuthorized = false
    var summary = DailyHealthSummary.empty
    var recentWorkouts: [WorkoutData] = []
    var sleepAnalysisData: SleepAnalysis = .empty
    var weeklySleepData: [DailySleepSummary] = []
    var weeklySummary: WeeklyHealthSummary = .empty

    private let healthStore = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func enableBackgroundDelivery() {
        guard isAvailable, observerQueries.isEmpty else { return }
        let types: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .heartRate, .appleExerciseTime]
        for typeId in types {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeId) else { continue }
            healthStore.enableBackgroundDelivery(for: quantityType, frequency: .immediate) { _, _ in }
            let query = HKObserverQuery(sampleType: quantityType, predicate: nil) { [weak self] _, completionHandler, _ in
                Task { @MainActor [weak self] in
                    await self?.fetchAllData()
                }
                completionHandler()
            }
            healthStore.execute(query)
            observerQueries.append(query)
        }
    }

    func requestAuthorization() async {
        guard isAvailable else { return }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .appleStandTime)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .environmentalAudioExposure)!,
            HKObjectType.quantityType(forIdentifier: .appleMoveTime)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.workoutType()
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            await fetchAllData()
        } catch {
            isAuthorized = false
        }
    }

    @ObservationIgnored private var fullRefreshTask: Task<Void, Never>?

    func fetchAllData() async {
        if let fullRefreshTask { await fullRefreshTask.value; return }
        let task = Task { await loadAllData() }
        fullRefreshTask = task
        await task.value
        if fullRefreshTask == task { fullRefreshTask = nil }
    }

    private func loadAllData() async {
        async let steps = fetchTodaySum(for: .stepCount, unit: .count())
        async let calories = fetchTodayDoubleSum(for: .activeEnergyBurned, unit: .kilocalorie())
        async let basalEnergy = fetchTodayDoubleSum(for: .basalEnergyBurned, unit: .kilocalorie())
        async let activeMin = fetchTodaySum(for: .appleExerciseTime, unit: .minute())
        async let hr = fetchLatestQuantity(for: .heartRate, unit: HKUnit(from: "count/min"))
        async let restingHR = fetchLatestQuantity(for: .restingHeartRate, unit: HKUnit(from: "count/min"))
        async let walkingHR = fetchLatestQuantity(for: .walkingHeartRateAverage, unit: HKUnit(from: "count/min"))
        async let hrv = fetchLatestQuantity(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let dist = fetchTodayDoubleSum(for: .distanceWalkingRunning, unit: .mile())
        async let cyclingDist = fetchTodayDoubleSum(for: .distanceCycling, unit: .mile())
        async let flights = fetchTodaySum(for: .flightsClimbed, unit: .count())
        async let standTime = fetchTodaySum(for: .appleStandTime, unit: .minute())
        async let vo2 = fetchLatestQuantity(for: .vo2Max, unit: HKUnit(from: "ml/kg*min"))
        async let respRate = fetchLatestQuantity(for: .respiratoryRate, unit: HKUnit(from: "count/min"))
        async let bloodO2 = fetchLatestQuantity(for: .oxygenSaturation, unit: .percent())
        async let bodyMass = fetchLatestQuantity(for: .bodyMass, unit: .pound())
        async let bodyFat = fetchLatestQuantity(for: .bodyFatPercentage, unit: .percent())
        async let audioExposure = fetchLatestQuantity(for: .environmentalAudioExposure, unit: .decibelAWeightedSoundPressureLevel())
        async let sleep = fetchSleepHours()
        async let mindful = fetchMindfulMinutes()
        async let workouts = fetchWorkouts()

        summary.steps = await steps
        summary.calories = await calories
        summary.basalEnergyBurned = await basalEnergy
        summary.activeMinutes = await activeMin
        summary.heartRate = await hr
        summary.restingHeartRate = await restingHR
        summary.walkingHeartRateAverage = await walkingHR
        summary.heartRateVariability = await hrv
        summary.distance = await dist
        summary.cyclingDistance = await cyclingDist
        summary.flightsClimbed = await flights
        summary.standHours = await standTime / 60
        summary.vo2Max = await vo2
        summary.respiratoryRate = await respRate
        summary.bloodOxygen = await bloodO2 * 100
        summary.bodyMass = await bodyMass
        summary.bodyFatPercentage = await bodyFat * 100
        summary.environmentalAudioExposure = await audioExposure
        summary.sleepHours = await sleep
        summary.mindfulMinutes = await mindful
        recentWorkouts = await workouts
        summary.workouts = recentWorkouts
        syncToWidget()
        await syncSleepScoreToWidget()
    }

    private func syncToWidget() {
        guard let shared = UserDefaults(suiteName: "group.com.mydailywhisper.whisper") else { return }
        shared.set(summary.sleepHours, forKey: "widget_sleepHours")
        shared.set(summary.steps, forKey: "widget_steps")
        shared.set(Int(summary.heartRate), forKey: "widget_heartRate")
        shared.set(Int(summary.calories), forKey: "widget_calories")
        shared.set(summary.activeMinutes, forKey: "widget_activeMinutes")
        shared.set(summary.bodyMass, forKey: "shared_bodyMass")
        shared.set(Int(summary.flightsClimbed), forKey: "shared_flights")
        shared.set(summary.mindfulMinutes, forKey: "shared_mindfulMinutes")
        shared.synchronize()

        // Compute & sync readiness + stress for the watch
        let hrv = summary.heartRateVariability
        let rhr = summary.restingHeartRate > 0 ? summary.restingHeartRate : summary.heartRate
        let hrvBaseline: Double = 45
        let rhrBaseline: Double = 65
        let hrvComp: Int = hrv > 0 ? min(100, Int(min(hrv / hrvBaseline, 1.5) * 70 + 10)) : 60
        let rhrComp: Int = rhr > 0 ? min(100, Int(rhrBaseline / max(rhr, 40) * 70 + 10)) : 65
        let sleepComp: Int = summary.sleepHours > 0 ? min(100, Int(summary.sleepHours / 8.0 * 100)) : 55
        let actComp: Int = summary.activeMinutes > 0 ? (summary.activeMinutes > 90 ? 50 : (summary.activeMinutes > 45 ? 70 : 100)) : 70
        let readiness = max(10, min(100, Int(Double(hrvComp) * 0.30 + Double(rhrComp) * 0.20 + Double(sleepComp) * 0.30 + Double(actComp) * 0.20)))
        shared.set(readiness, forKey: "widget_readinessScore")

        var stressFromHRV: Double = 45
        if hrv > 0 {
            stressFromHRV = max(5, min(95, 100 - (hrv / 50.0 * 55)))
        }
        let stressFromRHR: Double = rhr > 0 ? max(5, min(95, (rhr - 50) * 1.5 + 30)) : 45
        let stress = max(5, min(95, Int(stressFromHRV * 0.6 + stressFromRHR * 0.4)))
        shared.set(stress, forKey: "widget_stressScore")
        shared.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func syncSleepScoreToWidget() async {
        let analysis = await fetchSleepAnalysis()
        sleepAnalysisData = analysis
        weeklySleepData = await fetchWeeklySleepData()
        weeklySummary = await fetchWeeklySummary()
        guard let shared = UserDefaults(suiteName: "group.com.mydailywhisper.whisper") else { return }
        shared.set(analysis.sleepScore, forKey: "widget_sleepScore")
        if let bedTime = analysis.bedTime {
            shared.set(bedTime.timeIntervalSince1970, forKey: "widget_bedTime")
        }
        if let wakeTime = analysis.wakeTime {
            shared.set(wakeTime.timeIntervalSince1970, forKey: "widget_wakeTime")
        }
        shared.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func value(for metric: HealthMetricType) -> String {
        let s = summary
        switch metric {
        case .heartRate: return s.heartRate > 0 ? "\(Int(s.heartRate))" : "--"
        case .restingHeartRate: return s.restingHeartRate > 0 ? "\(Int(s.restingHeartRate))" : "--"
        case .steps: return "\(s.steps)"
        case .sleep: return String(format: "%.1f", s.sleepHours)
        case .distance: return String(format: "%.2f", s.distance)
        case .calories: return "\(Int(s.calories))"
        case .activeMinutes: return "\(s.activeMinutes)"
        case .vo2Max: return s.vo2Max > 0 ? String(format: "%.1f", s.vo2Max) : "--"
        case .respiratoryRate: return s.respiratoryRate > 0 ? String(format: "%.0f", s.respiratoryRate) : "--"
        case .bloodOxygen: return s.bloodOxygen > 0 ? String(format: "%.0f", s.bloodOxygen) : "--"
        case .bodyMass: return s.bodyMass > 0 ? String(format: "%.1f", s.bodyMass) : "--"
        case .bodyFatPercentage: return s.bodyFatPercentage > 0 ? String(format: "%.1f", s.bodyFatPercentage) : "--"
        case .flightsClimbed: return "\(s.flightsClimbed)"
        case .standHours: return "\(s.standHours)"
        case .mindfulMinutes: return "\(s.mindfulMinutes)"
        case .cyclingDistance: return String(format: "%.2f", s.cyclingDistance)
        case .heartRateVariability: return s.heartRateVariability > 0 ? String(format: "%.0f", s.heartRateVariability) : "--"
        case .basalEnergy: return "\(Int(s.basalEnergyBurned))"
        case .walkingHeartRate: return s.walkingHeartRateAverage > 0 ? "\(Int(s.walkingHeartRateAverage))" : "--"
        case .audioExposure: return s.environmentalAudioExposure > 0 ? String(format: "%.0f", s.environmentalAudioExposure) : "--"
        }
    }

    func status(for metric: HealthMetricType) -> (text: String, color: String) {
        let s = summary
        switch metric {
        case .heartRate:
            if s.heartRate <= 0 { return ("No data", "secondary") }
            if s.heartRate < 60 { return ("Low", "blue") }
            if s.heartRate <= 100 { return ("Normal", "green") }
            return ("Elevated", "orange")
        case .restingHeartRate:
            if s.restingHeartRate <= 0 { return ("No data", "secondary") }
            if s.restingHeartRate < 60 { return ("Athletic", "green") }
            if s.restingHeartRate <= 80 { return ("Normal", "green") }
            return ("Elevated", "orange")
        case .steps:
            if s.steps >= 10000 { return ("Goal reached!", "green") }
            if s.steps >= 5000 { return ("On track", "blue") }
            return ("Keep moving", "orange")
        case .sleep:
            if s.sleepHours >= 7 { return ("Well rested", "green") }
            if s.sleepHours >= 5 { return ("Fair", "yellow") }
            if s.sleepHours > 0 { return ("Needs improvement", "orange") }
            return ("No data", "secondary")
        case .distance:
            if s.distance >= 3 { return ("Active day", "green") }
            if s.distance >= 1 { return ("Moderate", "blue") }
            return ("Low activity", "orange")
        case .calories:
            if s.calories >= 500 { return ("Great burn", "green") }
            if s.calories >= 200 { return ("On pace", "blue") }
            return ("Getting started", "orange")
        case .activeMinutes:
            if s.activeMinutes >= 30 { return ("Goal met", "green") }
            if s.activeMinutes >= 15 { return ("Keep going", "blue") }
            return ("Get moving", "orange")
        case .vo2Max:
            if s.vo2Max <= 0 { return ("No data", "secondary") }
            if s.vo2Max >= 40 { return ("Above average", "green") }
            if s.vo2Max >= 30 { return ("Average", "blue") }
            return ("Below average", "orange")
        case .bloodOxygen:
            if s.bloodOxygen <= 0 { return ("No data", "secondary") }
            if s.bloodOxygen >= 95 { return ("Normal", "green") }
            return ("Low", "red")
        case .bodyMass:
            return s.bodyMass > 0 ? ("Recorded", "green") : ("No data", "secondary")
        case .bodyFatPercentage:
            return s.bodyFatPercentage > 0 ? ("Recorded", "green") : ("No data", "secondary")
        case .flightsClimbed:
            if s.flightsClimbed >= 10 { return ("Great effort", "green") }
            return ("Today's flights", "blue")
        case .standHours:
            if s.standHours >= 12 { return ("Goal met", "green") }
            return ("\(12 - s.standHours) more to go", "blue")
        case .heartRateVariability:
            if s.heartRateVariability <= 0 { return ("No data", "secondary") }
            if s.heartRateVariability >= 50 { return ("Good recovery", "green") }
            return ("Moderate", "blue")
        case .respiratoryRate:
            if s.respiratoryRate <= 0 { return ("No data", "secondary") }
            if s.respiratoryRate >= 12 && s.respiratoryRate <= 20 { return ("Normal", "green") }
            return ("Check reading", "orange")
        case .mindfulMinutes:
            if s.mindfulMinutes >= 10 { return ("Centered", "green") }
            return ("Take a moment", "blue")
        case .cyclingDistance:
            return s.cyclingDistance > 0 ? ("Active", "green") : ("No rides today", "secondary")
        case .basalEnergy:
            return s.basalEnergyBurned > 0 ? ("Burning", "green") : ("Calculating", "secondary")
        case .walkingHeartRate:
            if s.walkingHeartRateAverage <= 0 { return ("No data", "secondary") }
            if s.walkingHeartRateAverage < 100 { return ("Normal", "green") }
            return ("Elevated", "orange")
        case .audioExposure:
            if s.environmentalAudioExposure <= 0 { return ("No data", "secondary") }
            if s.environmentalAudioExposure < 80 { return ("Safe", "green") }
            return ("Loud", "orange")
        }
    }

    /// Most recent heart-rate sample today (bpm) — streams live vitals into
    /// coach calls. Returns 0 when HealthKit has no fresh reading.
    func latestHeartRate() async -> Double {
        guard isAvailable else { return 0 }
        return await fetchLatestQuantity(for: .heartRate, unit: HKUnit(from: "count/min"))
    }

    private func fetchLatestQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func fetchTodayDoubleSum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                guard let sum = result?.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func fetchSleepHours() async -> Double {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let sleepWindowStart = calendar.date(byAdding: .hour, value: -6, to: todayStart)!

        let predicate = HKQuery.predicateForSamples(withStart: sleepWindowStart, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                let asleep = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                }
                let totalSeconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            healthStore.execute(query)
        }
    }

    func fetchSleepAnalysis() async -> SleepAnalysis {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return .empty }
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let sleepWindowStart = calendar.date(byAdding: .hour, value: -6, to: todayStart)!

        let predicate = HKQuery.predicateForSamples(withStart: sleepWindowStart, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: .empty)
                    return
                }

                var stages: [SleepStageEntry] = []
                var remDuration: TimeInterval = 0
                var coreDuration: TimeInterval = 0
                var deepDuration: TimeInterval = 0
                var awakeDuration: TimeInterval = 0
                var totalSleepDuration: TimeInterval = 0
                var bedTime: Date?
                var wakeTime: Date?

                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ]

                for sample in samples {
                    let stageType: SleepStageType?
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        stageType = .rem
                        remDuration += sample.endDate.timeIntervalSince(sample.startDate)
                        totalSleepDuration += sample.endDate.timeIntervalSince(sample.startDate)
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        stageType = .core
                        coreDuration += sample.endDate.timeIntervalSince(sample.startDate)
                        totalSleepDuration += sample.endDate.timeIntervalSince(sample.startDate)
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        stageType = .deep
                        deepDuration += sample.endDate.timeIntervalSince(sample.startDate)
                        totalSleepDuration += sample.endDate.timeIntervalSince(sample.startDate)
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        stageType = .core
                        coreDuration += sample.endDate.timeIntervalSince(sample.startDate)
                        totalSleepDuration += sample.endDate.timeIntervalSince(sample.startDate)
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        stageType = .awake
                        awakeDuration += sample.endDate.timeIntervalSince(sample.startDate)
                    default:
                        stageType = nil
                    }

                    if let st = stageType {
                        stages.append(SleepStageEntry(stage: st, startDate: sample.startDate, endDate: sample.endDate))
                    }

                    if asleepValues.contains(sample.value) {
                        if bedTime == nil || sample.startDate < bedTime! {
                            bedTime = sample.startDate
                        }
                        if wakeTime == nil || sample.endDate > wakeTime! {
                            wakeTime = sample.endDate
                        }
                    }
                }

                let analysis = SleepAnalysis(
                    stages: stages,
                    bedTime: bedTime,
                    wakeTime: wakeTime,
                    totalSleepDuration: totalSleepDuration,
                    remDuration: remDuration,
                    coreDuration: coreDuration,
                    deepDuration: deepDuration,
                    awakeDuration: awakeDuration
                )
                continuation.resume(returning: analysis)
            }
            healthStore.execute(query)
        }
    }

    private func fetchMindfulMinutes() async -> Int {
        guard let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return 0 }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                let totalSeconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: Int(totalSeconds / 60.0))
            }
            healthStore.execute(query)
        }
    }

    private func fetchWorkouts() async -> [WorkoutData] {
        let now = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 20, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }
                let mapped = workouts.map { workout in
                    WorkoutData(
                        type: workout.workoutActivityType.displayName,
                        duration: workout.duration,
                        calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                        date: workout.startDate,
                        icon: workout.workoutActivityType.sfSymbol
                    )
                }
                continuation.resume(returning: mapped)
            }
            healthStore.execute(query)
        }
    }

    private func fetchTodaySum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                guard let sum = result?.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: Int(sum.doubleValue(for: unit)))
            }
            healthStore.execute(query)
        }
    }

    func fetchWeeklySleepData() async -> [DailySleepSummary] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let calendar = Calendar.current
        let now = Date()
        var results: [DailySleepSummary] = []

        for dayOffset in 0..<7 {
            let wakeDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: now)!)
            let sleepWindowStart = calendar.date(byAdding: .hour, value: -6, to: wakeDay)!
            let sleepWindowEnd = calendar.date(byAdding: .hour, value: 18, to: wakeDay)!

            let predicate = HKQuery.predicateForSamples(withStart: sleepWindowStart, end: sleepWindowEnd, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let analysis: SleepAnalysis = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                    guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                        continuation.resume(returning: .empty)
                        return
                    }
                    continuation.resume(returning: self.parseSleepSamples(samples))
                }
                healthStore.execute(query)
            }
            results.append(DailySleepSummary(date: wakeDay, analysis: analysis))
        }
        return results.reversed()
    }

    private nonisolated func parseSleepSamples(_ samples: [HKCategorySample]) -> SleepAnalysis {
        var stages: [SleepStageEntry] = []
        var remDuration: TimeInterval = 0
        var coreDuration: TimeInterval = 0
        var deepDuration: TimeInterval = 0
        var awakeDuration: TimeInterval = 0
        var totalSleepDuration: TimeInterval = 0
        var bedTime: Date?
        var wakeTime: Date?

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]

        for sample in samples {
            let stageType: SleepStageType?
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                stageType = .rem
                remDuration += sample.endDate.timeIntervalSince(sample.startDate)
                totalSleepDuration += sample.endDate.timeIntervalSince(sample.startDate)
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                stageType = .core
                coreDuration += sample.endDate.timeIntervalSince(sample.startDate)
                totalSleepDuration += sample.endDate.timeIntervalSince(sample.startDate)
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                stageType = .deep
                deepDuration += sample.endDate.timeIntervalSince(sample.startDate)
                totalSleepDuration += sample.endDate.timeIntervalSince(sample.startDate)
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                stageType = .core
                coreDuration += sample.endDate.timeIntervalSince(sample.startDate)
                totalSleepDuration += sample.endDate.timeIntervalSince(sample.startDate)
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                stageType = .awake
                awakeDuration += sample.endDate.timeIntervalSince(sample.startDate)
            default:
                stageType = nil
            }

            if let st = stageType {
                stages.append(SleepStageEntry(stage: st, startDate: sample.startDate, endDate: sample.endDate))
            }

            if asleepValues.contains(sample.value) {
                if bedTime == nil || sample.startDate < bedTime! {
                    bedTime = sample.startDate
                }
                if wakeTime == nil || sample.endDate > wakeTime! {
                    wakeTime = sample.endDate
                }
            }
        }

        return SleepAnalysis(
            stages: stages, bedTime: bedTime, wakeTime: wakeTime,
            totalSleepDuration: totalSleepDuration, remDuration: remDuration,
            coreDuration: coreDuration, deepDuration: deepDuration, awakeDuration: awakeDuration
        )
    }

    func fetchWeeklySummary() async -> WeeklyHealthSummary {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!

        var dailySteps: [Int] = []
        var dailyCalories: [Double] = []
        var heartRates: [Double] = []
        var restingHRs: [Double] = []
        var hrvValues: [Double] = []
        var totalActiveMin = 0
        var totalDist = 0.0

        for dayOffset in 0..<7 {
            let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: now)!)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let steps = await fetchSumForRange(for: .stepCount, unit: .count(), start: dayStart, end: dayEnd)
            dailySteps.append(Int(steps))

            let cal = await fetchSumForRange(for: .activeEnergyBurned, unit: .kilocalorie(), start: dayStart, end: dayEnd)
            dailyCalories.append(cal)

            let hr = await fetchAvgForRange(for: .heartRate, unit: HKUnit(from: "count/min"), start: dayStart, end: dayEnd)
            if hr > 0 { heartRates.append(hr) }

            let rhr = await fetchAvgForRange(for: .restingHeartRate, unit: HKUnit(from: "count/min"), start: dayStart, end: dayEnd)
            if rhr > 0 { restingHRs.append(rhr) }

            let hrv = await fetchAvgForRange(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: dayStart, end: dayEnd)
            if hrv > 0 { hrvValues.append(hrv) }

            let activeMin = await fetchSumForRange(for: .appleExerciseTime, unit: .minute(), start: dayStart, end: dayEnd)
            totalActiveMin += Int(activeMin)

            let dist = await fetchSumForRange(for: .distanceWalkingRunning, unit: .mile(), start: dayStart, end: dayEnd)
            totalDist += dist
        }

        let sleepData = weeklySleepData
        let validSleep = sleepData.filter { $0.analysis.totalSleepDuration > 0 }
        let avgSleepHours = validSleep.isEmpty ? 0 : validSleep.reduce(0.0) { $0 + $1.analysis.totalSleepDuration / 3600.0 } / Double(validSleep.count)
        let avgSleepScore = validSleep.isEmpty ? 0 : validSleep.reduce(0) { $0 + $1.analysis.sleepScore } / validSleep.count
        let bestSleep = validSleep.max(by: { $0.analysis.sleepScore < $1.analysis.sleepScore })?.date
        let worstSleep = validSleep.min(by: { $0.analysis.sleepScore < $1.analysis.sleepScore })?.date

        return WeeklyHealthSummary(
            startDate: weekAgo, endDate: now,
            avgSteps: dailySteps.isEmpty ? 0 : dailySteps.reduce(0, +) / dailySteps.count,
            totalSteps: dailySteps.reduce(0, +),
            avgCalories: dailyCalories.isEmpty ? 0 : dailyCalories.reduce(0, +) / Double(dailyCalories.count),
            totalCalories: dailyCalories.reduce(0, +),
            avgSleepHours: avgSleepHours,
            avgHeartRate: heartRates.isEmpty ? 0 : heartRates.reduce(0, +) / Double(heartRates.count),
            avgRestingHR: restingHRs.isEmpty ? 0 : restingHRs.reduce(0, +) / Double(restingHRs.count),
            avgHRV: hrvValues.isEmpty ? 0 : hrvValues.reduce(0, +) / Double(hrvValues.count),
            totalActiveMinutes: totalActiveMin,
            totalDistance: totalDist,
            totalWorkouts: recentWorkouts.count,
            avgSleepScore: avgSleepScore,
            dailySleep: sleepData,
            bestSleepDay: bestSleep,
            worstSleepDay: worstSleep
        )
    }

    func fetchDailySum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        return await fetchSumForRange(for: identifier, unit: unit, start: start, end: end)
    }

    func fetchDailyAvg(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        return await fetchAvgForRange(for: identifier, unit: unit, start: start, end: end)
    }

    func fetchHistoricalDailyAverages(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let now = Date()
        var results: [(date: Date, value: Double)] = []
        for dayOffset in 0..<days {
            let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: now)!)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let value = await fetchAvgForRange(for: identifier, unit: unit, start: dayStart, end: dayEnd)
            results.append((date: dayStart, value: value))
        }
        return results.reversed()
    }

    func fetchHistoricalDailySums(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let now = Date()
        var results: [(date: Date, value: Double)] = []
        for dayOffset in 0..<days {
            let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: now)!)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let value = await fetchSumForRange(for: identifier, unit: unit, start: dayStart, end: dayEnd)
            results.append((date: dayStart, value: value))
        }
        return results.reversed()
    }

    func fetchHourlySamples(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, date: Date) async -> [(hour: Int, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let currentHour = calendar.component(.hour, from: Date())
        let isToday = calendar.isDateInToday(date)
        let maxHour = isToday ? currentHour : 23

        var results: [(hour: Int, value: Double)] = []
        for hour in 0...maxHour {
            let hourStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay)!
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart)!
            let value = await fetchAvgForRange(for: identifier, unit: unit, start: hourStart, end: hourEnd)
            results.append((hour: hour, value: value))
        }
        return results
    }

    func fetchHistoricalSleepHours(days: Int) async -> [(date: Date, hours: Double)] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let calendar = Calendar.current
        let now = Date()
        var results: [(date: Date, hours: Double)] = []

        for dayOffset in 0..<days {
            let wakeDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: now)!)
            let sleepWindowStart = calendar.date(byAdding: .hour, value: -6, to: wakeDay)!
            let sleepWindowEnd = calendar.date(byAdding: .hour, value: 18, to: wakeDay)!
            let predicate = HKQuery.predicateForSamples(withStart: sleepWindowStart, end: sleepWindowEnd, options: .strictStartDate)

            let hours: Double = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                    guard let samples = samples as? [HKCategorySample] else {
                        continuation.resume(returning: 0)
                        return
                    }
                    let asleep = samples.filter {
                        $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                        $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                        $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                        $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    }
                    let totalSeconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                    continuation.resume(returning: totalSeconds / 3600.0)
                }
                healthStore.execute(query)
            }
            results.append((date: wakeDay, hours: hours))
        }
        return results.reversed()
    }

    func fetchHistoricalActiveMinutes(days: Int) async -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let now = Date()
        var results: [(date: Date, minutes: Int)] = []
        for dayOffset in 0..<days {
            let dayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -dayOffset, to: now)!)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let value = await fetchSumForRange(for: .appleExerciseTime, unit: .minute(), start: dayStart, end: dayEnd)
            results.append((date: dayStart, minutes: Int(value)))
        }
        return results.reversed()
    }

    private func fetchSumForRange(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                guard let sum = result?.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func fetchAvgForRange(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                guard let avg = result?.averageQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: avg.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    func saveWorkoutToHealthKit(session: WorkoutSessionRecord) async {
        guard isAvailable else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = workoutActivityType(for: session.focus)
        config.locationType = .indoor

        let startDate = session.date.addingTimeInterval(-session.duration)
        let endDate = session.date

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())

        do {
            try await builder.beginCollection(at: startDate)

            if session.caloriesBurned > 0,
               let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: session.caloriesBurned)
                let energySample = HKQuantitySample(
                    type: energyType,
                    quantity: energyQuantity,
                    start: startDate,
                    end: endDate
                )
                try await builder.addSamples([energySample])
            }

            try await builder.endCollection(at: endDate)
            try await builder.finishWorkout()
        } catch {}
    }

    private func workoutActivityType(for focus: String) -> HKWorkoutActivityType {
        let f = focus.lowercased()
        if f.contains("chest") || f.contains("back") || f.contains("leg") || f.contains("arm") || f.contains("shoulder") || f.contains("strength") || f.contains("push") || f.contains("pull") {
            return .traditionalStrengthTraining
        } else if f.contains("cardio") || f.contains("hiit") {
            return .highIntensityIntervalTraining
        } else if f.contains("yoga") || f.contains("stretch") || f.contains("mobility") {
            return .yoga
        } else if f.contains("run") {
            return .running
        } else if f.contains("cycle") || f.contains("bike") {
            return .cycling
        }
        return .functionalStrengthTraining
    }

    func detailedHealthContext() async -> String {
        let s = summary
        let sleep = sleepAnalysisData
        let weekly = weeklySummary

        var ctx = """
        === TODAY'S HEALTH DATA ===
        Steps: \(s.steps)
        Active Energy: \(Int(s.calories)) kcal
        Resting Energy: \(Int(s.basalEnergyBurned)) kcal
        Heart Rate: \(Int(s.heartRate)) BPM
        Resting HR: \(Int(s.restingHeartRate)) BPM
        Walking Avg HR: \(Int(s.walkingHeartRateAverage)) BPM
        HRV: \(Int(s.heartRateVariability)) ms
        VO2 Max: \(String(format: "%.1f", s.vo2Max)) mL/kg/min
        Blood Oxygen: \(String(format: "%.0f", s.bloodOxygen))%
        Respiratory Rate: \(String(format: "%.0f", s.respiratoryRate)) br/min
        Body Mass: \(String(format: "%.1f", s.bodyMass)) lbs
        Body Fat: \(String(format: "%.1f", s.bodyFatPercentage))%
        Distance: \(String(format: "%.2f", s.distance)) miles
        Flights Climbed: \(s.flightsClimbed)
        Stand Hours: \(s.standHours)
        Active Minutes: \(s.activeMinutes) min
        Mindful Minutes: \(s.mindfulMinutes)

        === LAST NIGHT'S SLEEP ===
        Sleep Score: \(sleep.sleepScore)/100
        Total Sleep: \(String(format: "%.1f", sleep.totalSleepDuration / 3600.0)) hours
        REM: \(String(format: "%.1f", sleep.remDuration / 60)) min (\(Int(sleep.remPercentage))%)
        Core: \(String(format: "%.1f", sleep.coreDuration / 60)) min (\(Int(sleep.corePercentage))%)
        Deep: \(String(format: "%.1f", sleep.deepDuration / 60)) min (\(Int(sleep.deepPercentage))%)
        Awake: \(String(format: "%.1f", sleep.awakeDuration / 60)) min
        """

        if let bed = sleep.bedTime {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            ctx += "\nBedtime: \(f.string(from: bed))"
        }
        if let wake = sleep.wakeTime {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            ctx += "\nWake Time: \(f.string(from: wake))"
        }

        if !sleep.stages.isEmpty {
            ctx += "\n\n=== SLEEP STAGE TIMELINE ==="
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            for stage in sleep.stages {
                ctx += "\n\(f.string(from: stage.startDate)) - \(f.string(from: stage.endDate)): \(stage.stage.displayName) (\(Int(stage.duration / 60)) min)"
            }
        }

        ctx += """


        === WEEKLY AVERAGES ===
        Avg Steps: \(weekly.avgSteps)/day
        Avg Calories: \(Int(weekly.avgCalories)) kcal/day
        Avg Sleep: \(String(format: "%.1f", weekly.avgSleepHours)) hours/night
        Avg Sleep Score: \(weekly.avgSleepScore)/100
        Avg Heart Rate: \(Int(weekly.avgHeartRate)) BPM
        Avg Resting HR: \(Int(weekly.avgRestingHR)) BPM
        Avg HRV: \(Int(weekly.avgHRV)) ms
        Total Active Minutes: \(weekly.totalActiveMinutes) min
        Total Distance: \(String(format: "%.1f", weekly.totalDistance)) miles
        Total Workouts: \(weekly.totalWorkouts)
        """

        return ctx
    }
}

extension HKWorkoutActivityType {
    nonisolated var displayName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength"
        case .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .pilates: return "Pilates"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stairs"
        case .hiking: return "Hiking"
        case .dance: return "Dance"
        default: return "Workout"
        }
    }

    nonisolated var sfSymbol: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .yoga: return "figure.yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "dumbbell.fill"
        case .highIntensityIntervalTraining: return "flame.fill"
        case .pilates: return "figure.pilates"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rowing"
        case .stairClimbing: return "figure.stair.stepper"
        case .hiking: return "figure.hiking"
        case .dance: return "figure.dance"
        default: return "figure.mixed.cardio"
        }
    }
}
