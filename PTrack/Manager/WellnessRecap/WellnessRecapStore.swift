//
//  WellnessRecapStore.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  指导建议的编排与缓存:
//  - 按时间范围(3 天 / 周 / 月 / 半年 / 年)分别生成与缓存;
//  - 缓存键 = 范围 + 周期标识 + 语言 + schema 版本;
//  - App 进入前台时仅预生成默认范围(已授权过才会跑,绝不触发授权弹窗);
//  - 打字机动画在"范围 × 周期"维度只播一次。

import Foundation

final class WellnessRecapStore {
    static let shared = WellnessRecapStore()

    static let defaultRange: WellnessRecapRange = .threeDays

    /// 有新内容待查看时发出,首页 title 收到后播放扫光。
    static let hasFreshInsightNotification = Notification.Name("WellnessRecapStoreHasFreshInsight")

    private enum Keys {
        static let authorizationRequested = "wellnessRecap.authorizationRequested"
        static let cachedReport = "wellnessRecap.cachedReport"
        static let animatedPeriods = "wellnessRecap.animatedPeriods"
        static let hasFreshInsight = "wellnessRecap.hasFreshInsight"
        static let lastShimmerAppVersion = "wellnessRecap.lastShimmerAppVersion"
    }

    /// 块顺序、规则集变化时必须递增,否则会命中旧缓存。
    private static let schemaVersion = 8

    private let reader = WellnessHealthKitReader()
    private let defaults = UserDefaults.standard
    private var generatingRanges = Set<WellnessRecapRange>()
    /// 生成期间到达的请求排队等待,完成后统一回调,避免拿到 nil 误判为"无数据"。
    private var pendingCompletions: [WellnessRecapRange: [(WellnessRecapReport?) -> Void]] = [:]

    private init() {}

    // MARK: - State

    var hasRequestedAuthorization: Bool {
        defaults.bool(forKey: Keys.authorizationRequested)
    }

    var isHealthDataAvailable: Bool {
        WellnessHealthKitReader.isHealthDataAvailable
    }

