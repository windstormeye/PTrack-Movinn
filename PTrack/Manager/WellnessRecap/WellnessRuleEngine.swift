//
//  WellnessRuleEngine.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  确定性规则引擎:输入日聚合样本与时间范围,输出结构化的指导报告
//  (段落 / 指标表 / 趋势图 / 建议块)。
//  - 短周期(3 天 / 一周):判断基准 = 前 28 天个人基线;
//  - 长周期(月 / 半年 / 年):判断基准 = 上一个等长周期;
//  - 覆盖率不足的规则不触发;未记录 ≠ 0;文案不下医疗结论。

import Foundation

nonisolated enum WellnessRuleEngine {
    private struct SleepBaseline {
        let medianDuration: Double
        let medianStart: Double
        let sigmaDuration: Double
    }

    /// 一个周期的聚合画像,长短周期通用。
    private struct PeriodProfile {
        let sleepMean: Double?
        let sleepCoverage: Int
        let stepsMean: Double?
        let stepsCoverage: Int
        let exerciseTotal: Double
        let workoutCount: Int
        let workoutMinutes: Double
        let distanceMeters: Double
        let loadMeanPerDay: Double
        let restingHeartRateMean: Double?
        let hrvMean: Double?
        let maxSingleDistanceMeters: Double
        let dayCount: Int
    }

    // MARK: - Entry

    static func makeReport(
        samples: [DailyWellnessSample],
        range: WellnessRecapRange,
        periodID: String,
        languageCode: String
    ) -> WellnessRecapReport {
        let evaluationDays = range.evaluationDays
        let current = Array(samples.suffix(evaluationDays))
        let previous = Array(samples.dropLast(evaluationDays).suffix(evaluationDays))
        let baselineWindow = Array(samples.dropLast(evaluationDays).suffix(28))

        let currentProfile = profile(of: current)
        let referenceProfile = profile(of: range.isLongTerm ? previous : baselineWindow)

        let advices: [RecapAdvice]
        if range.isLongTerm {
            advices = longTermAdvices(
                current: currentProfile,
                previous: referenceProfile,
                samples: current,
                range: range
            )
        } else {
            advices = shortTermAdvices(
                recent: current,
                baselineWindow: baselineWindow,
                samples: samples,
                range: range
            )
        }
        let selected = decorate(select(advices), periodID: periodID)
        let summary = makeSummary(advices: selected, hasFacts: currentProfile.sleepCoverage > 0 || currentProfile.stepsCoverage > 0 || currentProfile.workoutCount > 0)

        var blocks: [RecapBlock] = []
        blocks.append(.paragraph(summary))

        // 指标表:本期 vs 常态/上期。
        let tableRows = makeMetricRows(current: currentProfile, reference: referenceProfile)
        if tableRows.count >= 2 {
            blocks.append(.heading(AppLocalization.text(.wellnessSectionFacts)))
            blocks.append(.metricTable(tableRows))
        } else {
            let facts = makeFactLines(currentProfile)
            if !facts.isEmpty {
                blocks.append(.heading(AppLocalization.text(.wellnessSectionFacts)))
                for fact in facts {
                    blocks.append(.paragraph(fact))
                }
            } else {
                blocks.append(.paragraph(AppLocalization.text(.wellnessEmptyBody)))
            }
        }

        // 趋势图。
        let charts = makeCharts(current: current, reference: referenceProfile, range: range)
        if !charts.isEmpty {
            blocks.append(.heading(AppLocalization.text(.wellnessSectionTrends)))
            for chart in charts {
                blocks.append(.chart(chart))
            }
        }

        // 建议放在最后:先让数据和趋势铺开,再给结论。
        if !selected.isEmpty {
            blocks.append(.heading(AppLocalization.text(.wellnessSectionAdvice)))
            for advice in selected {
                blocks.append(.advice(advice))
            }
        }

        // 免责声明不作为内容块,由页面固定在底部展示。
        return WellnessRecapReport(
            periodID: periodID,
            range: range,
            generatedAt: Date(),
            languageCode: languageCode,
            summary: summary,
            blocks: blocks
        )
    }

    // MARK: - Profile

    private static func profile(of samples: [DailyWellnessSample]) -> PeriodProfile {
        let sleepValues = samples.compactMap(\.sleepDurationMinutes)
        let stepValues = samples.compactMap(\.stepCount)
        let rhrValues = samples.compactMap(\.restingHeartRate)
        let hrvValues = samples.compactMap(\.hrvSDNN)
        return PeriodProfile(
            sleepMean: WellnessBaseline.mean(sleepValues),
            sleepCoverage: sleepValues.count,
            stepsMean: WellnessBaseline.mean(stepValues),
            stepsCoverage: stepValues.count,
            exerciseTotal: samples.compactMap(\.exerciseMinutes).reduce(0, +),
            workoutCount: samples.reduce(0) { $0 + $1.workoutCount },
            workoutMinutes: samples.reduce(0.0) { $0 + $1.workoutMinutes },
            distanceMeters: samples.reduce(0.0) { $0 + $1.workoutDistanceMeters },
            loadMeanPerDay: samples.isEmpty ? 0 : samples.map(\.workoutLoad).reduce(0, +) / Double(samples.count),
            restingHeartRateMean: WellnessBaseline.mean(rhrValues),
            hrvMean: WellnessBaseline.mean(hrvValues),
            maxSingleDistanceMeters: samples.map(\.workoutDistanceMeters).max() ?? 0,
            dayCount: samples.count
        )
    }

    // MARK: - Metric Table

    private static func makeMetricRows(
        current: PeriodProfile,
        reference: PeriodProfile
    ) -> [RecapMetricRow] {
        var rows: [RecapMetricRow] = []

        func addRow(
            nameKey: AppTextKey,
            current currentValue: Double?,
            reference referenceValue: Double?,
            format: (Double) -> String,
            higherIsBetter: Bool?
        ) {
            guard let currentValue else {
                return
            }
            guard let referenceValue, referenceValue > 0 else {
                rows.append(RecapMetricRow(
                    name: AppLocalization.text(nameKey),
                    current: format(currentValue),
                    reference: "—",
                    delta: "—",
                    deltaDirection: 0
                ))
                return
            }
            let change = (currentValue - referenceValue) / referenceValue
            let deltaText: String
            if abs(change) < 0.02 {
                deltaText = "≈"
            } else {
                deltaText = String(format: "%@%.0f%%", change > 0 ? "+" : "−", abs(change) * 100)
            }
            var direction = 0
            if let higherIsBetter, abs(change) >= 0.05 {
                direction = (change > 0) == higherIsBetter ? 1 : -1
            }
            rows.append(RecapMetricRow(
                name: AppLocalization.text(nameKey),
                current: format(currentValue),
                reference: format(referenceValue),
                delta: deltaText,
                deltaDirection: direction
            ))
        }

        addRow(
            nameKey: .wellnessMetricSleep,
            current: current.sleepMean,
            reference: reference.sleepMean,
            format: { String(format: "%.1fh", $0 / 60) },
            higherIsBetter: true
        )
        addRow(
            nameKey: .wellnessMetricSteps,
            current: current.stepsMean,
            reference: reference.stepsMean,
            format: { groupedNumber($0) },
            higherIsBetter: true
        )
        addRow(
            nameKey: .wellnessMetricExercise,
            current: current.exerciseTotal > 0 ? current.exerciseTotal : nil,
            reference: reference.exerciseTotal > 0 ? reference.exerciseTotal * scaleFactor(current: current, reference: reference) : nil,
            format: { "\(Int($0.rounded()))min" },
            higherIsBetter: true
        )
        addRow(
            nameKey: .wellnessMetricWorkouts,
            current: current.workoutCount > 0 ? Double(current.workoutCount) : nil,
            reference: reference.workoutCount > 0 ? Double(reference.workoutCount) * scaleFactor(current: current, reference: reference) : nil,
            format: { String(Int($0.rounded())) },
            higherIsBetter: true
        )
        addRow(
            nameKey: .wellnessMetricDistance,
            current: current.distanceMeters > 0 ? current.distanceMeters / 1000 : nil,
            reference: reference.distanceMeters > 0 ? reference.distanceMeters / 1000 * scaleFactor(current: current, reference: reference) : nil,
            format: { String(format: "%.1fkm", $0) },
            higherIsBetter: true
        )
        addRow(
            nameKey: .wellnessMetricRHR,
            current: current.restingHeartRateMean,
            reference: reference.restingHeartRateMean,
            format: { "\(Int($0.rounded()))bpm" },
            higherIsBetter: false
        )
        addRow(
            nameKey: .wellnessMetricHRV,
            current: current.hrvMean,
            reference: reference.hrvMean,
            format: { "\(Int($0.rounded()))ms" },
            higherIsBetter: true
        )
        return rows
    }

    /// 参考期与本期天数不同(短周期基线 28 天 vs 评估 3/7 天)时,总量类指标按天数换算。
    private static func scaleFactor(current: PeriodProfile, reference: PeriodProfile) -> Double {
        guard reference.dayCount > 0 else {
            return 1
        }
        return Double(current.dayCount) / Double(reference.dayCount)
    }

    // MARK: - Charts

    private static func makeCharts(
        current: [DailyWellnessSample],
        reference: PeriodProfile,
        range: WellnessRecapRange
    ) -> [RecapChartData] {
        var charts: [RecapChartData] = []

        let sleepPoints = bucketedPoints(
            samples: current,
            granularity: range.chartGranularity,
            value: { $0.sleepDurationMinutes.map { $0 / 60 } },
            aggregate: .mean
        )
        if sleepPoints.contains(where: { $0.value != nil }) {
            charts.append(RecapChartData(
                title: AppLocalization.text(.wellnessChartSleep),
                points: sleepPoints,
                baseline: reference.sleepMean.map { $0 / 60 }
            ))
        }

        let stepPoints = bucketedPoints(
            samples: current,
            granularity: range.chartGranularity,
            value: { $0.stepCount },
            aggregate: .mean
        )
        if stepPoints.contains(where: { $0.value != nil }) {
            charts.append(RecapChartData(
                title: AppLocalization.text(.wellnessChartSteps),
                points: stepPoints,
                baseline: reference.stepsMean
            ))
        }

        let loadPoints = bucketedPoints(
            samples: current,
            granularity: range.chartGranularity,
            value: { $0.workoutLoad > 0 ? $0.workoutLoad : nil },
            aggregate: .meanTreatingNilAsZero
        )
        if loadPoints.contains(where: { ($0.value ?? 0) > 0 }) {
            charts.append(RecapChartData(
                title: AppLocalization.text(.wellnessChartLoad),
                points: loadPoints,
                baseline: reference.loadMeanPerDay > 0 ? reference.loadMeanPerDay : nil
            ))
        }

        return charts
    }

    private enum BucketAggregate {
        case mean
        case meanTreatingNilAsZero
    }

    private static func bucketedPoints(
        samples: [DailyWellnessSample],
        granularity: WellnessRecapRange.ChartGranularity,
        value: (DailyWellnessSample) -> Double?,
        aggregate: BucketAggregate
    ) -> [RecapChartPoint] {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.setLocalizedDateFormatFromTemplate("Md")
        let monthFormatter = DateFormatter()
        monthFormatter.setLocalizedDateFormatFromTemplate("M")

        func aggregateBucket(_ bucket: [DailyWellnessSample]) -> Double? {
            switch aggregate {
            case .mean:
                return WellnessBaseline.mean(bucket.compactMap(value))
            case .meanTreatingNilAsZero:
                guard !bucket.isEmpty else {
                    return nil
                }
                return bucket.map { value($0) ?? 0 }.reduce(0, +) / Double(bucket.count)
            }
        }

        switch granularity {
        case .daily:
            return samples.map { sample in
                RecapChartPoint(label: dayFormatter.string(from: sample.day), value: value(sample))
            }
        case .weekly:
            var points: [RecapChartPoint] = []
            var index = 0
            while index < samples.count {
                let bucket = Array(samples[index..<min(index + 7, samples.count)])
                points.append(RecapChartPoint(
                    label: dayFormatter.string(from: bucket[0].day),
                    value: aggregateBucket(bucket)
                ))
                index += 7
            }
            return points
        case .monthly:
            var buckets: [(month: Date, samples: [DailyWellnessSample])] = []
            for sample in samples {
                let components = calendar.dateComponents([.year, .month], from: sample.day)
                guard let monthStart = calendar.date(from: components) else {
                    continue
                }
                if let lastIndex = buckets.indices.last, buckets[lastIndex].month == monthStart {
                    buckets[lastIndex].samples.append(sample)
                } else {
                    buckets.append((monthStart, [sample]))
                }
            }
            return buckets.map { bucket in
                RecapChartPoint(
                    label: monthFormatter.string(from: bucket.month),
                    value: aggregateBucket(bucket.samples)
                )
            }
        }
    }

    // MARK: - Variants

    /// 每条建议末尾追加一句同类别的补充提示,按"周期 + 规则标题"确定性轮换:
    /// 同一份报告内容稳定,但随着周期推进会换新,避免长期看到完全相同的文案。
    private static func decorate(_ advices: [RecapAdvice], periodID: String) -> [RecapAdvice] {
        let periodSeed = stableHash(periodID)
        return advices.map { advice in
            let pool = tipPool(for: advice.category)
            guard !pool.isEmpty else {
                return advice
            }
            let index = Int((periodSeed &+ stableHash(advice.title)) % UInt64(pool.count))
            var decorated = advice
            decorated.tip = AppLocalization.text(pool[index])
            return decorated
        }
    }

    private static func tipPool(for category: RecapAdviceCategory) -> [AppTextKey] {
        switch category {
        case .sleep:
            return [.wellnessTipSleep1, .wellnessTipSleep2, .wellnessTipSleep3, .wellnessTipSleep4, .wellnessTipSleep5]
        case .activity:
            return [.wellnessTipActivity1, .wellnessTipActivity2, .wellnessTipActivity3, .wellnessTipActivity4, .wellnessTipActivity5]
        case .nutrition:
            return [.wellnessTipNutrition1, .wellnessTipNutrition2, .wellnessTipNutrition3, .wellnessTipNutrition4, .wellnessTipNutrition5]
        case .recovery, .risk:
            return [.wellnessTipRecovery1, .wellnessTipRecovery2, .wellnessTipRecovery3, .wellnessTipRecovery4]
        case .positive:
            return [.wellnessTipPositive1, .wellnessTipPositive2, .wellnessTipPositive3, .wellnessTipPositive4]
        }
    }

    /// 跨进程稳定的哈希(Swift 的 String.hashValue 每次启动都会变)。
    /// 返回 UInt64,调用方全程在无符号域内做加法取模,避免溢出成负数。
    private static func stableHash(_ value: String) -> UInt64 {
        var result: UInt64 = 5381
        for scalar in value.unicodeScalars {
            result = (result &* 33) &+ UInt64(scalar.value)
        }
        return result
    }

    // MARK: - Selection & Summary

    /// 先保证每个维度至少出现一条(轮转选取),再按分数补足到上限,
    /// 让睡眠 / 运动 / 饮食 / 恢复各维度都能看到内容。
    private static func select(_ advices: [RecapAdvice]) -> [RecapAdvice] {
        let risks = advices.filter { $0.category == .risk }.sorted { $0.score > $1.score }
        var pools: [RecapAdviceCategory: [RecapAdvice]] = [:]
        for advice in advices where advice.category != .risk {
            pools[advice.category, default: []].append(advice)
        }
        pools = pools.mapValues { $0.sorted { $0.score > $1.score } }

        let dimensionOrder: [RecapAdviceCategory] = [.sleep, .activity, .nutrition, .recovery, .positive]
        var selected = risks
        let limit = 10
        let perCategoryLimit = 3

        // 逐轮从各维度取一条,保证覆盖面。
        for round in 0..<perCategoryLimit {
            for category in dimensionOrder {
                guard selected.count < limit else {
                    break
                }
                guard let pool = pools[category], pool.count > round else {
                    continue
                }
                selected.append(pool[round])
            }
        }

        return selected.sorted { lhs, rhs in
            lhs.priority == rhs.priority ? lhs.score > rhs.score : lhs.priority < rhs.priority
        }
    }

    private static func makeSummary(advices: [RecapAdvice], hasFacts: Bool) -> String {
        if !hasFacts {
            return AppLocalization.text(.wellnessSummaryCold)
        }
        if advices.contains(where: { $0.category == .risk }) {
            return AppLocalization.text(.wellnessSummaryRisk)
        }
        if advices.contains(where: { $0.category != .positive }) {
            return AppLocalization.text(.wellnessSummaryAttention)
        }
        return AppLocalization.text(.wellnessSummaryGood)
    }

    private static func makeFactLines(_ profile: PeriodProfile) -> [String] {
        var facts: [String] = []
        if let sleepMean = profile.sleepMean {
            facts.append(AppLocalization.format(.wellnessFactSleepFormat, String(format: "%.1f", sleepMean / 60), profile.sleepCoverage))
        }
        if let stepsMean = profile.stepsMean {
            facts.append(AppLocalization.format(.wellnessFactStepsFormat, groupedNumber(stepsMean)))
        }
        if profile.workoutCount > 0 {
            facts.append(AppLocalization.format(
                .wellnessFactWorkoutsFormat,
                profile.workoutCount,
                String(format: "%.1f", profile.distanceMeters / 1000),
                Int(profile.workoutMinutes.rounded())
            ))
        }
        return facts
    }

    // MARK: - Short-Term Rules(3 天 / 一周)

    private static func shortTermAdvices(
        recent: [DailyWellnessSample],
        baselineWindow: [DailyWellnessSample],
        samples: [DailyWellnessSample],
        range: WellnessRecapRange
    ) -> [RecapAdvice] {
        var advices: [RecapAdvice] = []
        let sleepBaseline = makeSleepBaseline(baselineWindow)
        let minimumCoverage = max(2, Int((Double(recent.count) * 0.7).rounded()))

        if range == .threeDays {
            // 三天视角:只谈"接下来 24–48 小时怎么办",不做趋势判断。
            if let advice = tonightBedtimeAdvice(recent: recent, baseline: sleepBaseline) {
                advices.append(advice)
            }
            if let advice = midpointLateAdvice(recent: recent, baselineWindow: baselineWindow) {
                advices.append(advice)
            }
            if let advice = recoveryAdvice(recent: recent, baselineWindow: baselineWindow) {
                advices.append(advice)
            }
            if let advice = hrvHighAdvice(recent: recent, baselineWindow: baselineWindow) {
                advices.append(advice)
            }
            if let advice = workoutGapAdvice(samples: samples) {
                advices.append(advice)
            }
            if let advice = workoutStreakAdvice(samples: samples) {
                advices.append(advice)
            }
        } else {
            // 一周视角:谈本周的结构与节奏。
            if let advice = sleepDebtAdvice(recent: recent, baseline: sleepBaseline, minimumCoverage: minimumCoverage) {
                advices.append(advice)
            }
            if let advice = sleepIrregularAdvice(recent: recent, baseline: sleepBaseline, minimumCoverage: minimumCoverage) {
                advices.append(advice)
            }
            if let advice = sleepShortAdvice(recent: recent, baseline: sleepBaseline, minimumCoverage: minimumCoverage) {
                advices.append(advice)
            }
            if let advice = weekendJetlagAdvice(recent: recent) {
                advices.append(advice)
            }
            if let advice = sleepStableAdvice(recent: recent, baseline: sleepBaseline) {
                advices.append(advice)
            }
            if let advice = deepSleepAdvice(recent: recent) {
                advices.append(advice)
            }
            if let advice = daylightAdvice(recent: recent) {
                advices.append(advice)
            }
            // 负荷规则用近 7 天(ACWR 的定义窗口)。
            let lastSeven = Array(samples.suffix(7))
            let loadBaseline = Array(samples.dropLast(7).suffix(28))
            if let advice = loadSpikeAdvice(recent: lastSeven, baselineWindow: loadBaseline) {
                advices.append(advice)
            }
            if let advice = loadDropAdvice(recent: lastSeven, baselineWindow: loadBaseline) {
                advices.append(advice)
            }
            if let advice = sedentaryAdvice(recent: recent, baselineWindow: baselineWindow) {
                advices.append(advice)
            }
            if let advice = activeWeekAdvice(recent: recent) {
                advices.append(advice)
            }
            if let advice = restingHeartRateImprovedAdvice(recent: recent, baselineWindow: baselineWindow) {
                advices.append(advice)
            }
            if let advice = stepsConsistentAdvice(recent: recent, baselineWindow: baselineWindow) {
                advices.append(advice)
            }
        }

        advices.append(contentsOf: nutritionAdvices(recent: recent, range: range))
        return advices
    }

    /// 三天视角专属:结合昨晚缺口与近期负荷,给出今晚的具体上床时刻。
    private static func tonightBedtimeAdvice(
        recent: [DailyWellnessSample],
        baseline: SleepBaseline?
    ) -> RecapAdvice? {
        guard let baseline,
              let lastNight = recent.last(where: { $0.sleepDurationMinutes != nil }),
              let lastNightDuration = lastNight.sleepDurationMinutes else {
            return nil
        }
        let deficit = max(0, baseline.medianDuration - lastNightDuration)
        let recentLoad = recent.map(\.workoutLoad).reduce(0, +)
        let loadBonus = recentLoad >= 120 ? 15.0 : 0
        let advance = min(deficit * 0.5 + loadBonus, 60)
        guard advance >= 10 else {
            return nil
        }
        let bedtime = clockText(baseline.medianStart - advance)
        return RecapAdvice(
            category: .sleep,
            priority: 1,
            evidence: AppLocalization.format(
                .wellnessAdviceTonightEvidence,
                String(format: "%.1f", lastNightDuration / 60),
                String(format: "%.1f", baseline.medianDuration / 60)
            ),
            title: AppLocalization.text(.wellnessAdviceTonightTitle),
            body: AppLocalization.format(.wellnessAdviceTonightBody, bedtime, Int(advance.rounded())),
            score: 2.2
        )
    }

    // MARK: - Nutrition Rules(饮食维度)

    /// 饮食建议只依赖当期客观事实,给区间不给处方,不涉及减重、疾病饮食或补剂。
    /// 三天窗口给"下一顿/今晚"的即时补给;一周窗口给结构性安排。
    private static func nutritionAdvices(
        recent: [DailyWellnessSample],
        range: WellnessRecapRange
    ) -> [RecapAdvice] {
        var advices: [RecapAdvice] = []
        let isImmediate = range == .threeDays

        let enduranceDays = recent.filter { $0.workoutMinutes >= 60 }
        let totalWorkoutMinutes = recent.reduce(0.0) { $0 + $1.workoutMinutes }
        let energyValues = recent.compactMap(\.activeEnergyKilocalories)
        let peakEnergy = energyValues.max() ?? 0

        // 1. 耐力日的碳水补充:三天窗口聚焦最近一次,一周窗口讲整体。
        if let longestMinutes = enduranceDays.map(\.workoutMinutes).max() {
            advices.append(RecapAdvice(
                category: .nutrition,
                priority: 2,
                evidence: isImmediate
                    ? AppLocalization.format(.wellnessAdviceCarbNowEvidence, Int(longestMinutes.rounded()))
                    : AppLocalization.format(
                        .wellnessAdviceCarbEvidence,
                        enduranceDays.count,
                        Int(longestMinutes.rounded())
                    ),
                title: AppLocalization.text(isImmediate ? .wellnessAdviceCarbNowTitle : .wellnessAdviceCarbTitle),
                body: AppLocalization.text(isImmediate ? .wellnessAdviceCarbNowBody : .wellnessAdviceCarbBody),
                score: 1.5
            ))
        }

        // 2. 蛋白质:门槛按窗口天数换算(日均 ≥ 13 分钟训练)。
        let proteinThreshold = Double(recent.count) * 13
        if totalWorkoutMinutes >= proteinThreshold, totalWorkoutMinutes > 0 {
            advices.append(RecapAdvice(
                category: .nutrition,
                priority: 2,
                evidence: isImmediate
                    ? AppLocalization.format(.wellnessAdviceProteinNowEvidence, Int(totalWorkoutMinutes.rounded()))
                    : AppLocalization.format(.wellnessAdviceProteinEvidence, Int(totalWorkoutMinutes.rounded())),
                title: AppLocalization.text(isImmediate ? .wellnessAdviceProteinNowTitle : .wellnessAdviceProteinTitle),
                body: AppLocalization.text(isImmediate ? .wellnessAdviceProteinNowBody : .wellnessAdviceProteinBody),
                score: 1.3
            ))
        }

        // 3. 高消耗后的补水与电解质。
        if peakEnergy >= 500 || enduranceDays.contains(where: { $0.workoutMinutes >= 90 }) {
            advices.append(RecapAdvice(
                category: .nutrition,
                priority: 2,
                evidence: peakEnergy >= 500
                    ? AppLocalization.format(.wellnessAdviceHydrationEvidence, Int(peakEnergy.rounded()))
                    : AppLocalization.text(.wellnessAdviceHydrationEvidenceLong),
                title: AppLocalization.text(.wellnessAdviceHydrationTitle),
                body: AppLocalization.text(.wellnessAdviceHydrationBody),
                score: 1.2
            ))
        }

        // 4. 睡眠不足时的进食节律。
        let sleepValues = recent.compactMap(\.sleepDurationMinutes)
        if sleepValues.count >= max(2, recent.count / 2),
           let meanSleep = WellnessBaseline.mean(sleepValues),
           meanSleep < 390 {
            advices.append(RecapAdvice(
                category: .nutrition,
                priority: 2,
                evidence: AppLocalization.format(
                    .wellnessAdviceLateMealEvidence,
                    String(format: "%.1f", meanSleep / 60)
                ),
                title: AppLocalization.text(.wellnessAdviceLateMealTitle),
                body: AppLocalization.text(.wellnessAdviceLateMealBody),
                score: 1.1
            ))
        }

        // 5. 低活动期的日常饮食提示(仅一周窗口,三天窗口样本太短不下结论)。
        if !isImmediate, totalWorkoutMinutes < proteinThreshold * 0.4, !recent.isEmpty {
            advices.append(RecapAdvice(
                category: .nutrition,
                priority: 3,
                evidence: AppLocalization.text(.wellnessAdviceLightWeekEvidence),
                title: AppLocalization.text(.wellnessAdviceLightWeekTitle),
                body: AppLocalization.text(.wellnessAdviceLightWeekBody),
                score: 0.8
            ))
        }

        return advices
    }

    /// 长周期的营养视角:不谈单次补给,谈与训练量匹配的长期饮食基础。
    private static func longTermNutritionAdvices(
        current: PeriodProfile,
        previous: PeriodProfile,
        range: WellnessRecapRange
    ) -> [RecapAdvice] {
        var advices: [RecapAdvice] = []
        guard current.workoutMinutes > 0, current.dayCount > 0 else {
            return advices
        }

        let weeklyMinutes = current.workoutMinutes / Double(current.dayCount) * 7

        // 训练量显著上升期:强调把营养基础同步跟上(月度视角)。
        if range == .month,
           previous.workoutMinutes > 0,
           current.workoutMinutes / previous.workoutMinutes >= 1.25 {
            advices.append(RecapAdvice(
                category: .nutrition,
                priority: 2,
                evidence: AppLocalization.format(.wellnessAdviceFuelGrowthEvidence, Int(weeklyMinutes.rounded())),
                title: AppLocalization.text(.wellnessAdviceFuelGrowthTitle),
                body: AppLocalization.text(.wellnessAdviceFuelGrowthBody),
                score: 1.4
            ))
        }

        // 稳定的高训练量:长期营养基础提醒(半年 / 年度视角,文案不同)。
        if range != .month, weeklyMinutes >= 150 {
            advices.append(RecapAdvice(
                category: .nutrition,
                priority: 2,
                evidence: AppLocalization.format(.wellnessAdviceNutritionBaseEvidence, Int(weeklyMinutes.rounded())),
                title: AppLocalization.text(.wellnessAdviceNutritionBaseTitle),
                body: AppLocalization.text(
                    range == .year ? .wellnessAdviceNutritionBaseYearBody : .wellnessAdviceNutritionBaseBody
                ),
                score: 1.2
            ))
        }

        return advices
    }

    /// 步数稳定达标(≥70% 天数不低于常态)。
    private static func stepsConsistentAdvice(recent: [DailyWellnessSample], baselineWindow: [DailyWellnessSample]) -> RecapAdvice? {
        let baselineSteps = baselineWindow.compactMap(\.stepCount)
        guard baselineSteps.count >= 14,
              let medianSteps = WellnessBaseline.median(baselineSteps) else {
            return nil
        }
        let recorded = recent.compactMap(\.stepCount)
        guard recorded.count >= 5 else {
            return nil
        }
        let achieved = recorded.filter { $0 >= medianSteps }.count
        guard Double(achieved) / Double(recorded.count) >= 0.7 else {
            return nil
        }
        return RecapAdvice(
            category: .positive,
            priority: 3,
            evidence: AppLocalization.format(.wellnessAdviceStepsConsistentEvidence, achieved, recorded.count),
            title: AppLocalization.text(.wellnessAdviceStepsConsistentTitle),
            body: AppLocalization.text(.wellnessAdviceStepsConsistentBody),
            score: 0.9
        )
    }

    /// HRV 高于常态 ≥15%:恢复良好,可以安排强度。
    private static func hrvHighAdvice(recent: [DailyWellnessSample], baselineWindow: [DailyWellnessSample]) -> RecapAdvice? {
        let baselineHRV = baselineWindow.compactMap(\.hrvSDNN)
        let recentHRV = recent.compactMap(\.hrvSDNN)
        guard baselineHRV.count >= 14,
              recentHRV.count >= 3,
              let medianHRV = WellnessBaseline.median(baselineHRV),
              medianHRV > 0,
              let recentEwma = WellnessBaseline.ewma(recentHRV),
              recentEwma >= medianHRV * 1.15 else {
            return nil
        }
        let percent = Int(((recentEwma / medianHRV - 1) * 100).rounded())
        return RecapAdvice(
            category: .recovery,
            priority: 2,
            evidence: AppLocalization.format(.wellnessAdviceHRVHighEvidence, percent),
            title: AppLocalization.text(.wellnessAdviceHRVHighTitle),
            body: AppLocalization.text(.wellnessAdviceHRVHighBody),
            score: 1.3
        )
    }

    /// 平时有训练习惯,但已连续 ≥4 天没有运动。
    private static func workoutGapAdvice(samples: [DailyWellnessSample]) -> RecapAdvice? {
        guard chronicLoad(Array(samples.dropLast(7).suffix(28))) != nil else {
            return nil
        }
        var gap = 0
        for sample in samples.reversed() {
            guard sample.workoutCount == 0 else {
                break
            }
            gap += 1
        }
        guard gap >= 4 else {
            return nil
        }
        return RecapAdvice(
            category: .activity,
            priority: 2,
            evidence: AppLocalization.format(.wellnessAdviceWorkoutGapEvidence, gap),
            title: AppLocalization.text(.wellnessAdviceWorkoutGapTitle),
            body: AppLocalization.text(.wellnessAdviceWorkoutGapBody),
            score: min(Double(gap) / 4, 2) + 0.1
        )
    }

    /// 连续 ≥3 天有运动:肯定 + 提醒安排恢复日。
    private static func workoutStreakAdvice(samples: [DailyWellnessSample]) -> RecapAdvice? {
        var streak = 0
        for sample in samples.reversed() {
            guard sample.workoutCount > 0 else {
                break
            }
            streak += 1
        }
        guard streak >= 3 else {
            return nil
        }
        return RecapAdvice(
            category: .positive,
            priority: 3,
            evidence: AppLocalization.format(.wellnessAdviceStreakEvidence, streak),
            title: AppLocalization.text(.wellnessAdviceStreakTitle),
            body: AppLocalization.text(.wellnessAdviceStreakBody),
            score: 1.2 + Double(streak) * 0.05
        )
    }

    /// 日照不足:与睡眠节律直接相关,是比"早点睡"更容易执行的干预点。
    private static func daylightAdvice(recent: [DailyWellnessSample]) -> RecapAdvice? {
        let values = recent.compactMap(\.daylightMinutes)
        guard values.count >= 4,
              let meanValue = WellnessBaseline.mean(values),
              meanValue < 30 else {
            return nil
        }
        return RecapAdvice(
            category: .sleep,
            priority: 2,
            evidence: AppLocalization.format(.wellnessAdviceDaylightEvidence, Int(meanValue.rounded())),
            title: AppLocalization.text(.wellnessAdviceDaylightTitle),
            body: AppLocalization.text(.wellnessAdviceDaylightBody),
            score: min(30 / max(meanValue, 1), 2) - 0.4
        )
    }

    /// 睡眠中点整体后移(相对基线 > 45 分钟)。
    private static func midpointLateAdvice(recent: [DailyWellnessSample], baselineWindow: [DailyWellnessSample]) -> RecapAdvice? {
        let baselineMidpoints = baselineWindow.compactMap(\.sleepMidpointMinutes).map(WellnessBaseline.normalizedClockMinutes)
        let recentMidpoints = recent.compactMap(\.sleepMidpointMinutes).map(WellnessBaseline.normalizedClockMinutes)
        guard baselineMidpoints.count >= 14,
              recentMidpoints.count >= 3,
              let baselineMedian = WellnessBaseline.median(baselineMidpoints),
              let recentMedian = WellnessBaseline.median(recentMidpoints) else {
            return nil
        }
        let shift = recentMedian - baselineMedian
        guard shift > 45 else {
            return nil
        }
        return RecapAdvice(
            category: .sleep,
            priority: 2,
            evidence: AppLocalization.format(.wellnessAdviceMidpointLateEvidence, Int(shift.rounded())),
            title: AppLocalization.text(.wellnessAdviceMidpointLateTitle),
            body: AppLocalization.text(.wellnessAdviceMidpointLateBody),
            score: min(shift / 45, 2) - 0.2
        )
    }

    /// 深睡占比偏低(估算值,文案保守)。
    private static func deepSleepAdvice(recent: [DailyWellnessSample]) -> RecapAdvice? {
        let ratios: [Double] = recent.compactMap { sample in
            guard let deep = sample.deepSleepMinutes,
                  let total = sample.sleepDurationMinutes,
                  total > 180 else {
                return nil
            }
            return deep / total
        }
        guard ratios.count >= 4,
              let meanRatio = WellnessBaseline.mean(ratios),
              meanRatio < 0.11 else {
            return nil
        }
        return RecapAdvice(
            category: .sleep,
            priority: 2,
            evidence: AppLocalization.format(.wellnessAdviceDeepSleepEvidence, Int((meanRatio * 100).rounded())),
            title: AppLocalization.text(.wellnessAdviceDeepSleepTitle),
            body: AppLocalization.text(.wellnessAdviceDeepSleepBody),
            score: 0.9
        )
    }

    /// 静息心率低于基线(≥3 bpm)= 心肺状态改善的正向信号。
    private static func restingHeartRateImprovedAdvice(recent: [DailyWellnessSample], baselineWindow: [DailyWellnessSample]) -> RecapAdvice? {
        let baselineRates = baselineWindow.compactMap(\.restingHeartRate)
        let recentRates = recent.compactMap(\.restingHeartRate)
        guard baselineRates.count >= 14,
              recentRates.count >= 3,
              let baselineMedian = WellnessBaseline.median(baselineRates),
              let recentEwma = WellnessBaseline.ewma(recentRates),
              baselineMedian - recentEwma >= 3 else {
            return nil
        }
        return RecapAdvice(
            category: .positive,
            priority: 3,
            evidence: AppLocalization.format(
                .wellnessAdviceRHRImprovedEvidence,
                Int((baselineMedian - recentEwma).rounded()),
                Int(recentEwma.rounded())
            ),
            title: AppLocalization.text(.wellnessAdviceRHRImprovedTitle),
            body: AppLocalization.text(.wellnessAdviceRHRImprovedBody),
            score: 1.4
        )
    }

    private static func makeSleepBaseline(_ window: [DailyWellnessSample]) -> SleepBaseline? {
        let durations = window.compactMap(\.sleepDurationMinutes)
        let starts = window.compactMap(\.sleepStartMinutes).map(WellnessBaseline.normalizedClockMinutes)
        guard durations.count >= 14,
              let medianDuration = WellnessBaseline.median(durations),
              let medianStart = WellnessBaseline.median(starts),
              let sigma = WellnessBaseline.robustSigma(durations) else {
            return nil
        }
        return SleepBaseline(medianDuration: medianDuration, medianStart: medianStart, sigmaDuration: max(sigma, 15))
    }

    private static func sleepDebtAdvice(recent: [DailyWellnessSample], baseline: SleepBaseline?, minimumCoverage: Int) -> RecapAdvice? {
        guard let baseline else {
            return nil
        }
        let durations = recent.compactMap(\.sleepDurationMinutes)
        guard durations.count >= minimumCoverage else {
            return nil
        }
        let debt = durations.reduce(0.0) { $0 + max(0, baseline.medianDuration - $1) }
        let debtThreshold = Double(recent.count) * 26  // 约 7 天 3 小时的等比阈值
        guard debt > debtThreshold else {
            return nil
        }
        let advance = Int(min(debt / 3, 60).rounded())
        let suggestedBedtime = clockText(baseline.medianStart - Double(advance))
        return RecapAdvice(
            category: .sleep,
            priority: 1,
            evidence: AppLocalization.format(.wellnessAdviceSleepDebtEvidence, String(format: "%.1f", debt / 60)),
            title: AppLocalization.text(.wellnessAdviceSleepDebtTitle),
            body: AppLocalization.format(.wellnessAdviceSleepDebtBody, advance, suggestedBedtime),
            score: min(debt / debtThreshold, 3)
        )
    }

    private static func sleepIrregularAdvice(recent: [DailyWellnessSample], baseline: SleepBaseline?, minimumCoverage: Int) -> RecapAdvice? {
        guard let baseline else {
            return nil
        }
        let midpoints = recent.compactMap(\.sleepMidpointMinutes).map(WellnessBaseline.normalizedClockMinutes)
        guard midpoints.count >= max(minimumCoverage, 3),
              let deviation = WellnessBaseline.standardDeviation(midpoints),
              deviation > 90 else {
            return nil
        }
        let windowStart = clockText(baseline.medianStart - 30)
        let windowEnd = clockText(baseline.medianStart + 30)
        return RecapAdvice(
            category: .sleep,
            priority: 1,
            evidence: AppLocalization.format(.wellnessAdviceSleepIrregularEvidence, Int(deviation.rounded())),
            title: AppLocalization.text(.wellnessAdviceSleepIrregularTitle),
            body: AppLocalization.format(.wellnessAdviceSleepIrregularBody, windowStart, windowEnd),
            score: min(deviation / 90, 3) - 0.1
        )
    }

    private static func sleepShortAdvice(recent: [DailyWellnessSample], baseline: SleepBaseline?, minimumCoverage: Int) -> RecapAdvice? {
        guard let baseline, baseline.medianDuration >= 390 else {
            return nil
        }
        let durations = recent.compactMap(\.sleepDurationMinutes)
        guard durations.count >= minimumCoverage,
              let ewma = WellnessBaseline.ewma(durations),
              ewma < 360 else {
            return nil
        }
        return RecapAdvice(
            category: .sleep,
            priority: 1,
            evidence: AppLocalization.format(
                .wellnessAdviceSleepShortEvidence,
                String(format: "%.1f", ewma / 60),
                String(format: "%.1f", baseline.medianDuration / 60)
            ),
            title: AppLocalization.text(.wellnessAdviceSleepShortTitle),
            body: AppLocalization.text(.wellnessAdviceSleepShortBody),
            score: min((baseline.medianDuration - ewma) / baseline.sigmaDuration, 3)
        )
    }

    private static func weekendJetlagAdvice(recent: [DailyWellnessSample]) -> RecapAdvice? {
        let calendar = Calendar.current
        var weekendValues: [Double] = []
        var weekdayValues: [Double] = []
        for sample in recent {
            guard let duration = sample.sleepDurationMinutes else {
                continue
            }
            if calendar.isDateInWeekend(sample.day) {
                weekendValues.append(duration)
            } else {
                weekdayValues.append(duration)
            }
        }
        guard weekendValues.count >= 2,
              weekdayValues.count >= 3,
              let weekendMean = WellnessBaseline.mean(weekendValues),
              let weekdayMean = WellnessBaseline.mean(weekdayValues) else {
            return nil
        }
        let difference = weekendMean - weekdayMean
        guard difference > 90 else {
            return nil
        }
        return RecapAdvice(
            category: .sleep,
            priority: 2,
            evidence: AppLocalization.format(.wellnessAdviceWeekendJetlagEvidence, String(format: "%.1f", difference / 60)),
            title: AppLocalization.text(.wellnessAdviceWeekendJetlagTitle),
            body: AppLocalization.text(.wellnessAdviceWeekendJetlagBody),
            score: min(difference / 90, 2) - 0.3
        )
    }

    private static func sleepStableAdvice(recent: [DailyWellnessSample], baseline: SleepBaseline?) -> RecapAdvice? {
        guard let baseline else {
            return nil
        }
        let durations = recent.compactMap(\.sleepDurationMinutes)
        let midpoints = recent.compactMap(\.sleepMidpointMinutes).map(WellnessBaseline.normalizedClockMinutes)
        guard durations.count >= max(3, recent.count - 1),
              let meanDuration = WellnessBaseline.mean(durations),
              abs(meanDuration - baseline.medianDuration) <= baseline.sigmaDuration * 0.5,
              let midpointDeviation = WellnessBaseline.standardDeviation(midpoints),
              midpointDeviation <= 45 else {
            return nil
        }
        return RecapAdvice(
            category: .positive,
            priority: 3,
            evidence: AppLocalization.format(.wellnessAdviceSleepStableEvidence, String(format: "%.1f", meanDuration / 60)),
            title: AppLocalization.text(.wellnessAdviceSleepStableTitle),
            body: AppLocalization.text(.wellnessAdviceSleepStableBody),
            score: 1
        )
    }

    private static func chronicLoad(_ window: [DailyWellnessSample]) -> Double? {
        guard window.count >= 14 else {
            return nil
        }
        let activeDays = window.filter { $0.workoutLoad > 0 }.count
        guard activeDays >= 8 else {
            return nil
        }
        return WellnessBaseline.mean(window.map(\.workoutLoad))
    }

    private static func loadSpikeAdvice(recent: [DailyWellnessSample], baselineWindow: [DailyWellnessSample]) -> RecapAdvice? {
        guard let chronic = chronicLoad(baselineWindow), chronic > 0,
              let acute = WellnessBaseline.mean(recent.map(\.workoutLoad)) else {
            return nil
        }
        let acwr = acute / chronic
        guard acwr > 1.5 else {
            return nil
        }
        return RecapAdvice(
            category: .risk,
            priority: 0,
            evidence: AppLocalization.format(.wellnessAdviceLoadSpikeEvidence, String(format: "%.1f", acwr)),
            title: AppLocalization.text(.wellnessAdviceLoadSpikeTitle),
            body: AppLocalization.text(.wellnessAdviceLoadSpikeBody),
            score: min(acwr, 3)
        )
    }

    private static func loadDropAdvice(recent: [DailyWellnessSample], baselineWindow: [DailyWellnessSample]) -> RecapAdvice? {
        guard let chronic = chronicLoad(baselineWindow), chronic > 0,
              let acute = WellnessBaseline.mean(recent.map(\.workoutLoad)) else {
            return nil
        }
        guard acute / chronic < 0.6 else {
            return nil
        }
        let activeDays = baselineWindow.filter { $0.workoutLoad > 0 }
        let typicalMinutes = WellnessBaseline.median(activeDays.map(\.workoutMinutes)) ?? 30
        return RecapAdvice(
            category: .activity,
            priority: 2,
            evidence: AppLocalization.text(.wellnessAdviceLoadDropEvidence),
            title: AppLocalization.text(.wellnessAdviceLoadDropTitle),
            body: AppLocalization.format(.wellnessAdviceLoadDropBody, Int(typicalMinutes.rounded())),
            score: 1.2
        )
    }

    private static func sedentaryAdvice(recent: [DailyWellnessSample], baselineWindow: [DailyWellnessSample]) -> RecapAdvice? {
        let baselineSteps = baselineWindow.compactMap(\.stepCount)
        guard baselineSteps.count >= 14,
              let medianSteps = WellnessBaseline.median(baselineSteps) else {
            return nil
        }
        let threshold = max(5000, medianSteps * 0.6)
        var consecutive = 0
        for sample in recent.reversed() {
            guard let steps = sample.stepCount, steps < threshold else {
                break
            }
            consecutive += 1
        }
        guard consecutive >= min(5, recent.count) , consecutive >= 3 else {
            return nil
        }
        let target = (medianSteps / 100).rounded() * 100
        return RecapAdvice(
            category: .activity,
            priority: 2,
            evidence: AppLocalization.format(.wellnessAdviceSedentaryEvidence, consecutive, groupedNumber(threshold)),
            title: AppLocalization.text(.wellnessAdviceSedentaryTitle),
            body: AppLocalization.format(.wellnessAdviceSedentaryBody, groupedNumber(target)),
            score: 1.5
        )
    }

    private static func recoveryAdvice(recent: [DailyWellnessSample], baselineWindow: [DailyWellnessSample]) -> RecapAdvice? {
        let baselineRates = baselineWindow.compactMap(\.restingHeartRate)
        guard baselineRates.count >= 14,
              let medianRate = WellnessBaseline.median(baselineRates) else {
            return nil
        }
        let recentRates = recent.compactMap(\.restingHeartRate)
        guard recentRates.count >= 3 else {
            return nil
        }
        let lastThree = Array(recentRates.suffix(3))
        guard lastThree.allSatisfy({ $0 >= medianRate + 5 }) else {
            return nil
        }
        let elevation = Int(((lastThree.reduce(0, +) / 3) - medianRate).rounded())

        var hrvSuffix = ""
        let baselineHRV = baselineWindow.compactMap(\.hrvSDNN)
        let recentHRV = recent.compactMap(\.hrvSDNN)
        if baselineHRV.count >= 14,
           let medianHRV = WellnessBaseline.median(baselineHRV),
           let recentHRVEwma = WellnessBaseline.ewma(recentHRV),
           recentHRVEwma <= medianHRV * 0.8 {
            hrvSuffix = AppLocalization.text(.wellnessAdviceRecoveryHRVSuffix)
        }

        return RecapAdvice(
            category: .risk,
            priority: 0,
            evidence: AppLocalization.format(.wellnessAdviceRecoveryEvidence, 3, elevation, hrvSuffix),
            title: AppLocalization.text(.wellnessAdviceRecoveryTitle),
            body: AppLocalization.text(.wellnessAdviceRecoveryBody),
            score: 2 + (hrvSuffix.isEmpty ? 0 : 0.5)
        )
    }

    private static func activeWeekAdvice(recent: [DailyWellnessSample]) -> RecapAdvice? {
        let total = recent.compactMap(\.exerciseMinutes).reduce(0, +)
        guard total >= 150 else {
            return nil
        }
        return RecapAdvice(
            category: .positive,
            priority: 3,
            evidence: AppLocalization.format(.wellnessAdviceActiveWeekEvidence, Int(total.rounded())),
            title: AppLocalization.text(.wellnessAdviceActiveWeekTitle),
            body: AppLocalization.text(.wellnessAdviceActiveWeekBody),
            score: 1.1
        )
    }

    // MARK: - Long-Term Rules(月 / 半年 / 年)

    private static func longTermAdvices(
        current: PeriodProfile,
        previous: PeriodProfile,
        samples: [DailyWellnessSample],
        range: WellnessRecapRange
    ) -> [RecapAdvice] {
        var advices: [RecapAdvice] = []

        // 睡眠均值位移(本期 vs 上期,各覆盖 ≥ 1/3 天数才可信)。仅月度视角展示。
        if range == .month,
           let currentSleep = current.sleepMean,
           let previousSleep = previous.sleepMean,
           current.sleepCoverage >= current.dayCount / 3,
           previous.sleepCoverage >= previous.dayCount / 3 {
            let difference = currentSleep - previousSleep
            if abs(difference) >= 20 {
                let improving = difference > 0
                advices.append(RecapAdvice(
                    category: improving ? .positive : .sleep,
                    priority: improving ? 3 : 1,
                    evidence: AppLocalization.format(
                        improving ? .wellnessAdviceSleepTrendUpEvidence : .wellnessAdviceSleepTrendDownEvidence,
                        String(format: "%.1f", abs(difference) / 60)
                    ),
                    title: AppLocalization.text(improving ? .wellnessAdviceSleepTrendUpTitle : .wellnessAdviceSleepTrendDownTitle),
                    body: AppLocalization.text(improving ? .wellnessAdviceSleepTrendUpBody : .wellnessAdviceSleepTrendDownBody),
                    score: min(abs(difference) / 20, 3)
                ))
            }
        }

        // 运动总量位移(±25%)。仅月度视角展示。
        if range == .month, current.exerciseTotal > 0 || previous.exerciseTotal > 0 {
            let previousTotal = max(previous.exerciseTotal, 1)
            let change = (current.exerciseTotal - previous.exerciseTotal) / previousTotal
            if abs(change) >= 0.25, previous.exerciseTotal >= 60 {
                let increasing = change > 0
                advices.append(RecapAdvice(
                    category: increasing ? .positive : .activity,
                    priority: increasing ? 3 : 2,
                    evidence: AppLocalization.format(
                        increasing ? .wellnessAdviceVolumeUpEvidence : .wellnessAdviceVolumeDownEvidence,
                        Int((abs(change) * 100).rounded())
                    ),
                    title: AppLocalization.text(increasing ? .wellnessAdviceVolumeUpTitle : .wellnessAdviceVolumeDownTitle),
                    body: AppLocalization.text(increasing ? .wellnessAdviceVolumeUpBody : .wellnessAdviceVolumeDownBody),
                    score: min(abs(change) / 0.25, 3) - 0.2
                ))
            }
        }

        // 规律性:有运动记录的周占比。半年视角展示(月度样本太少、年度看季节性)。
        let weeks = stride(from: 0, to: samples.count, by: 7).map { start in
            Array(samples[start..<min(start + 7, samples.count)])
        }
        if range == .halfYear, weeks.count >= 4 {
            let activeWeeks = weeks.filter { week in
                week.contains { $0.workoutCount > 0 }
            }.count
            let ratio = Double(activeWeeks) / Double(weeks.count)
            if ratio >= 0.8 {
                advices.append(RecapAdvice(
                    category: .positive,
                    priority: 3,
                    evidence: AppLocalization.format(.wellnessAdviceConsistencyGoodEvidence, activeWeeks, weeks.count),
                    title: AppLocalization.text(.wellnessAdviceConsistencyGoodTitle),
                    body: AppLocalization.text(.wellnessAdviceConsistencyGoodBody),
                    score: 1.3
                ))
            } else if ratio < 0.5, current.workoutCount > 0 {
                advices.append(RecapAdvice(
                    category: .activity,
                    priority: 2,
                    evidence: AppLocalization.format(.wellnessAdviceConsistencyLowEvidence, activeWeeks, weeks.count),
                    title: AppLocalization.text(.wellnessAdviceConsistencyLowTitle),
                    body: AppLocalization.text(.wellnessAdviceConsistencyLowBody),
                    score: 1.4
                ))
            }
        }

        // 个人纪录:本期单日最长距离超过上期。月度视角展示。
        if range == .month,
           current.maxSingleDistanceMeters > 1000,
           current.maxSingleDistanceMeters > previous.maxSingleDistanceMeters,
           previous.maxSingleDistanceMeters > 0 {
            advices.append(RecapAdvice(
                category: .positive,
                priority: 3,
                evidence: AppLocalization.format(
                    .wellnessAdvicePBEvidence,
                    String(format: "%.1f", current.maxSingleDistanceMeters / 1000)
                ),
                title: AppLocalization.text(.wellnessAdvicePBTitle),
                body: AppLocalization.text(.wellnessAdvicePBBody),
                score: 1.6
            ))
        }

        // 步数均值位移(±15%)。半年视角展示。
        if range == .halfYear,
           let currentSteps = current.stepsMean,
           let previousSteps = previous.stepsMean,
           current.stepsCoverage >= current.dayCount / 3,
           previous.stepsCoverage >= previous.dayCount / 3,
           previousSteps > 0 {
            let change = (currentSteps - previousSteps) / previousSteps
            if abs(change) >= 0.15 {
                let increasing = change > 0
                advices.append(RecapAdvice(
                    category: increasing ? .positive : .activity,
                    priority: increasing ? 3 : 2,
                    evidence: AppLocalization.format(
                        increasing ? .wellnessAdviceStepsUpEvidence : .wellnessAdviceStepsDownEvidence,
                        Int((abs(change) * 100).rounded())
                    ),
                    title: AppLocalization.text(increasing ? .wellnessAdviceStepsUpTitle : .wellnessAdviceStepsDownTitle),
                    body: AppLocalization.text(increasing ? .wellnessAdviceStepsUpBody : .wellnessAdviceStepsDownBody),
                    score: min(abs(change) / 0.15, 2.5) - 0.3
                ))
            }
        }

        // 习惯识别:某个星期几集中了大部分运动。年度视角展示(样本最足)。
        if range == .year, let habit = habitWeekdayAdvice(samples: samples) {
            advices.append(habit)
        }

        // 里程碑:半年与年度视角(文案不同)。
        if range == .halfYear || range == .year {
            if current.distanceMeters >= 100_000 {
                advices.append(RecapAdvice(
                    category: .positive,
                    priority: 3,
                    evidence: AppLocalization.format(
                        .wellnessAdviceMilestoneEvidence,
                        String(format: "%.0f", current.distanceMeters / 1000),
                        current.workoutCount
                    ),
                    title: AppLocalization.text(.wellnessAdviceMilestoneTitle),
                    body: AppLocalization.text(range == .year ? .wellnessAdviceMilestoneYearBody : .wellnessAdviceMilestoneBody),
                    score: 1.7
                ))
            }

        }

        // 季节波动:仅年度视角(半年样本跨不满四季)。
        if range == .year, let seasonal = seasonalAdvice(samples: samples) {
            advices.append(seasonal)
        }

        advices.append(contentsOf: longTermNutritionAdvices(current: current, previous: previous, range: range))

        // 静息心率长期位移(±3 bpm)。年度视角展示。
        if range == .year,
           let currentRHR = current.restingHeartRateMean,
           let previousRHR = previous.restingHeartRateMean,
           current.dayCount > 0,
           previous.dayCount > 0 {
            let difference = currentRHR - previousRHR
            if abs(difference) >= 3 {
                let improving = difference < 0
                advices.append(RecapAdvice(
                    category: improving ? .positive : .recovery,
                    priority: improving ? 3 : 2,
                    evidence: AppLocalization.format(
                        improving ? .wellnessAdviceRHRTrendGoodEvidence : .wellnessAdviceRHRTrendBadEvidence,
                        Int(abs(difference).rounded()),
                        Int(currentRHR.rounded())
                    ),
                    title: AppLocalization.text(improving ? .wellnessAdviceRHRTrendGoodTitle : .wellnessAdviceRHRTrendBadTitle),
                    body: AppLocalization.text(improving ? .wellnessAdviceRHRTrendGoodBody : .wellnessAdviceRHRTrendBadBody),
                    score: min(abs(difference) / 3, 2.5)
                ))
            }
        }

        return advices
    }

    /// 季节性:按自然月聚合训练量,最高月与最低月差距 ≥2 倍时给出观察。
    private static func seasonalAdvice(samples: [DailyWellnessSample]) -> RecapAdvice? {
        let calendar = Calendar.current
        var minutesByMonth: [Int: Double] = [:]
        var daysByMonth: [Int: Int] = [:]
        for sample in samples {
            let month = calendar.component(.month, from: sample.day)
            minutesByMonth[month, default: 0] += sample.workoutMinutes
            daysByMonth[month, default: 0] += 1
        }
        // 只保留记录较完整的月份,避免首尾半个月造成假象。
        let eligible = minutesByMonth.filter { (daysByMonth[$0.key] ?? 0) >= 20 }
        guard eligible.count >= 3,
              let peak = eligible.max(by: { $0.value < $1.value }),
              let trough = eligible.min(by: { $0.value < $1.value }),
              trough.value > 0,
              peak.value / trough.value >= 2 else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: AppLanguageStore.resolveLanguage(in: .standard).rawValue
        )
        let peakName = formatter.standaloneMonthSymbols[(peak.key - 1) % 12]
        let troughName = formatter.standaloneMonthSymbols[(trough.key - 1) % 12]
        return RecapAdvice(
            category: .activity,
            priority: 2,
            evidence: AppLocalization.format(.wellnessAdviceSeasonalEvidence, peakName, troughName),
            title: AppLocalization.text(.wellnessAdviceSeasonalTitle),
            body: AppLocalization.text(.wellnessAdviceSeasonalBody),
            score: 1.35
        )
    }

    private static func habitWeekdayAdvice(samples: [DailyWellnessSample]) -> RecapAdvice? {
        let calendar = Calendar.current
        var countsByWeekday: [Int: Int] = [:]
        var totalWorkoutDays = 0
        for sample in samples where sample.workoutCount > 0 {
            let weekday = calendar.component(.weekday, from: sample.day)
            countsByWeekday[weekday, default: 0] += 1
            totalWorkoutDays += 1
        }
        guard totalWorkoutDays >= 8,
              let (topWeekday, topCount) = countsByWeekday.max(by: { $0.value < $1.value }),
              Double(topCount) / Double(totalWorkoutDays) >= 0.4 else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: AppLanguageStore.resolveLanguage(in: .standard).rawValue
        )
        let weekdayName = formatter.weekdaySymbols[(topWeekday - 1) % 7]
        return RecapAdvice(
            category: .positive,
            priority: 3,
            evidence: AppLocalization.format(.wellnessAdviceHabitDayEvidence, topCount, weekdayName),
            title: AppLocalization.format(.wellnessAdviceHabitDayTitle, weekdayName),
            body: AppLocalization.text(.wellnessAdviceHabitDayBody),
            score: 1.2
        )
    }

    // MARK: - Formatting

    private static func clockText(_ minutes: Double) -> String {
        let wrapped = ((Int(minutes.rounded()) % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    private static func groupedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))
    }
}
