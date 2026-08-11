//
//  WellnessHealthKitReader.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  按自然日聚合读取 HealthKit 数据,供运动回顾规则引擎使用。
//  数量型指标用 HKStatisticsCollectionQuery(系统自动处理多来源去重),
//  睡眠与锻炼用样本查询后本地归并。

import Foundation
import HealthKit

nonisolated final class WellnessHealthKitReader {
    private let healthStore = HKHealthStore()
    private let assemblyQueue = DispatchQueue(label: "com.ptrack.wellness-recap.assembly", qos: .userInitiated)

    /// 所有读写都限定在 assemblyQueue 上,串行安全。
    private final class SampleAccumulator: @unchecked Sendable {
        var samplesByDay: [Date: DailyWellnessSample] = [:]
    }

    private struct QuantitySpec {
        let identifier: HKQuantityTypeIdentifier
        let options: HKStatisticsOptions
        let unit: HKUnit
        let assign: @Sendable (inout DailyWellnessSample, Double) -> Void
    }

    private static let quantitySpecs: [QuantitySpec] = [
        QuantitySpec(identifier: .stepCount, options: .cumulativeSum, unit: .count()) {
            $0.stepCount = $1
        },
        QuantitySpec(identifier: .restingHeartRate, options: .discreteAverage, unit: HKUnit.count().unitDivided(by: .minute())) {
            $0.restingHeartRate = $1
        },
        QuantitySpec(identifier: .heartRateVariabilitySDNN, options: .discreteAverage, unit: .secondUnit(with: .milli)) {
            $0.hrvSDNN = $1
        },
        QuantitySpec(identifier: .activeEnergyBurned, options: .cumulativeSum, unit: .kilocalorie()) {
            $0.activeEnergyKilocalories = $1
        },
        QuantitySpec(identifier: .appleExerciseTime, options: .cumulativeSum, unit: .minute()) {
            $0.exerciseMinutes = $1
        },
        QuantitySpec(identifier: .timeInDaylight, options: .cumulativeSum, unit: .minute()) {
            $0.daylightMinutes = $1
        }
    ]

    /// 当前版本已用于分析的字段之外,一次性把后续分析会用到的字段也一并申请。
    /// HealthKit 的读授权只有一次好时机:用户拒绝或跳过后,很难再引导他回到设置里补授权,
    /// 所以这里按设计文档的字段清单一次问全,后续版本不再打扰用户。
    /// 明确不申请:心电、心律不齐、血压、血糖、血氧、跌倒风险等医疗类字段。
    private static let additionalQuantityIdentifiers: [HKQuantityTypeIdentifier] = [
        // 恢复与体能
        .vo2Max,
        .heartRate,
        .heartRateRecoveryOneMinute,
        .respiratoryRate,
        .appleSleepingWristTemperature,
        // 能量与身体指标
        .basalEnergyBurned,
        .bodyMass,
        // 日常活动
        .flightsClimbed,
        .appleStandTime,
        .distanceWalkingRunning,
        .distanceCycling,
        .walkingSpeed,
        .walkingStepLength,
        .physicalEffort,
        // 跑步动态
        .runningSpeed,
        .runningPower,
        .runningStrideLength,
        .runningVerticalOscillation,
        .runningGroundContactTime,
        // 骑行
        .cyclingPower,
        .cyclingCadence,
        .cyclingSpeed,
        // 机会型:用户本来就有记录时才会有数据
        .dietaryWater,
        .dietaryEnergyConsumed
    ]

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for spec in quantitySpecs {
            if let type = HKObjectType.quantityType(forIdentifier: spec.identifier) {
                types.insert(type)
            }
        }
        for identifier in additionalQuantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        for identifier in [HKCategoryTypeIdentifier.sleepAnalysis, .appleStandHour, .mindfulSession] {
            if let type = HKObjectType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if #available(iOS 18.0, *) {
            if let effortType = HKObjectType.quantityType(forIdentifier: .workoutEffortScore) {
                types.insert(effortType)
            }
        }
        return types
    }

    static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard Self.isHealthDataAvailable else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        healthStore.requestAuthorization(toShare: nil, read: Self.readTypes) { success, error in
            if let error {
                print("PTrack WellnessRecap: authorization failed: \(error)")
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    /// 拉取近 `dayCount` 天(含今天)的日聚合样本,按时间升序返回,主线程回调。
    func fetchDailySamples(dayCount: Int, completion: @escaping ([DailyWellnessSample]) -> Void) {
        guard Self.isHealthDataAvailable, dayCount > 0 else {
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: todayStart),
              let windowEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

        let accumulator = SampleAccumulator()
        var day = windowStart
        while day < windowEnd {
            accumulator.samplesByDay[day] = DailyWellnessSample(day: day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = next
        }

        let group = DispatchGroup()

        for spec in Self.quantitySpecs {
            guard let quantityType = HKObjectType.quantityType(forIdentifier: spec.identifier) else {
                continue
            }
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: spec.options,
                anchorDate: windowStart,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { [assemblyQueue] _, collection, _ in
                assemblyQueue.async {
                    defer {
                        group.leave()
                    }
                    guard let collection else {
                        return
                    }
                    collection.enumerateStatistics(from: windowStart, to: windowEnd) { statistics, _ in
                        let quantity = spec.options == .cumulativeSum
                            ? statistics.sumQuantity()
                            : statistics.averageQuantity()
                        guard let quantity else {
                            return
                        }
                        let dayKey = calendar.startOfDay(for: statistics.startDate)
                        if var sample = accumulator.samplesByDay[dayKey] {
                            spec.assign(&sample, quantity.doubleValue(for: spec.unit))
                            accumulator.samplesByDay[dayKey] = sample
                        }
                    }
                }
            }
            healthStore.execute(query)
        }

        // 睡眠:向前多取 1 天,保证今天凌晨结束的睡眠段完整。
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
           let sleepQueryStart = calendar.date(byAdding: .day, value: -1, to: windowStart) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: sleepQueryStart, end: windowEnd, options: [])
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { [assemblyQueue] _, samples, _ in
                assemblyQueue.async {
                    defer {
                        group.leave()
                    }
                    Self.mergeSleepSamples(
                        samples as? [HKCategorySample] ?? [],
                        into: accumulator,
                        calendar: calendar
                    )
                }
            }
            healthStore.execute(query)
        }

        group.enter()
        let workoutPredicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let workoutQuery = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: workoutPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [assemblyQueue] _, samples, _ in
            assemblyQueue.async {
                defer {
                    group.leave()
                }
                for workout in samples as? [HKWorkout] ?? [] {
                    let dayKey = calendar.startOfDay(for: workout.startDate)
                    guard var sample = accumulator.samplesByDay[dayKey] else {
                        continue
                    }
                    let minutes = workout.duration / 60
                    sample.workoutCount += 1
                    sample.workoutMinutes += minutes
                    sample.workoutLoad += minutes * Self.intensityFactor(for: workout.workoutActivityType)
                    if let distance = workout.totalDistance?.doubleValue(for: .meter()) {
                        sample.workoutDistanceMeters += distance
                    }
                    accumulator.samplesByDay[dayKey] = sample
                }
            }
        }
        healthStore.execute(workoutQuery)

        group.notify(queue: assemblyQueue) {
            let ordered = accumulator.samplesByDay.values.sorted { $0.day < $1.day }
            DispatchQueue.main.async {
                completion(ordered)
            }
        }
    }

    // MARK: - Sleep Merging

    nonisolated private static func mergeSleepSamples(
        _ samples: [HKCategorySample],
        into accumulator: SampleAccumulator,
        calendar: Calendar
    ) {
        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        guard !asleepSamples.isEmpty else {
            return
        }

        // 多来源(手表 + 第三方)会产生重叠段,优先取 Apple 来源;没有则全收。
        let appleSamples = asleepSamples.filter {
            $0.sourceRevision.source.bundleIdentifier.hasPrefix("com.apple.health")
        }
        let chosenSamples = appleSamples.isEmpty ? asleepSamples : appleSamples

        // 按"醒来所在的自然日"归属整晚睡眠。
        var intervalsByDay: [Date: [(start: Date, end: Date, isDeep: Bool)]] = [:]
        for sample in chosenSamples {
            let dayKey = calendar.startOfDay(for: sample.endDate)
            let isDeep = sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            intervalsByDay[dayKey, default: []].append((sample.startDate, sample.endDate, isDeep))
        }

        for (dayKey, intervals) in intervalsByDay {
            guard var sample = accumulator.samplesByDay[dayKey] else {
                continue
            }

            let sorted = intervals.sorted { $0.start < $1.start }
            // 合并重叠区间,得到无重复的总时长;同时切出各个"睡眠段"。
            // 中间断开超过 2 小时视为不同段(白天小睡不应污染夜间睡眠的中点)。
            var blocks: [(start: Date, end: Date, duration: TimeInterval)] = []
            var mergedDuration: TimeInterval = 0
            var currentStart = sorted[0].start
            var currentEnd = sorted[0].end
            var blockStart = sorted[0].start
            var blockDuration: TimeInterval = 0

            for interval in sorted.dropFirst() {
                if interval.start <= currentEnd {
                    currentEnd = max(currentEnd, interval.end)
                    continue
                }
                let segment = currentEnd.timeIntervalSince(currentStart)
                mergedDuration += segment
                blockDuration += segment
                if interval.start.timeIntervalSince(currentEnd) > 2 * 3600 {
                    blocks.append((blockStart, currentEnd, blockDuration))
                    blockStart = interval.start
                    blockDuration = 0
                }
                currentStart = interval.start
                currentEnd = interval.end
            }
            let lastSegment = currentEnd.timeIntervalSince(currentStart)
            mergedDuration += lastSegment
            blockDuration += lastSegment
            blocks.append((blockStart, currentEnd, blockDuration))

            // 深睡同样做重叠合并,避免多来源重复累加导致占比超过 100%。
            let deepIntervals = sorted.filter(\.isDeep)
            var deepDuration: TimeInterval = 0
            if let first = deepIntervals.first {
                var deepStart = first.start
                var deepEnd = first.end
                for interval in deepIntervals.dropFirst() {
                    if interval.start <= deepEnd {
                        deepEnd = max(deepEnd, interval.end)
                    } else {
                        deepDuration += deepEnd.timeIntervalSince(deepStart)
                        deepStart = interval.start
                        deepEnd = interval.end
                    }
                }
                deepDuration += deepEnd.timeIntervalSince(deepStart)
            }

            // 入睡时刻与中点取时长最长的那一段(通常就是夜间主睡眠)。
            let mainBlock = blocks.max { $0.duration < $1.duration } ?? blocks[0]
            let midnight = dayKey
            let midpoint = mainBlock.start
                .addingTimeInterval(mainBlock.end.timeIntervalSince(mainBlock.start) / 2)

            sample.sleepDurationMinutes = mergedDuration / 60
            sample.sleepStartMinutes = mainBlock.start.timeIntervalSince(midnight) / 60
            sample.sleepMidpointMinutes = midpoint.timeIntervalSince(midnight) / 60
            sample.deepSleepMinutes = deepDuration > 0 ? deepDuration / 60 : sample.deepSleepMinutes
            accumulator.samplesByDay[dayKey] = sample
        }
    }

    // MARK: - Load

    nonisolated private static func intensityFactor(for activityType: HKWorkoutActivityType) -> Double {
        switch activityType {
        case .running, .swimming:
            return 1.2
        case .highIntensityIntervalTraining:
            return 1.3
        case .hiking, .stairClimbing:
            return 1.1
        case .walking:
            return 0.7
        default:
            return 1.0
        }
    }
}