    /// 周期标识:短周期按天滚动,长周期按自然月 / 半年 / 年。
    static func periodID(for range: WellnessRecapRange) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        switch range {
        case .threeDays, .week:
            return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        case .month:
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        case .halfYear:
            return String(format: "%04d-H%d", components.year ?? 0, (components.month ?? 1) <= 6 ? 1 : 2)
        case .year:
            return String(format: "%04d", components.year ?? 0)
        }
    }

    private static var currentLanguageCode: String {
        AppLanguageStore.shared.language.rawValue
    }

    // MARK: - Fresh Insight(扫光提示)

    /// 是否有未查看的新内容。
    private(set) var hasFreshInsight: Bool {
        get {
            defaults.bool(forKey: Keys.hasFreshInsight)
        }
        set {
            defaults.set(newValue, forKey: Keys.hasFreshInsight)
        }
    }

    private func markFreshInsight() {
        guard !hasFreshInsight else {
            return
        }
        hasFreshInsight = true
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.hasFreshInsightNotification, object: nil)
        }
    }

    /// 用户点开指导页后调用,消费掉提示。
    func clearFreshInsight() {
        hasFreshInsight = false
    }

    /// 新版本首次启动时提示一次。
    func markFreshInsightForNewAppVersionIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard !currentVersion.isEmpty else {
            return
        }
        guard defaults.string(forKey: Keys.lastShimmerAppVersion) != currentVersion else {
            return
        }
        defaults.set(currentVersion, forKey: Keys.lastShimmerAppVersion)
        markFreshInsight()
    }

    // MARK: - Cache

    private func cacheKey(for range: WellnessRecapRange) -> String {
        "\(Keys.cachedReport).v\(Self.schemaVersion).\(range.rawValue).\(Self.periodID(for: range)).\(Self.currentLanguageCode)"
    }

    func cachedReport(for range: WellnessRecapRange) -> WellnessRecapReport? {
        guard let data = defaults.data(forKey: cacheKey(for: range)) else {
            return nil
        }
        return try? JSONDecoder().decode(WellnessRecapReport.self, from: data)
    }

    private func cache(_ report: WellnessRecapReport) {
        guard let data = try? JSONEncoder().encode(report) else {
            return
        }
        defaults.set(data, forKey: cacheKey(for: report.range))
    }

    func hasAnimated(periodID: String, range: WellnessRecapRange) -> Bool {
        let animated = defaults.stringArray(forKey: Keys.animatedPeriods) ?? []
        return animated.contains("\(range.rawValue)#\(periodID)")
    }

    func markAnimated(periodID: String, range: WellnessRecapRange) {
        var animated = defaults.stringArray(forKey: Keys.animatedPeriods) ?? []
        let token = "\(range.rawValue)#\(periodID)"
        guard !animated.contains(token) else {
            return
        }
        animated.append(token)
        if animated.count > 16 {
            animated.removeFirst(animated.count - 16)
        }
        defaults.set(animated, forKey: Keys.animatedPeriods)
    }

    // MARK: - Generation

    /// App 启动/进前台时调用:已授权过就后台重算默认范围,保证缓存新鲜。
    func prepareIfNeeded() {
        guard hasRequestedAuthorization else {
            return
        }
        generate(range: Self.defaultRange, completion: nil)
    }

    /// 新运动同步入库后调用:作废全部缓存并重算默认范围,同时点亮扫光提示。
    func invalidateCaches() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("\(Keys.cachedReport).") {
            defaults.removeObject(forKey: key)
        }
        markFreshInsight()
        guard hasRequestedAuthorization else {
            return
        }
        generate(range: Self.defaultRange, completion: nil)
    }

    /// 用户首次点击入口:请求授权后生成。
    func requestAuthorizationAndGenerate(
        range: WellnessRecapRange,
        completion: @escaping (WellnessRecapReport?) -> Void
    ) {
        reader.requestAuthorization { [weak self] _ in
            guard let self else {
                completion(nil)
                return
            }
            // HealthKit 不暴露"读授权"结果,统一标记已请求并直接尝试查询;
            // 被拒的字段查询结果为空,对应规则自然静默。
            defaults.set(true, forKey: Keys.authorizationRequested)
            generate(range: range, completion: completion)
        }
    }

    /// 兼容旧调用点:等同于作废缓存并重算。
    func regenerate() {
        invalidateCaches()
    }

    func generate(range: WellnessRecapRange, completion: ((WellnessRecapReport?) -> Void)?) {
        // 已有同范围的生成在跑:把回调排队,别直接返回可能为 nil 的缓存。
        if generatingRanges.contains(range) {
            if let completion {
                pendingCompletions[range, default: []].append(completion)
            }
            return
        }

        generatingRanges.insert(range)
        if let completion {
            pendingCompletions[range, default: []].append(completion)
        }

        let periodID = Self.periodID(for: range)
        let languageCode = Self.currentLanguageCode
        var hasFinished = false

        func finish(_ report: WellnessRecapReport?) {
            guard !hasFinished else {
                return
            }
            hasFinished = true
            generatingRanges.remove(range)
            let callbacks = pendingCompletions.removeValue(forKey: range) ?? []
            callbacks.forEach { $0(report) }
        }

        // 兜底:HealthKit 回调若始终不来,超时后释放占位,避免该范围永久卡住。
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            finish(nil)
        }

        reader.fetchDailySamples(dayCount: range.fetchDays) { [weak self] samples in
            guard let self else {
                finish(nil)
                return
            }
            guard !samples.isEmpty else {
                finish(nil)
                return
            }
            let report = WellnessRuleEngine.makeReport(
                samples: samples,
                range: range,
                periodID: periodID,
                languageCode: languageCode
            )
            // 分析出新结论(与上次缓存不同)时点亮扫光提示。
            if let previous = cachedReport(for: range), !isSameContent(previous, report) {
                markFreshInsight()
            }
            cache(report)
            finish(report)
        }
    }

    /// 内容是否等价:按编码后的块数据比较,避免"条数相同但数字变了"被当成没变。
    func isSameContent(_ lhs: WellnessRecapReport, _ rhs: WellnessRecapReport) -> Bool {
        guard lhs.summary == rhs.summary else {
            return false
        }
        let encoder = JSONEncoder()
        guard let lhsData = try? encoder.encode(lhs.blocks),
              let rhsData = try? encoder.encode(rhs.blocks) else {
            return false
        }
        return lhsData == rhsData
    }
}
