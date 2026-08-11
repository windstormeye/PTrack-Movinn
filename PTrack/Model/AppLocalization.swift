//
//  AppLocalization.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/15.
//

import Foundation

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case english = "en"

    var nativeName: String {
        switch self {
        case .chinese:
            return "简体中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .english:
            return "English"
        }
    }
}

enum AppTextKey: String {
    case all
    case applyToAll
    case appleFitnessDownloadCTA
    case appearanceSettings
    case appearanceSystem
    case appLanguage
    case appIsUpToDate
    case checkForUpdates
    case checkingForUpdates
    case updateAvailableTitle
    case updateCheckFailed
    case updateDismiss
    case updateNow
    case aspectRatio
    case appleHealth
    case appDefault
    case activitySummaryPrefix
    case newDataSyncing
    case cancel
    case collage
    case collageSingleLivePhotoLimit
    case collageStyle
    case colorBlack
    case colorBlue
    case colorCustom
    case colorGray
    case colorOrange
    case colorPink
    case colorWhite
    case color
    case canvas
    case cycling
    case dark
    case dataIntegration
    case dayBeforeYesterday
    case delete
    case deleteRoute
    case deleteRouteMessage
    case debugProAccessLocked
    case debugProAccessMockEnabled
    case debugProAccessSimulation
    case debugProAccessUnlocked
    case debugHomeDataSimulation
    case debugSimulateHomeEmptyData
    case demoModeEntry
    case demoModeExit
    case demoModeExitMessage
    case demoModeExitTitle
    case demoModeTitle
    case developerWebsite
    case developerTools
    case disable
    case distanceMetersFormat
    case enable
    case exit
    case healthAuthorizationDenied
    case healthAuthorizationFailed
    case healthAuthorizationProgress
    case healthAuthorizationSettingsRequiredMessage
    case healthAuthorizationSettingsRequiredTitle
    case healthAuthorizationTemporarilyUnavailable
    case healthDataReadAuthorized
    case healthDataUnavailable
    case homeDataLoadingMessage
    case homeNoWorkoutDataMessage
    case appleHealthDataSourceSubtitle
    case exportGPX
    case estimatedBurnedCaloriesFormat
    case gpxExportFailed
    case gpxExportNoRoute
    case gpxExportRouteName
    case gpxExporting
    case gpxImportInvalidFile
    case gpxImportNoRoute
    case followPhoto
    case hiking
    case iCloudRouteSync
    case iCloudRouteSyncAccountChangedMessage
    case iCloudRouteSyncAccountUnavailableMessage
    case iCloudRouteSyncAlreadyEnabled
    case iCloudRouteSyncConfirmMessage
    case iCloudRouteSyncConfirmTitle
    case iCloudRouteSyncDisabled
    case iCloudRouteSyncDisableConfirmMessage
    case iCloudRouteSyncDisableConfirmTitle
    case iCloudRouteSyncEnabled
    case iCloudRouteSyncDocumentUnavailableMessage
    case iCloudRouteSyncDriveUnavailableMessage
    case iCloudRouteSyncFailed
    case routeCollectionICloudSyncFooterCompleteFormat
    case routeCollectionICloudSyncFooterErrorFormat
    case routeCollectionICloudSyncFooterPendingFormat
    case routeCollectionICloudSyncFooterPreparing
    case mapBackgroundAdjustmentHint
    case mapStyle
    case livePhotoSaved
    case livePhotoSaving
    case light
    case more
    case movinnLocalDataPrivacyStatement
    case movinnPro
    case newActivity
    case newRoute
    case ok
    case navigation
    case startNavigation
    case openEnd
    case openPhotos
    case openStart
    case openSettings
    case other
    case outdoorSwimming
    case outdoorWorkout
    case photoLibraryFullAccessRequiredMessage
    case photoLibraryFullAccessRequiredTitle
    case photoLibraryReadAuthorized
    case photoSaving
    case photoBackgroundAdjustmentHint
    case photoMatching
    case privacyPolicy
    case proCodeRedemption
    case proFeatureHeatmap
    case proFeatureWellnessRecap
    case proFeatureICloudRouteSync
    case proFeatureMultiLivePhotoExport
    case proFeatureMoreComing
    case proFeatureRouteMerge
    case proFeatureRouteSlope
    case proPaywallSubtitle
    case proPaywallTitle
    case proProductUnavailable
    case proPurchaseButton
    case proPurchaseButtonPriceFormat
    case proPurchaseFailed
    case proPurchaseLoading
    case proPurchaseNotAllowed
    case proPurchasePending
    case proPurchaseSuccess
    case proPurchaseUnverified
    case proRestoreNoPurchase
    case proRestoreSuccess
    case proStatusActive
    case proUnlockedTitle
    case queryingLocation
    case routeBook
    case routeBookExit
    case routeBookExitMessage
    case routeBookLocationPermissionRequiredMessage
    case routeBookLocationPermissionRequiredTitle
    case route
    case routeSlope
    case routeSlopeColorHint
    case routeStyle3DFollowColor
    case routeStyle3DSlopeColor
    case wellnessRecapSheetTitle
    case wellnessHeaderTip
    case wellnessSummaryRisk
    case wellnessSummaryAttention
    case wellnessSummaryGood
    case wellnessSummaryCold
    case wellnessFactSleepFormat
    case wellnessFactStepsFormat
    case wellnessFactWorkoutsFormat
    case wellnessFactExerciseFormat
    case wellnessCoverageNoteFormat
    case wellnessDisclaimer
    case wellnessAuthPromptTitle
    case wellnessAuthPromptBody
    case wellnessAuthButton
    case wellnessLoading
    case wellnessEmptyBody
    case wellnessAdviceSleepDebtTitle
    case wellnessAdviceSleepDebtEvidence
    case wellnessAdviceSleepDebtBody
    case wellnessAdviceSleepIrregularTitle
    case wellnessAdviceSleepIrregularEvidence
    case wellnessAdviceSleepIrregularBody
    case wellnessAdviceSleepShortTitle
    case wellnessAdviceSleepShortEvidence
    case wellnessAdviceSleepShortBody
    case wellnessAdviceWeekendJetlagTitle
    case wellnessAdviceWeekendJetlagEvidence
    case wellnessAdviceWeekendJetlagBody
    case wellnessAdviceSleepStableTitle
    case wellnessAdviceSleepStableEvidence
    case wellnessAdviceSleepStableBody
    case wellnessAdviceLoadSpikeTitle
    case wellnessAdviceLoadSpikeEvidence
    case wellnessAdviceLoadSpikeBody
    case wellnessAdviceLoadDropTitle
    case wellnessAdviceLoadDropEvidence
    case wellnessAdviceLoadDropBody
    case wellnessAdviceSedentaryTitle
    case wellnessAdviceSedentaryEvidence
    case wellnessAdviceSedentaryBody
    case wellnessAdviceRecoveryTitle
    case wellnessAdviceRecoveryEvidence
    case wellnessAdviceRecoveryBody
    case wellnessAdviceRecoveryHRVSuffix
    case wellnessAdviceActiveWeekTitle
    case wellnessAdviceActiveWeekEvidence
    case wellnessAdviceActiveWeekBody
    case wellnessRangeThreeDays
    case wellnessRangeWeek
    case wellnessRangeMonth
    case wellnessRangeHalfYear
    case wellnessRangeYear
    case wellnessSectionFacts
    case wellnessSectionTrends
    case wellnessSectionAdvice
    case wellnessChartSleep
    case wellnessChartSteps
    case wellnessChartLoad
    case wellnessTableHeaderMetric
    case wellnessTableHeaderCurrent
    case wellnessTableHeaderReference
    case wellnessTableHeaderChange
    case wellnessMetricSleep
    case wellnessMetricSteps
    case wellnessMetricExercise
    case wellnessMetricWorkouts
    case wellnessMetricDistance
    case wellnessMetricRHR
    case wellnessMetricHRV
    case wellnessAdviceSleepTrendUpTitle
    case wellnessAdviceSleepTrendUpEvidence
    case wellnessAdviceSleepTrendUpBody
    case wellnessAdviceSleepTrendDownTitle
    case wellnessAdviceSleepTrendDownEvidence
    case wellnessAdviceSleepTrendDownBody
    case wellnessAdviceVolumeUpTitle
    case wellnessAdviceVolumeUpEvidence
    case wellnessAdviceVolumeUpBody
    case wellnessAdviceVolumeDownTitle
    case wellnessAdviceVolumeDownEvidence
    case wellnessAdviceVolumeDownBody
    case wellnessAdviceConsistencyGoodTitle
    case wellnessAdviceConsistencyGoodEvidence
    case wellnessAdviceConsistencyGoodBody
    case wellnessAdviceConsistencyLowTitle
    case wellnessAdviceConsistencyLowEvidence
    case wellnessAdviceConsistencyLowBody
    case wellnessAdvicePBTitle
    case wellnessAdvicePBEvidence
    case wellnessAdvicePBBody
    case wellnessAdviceDaylightTitle
    case wellnessAdviceDaylightEvidence
    case wellnessAdviceDaylightBody
    case wellnessAdviceMidpointLateTitle
    case wellnessAdviceMidpointLateEvidence
    case wellnessAdviceMidpointLateBody
    case wellnessAdviceDeepSleepTitle
    case wellnessAdviceDeepSleepEvidence
    case wellnessAdviceDeepSleepBody
    case wellnessAdviceRHRImprovedTitle
    case wellnessAdviceRHRImprovedEvidence
    case wellnessAdviceRHRImprovedBody
    case wellnessAdviceStepsUpTitle
    case wellnessAdviceStepsUpEvidence
    case wellnessAdviceStepsUpBody
    case wellnessAdviceStepsDownTitle
    case wellnessAdviceStepsDownEvidence
    case wellnessAdviceStepsDownBody
    case wellnessAdviceHabitDayTitle
    case wellnessAdviceHabitDayEvidence
    case wellnessAdviceHabitDayBody
    case wellnessAdviceStepsConsistentTitle
    case wellnessAdviceStepsConsistentEvidence
    case wellnessAdviceStepsConsistentBody
    case wellnessAdviceHRVHighTitle
    case wellnessAdviceHRVHighEvidence
    case wellnessAdviceHRVHighBody
    case wellnessAdviceWorkoutGapTitle
    case wellnessAdviceWorkoutGapEvidence
    case wellnessAdviceWorkoutGapBody
    case wellnessAdviceStreakTitle
    case wellnessAdviceStreakEvidence
    case wellnessAdviceStreakBody
    case wellnessAdviceRHRTrendGoodTitle
    case wellnessAdviceRHRTrendGoodEvidence
    case wellnessAdviceRHRTrendGoodBody
    case wellnessAdviceRHRTrendBadTitle
    case wellnessAdviceRHRTrendBadEvidence
    case wellnessAdviceRHRTrendBadBody
    case wellnessAdviceCarbTitle
    case wellnessAdviceCarbEvidence
    case wellnessAdviceCarbBody
    case wellnessAdviceProteinTitle
    case wellnessAdviceProteinEvidence
    case wellnessAdviceProteinBody
    case wellnessAdviceHydrationTitle
    case wellnessAdviceHydrationEvidence
    case wellnessAdviceHydrationEvidenceLong
    case wellnessAdviceHydrationBody
    case wellnessAdviceLateMealTitle
    case wellnessAdviceLateMealEvidence
    case wellnessAdviceLateMealBody
    case wellnessAdviceLightWeekTitle
    case wellnessAdviceLightWeekEvidence
    case wellnessAdviceLightWeekBody
    case wellnessAdviceSleepRoutineTitle
    case wellnessAdviceSleepRoutineEvidence
    case wellnessAdviceSleepRoutineBody
    case wellnessAdviceMixTitle
    case wellnessAdviceMixEvidence
    case wellnessAdviceMixBody
    case wellnessAdviceRestDayTitle
    case wellnessAdviceRestDayEvidence
    case wellnessAdviceRestDayBody
    case wellnessAdviceCarbNowTitle
    case wellnessAdviceCarbNowEvidence
    case wellnessAdviceCarbNowBody
    case wellnessAdviceProteinNowTitle
    case wellnessAdviceProteinNowEvidence
    case wellnessAdviceProteinNowBody
    case wellnessAdviceFuelGrowthTitle
    case wellnessAdviceFuelGrowthEvidence
    case wellnessAdviceFuelGrowthBody
    case wellnessAdviceNutritionBaseTitle
    case wellnessAdviceNutritionBaseEvidence
    case wellnessAdviceNutritionBaseBody
    case wellnessAdviceNutritionBaseYearBody
    case wellnessAdviceMilestoneTitle
    case wellnessAdviceMilestoneEvidence
    case wellnessAdviceMilestoneBody
    case wellnessAdviceMilestoneYearBody
    case wellnessAdviceSeasonalTitle
    case wellnessAdviceSeasonalEvidence
    case wellnessAdviceSeasonalBody
    case wellnessAdviceTonightTitle
    case wellnessAdviceTonightEvidence
    case wellnessAdviceTonightBody
    case wellnessTipSleep1
    case wellnessTipSleep2
    case wellnessTipSleep3
    case wellnessTipSleep4
    case wellnessTipSleep5
    case wellnessTipActivity1
    case wellnessTipActivity2
    case wellnessTipActivity3
    case wellnessTipActivity4
    case wellnessTipActivity5
    case wellnessTipNutrition1
    case wellnessTipNutrition2
    case wellnessTipNutrition3
    case wellnessTipNutrition4
    case wellnessTipNutrition5
    case wellnessTipRecovery1
    case wellnessTipRecovery2
    case wellnessTipRecovery3
    case wellnessTipRecovery4
    case wellnessTipPositive1
    case wellnessTipPositive2
    case wellnessTipPositive3
    case wellnessTipPositive4
    case routeCollection
    case routeCollectionMenuTitle
    case routeCollectionEmptyMessage
    case routeCollectionImportSectionTitle
    case routeCollectionImportSuccess
    case routeCollectionImporting
    case routeCollectionMergeSectionTitle
    case routeHeatmap
    case heatmapShareMask
    case heatmapShareMaskOpacity
    case heatmapShareMonth
    case heatmapShareNoRoutes
    case heatmapSharePhoto
    case heatmapShareSelectRouteForColor
    case heatmapShareTitle
    case heatmapShareWeek
    case heatmapShareYear
    case routeLoading
    case routeMerge
    case routeMergeCompletedMessage
    case routeMergeCompletedTitle
    case routeMergeDefaultTitle
    case routeMergeFailed
    case routeMergeLoading
    case routeMergeMultipleTitleFormat
    case routeMergeNoRoutes
    case routeMergeViewRoutes
    case restorePurchases
    case running
    case satellite
    case share
    case sportsCareerAnnualData
    case sportsCareerMonthlyData
    case sportsCareerOverview
    case sportsCareerLocations
    case sportsCareerWorldMap
    case sportsCareerChinaMap
    case sportsCareerCountryCountFormat
    case sportsCareerCityCountFormat
    case sportsCareerSummary
    case sportsCareerWeeklyData
    case sportsCareerWeekDistanceFormat
    case sportsCareerWeekTitleWithRangeFormat
    case sportTypeCountSummary
    case sportTypeTimeSummary
    case sportsCareer
    case data
    case standard
    case sportType
    case sportTypeSummary
    case strava
    case stravaAuthorizationAlreadyGrantedMessage
    case stravaDataSourceSubtitle
    case stravaReauthorizationRequired
    case saveLivePhoto
    case startTimeFormat
    case stillOpen
    case systemPhotos
    case systemMapsNotFound
    case termsOfUse
    case totalActivityCountFormat
    case totalDistanceFormat
    case totalWorkoutCount
    case totalWorkoutDistance
    case totalWorkoutTime
    case trailRunning
    case tools
    case time
    case today
    case uiSettings
    case unknownDistance
    case unknownDuration
    case unknownLocation
    case virtualCycling
    case virtualRunning
    case walking
    case walkingHiking
    case widgets
    case widgetSmallWeeklyGoal
    case widgetWeeklyChart
    case widgetMonthlyCalendar
    case widgetAnnualTrajectory
    case widgetLocationMaps
    case widgetWorldMap
    case widgetWorldCountryWorkoutFormat
    case widgetChinaMap
    case widgetChinaCityWorkoutFormat
    case widgetWeeklyGoalDistance
    case kilometers
    case workoutStart
    case workoutEnd
    case endNotFound
    case startNotFound
    case yesterday
    case burnedCaloriesFormat
    case calories
    case durationHoursFormat
    case durationHoursMinutesFormat
    case durationMinutesFormat
    case elevationGainFormat
}

final class AppLanguageStore {
    static let shared = AppLanguageStore()
    static let languageDidChangeNotification = Notification.Name("studio.pj.PTrack.languageDidChange")

    private static let fallbackLanguage: AppLanguage = .chinese
    private static let appleLanguagesKey = "AppleLanguages"
    private static let legacyLanguageKey = "studio.pj.PTrack.appLanguage"

    private let defaults: UserDefaults
    private var lastResolvedLanguage: AppLanguage

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastResolvedLanguage = Self.resolveLanguage(in: defaults)
    }

    var language: AppLanguage {
        get {
            let resolvedLanguage = Self.resolveLanguage(in: defaults)
            lastResolvedLanguage = resolvedLanguage
            return resolvedLanguage
        }
        set {
            let storedSystemLanguage = Self.preferredSupportedLanguage(
                from: defaults.array(forKey: Self.appleLanguagesKey) as? [String]
            )
            guard newValue != Self.resolveLanguage(in: defaults) || storedSystemLanguage != newValue else {
                return
            }

            defaults.set([newValue.rawValue], forKey: Self.appleLanguagesKey)
            defaults.removeObject(forKey: Self.legacyLanguageKey)
            defaults.synchronize()
            lastResolvedLanguage = newValue
            NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: newValue)
        }
    }

    @discardableResult
    func refreshFromSystemSettingsIfNeeded() -> Bool {
        let resolvedLanguage = Self.resolveLanguage(in: defaults)
        guard resolvedLanguage != lastResolvedLanguage else {
            return false
        }

        lastResolvedLanguage = resolvedLanguage
        NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: resolvedLanguage)
        return true
    }

    private static func resolveLanguage(in defaults: UserDefaults) -> AppLanguage {
        if let language = preferredSupportedLanguage(from: defaults.array(forKey: appleLanguagesKey) as? [String]) {
            return language
        }

        if let rawValue = defaults.string(forKey: legacyLanguageKey),
           let legacyLanguage = AppLanguage(rawValue: rawValue) {
            return legacyLanguage
        }

        if let language = preferredSupportedLanguage(from: Bundle.main.preferredLocalizations) {
            return language
        }

        if let language = preferredSupportedLanguage(from: Locale.preferredLanguages) {
            return language
        }

        return fallbackLanguage
    }

    private static func preferredSupportedLanguage(from identifiers: [String]?) -> AppLanguage? {
        identifiers?.compactMap { language(for: $0) }.first
    }

    private static func language(for identifier: String) -> AppLanguage? {
        let normalizedIdentifier = Locale(identifier: identifier)
            .identifier
            .replacingOccurrences(of: "_", with: "-")

        if normalizedIdentifier == AppLanguage.chinese.rawValue
            || normalizedIdentifier.hasPrefix("\(AppLanguage.chinese.rawValue)-")
            || normalizedIdentifier == "zh"
            || normalizedIdentifier.hasPrefix("zh-CN")
            || normalizedIdentifier.hasPrefix("zh-SG") {
            return .chinese
        }

        if normalizedIdentifier == AppLanguage.japanese.rawValue
            || normalizedIdentifier.hasPrefix("\(AppLanguage.japanese.rawValue)-") {
            return .japanese
        }

        if normalizedIdentifier == AppLanguage.korean.rawValue
            || normalizedIdentifier.hasPrefix("\(AppLanguage.korean.rawValue)-") {
            return .korean
        }

        if normalizedIdentifier == AppLanguage.english.rawValue
            || normalizedIdentifier.hasPrefix("\(AppLanguage.english.rawValue)-") {
            return .english
        }

        return nil
    }
}

enum AppLocalization {
    static func text(_ key: AppTextKey, language: AppLanguage = AppLanguageStore.shared.language) -> String {
        translations[language]?[key] ?? translations[.chinese]?[key] ?? key.rawValue
    }

    static func format(
        _ key: AppTextKey,
        _ arguments: CVarArg...,
        language: AppLanguage = AppLanguageStore.shared.language
    ) -> String {
        String(format: text(key, language: language), arguments: arguments)
    }

    private static let translations: [AppLanguage: [AppTextKey: String]] = [
        .chinese: [
            .all: "全部",
            .applyToAll: "应用到全部",
            .appleFitnessDownloadCTA: "下载 apple 健身去运动！",
            .appearanceSettings: "外观设置",
            .appearanceSystem: "跟随系统",
            .appLanguage: "App 语言",
            .appIsUpToDate: "已是最新版本",
            .checkForUpdates: "检查更新",
            .checkingForUpdates: "正在检查更新…",
            .updateAvailableTitle: "版本更新",
            .updateCheckFailed: "暂时无法检查更新，请稍后再试",
            .updateDismiss: "好的",
            .updateNow: "去更新",
            .aspectRatio: "比例",
            .appleHealth: "苹果健康",
            .appDefault: "默认",
            .activitySummaryPrefix: "运动",
            .newDataSyncing: "新数据同步中",
            .cancel: "取消",
            .collage: "拼图",
            .collageSingleLivePhotoLimit: "拼图模式只允许加入一张 Live 图",
            .collageStyle: "样式",
            .colorBlack: "黑色",
            .colorBlue: "蓝色",
            .colorCustom: "色板",
            .colorGray: "浅灰",
            .colorOrange: "橙色",
            .colorPink: "粉色",
            .colorWhite: "白色",
            .color: "颜色",
            .canvas: "画布",
            .cycling: "骑行",
            .dark: "暗色",
            .dataIntegration: "数据接入",
            .dayBeforeYesterday: "前天",
            .delete: "删除",
            .deleteRoute: "删除路线？",
            .deleteRouteMessage: "删除后无法恢复。",
            .debugProAccessLocked: "未解锁",
            .debugProAccessMockEnabled: "启用 Pro 模拟",
            .debugProAccessSimulation: "模拟 Pro 功能解锁",
            .debugProAccessUnlocked: "已解锁",
            .debugHomeDataSimulation: "首页数据模拟",
            .debugSimulateHomeEmptyData: "模拟首页空数据",
            .demoModeEntry: "查看演示模式",
            .demoModeExit: "退出演示模式",
            .demoModeExitMessage: "退出后将回到真实数据模式。",
            .demoModeExitTitle: "退出演示模式？",
            .demoModeTitle: "演示模式",
            .developerWebsite: "开发者网站",
            .developerTools: "开发者工具",
            .disable: "关闭",
            .distanceMetersFormat: "%.0f 米",
            .enable: "开启",
            .estimatedBurnedCaloriesFormat: "约消耗 %.0f 大卡",
            .exit: "退出",
            .healthAuthorizationDenied: "未获得健康数据读取权限。",
            .healthAuthorizationFailed: "健康授权失败",
            .healthAuthorizationProgress: "正在请求 Apple 健康体能训练、路线和运动指标读取权限...",
            .healthAuthorizationSettingsRequiredMessage: "请在系统设置或健康 App 中为 Movinn 打开体能训练、路线和运动指标读取权限。",
            .healthAuthorizationSettingsRequiredTitle: "需要 Apple 健康权限",
            .healthAuthorizationTemporarilyUnavailable: "Apple 健康暂时还没准备好，请稍后重试。",
            .healthDataReadAuthorized: "已授权读取数据",
            .healthDataUnavailable: "当前设备不支持健康数据。",
            .homeDataLoadingMessage: "数据加载中，请稍后...",
            .homeNoWorkoutDataMessage: "没有查到你的数据，快出门运动吧！",
            .appleHealthDataSourceSubtitle: "读取 Apple 健康中记录的数据。",
            .exportGPX: "导出 GPX",
            .gpxExportFailed: "GPX 导出失败",
            .gpxExportNoRoute: "这条轨迹没有可导出的路线点。",
            .gpxExportRouteName: "来自 Movinn 的路线",
            .gpxExporting: "正在导出 GPX",
            .gpxImportInvalidFile: "无法解析这个 GPX 文件。",
            .gpxImportNoRoute: "这个 GPX 文件里没有可用轨迹。",
            .followPhoto: "跟随",
            .hiking: "徒步",
            .iCloudRouteSync: "iCloud 同步",
            .iCloudRouteSyncAccountChangedMessage: "iCloud 账号已变化，请重新开启路线同步。",
            .iCloudRouteSyncAccountUnavailableMessage: "请先在系统设置中登录 iCloud，并开启 iCloud Drive。",
            .iCloudRouteSyncAlreadyEnabled: "iCloud 同步已开启",
            .iCloudRouteSyncConfirmMessage: "确认后会同步导入路线数据，并在之后导入或删除路线时自动同步 iCloud。",
            .iCloudRouteSyncConfirmTitle: "确认同步导入路线数据？",
            .iCloudRouteSyncDisabled: "已关闭 iCloud 同步",
            .iCloudRouteSyncDisableConfirmMessage: "关闭后将停止同步导入路线数据，之后导入或删除路线不会自动同步 iCloud。已同步到 iCloud 的数据会保留。",
            .iCloudRouteSyncDisableConfirmTitle: "关闭 iCloud 同步？",
            .iCloudRouteSyncEnabled: "已开启 iCloud 同步",
            .iCloudRouteSyncDocumentUnavailableMessage: "暂时无法读取 iCloud 中的路线文件。",
            .iCloudRouteSyncDriveUnavailableMessage: "暂时无法访问 iCloud Drive，请稍后再试。",
            .iCloudRouteSyncFailed: "iCloud 同步开启失败",
            .routeCollectionICloudSyncFooterCompleteFormat: "已与 iCloud 同步 · 共 %d 个文件",
            .routeCollectionICloudSyncFooterErrorFormat: "iCloud 同步暂不可用 · 还有 %d/%d 个文件未同步",
            .routeCollectionICloudSyncFooterPendingFormat: "还有 %d/%d 个文件未同步",
            .routeCollectionICloudSyncFooterPreparing: "正在检查 iCloud 同步状态…",
            .mapBackgroundAdjustmentHint: "双击地图调整",
            .mapStyle: "地图样式",
            .livePhotoSaved: "已保存到相册",
            .livePhotoSaving: "正在生成 Live Photo",
            .light: "亮色",
            .more: "更多",
            .movinnLocalDataPrivacyStatement: "- Movinn 默认只在本地读取和处理你的数据。仅当你主动开启 iCloud 同步时，导入路线的 GPX 文件会保存到你的 iCloud Drive。\n- 内置了全球国家和部分城市数据库，所有查询均不联网。",
            .movinnPro: "Movinn Pro",
            .newActivity: "新活动！",
            .newRoute: "新路线！",
            .ok: "好",
            .navigation: "导航",
            .startNavigation: "开始导航",
            .openEnd: "去终点",
            .openPhotos: "去相册查看",
            .openStart: "去起点",
            .openSettings: "打开设置",
            .other: "其他",
            .outdoorSwimming: "户外游泳",
            .outdoorWorkout: "户外运动",
            .photoLibraryFullAccessRequiredMessage: "只有完整访问权限才能为轨迹匹配照片。请在系统设置中把照片权限改为“完全访问”。",
            .photoLibraryFullAccessRequiredTitle: "需要完整相册权限",
            .photoLibraryReadAuthorized: "已授权读取相册",
            .photoSaving: "正在保存图片",
            .photoBackgroundAdjustmentHint: "双击照片调整",
            .photoMatching: "照片匹配",
            .privacyPolicy: "隐私政策",
            .proCodeRedemption: "代码兑换",
            .proFeatureHeatmap: "查看运动路线热图",
            .proFeatureWellnessRecap: "根据你的运动数据提供指导建议",
            .proFeatureICloudRouteSync: "iCloud 同步导入路线",
            .proFeatureMultiLivePhotoExport: "支持轨迹多动图\n分享",
            .proFeatureMoreComing: "未来更多功能",
            .proFeatureRouteMerge: "合并多段运动轨迹",
            .proFeatureRouteSlope: "显示轨迹坡度情况",
            .proPaywallSubtitle: "Movinn 持续提供高级功能，让你的运动更加从容！",
            .proPaywallTitle: "解锁高级功能",
            .proProductUnavailable: "暂时无法获取订阅商品，请稍后再试。",
            .proPurchaseButton: "永久解锁",
            .proPurchaseButtonPriceFormat: "永久解锁 %@",
            .proPurchaseFailed: "购买没有完成，请稍后重试。",
            .proPurchaseLoading: "处理中",
            .proPurchaseNotAllowed: "当前设备不允许 App 内购买。",
            .proPurchasePending: "购买正在等待确认。",
            .proPurchaseSuccess: "已开通 Movinn Pro",
            .proPurchaseUnverified: "购买校验失败，请稍后重试。",
            .proRestoreNoPurchase: "没有找到可恢复的购买",
            .proRestoreSuccess: "购买已恢复",
            .proStatusActive: "高级功能已解锁",
            .proUnlockedTitle: "已解锁高级功能",
            .queryingLocation: "位置查询中",
            .routeBook: "作为路书",
            .routeBookExit: "退出作为路书？",
            .routeBookExitMessage: "退出后将回到运动列表。",
            .routeBookLocationPermissionRequiredMessage: "请在系统设置中允许 Movinn 使用位置，这样才能在作为路书时显示你的位置。",
            .routeBookLocationPermissionRequiredTitle: "需要位置权限",
            .route: "轨迹",
            .routeSlope: "坡度",
            .routeSlopeColorHint: "偏绿的路段平缓，偏红的路段陡峭",
            .routeStyle3DFollowColor: "跟随颜色",
            .routeStyle3DSlopeColor: "坡度配色",
            .wellnessRecapSheetTitle: "指导建议",
            .wellnessHeaderTip: "👆 点这里，看看基于你运动数据的指导建议",
            .wellnessRangeThreeDays: "三天",
            .wellnessRangeWeek: "一周",
            .wellnessRangeMonth: "一月",
            .wellnessRangeHalfYear: "半年",
            .wellnessRangeYear: "一年",
            .wellnessSectionFacts: "数据概览",
            .wellnessSectionTrends: "趋势",
            .wellnessSectionAdvice: "建议",
            .wellnessChartSleep: "睡眠时长（小时）",
            .wellnessChartSteps: "每日步数",
            .wellnessChartLoad: "运动负荷",
            .wellnessTableHeaderMetric: "指标",
            .wellnessTableHeaderCurrent: "本期",
            .wellnessTableHeaderReference: "参照",
            .wellnessTableHeaderChange: "变化",
            .wellnessMetricSleep: "睡眠时长",
            .wellnessMetricSteps: "日均步数",
            .wellnessMetricExercise: "锻炼分钟",
            .wellnessMetricWorkouts: "运动次数",
            .wellnessMetricDistance: "运动距离",
            .wellnessMetricRHR: "静息心率",
            .wellnessMetricHRV: "心率变异性",
            .wellnessAdviceSleepTrendUpTitle: "睡眠在变好",
            .wellnessAdviceSleepTrendUpEvidence: "本期平均比上期多睡约 %@ 小时",
            .wellnessAdviceSleepTrendUpBody: "无论是刻意调整还是节奏使然，这个方向是对的，保持住。",
            .wellnessAdviceSleepTrendDownTitle: "睡眠在变少",
            .wellnessAdviceSleepTrendDownEvidence: "本期平均比上期少睡约 %@ 小时",
            .wellnessAdviceSleepTrendDownBody: "持续数周的下滑比单日波动更值得关注，回想一下这段时间作息发生了什么变化。",
            .wellnessAdviceVolumeUpTitle: "运动量在上升",
            .wellnessAdviceVolumeUpEvidence: "本期锻炼总量比上期多约 %d%%",
            .wellnessAdviceVolumeUpBody: "总量上升的同时注意循序渐进，把恢复日留够。",
            .wellnessAdviceVolumeDownTitle: "运动量在回落",
            .wellnessAdviceVolumeDownEvidence: "本期锻炼总量比上期少约 %d%%",
            .wellnessAdviceVolumeDownBody: "回落本身不是问题，关键是别让间隔拉太长；先安排一次轻松的即可。",
            .wellnessAdviceConsistencyGoodTitle: "运动非常规律",
            .wellnessAdviceConsistencyGoodEvidence: "%d/%d 周有运动记录",
            .wellnessAdviceConsistencyGoodBody: "规律性是长期收益的核心，比单次强度更重要，继续保持。",
            .wellnessAdviceConsistencyLowTitle: "规律性可以更好",
            .wellnessAdviceConsistencyLowEvidence: "只有 %d/%d 周有运动记录",
            .wellnessAdviceConsistencyLowBody: "比起偶尔的大强度，每周固定一个时间段的小运动更容易坚持。",
            .wellnessAdvicePBTitle: "刷新了纪录",
            .wellnessAdvicePBEvidence: "本期单次最长距离 %@ 公里，超过上期",
            .wellnessAdvicePBBody: "距离纪录被刷新，说明底子在变厚。",
            .wellnessAdviceDaylightTitle: "白天光照偏少",
            .wellnessAdviceDaylightEvidence: "近几天日均户外光照约 %d 分钟",
            .wellnessAdviceDaylightBody: "白天的自然光是校准生物钟最有效的信号。上午出门 15 分钟，比晚上强迫自己早睡更管用。",
            .wellnessAdviceMidpointLateTitle: "入睡整体在后移",
            .wellnessAdviceMidpointLateEvidence: "近几天睡眠中点比常态晚约 %d 分钟",
            .wellnessAdviceMidpointLateBody: "整体后移往往是不知不觉发生的。今晚把上床时间往回挪 20 分钟，比周末一次性补觉有效。",
            .wellnessAdviceDeepSleepTitle: "深睡占比偏低",
            .wellnessAdviceDeepSleepEvidence: "近几晚深睡约占总睡眠的 %d%%",
            .wellnessAdviceDeepSleepBody: "设备的深睡为估算值，仅供参考。睡前一小时远离咖啡因和强光，通常对深睡最直接。",
            .wellnessAdviceRHRImprovedTitle: "心肺在变强",
            .wellnessAdviceRHRImprovedEvidence: "静息心率比常态低约 %d bpm（当前约 %d bpm）",
            .wellnessAdviceRHRImprovedBody: "静息心率下降是有氧能力提升最可靠的信号之一，最近的训练在起作用。",
            .wellnessAdviceStepsUpTitle: "日常活动量在上升",
            .wellnessAdviceStepsUpEvidence: "本期日均步数比上期多约 %d%%",
            .wellnessAdviceStepsUpBody: "日常步行的提升往往比刻意训练更可持续，这是个好势头。",
            .wellnessAdviceStepsDownTitle: "日常活动量在下降",
            .wellnessAdviceStepsDownEvidence: "本期日均步数比上期少约 %d%%",
            .wellnessAdviceStepsDownBody: "运动之外的日常活动同样重要。通勤或午后加一段步行，是最容易补回来的部分。",
            .wellnessAdviceHabitDayTitle: "你的运动日是%@",
            .wellnessAdviceHabitDayEvidence: "%d 个运动日集中在%@",
            .wellnessAdviceHabitDayBody: "固定的运动日是最被低估的坚持技巧——它把\u{201C}要不要动\u{201D}变成了\u{201C}到点就动\u{201D}。",
            .wellnessAdviceStepsConsistentTitle: "步数很稳",
            .wellnessAdviceStepsConsistentEvidence: "近 %2$d 天中有 %1$d 天达到常态水平以上",
            .wellnessAdviceStepsConsistentBody: "稳定比冲高更难得，日常活动的底盘很扎实。",
            .wellnessAdviceHRVHighTitle: "恢复状态在线",
            .wellnessAdviceHRVHighEvidence: "心率变异性比常态高约 %d%%",
            .wellnessAdviceHRVHighBody: "身体恢复得不错，如果计划里有强度课，最近是安排的好时机。",
            .wellnessAdviceWorkoutGapTitle: "间隔有点长了",
            .wellnessAdviceWorkoutGapEvidence: "已连续 %d 天没有运动记录",
            .wellnessAdviceWorkoutGapBody: "对平时有训练习惯的你来说，间隔拉长会让重启变难。今天来一次轻松的就够。",
            .wellnessAdviceStreakTitle: "连着动起来了",
            .wellnessAdviceStreakEvidence: "已连续 %d 天有运动记录",
            .wellnessAdviceStreakBody: "势头很好。也别忘了给身体留恢复日——连续之后的轻松日同样是训练的一部分。",
            .wellnessAdviceRHRTrendGoodTitle: "静息心率在下降",
            .wellnessAdviceRHRTrendGoodEvidence: "本期比上期低约 %d bpm（当前约 %d bpm）",
            .wellnessAdviceRHRTrendGoodBody: "长期静息心率下降通常意味着有氧底子在变厚，这个趋势值得保持。",
            .wellnessAdviceRHRTrendBadTitle: "静息心率在上升",
            .wellnessAdviceRHRTrendBadEvidence: "本期比上期高约 %d bpm（当前约 %d bpm）",
            .wellnessAdviceRHRTrendBadBody: "长期上升可能与压力、睡眠或恢复不足有关。仅供参考，如伴随不适请咨询专业人员。",
            .wellnessAdviceCarbTitle: "长时间运动后先补碳水",
            .wellnessAdviceCarbEvidence: "本期有 %d 次 60 分钟以上的运动，最长约 %d 分钟",
            .wellnessAdviceCarbBody: "60 分钟以上的运动会明显消耗糖原。结束后 1–2 小时内吃到主食类碳水（米饭、面食、燕麦或水果），恢复效率最高。",
            .wellnessAdviceProteinTitle: "蛋白质别只在晚饭补",
            .wellnessAdviceProteinEvidence: "本期运动合计约 %d 分钟",
            .wellnessAdviceProteinBody: "运动后 20–30 克蛋白质（约一个手掌大小的肉类、两个鸡蛋或一杯希腊酸奶）就够。分散在三餐比集中一顿更有效。",
            .wellnessAdviceHydrationTitle: "补水要分次，不要一次灌",
            .wellnessAdviceHydrationEvidence: "本期单日最高活动消耗约 %d 千卡",
            .wellnessAdviceHydrationEvidenceLong: "本期有 90 分钟以上的长时间运动",
            .wellnessAdviceHydrationBody: "大量出汗后一次性喝大量白水反而会稀释电解质。少量多次，超过 1 小时的运动可以补含钠的饮品或加点盐分的食物。",
            .wellnessAdviceLateMealTitle: "睡不够时更容易想吃",
            .wellnessAdviceLateMealEvidence: "本期平均睡眠约 %@ 小时",
            .wellnessAdviceLateMealBody: "睡眠不足会推高饥饿感、削弱饱腹信号，晚上尤其明显。把正餐安排在睡前 2 小时以上，会比刻意克制更省力。",
            .wellnessAdviceLightWeekTitle: "低活动期按需吃就好",
            .wellnessAdviceLightWeekEvidence: "本期运动量较低",
            .wellnessAdviceLightWeekBody: "训练量少的阶段不需要额外加餐，保持蛋白质和蔬菜的基本量即可，等训练量回来了再调整。",
            .wellnessAdviceSleepRoutineTitle: "睡眠节奏保持得不错",
            .wellnessAdviceSleepRoutineEvidence: "本期平均睡眠约 %@ 小时",
            .wellnessAdviceSleepRoutineBody: "没有明显异常。继续维持固定的上床时间，比偶尔的长睡更有价值。",
            .wellnessAdviceMixTitle: "试试搭配不同强度",
            .wellnessAdviceMixEvidence: "本期运动合计约 %d 分钟",
            .wellnessAdviceMixBody: "大部分时间做轻松有氧、少部分做高强度，是被反复验证的耐力提升结构。都堆在中等强度反而收益最低。",
            .wellnessAdviceRestDayTitle: "把恢复日排进计划",
            .wellnessAdviceRestDayEvidence: "恢复同样是训练的一部分",
            .wellnessAdviceRestDayBody: "身体是在休息时变强的，不是在训练时。每周留 1–2 天低强度或完全休息，长期进步更稳。",
            .wellnessAdviceCarbNowTitle: "这一两天先把糖原补回来",
            .wellnessAdviceCarbNowEvidence: "最近一次长时间运动约 %d 分钟",
            .wellnessAdviceCarbNowBody: "长时间运动后的 24 小时里，碳水的补充比蛋白质更关键。下一顿主食吃够，比只加一份鸡胸肉更有用。",
            .wellnessAdviceProteinNowTitle: "接下来两餐带上蛋白质",
            .wellnessAdviceProteinNowEvidence: "近三天运动合计约 %d 分钟",
            .wellnessAdviceProteinNowBody: "刚练完的这一两天肌肉修复最活跃。每餐加一份蛋白质（鸡蛋、豆制品、鱼肉都行），比集中补一顿有效。",
            .wellnessAdviceFuelGrowthTitle: "训练量涨了，吃也要跟上",
            .wellnessAdviceFuelGrowthEvidence: "折合每周约 %d 分钟训练，且明显高于上期",
            .wellnessAdviceFuelGrowthBody: "训练量上台阶时，最常见的问题不是吃太多而是吃太少，表现为越练越没劲。主食和蛋白质都该同步上调。",
            .wellnessAdviceNutritionBaseTitle: "这个训练量下的饮食基础",
            .wellnessAdviceNutritionBaseEvidence: "折合每周约 %d 分钟训练",
            .wellnessAdviceNutritionBaseBody: "维持这个量，日常三餐里稳定的主食、蛋白质和蔬菜比任何补剂都重要。真正决定长期状态的是基础饮食的稳定性。",
            .wellnessAdviceNutritionBaseYearBody: "一整年维持这个量，靠的是可持续的日常饮食，而不是赛前突击。稳定的三餐结构就是最好的长期方案。",
            .wellnessAdviceMilestoneTitle: "这段时间的里程碑",
            .wellnessAdviceMilestoneEvidence: "累计 %@ 公里，共 %d 次运动",
            .wellnessAdviceMilestoneBody: "这个累计量是靠一次次积累出来的。回头看，坚持本身就是最难的部分。",
            .wellnessAdviceMilestoneYearBody: "一年的累计量摊开看很惊人，但它只是由每一次普通的出门组成的。这就是长期主义的样子。",
            .wellnessAdviceSeasonalTitle: "运动量有季节性",
            .wellnessAdviceSeasonalEvidence: "%@ 最活跃，%@ 最少",
            .wellnessAdviceSeasonalBody: "季节波动很正常，值得做的是给淡季准备替代方案——室内、短时长或换个项目，让底子不至于掉太多。",
            .wellnessAdviceTonightTitle: "今晚早点睡",
            .wellnessAdviceTonightEvidence: "昨晚睡了约 %@ 小时，常态是 %@ 小时",
            .wellnessAdviceTonightBody: "今晚争取 %@ 前上床，比平时提前约 %d 分钟。缺口在当天补最有效，拖到周末效果会打折。",
            .wellnessTipSleep1: "固定起床时间比固定入睡时间更容易做到，也更能稳住生物钟。",
            .wellnessTipSleep2: "睡前一小时把灯调暗，比数羊有用得多——光照是最强的清醒信号。",
            .wellnessTipSleep3: "咖啡因的半衰期约 5 小时，下午三点后的那杯常常是深睡变少的原因。",
            .wellnessTipSleep4: "睡前泡个热水澡，出浴后体温下降的过程本身就是助眠信号。",
            .wellnessTipSleep5: "如果躺下 20 分钟还睡不着，起身做点安静的事再回来，比硬躺更有效。",
            .wellnessTipActivity1: "把运动装备提前一晚放门口，是被验证过最有效的\u{201C}降低启动门槛\u{201D}方法。",
            .wellnessTipActivity2: "宁可缩短时长也别跳过——十分钟的运动对习惯的价值远高于零。",
            .wellnessTipActivity3: "换个路线或换个项目，往往比逼自己加量更能续上兴趣。",
            .wellnessTipActivity4: "热身不用复杂，前五分钟放慢速度本身就是最好的热身。",
            .wellnessTipActivity5: "一周里有一次和别人一起运动，坚持率会明显高于全部独自完成。",
            .wellnessTipNutrition1: "运动后先补水再吃东西，脱水状态下的食欲信号往往不准。",
            .wellnessTipNutrition2: "把水果放在看得见的地方，是成本最低的饮食结构调整。",
            .wellnessTipNutrition3: "训练日和休息日的食量本来就该不同，不必每天一模一样。",
            .wellnessTipNutrition4: "加工程度越低的碳水，饱腹感和血糖波动通常都更友好。",
            .wellnessTipNutrition5: "晚餐吃太晚会挤占深睡时间，睡前两小时是个好界限。",
            .wellnessTipRecovery1: "恢复不只是躺着——散步、拉伸这类低强度活动往往比完全不动恢复更快。",
            .wellnessTipRecovery2: "连续两周状态下滑，通常是训练之外的因素（工作、睡眠、情绪）在起作用。",
            .wellnessTipRecovery3: "静息心率和心率变异性受当天饮酒、疾病影响很大，看趋势别看单日。",
            .wellnessTipRecovery4: "感到\u{201C}腿沉\u{201D}时降强度不降频率，比直接停练更容易回到状态。",
            .wellnessTipPositive1: "进步大多不是线性的，平台期同样是变强过程的一部分。",
            .wellnessTipPositive2: "把这个状态记下来，下次低谷时回看会很有帮助。",
            .wellnessTipPositive3: "状态好的时候最容易加量过头，记得给下一周留出余地。",
            .wellnessTipPositive4: "能长期坚持的运动，通常是那个你不讨厌的运动，而不是最高效的那个。",
            .wellnessSummaryRisk: "本周有需要注意的信号，先看置顶这条。",
            .wellnessSummaryAttention: "整体不错，有几处可以微调。",
            .wellnessSummaryGood: "状态在线，继续保持。",
            .wellnessSummaryCold: "数据还在积累，先看看本周的事实。",
            .wellnessFactSleepFormat: "睡眠：近 7 天平均 %@ 小时（记录 %d 天）",
            .wellnessFactStepsFormat: "步数：日均 %@ 步",
            .wellnessFactWorkoutsFormat: "运动：%d 次 · 共 %@ 公里 · %d 分钟",
            .wellnessFactExerciseFormat: "锻炼时长：本周合计 %d 分钟",
            .wellnessCoverageNoteFormat: "部分日期未记录（睡眠 %d/%d 天、步数 %d/%d 天），未记录不计为 0。",
            .wellnessDisclaimer: "以上为基于你个人数据的生活方式参考，在本机生成，不构成医疗建议。",
            .wellnessAuthPromptTitle: "想更懂自己的运动吗",
            .wellnessAuthPromptBody: "如果愿意，可以让 Movinn 读取健康数据。它会结合你的睡眠、步数和运动，在这台设备上生成属于你的总结与建议——所有分析都在本地完成，数据不会上传，也不会分享给任何人。你随时可以在系统设置里调整。",
            .wellnessAuthButton: "好，试试看",
            .wellnessLoading: "正在生成本周指导…",
            .wellnessEmptyBody: "数据还在积累。佩戴设备记录几天后，这里会给出你的专属总结。",
            .wellnessAdviceSleepDebtTitle: "补一补睡眠债",
            .wellnessAdviceSleepDebtEvidence: "近 7 天累计比常态少睡约 %@ 小时",
            .wellnessAdviceSleepDebtBody: "建议接下来 3 晚提前约 %d 分钟上床，今晚可在 %@ 前休息。",
            .wellnessAdviceSleepIrregularTitle: "作息波动较大",
            .wellnessAdviceSleepIrregularEvidence: "近 7 天入睡时间波动约 ±%d 分钟",
            .wellnessAdviceSleepIrregularBody: "比起补时长，固定上床窗口更有效：试试在 %@–%@ 之间入睡。",
            .wellnessAdviceSleepShortTitle: "睡眠持续偏短",
            .wellnessAdviceSleepShortEvidence: "近 7 天平均 %@ 小时，低于你的常态 %@ 小时",
            .wellnessAdviceSleepShortBody: "连续偏短会先拖慢恢复，再影响状态。本周先把最容易的一晚补回来。",
            .wellnessAdviceWeekendJetlagTitle: "周末补觉明显",
            .wellnessAdviceWeekendJetlagEvidence: "周末比工作日平均多睡约 %@ 小时",
            .wellnessAdviceWeekendJetlagBody: "补觉说明工作日在欠债。建议工作日上床时间小步前移 15–30 分钟。",
            .wellnessAdviceSleepStableTitle: "睡眠状态稳定",
            .wellnessAdviceSleepStableEvidence: "近 7 天平均 %@ 小时，作息规律",
            .wellnessAdviceSleepStableBody: "时长和规律都在你的常态区间，保持现在的节奏就好。",
            .wellnessAdviceLoadSpikeTitle: "本周加量偏快",
            .wellnessAdviceLoadSpikeEvidence: "近 7 天运动负荷约为近月常态的 %@ 倍",
            .wellnessAdviceLoadSpikeBody: "短期快速加量与伤病风险相关。建议下周回落到常态水平，优先安排低强度。",
            .wellnessAdviceLoadDropTitle: "运动量明显回落",
            .wellnessAdviceLoadDropEvidence: "本周负荷不足常态的六成",
            .wellnessAdviceLoadDropBody: "不必一次补回来：从 2 次、每次约 %d 分钟开始，先回到节奏。",
            .wellnessAdviceSedentaryTitle: "活动量连续偏低",
            .wellnessAdviceSedentaryEvidence: "连续 %d 天步数低于 %@",
            .wellnessAdviceSedentaryBody: "今天先以 %@ 步为目标——这是按你自己的常态定的，不是统一的一万步。",
            .wellnessAdviceRecoveryTitle: "恢复信号偏弱",
            .wellnessAdviceRecoveryEvidence: "静息心率连续 %d 天高于常态约 %d bpm%@",
            .wellnessAdviceRecoveryBody: "建议今明两天安排低强度或休息。仅供参考，如伴随不适请咨询专业人员。",
            .wellnessAdviceRecoveryHRVSuffix: "，且心率变异性同步走低",
            .wellnessAdviceActiveWeekTitle: "本周活动达标",
            .wellnessAdviceActiveWeekEvidence: "本周锻炼合计 %d 分钟",
            .wellnessAdviceActiveWeekBody: "已达到世界卫生组织建议的每周 150 分钟，给自己一点肯定。",
            .routeCollection: "导入路线",
            .routeCollectionMenuTitle: "路线",
            .routeCollectionEmptyMessage: "还没有导入路线",
            .routeCollectionImportSectionTitle: "导入",
            .routeCollectionImportSuccess: "已导入 GPX 路线",
            .routeCollectionImporting: "正在导入 GPX",
            .routeCollectionMergeSectionTitle: "合并",
            .routeHeatmap: "轨迹热图",
            .heatmapShareMask: "遮罩",
            .heatmapShareMaskOpacity: "遮罩透明度",
            .heatmapShareMonth: "月",
            .heatmapShareNoRoutes: "当前时间范围暂无轨迹",
            .heatmapSharePhoto: "照片",
            .heatmapShareSelectRouteForColor: "先选择一条轨迹",
            .heatmapShareTitle: "分享轨迹合集",
            .heatmapShareWeek: "周",
            .heatmapShareYear: "年",
            .routeLoading: "正在加载轨迹",
            .routeMerge: "合并路线",
            .routeMergeCompletedMessage: "合并完成，可以去路线页面里查看。",
            .routeMergeCompletedTitle: "路线已合并",
            .routeMergeDefaultTitle: "合并路线",
            .routeMergeFailed: "合并路线失败",
            .routeMergeLoading: "正在合并路线",
            .routeMergeMultipleTitleFormat: "%@ 等 %d 段",
            .routeMergeNoRoutes: "请选择需要合并的路线。",
            .routeMergeViewRoutes: "去看看",
            .restorePurchases: "恢复购买",
            .running: "跑步",
            .satellite: "卫星",
            .share: "分享",
            .sportsCareerAnnualData: "全年",
            .sportsCareerMonthlyData: "月度",
            .sportsCareerOverview: "总览",
            .sportsCareerLocations: "运动地点",
            .sportsCareerWorldMap: "世界",
            .sportsCareerChinaMap: "中国",
            .sportsCareerCountryCountFormat: "%d 个国家",
            .sportsCareerCityCountFormat: "%d 个城市",
            .sportsCareerSummary: "总览",
            .sportsCareerWeeklyData: "本周",
            .sportsCareerWeekDistanceFormat: "第 %d 周\n%.1f km",
            .sportsCareerWeekTitleWithRangeFormat: "第 %d 周 · %@-%@",
            .sportTypeCountSummary: "不同运动类型的运动次数汇总",
            .sportTypeTimeSummary: "运动时间汇总",
            .sportsCareer: "运动生涯",
            .data: "数据",
            .standard: "标准",
            .sportType: "运动类型",
            .sportTypeSummary: "运动类型汇总",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava 已拿到授权，可以读取你的运动数据。",
            .stravaDataSourceSubtitle: "读取 Strava 中记录的数据。",
            .stravaReauthorizationRequired: "Strava 授权已失效，请进入“更多”页面点击 Strava 重新登录。",
            .saveLivePhoto: "保存 Live Photo",
            .startTimeFormat: "%@ 开始",
            .stillOpen: "仍要打开",
            .systemPhotos: "系统相册",
            .systemMapsNotFound: "未找到系统地图",
            .termsOfUse: "使用条款",
            .totalActivityCountFormat: "%d 次",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "总次数",
            .totalWorkoutDistance: "总里程",
            .totalWorkoutTime: "总时间",
            .trailRunning: "越野跑",
            .tools: "工具",
            .time: "时间",
            .today: "今天",
            .uiSettings: "功能设置",
            .unknownDistance: "未知距离",
            .unknownDuration: "未知时长",
            .unknownLocation: "未知位置",
            .virtualCycling: "虚拟骑行",
            .virtualRunning: "虚拟跑步",
            .walking: "行走",
            .walkingHiking: "行走/徒步",
            .widgets: "小组件",
            .widgetSmallWeeklyGoal: "本周圆环数据",
            .widgetWeeklyChart: "本周柱状图",
            .widgetMonthlyCalendar: "月度日历",
            .widgetAnnualTrajectory: "年度轨迹",
            .widgetLocationMaps: "运动地图",
            .widgetWorldMap: "世界地图",
            .widgetWorldCountryWorkoutFormat: "去过 %d/%d 个国家运动",
            .widgetChinaMap: "中国地图",
            .widgetChinaCityWorkoutFormat: "去过 %d/%d 个城市运动",
            .widgetWeeklyGoalDistance: "每周目标距离",
            .kilometers: "公里",
            .workoutStart: "运动起点",
            .workoutEnd: "运动终点",
            .endNotFound: "未找到终点",
            .startNotFound: "未找到起点",
            .yesterday: "昨天",
            .burnedCaloriesFormat: "消耗 %.0f 大卡",
            .calories: "卡路里",
            .durationHoursFormat: "%d小时",
            .durationHoursMinutesFormat: "%d小时%d分钟",
            .durationMinutesFormat: "%d分钟",
            .elevationGainFormat: "爬升 %.0f 米"
        ],
        .japanese: [
            .all: "すべて",
            .applyToAll: "すべてに適用",
            .appleFitnessDownloadCTA: "Apple Fitness をダウンロードして運動しよう！",
            .appearanceSettings: "外観設定",
            .appearanceSystem: "システムに合わせる",
            .appLanguage: "アプリの言語",
            .appIsUpToDate: "最新バージョンです",
            .checkForUpdates: "アップデートを確認",
            .checkingForUpdates: "アップデートを確認中…",
            .updateAvailableTitle: "バージョンアップデート",
            .updateCheckFailed: "アップデートを確認できません。しばらくしてからもう一度お試しください",
            .updateDismiss: "OK",
            .updateNow: "アップデート",
            .aspectRatio: "比率",
            .appleHealth: "Appleヘルスケア",
            .appDefault: "デフォルト",
            .activitySummaryPrefix: "運動",
            .newDataSyncing: "新しいデータを同期中",
            .cancel: "キャンセル",
            .collage: "コラージュ",
            .collageSingleLivePhotoLimit: "コラージュモードでは Live Photo は1枚だけ追加できます",
            .collageStyle: "レイアウト",
            .colorBlack: "ブラック",
            .colorBlue: "ブルー",
            .colorCustom: "カラーパレット",
            .colorGray: "ライトグレー",
            .colorOrange: "オレンジ",
            .colorPink: "ピンク",
            .colorWhite: "ホワイト",
            .color: "カラー",
            .canvas: "キャンバス",
            .cycling: "サイクリング",
            .dark: "ダーク",
            .dataIntegration: "データ連携",
            .dayBeforeYesterday: "一昨日",
            .delete: "削除",
            .deleteRoute: "ルートを削除しますか？",
            .deleteRouteMessage: "削除すると元に戻せません。",
            .debugProAccessLocked: "未解放",
            .debugProAccessMockEnabled: "Pro 模擬を有効化",
            .debugProAccessSimulation: "Pro 状態をシミュレート",
            .debugProAccessUnlocked: "解放済み",
            .debugHomeDataSimulation: "ホームデータのシミュレーション",
            .debugSimulateHomeEmptyData: "ホームの空データをシミュレート",
            .demoModeEntry: "デモモードを見る",
            .demoModeExit: "デモモードを終了",
            .demoModeExitMessage: "終了すると実データのモードに戻ります。",
            .demoModeExitTitle: "デモモードを終了しますか？",
            .demoModeTitle: "デモモード",
            .developerWebsite: "開発者サイト",
            .developerTools: "開発者ツール",
            .disable: "オフにする",
            .distanceMetersFormat: "%.0f m",
            .enable: "オンにする",
            .estimatedBurnedCaloriesFormat: "約 %.0f kcal 消費",
            .exit: "終了",
            .healthAuthorizationDenied: "ヘルスケアデータの読み取り権限がありません。",
            .healthAuthorizationFailed: "ヘルスケア認証に失敗しました",
            .healthAuthorizationProgress: "Appleヘルスケアのワークアウト、ルート、運動指標の読み取り権限を要求しています...",
            .healthAuthorizationSettingsRequiredMessage: "システム設定またはヘルスケア App で、Movinn のワークアウト、ルート、運動指標の読み取り権限を有効にしてください。",
            .healthAuthorizationSettingsRequiredTitle: "Appleヘルスケアの権限が必要です",
            .healthAuthorizationTemporarilyUnavailable: "Appleヘルスケアはまだ準備中です。少し時間をおいてもう一度お試しください。",
            .healthDataReadAuthorized: "データ読み取りは許可されています",
            .healthDataUnavailable: "このデバイスはヘルスケアデータに対応していません。",
            .homeDataLoadingMessage: "データを読み込んでいます。しばらくお待ちください...",
            .homeNoWorkoutDataMessage: "データが見つかりませんでした。外へ運動に出かけましょう！",
            .appleHealthDataSourceSubtitle: "Appleヘルスケアに記録されたデータを読み取ります。",
            .exportGPX: "GPXを書き出す",
            .gpxExportFailed: "GPXの書き出しに失敗しました",
            .gpxExportNoRoute: "この軌跡には書き出せるルートポイントがありません。",
            .gpxExportRouteName: "Movinn からのルート",
            .gpxExporting: "GPXを書き出し中",
            .gpxImportInvalidFile: "この GPX ファイルを解析できません。",
            .gpxImportNoRoute: "この GPX ファイルに利用できるルートがありません。",
            .followPhoto: "追従",
            .hiking: "ハイキング",
            .iCloudRouteSync: "iCloud同期",
            .iCloudRouteSyncAccountChangedMessage: "iCloudアカウントが変更されました。ルート同期をもう一度オンにしてください。",
            .iCloudRouteSyncAccountUnavailableMessage: "設定でiCloudにサインインし、iCloud Driveをオンにしてください。",
            .iCloudRouteSyncAlreadyEnabled: "iCloud同期はオンです",
            .iCloudRouteSyncConfirmMessage: "読み込んだルートのデータを同期し、今後ルートを読み込むか削除したときに iCloud へ自動同期します。",
            .iCloudRouteSyncConfirmTitle: "読み込んだルートを同期しますか？",
            .iCloudRouteSyncDisabled: "iCloud同期をオフにしました",
            .iCloudRouteSyncDisableConfirmMessage: "オフにすると読み込んだルートの同期を停止し、今後ルートを読み込むか削除したときに iCloud へ自動同期しません。すでに iCloud に同期されたデータは保持されます。",
            .iCloudRouteSyncDisableConfirmTitle: "iCloud同期をオフにしますか？",
            .iCloudRouteSyncEnabled: "iCloud同期をオンにしました",
            .iCloudRouteSyncDocumentUnavailableMessage: "iCloud上のルートファイルを一時的に読み込めません。",
            .iCloudRouteSyncDriveUnavailableMessage: "iCloud Driveに一時的にアクセスできません。後でもう一度お試しください。",
            .iCloudRouteSyncFailed: "iCloud同期をオンにできませんでした",
            .routeCollectionICloudSyncFooterCompleteFormat: "iCloudと同期済み · 全%dファイル",
            .routeCollectionICloudSyncFooterErrorFormat: "iCloud同期を一時利用できません · 未同期：%d/%d件",
            .routeCollectionICloudSyncFooterPendingFormat: "未同期のファイル：%d/%d件",
            .routeCollectionICloudSyncFooterPreparing: "iCloud同期の状態を確認中…",
            .mapBackgroundAdjustmentHint: "地図をダブルタップして調整",
            .mapStyle: "地図スタイル",
            .livePhotoSaved: "写真に保存しました",
            .livePhotoSaving: "Live Photoを生成中",
            .light: "ライト",
            .more: "その他",
            .movinnLocalDataPrivacyStatement: "- Movinnはデフォルトでデータを端末内だけで読み取り、処理します。iCloud同期を自分でオンにした場合のみ、読み込んだルートのGPXファイルがiCloud Driveに保存されます。\n- 世界の国と一部都市のデータベースを内蔵しており、すべての検索はネットワークを使いません。",
            .movinnPro: "Movinn Pro",
            .newActivity: "新規",
            .newRoute: "新規ルート",
            .ok: "OK",
            .navigation: "ナビゲーション",
            .startNavigation: "ナビを開始",
            .openEnd: "ゴールへ",
            .openPhotos: "写真で表示",
            .openStart: "スタートへ",
            .openSettings: "設定を開く",
            .other: "その他",
            .outdoorSwimming: "屋外スイミング",
            .outdoorWorkout: "屋外ワークアウト",
            .photoLibraryFullAccessRequiredMessage: "ルートに写真を照合するには、写真へのフルアクセスが必要です。システム設定で写真の権限を「フルアクセス」に変更してください。",
            .photoLibraryFullAccessRequiredTitle: "写真へのフルアクセスが必要です",
            .photoLibraryReadAuthorized: "写真の読み取りは許可されています",
            .photoSaving: "画像を保存中",
            .photoBackgroundAdjustmentHint: "写真をダブルタップして調整",
            .photoMatching: "写真照合",
            .privacyPolicy: "プライバシー",
            .proCodeRedemption: "コードを使う",
            .proFeatureHeatmap: "ルートヒートマップ",
            .proFeatureWellnessRecap: "運動データに基づくガイドと提案",
            .proFeatureICloudRouteSync: "読み込んだルートを iCloud で同期",
            .proFeatureMultiLivePhotoExport: "複数の軌跡アニメーション共有に対応",
            .proFeatureMoreComing: "今後の機能",
            .proFeatureRouteMerge: "複数区間のルート結合",
            .proFeatureRouteSlope: "ルートの勾配を表示",
            .proPaywallSubtitle: "Movinn は高度な機能で運動をもっと快適にします。",
            .proPaywallTitle: "高度な機能を解放",
            .proProductUnavailable: "サブスクリプションを取得できません。あとでもう一度お試しください。",
            .proPurchaseButton: "永久に解放",
            .proPurchaseButtonPriceFormat: "永久に解放 %@",
            .proPurchaseFailed: "購入を完了できませんでした。",
            .proPurchaseLoading: "処理中",
            .proPurchaseNotAllowed: "このデバイスでは App 内購入を利用できません。",
            .proPurchasePending: "購入は確認待ちです。",
            .proPurchaseSuccess: "Movinn Pro が有効です",
            .proPurchaseUnverified: "購入を確認できませんでした。",
            .proRestoreNoPurchase: "復元できる購入がありません",
            .proRestoreSuccess: "購入を復元しました",
            .proStatusActive: "高度な機能が有効です",
            .proUnlockedTitle: "高度な機能を解放済み",
            .queryingLocation: "位置を検索中",
            .routeBook: "ルートブックとして使う",
            .routeBookExit: "ルートブックモードを終了しますか？",
            .routeBookExitMessage: "終了するとワークアウト一覧に戻ります。",
            .routeBookLocationPermissionRequiredMessage: "ルートブックモードで現在地を表示するには、システム設定で Movinn の位置情報利用を許可してください。",
            .routeBookLocationPermissionRequiredTitle: "位置情報の許可が必要です",
            .route: "ルート",
            .routeSlope: "勾配",
            .routeSlopeColorHint: "緑寄りの区間は緩やかで、赤寄りの区間は急です",
            .routeStyle3DFollowColor: "カラー連動",
            .routeStyle3DSlopeColor: "勾配カラー",
            .wellnessRecapSheetTitle: "ガイドと提案",
            .wellnessHeaderTip: "👆 ここをタップすると、運動データに基づく提案が見られます",
            .wellnessRangeThreeDays: "3日",
            .wellnessRangeWeek: "1週間",
            .wellnessRangeMonth: "1か月",
            .wellnessRangeHalfYear: "半年",
            .wellnessRangeYear: "1年",
            .wellnessSectionFacts: "データ概要",
            .wellnessSectionTrends: "トレンド",
            .wellnessSectionAdvice: "アドバイス",
            .wellnessChartSleep: "睡眠時間（時間）",
            .wellnessChartSteps: "1日の歩数",
            .wellnessChartLoad: "運動負荷",
            .wellnessTableHeaderMetric: "指標",
            .wellnessTableHeaderCurrent: "今期",
            .wellnessTableHeaderReference: "参照",
            .wellnessTableHeaderChange: "変化",
            .wellnessMetricSleep: "睡眠時間",
            .wellnessMetricSteps: "平均歩数",
            .wellnessMetricExercise: "運動時間(分)",
            .wellnessMetricWorkouts: "運動回数",
            .wellnessMetricDistance: "運動距離",
            .wellnessMetricRHR: "安静時心拍",
            .wellnessMetricHRV: "心拍変動",
            .wellnessAdviceSleepTrendUpTitle: "睡眠が改善傾向",
            .wellnessAdviceSleepTrendUpEvidence: "今期は前期より平均約 %@ 時間多く睡眠",
            .wellnessAdviceSleepTrendUpBody: "意識的な調整でも自然な流れでも、良い方向です。維持しましょう。",
            .wellnessAdviceSleepTrendDownTitle: "睡眠が減少傾向",
            .wellnessAdviceSleepTrendDownEvidence: "今期は前期より平均約 %@ 時間少ない睡眠",
            .wellnessAdviceSleepTrendDownBody: "数週間続く減少は単日の変動より注意が必要です。この期間の生活の変化を振り返ってみましょう。",
            .wellnessAdviceVolumeUpTitle: "運動量が増加",
            .wellnessAdviceVolumeUpEvidence: "今期の運動量は前期より約 %d%% 増",
            .wellnessAdviceVolumeUpBody: "増やすときは段階的に。回復日も十分確保しましょう。",
            .wellnessAdviceVolumeDownTitle: "運動量が減少",
            .wellnessAdviceVolumeDownEvidence: "今期の運動量は前期より約 %d%% 減",
            .wellnessAdviceVolumeDownBody: "減ること自体は問題ではありません。間隔を空けすぎず、まず軽い 1 回から。",
            .wellnessAdviceConsistencyGoodTitle: "とても規則的な運動習慣",
            .wellnessAdviceConsistencyGoodEvidence: "%d/%d 週で運動記録あり",
            .wellnessAdviceConsistencyGoodBody: "規則性は長期的な効果の核心で、単発の強度より重要です。この調子で。",
            .wellnessAdviceConsistencyLowTitle: "規則性に改善の余地",
            .wellnessAdviceConsistencyLowEvidence: "運動記録があるのは %d/%d 週のみ",
            .wellnessAdviceConsistencyLowBody: "たまの高強度より、毎週決まった時間帯の軽い運動の方が続けやすいです。",
            .wellnessAdvicePBTitle: "記録更新",
            .wellnessAdvicePBEvidence: "今期の 1 回最長距離は %@ km で前期を上回りました",
            .wellnessAdvicePBBody: "距離の記録更新は基礎が厚くなっている証拠です。",
            .wellnessAdviceDaylightTitle: "日中の光が不足気味",
            .wellnessAdviceDaylightEvidence: "直近の屋外光は 1 日平均約 %d 分",
            .wellnessAdviceDaylightBody: "日中の自然光は体内時計を整える最も有効な信号です。午前中に 15 分外に出る方が、夜に早寝を頑張るより効果的です。",
            .wellnessAdviceMidpointLateTitle: "就寝が全体的に後ろ倒し",
            .wellnessAdviceMidpointLateEvidence: "直近の睡眠中間点が普段より約 %d 分遅れています",
            .wellnessAdviceMidpointLateBody: "後ろ倒しは気づかぬうちに進みます。今夜 20 分だけ早めるのが、週末の寝だめより有効です。",
            .wellnessAdviceDeepSleepTitle: "深い睡眠の割合が低め",
            .wellnessAdviceDeepSleepEvidence: "直近の深い睡眠は全体の約 %d%%",
            .wellnessAdviceDeepSleepBody: "デバイスの深睡眠は推定値で参考程度に。就寝 1 時間前のカフェインと強い光を避けるのが最も直接的です。",
            .wellnessAdviceRHRImprovedTitle: "心肺機能が向上中",
            .wellnessAdviceRHRImprovedEvidence: "安静時心拍数が普段より約 %d bpm 低下（現在約 %d bpm）",
            .wellnessAdviceRHRImprovedBody: "安静時心拍数の低下は有酸素能力向上の最も確かな信号の一つ。最近のトレーニングが効いています。",
            .wellnessAdviceStepsUpTitle: "日常の活動量が増加",
            .wellnessAdviceStepsUpEvidence: "今期の 1 日平均歩数は前期より約 %d%% 増",
            .wellnessAdviceStepsUpBody: "日常の歩行の増加は意図的なトレーニングより持続しやすい、良い傾向です。",
            .wellnessAdviceStepsDownTitle: "日常の活動量が減少",
            .wellnessAdviceStepsDownEvidence: "今期の 1 日平均歩数は前期より約 %d%% 減",
            .wellnessAdviceStepsDownBody: "運動以外の日常活動も同じく大切です。通勤や午後に少し歩くのが、最も取り戻しやすい部分です。",
            .wellnessAdviceHabitDayTitle: "あなたの運動日は%@",
            .wellnessAdviceHabitDayEvidence: "%d 回の運動日が%@に集中",
            .wellnessAdviceHabitDayBody: "決まった運動日は最も過小評価されている継続のコツ。「やるかどうか」を「時間が来たらやる」に変えてくれます。",
            .wellnessAdviceStepsConsistentTitle: "歩数が安定",
            .wellnessAdviceStepsConsistentEvidence: "直近 %2$d 日のうち %1$d 日で普段の水準を達成",
            .wellnessAdviceStepsConsistentBody: "安定は瞬発力より得がたいもの。日常活動の土台がしっかりしています。",
            .wellnessAdviceHRVHighTitle: "回復状態は良好",
            .wellnessAdviceHRVHighEvidence: "心拍変動が普段より約 %d%% 高い状態",
            .wellnessAdviceHRVHighBody: "体はよく回復しています。強度の高い練習を予定しているなら、今が良いタイミングです。",
            .wellnessAdviceWorkoutGapTitle: "間隔が空き気味",
            .wellnessAdviceWorkoutGapEvidence: "%d 日連続で運動記録なし",
            .wellnessAdviceWorkoutGapBody: "普段運動習慣のあるあなたにとって、間隔が長引くと再開が難しくなります。今日は軽めの 1 回で十分。",
            .wellnessAdviceStreakTitle: "連続で動けています",
            .wellnessAdviceStreakEvidence: "%d 日連続で運動記録あり",
            .wellnessAdviceStreakBody: "良い勢いです。回復日も忘れずに——連続後の軽い日もトレーニングの一部です。",
            .wellnessAdviceRHRTrendGoodTitle: "安静時心拍数が低下傾向",
            .wellnessAdviceRHRTrendGoodEvidence: "今期は前期より約 %d bpm 低下（現在約 %d bpm）",
            .wellnessAdviceRHRTrendGoodBody: "長期的な低下は有酸素の基礎が厚くなっているサイン。この傾向を維持しましょう。",
            .wellnessAdviceRHRTrendBadTitle: "安静時心拍数が上昇傾向",
            .wellnessAdviceRHRTrendBadEvidence: "今期は前期より約 %d bpm 上昇（現在約 %d bpm）",
            .wellnessAdviceRHRTrendBadBody: "長期的な上昇はストレス・睡眠・回復不足と関連する場合があります。参考情報です。不調を伴う場合は専門家にご相談ください。",
            .wellnessAdviceCarbTitle: "長時間運動後はまず炭水化物",
            .wellnessAdviceCarbEvidence: "今期は 60 分以上の運動が %d 回、最長約 %d 分",
            .wellnessAdviceCarbBody: "60 分を超える運動はグリコーゲンを大きく消費します。終了後 1〜2 時間以内に主食系の炭水化物（ご飯・麺・オートミール・果物）を摂ると回復効率が高まります。",
            .wellnessAdviceProteinTitle: "たんぱく質は夕食だけに偏らせない",
            .wellnessAdviceProteinEvidence: "今期の運動は合計約 %d 分",
            .wellnessAdviceProteinBody: "運動後は 20〜30g のたんぱく質（手のひら大の肉、卵 2 個、ギリシャヨーグルト 1 カップ程度）で十分。3 食に分けた方が効果的です。",
            .wellnessAdviceHydrationTitle: "水分はこまめに、一気飲みはしない",
            .wellnessAdviceHydrationEvidence: "今期の 1 日最大消費カロリーは約 %d kcal",
            .wellnessAdviceHydrationEvidenceLong: "今期は 90 分を超える長時間運動あり",
            .wellnessAdviceHydrationBody: "大量発汗後に水だけを一気に飲むと電解質が薄まります。少量ずつ頻回に、1 時間を超える運動ではナトリウムを含む飲料や食品を。",
            .wellnessAdviceLateMealTitle: "睡眠不足だと食欲が増えやすい",
            .wellnessAdviceLateMealEvidence: "今期の平均睡眠は約 %@ 時間",
            .wellnessAdviceLateMealBody: "睡眠不足は空腹感を高め満腹感を弱めます。特に夜に顕著です。食事を就寝 2 時間前までに済ませる方が我慢するより楽です。",
            .wellnessAdviceLightWeekTitle: "運動が少ない時期は普段どおりで",
            .wellnessAdviceLightWeekEvidence: "今期は運動量が少なめ",
            .wellnessAdviceLightWeekBody: "トレーニング量が少ない時期に追加の補食は不要です。たんぱく質と野菜の基本量を保ち、量が戻ってから調整しましょう。",
            .wellnessAdviceSleepRoutineTitle: "睡眠リズムは良好",
            .wellnessAdviceSleepRoutineEvidence: "今期の平均睡眠は約 %@ 時間",
            .wellnessAdviceSleepRoutineBody: "目立った乱れはありません。就寝時刻を一定に保つことは、たまの長時間睡眠より価値があります。",
            .wellnessAdviceMixTitle: "強度に変化をつけてみる",
            .wellnessAdviceMixEvidence: "今期の運動は合計約 %d 分",
            .wellnessAdviceMixBody: "大半を楽な有酸素に、一部を高強度に——持久力向上で繰り返し検証された構成です。すべて中強度が最も効率が低くなります。",
            .wellnessAdviceRestDayTitle: "回復日も計画に入れる",
            .wellnessAdviceRestDayEvidence: "回復もトレーニングの一部です",
            .wellnessAdviceRestDayBody: "体は休んでいる間に強くなります。週に 1〜2 日は低強度か完全休養を入れると、長期的な進歩が安定します。",
            .wellnessAdviceCarbNowTitle: "この 1〜2 日はグリコーゲンの回復を",
            .wellnessAdviceCarbNowEvidence: "直近の長時間運動は約 %d 分",
            .wellnessAdviceCarbNowBody: "長時間運動後の 24 時間は、たんぱく質より炭水化物の補給が重要です。次の食事で主食をしっかり摂る方が、鶏むね肉を足すより効果的です。",
            .wellnessAdviceProteinNowTitle: "次の 2 食にたんぱく質を",
            .wellnessAdviceProteinNowEvidence: "直近 3 日の運動は合計約 %d 分",
            .wellnessAdviceProteinNowBody: "運動直後の 1〜2 日は筋肉の修復が最も活発です。毎食に 1 品（卵・大豆製品・魚など）加える方が、1 食に集中させるより効果的です。",
            .wellnessAdviceFuelGrowthTitle: "運動量が増えた分、食事も",
            .wellnessAdviceFuelGrowthEvidence: "週あたり約 %d 分に相当し、前期を大きく上回ります",
            .wellnessAdviceFuelGrowthBody: "運動量が一段上がるとき、よくある問題は食べ過ぎではなく食べ不足で、練るほど力が出ない形で現れます。主食もたんぱく質も同時に増やしましょう。",
            .wellnessAdviceNutritionBaseTitle: "この運動量に見合う食事の土台",
            .wellnessAdviceNutritionBaseEvidence: "週あたり約 %d 分に相当",
            .wellnessAdviceNutritionBaseBody: "この量を維持するなら、日々の主食・たんぱく質・野菜の安定がどんなサプリより重要です。長期の調子を決めるのは基礎的な食事の安定性です。",
            .wellnessAdviceNutritionBaseYearBody: "1 年を通してこの量を維持できるのは、直前の詰め込みではなく持続可能な日常の食事があるからです。安定した 3 食の構成が最良の長期戦略です。",
            .wellnessAdviceMilestoneTitle: "この期間のマイルストーン",
            .wellnessAdviceMilestoneEvidence: "累計 %@ km、運動 %d 回",
            .wellnessAdviceMilestoneBody: "この累計は 1 回ずつの積み重ねです。振り返れば、続けること自体が最も難しい部分でした。",
            .wellnessAdviceMilestoneYearBody: "1 年の累計は圧巻ですが、その中身は普通に外へ出た 1 回 1 回です。それが長期の積み上げの姿です。",
            .wellnessAdviceSeasonalTitle: "運動量に季節性あり",
            .wellnessAdviceSeasonalEvidence: "%@ が最も活発で、%@ が最少",
            .wellnessAdviceSeasonalBody: "季節変動は自然なことです。閑散期の代替案——室内・短時間・別種目——を用意しておくと、基礎を落とさずに済みます。",
            .wellnessAdviceTonightTitle: "今夜は早めに就寝を",
            .wellnessAdviceTonightEvidence: "昨夜の睡眠は約 %@ 時間、普段は %@ 時間",
            .wellnessAdviceTonightBody: "今夜は %@ までに就寝を。普段より約 %d 分早めです。不足はその日のうちに補うのが最も効果的で、週末まで持ち越すと効果が薄れます。",
            .wellnessTipSleep1: "就寝時刻より起床時刻を固定する方が実行しやすく、体内時計も安定します。",
            .wellnessTipSleep2: "就寝 1 時間前に照明を落とす方が、羊を数えるよりずっと有効です。光は最も強い覚醒信号です。",
            .wellnessTipSleep3: "カフェインの半減期は約 5 時間。午後 3 時以降の 1 杯が深い睡眠を減らす原因になりがちです。",
            .wellnessTipSleep4: "就寝前の入浴後、体温が下がる過程そのものが入眠の合図になります。",
            .wellnessTipSleep5: "横になって 20 分眠れなければ、一度起きて静かなことをしてから戻る方が効果的です。",
            .wellnessTipActivity1: "前夜のうちにウェアを玄関に置くのは、開始のハードルを下げる最も検証された方法です。",
            .wellnessTipActivity2: "時間を短くしてでも飛ばさない——10 分の運動は習慣にとってゼロよりはるかに価値があります。",
            .wellnessTipActivity3: "コースや種目を変える方が、量を無理に増やすより興味が続きます。",
            .wellnessTipActivity4: "ウォームアップは複雑でなくてよく、最初の 5 分をゆっくり動くこと自体が最良の準備です。",
            .wellnessTipActivity5: "週に 1 回誰かと一緒に運動すると、継続率が明らかに上がります。",
            .wellnessTipNutrition1: "運動後はまず水分を。脱水状態では食欲の信号が正確でないことが多いです。",
            .wellnessTipNutrition2: "果物を見える場所に置くのは、最も低コストな食習慣の調整です。",
            .wellnessTipNutrition3: "トレーニング日と休養日で食べる量が違うのは自然なこと。毎日同じにする必要はありません。",
            .wellnessTipNutrition4: "加工度の低い炭水化物ほど、満腹感も血糖の変動も穏やかになりやすいです。",
            .wellnessTipNutrition5: "夕食が遅いと深い睡眠の時間を圧迫します。就寝 2 時間前が良い目安です。",
            .wellnessTipRecovery1: "回復は寝ているだけではありません。散歩やストレッチなど低強度の活動の方が回復が早いことも多いです。",
            .wellnessTipRecovery2: "2 週間続く不調は、トレーニング以外の要因（仕事・睡眠・気分）が関わっていることが多いです。",
            .wellnessTipRecovery3: "安静時心拍数や心拍変動は飲酒や体調に大きく左右されます。単日でなく傾向で見ましょう。",
            .wellnessTipRecovery4: "脚が重いときは頻度を保ったまま強度だけ下げる方が、完全に止めるより戻りやすいです。",
            .wellnessTipPositive1: "進歩は直線的ではありません。停滞期も強くなる過程の一部です。",
            .wellnessTipPositive2: "この状態を記録しておくと、次に落ち込んだとき見返す価値があります。",
            .wellnessTipPositive3: "調子が良いときほど増やしすぎがち。翌週に余裕を残しておきましょう。",
            .wellnessTipPositive4: "長く続く運動は、最も効率的なものではなく、あなたが嫌いでないものです。",
            .wellnessSummaryRisk: "今週は注意すべきサインがあります。まず先頭の項目をご覧ください。",
            .wellnessSummaryAttention: "全体的に良好です。いくつか微調整できる点があります。",
            .wellnessSummaryGood: "良い状態です。この調子で続けましょう。",
            .wellnessSummaryCold: "データを蓄積中です。まず今週の事実をご覧ください。",
            .wellnessFactSleepFormat: "睡眠：直近 7 日平均 %@ 時間（記録 %d 日）",
            .wellnessFactStepsFormat: "歩数：1 日平均 %@ 歩",
            .wellnessFactWorkoutsFormat: "ワークアウト：%d 回 · 計 %@ km · %d 分",
            .wellnessFactExerciseFormat: "エクササイズ時間：今週合計 %d 分",
            .wellnessCoverageNoteFormat: "未記録の日があります（睡眠 %d/%d 日、歩数 %d/%d 日）。未記録は 0 として扱いません。",
            .wellnessDisclaimer: "以上はあなたのデータに基づく生活習慣の参考情報で、本体内で生成されます。医療上の助言ではありません。",
            .wellnessAuthPromptTitle: "運動をもっと知ってみませんか",
            .wellnessAuthPromptBody: "よろしければ、ヘルスケアデータの読み取りを許可してください。睡眠・歩数・ワークアウトをもとに、あなた専用のサマリーと提案をこの端末内で作成します。解析はすべて端末内で完結し、アップロードも共有もされません。設定はいつでも変更できます。",
            .wellnessAuthButton: "試してみる",
            .wellnessLoading: "今週のガイドを生成中…",
            .wellnessEmptyBody: "データを蓄積中です。数日記録すると、ここにあなた専用のサマリーが表示されます。",
            .wellnessAdviceSleepDebtTitle: "睡眠負債を返しましょう",
            .wellnessAdviceSleepDebtEvidence: "直近 7 日で普段より合計約 %@ 時間睡眠が不足",
            .wellnessAdviceSleepDebtBody: "今後 3 晩は約 %d 分早めの就寝を。今夜は %@ までに休みましょう。",
            .wellnessAdviceSleepIrregularTitle: "就寝リズムの乱れ",
            .wellnessAdviceSleepIrregularEvidence: "直近 7 日の就寝時刻のばらつきは約 ±%d 分",
            .wellnessAdviceSleepIrregularBody: "時間を補うより就寝時刻を固定する方が効果的です。%@–%@ の間の就寝を試してみてください。",
            .wellnessAdviceSleepShortTitle: "睡眠時間が継続的に不足",
            .wellnessAdviceSleepShortEvidence: "直近 7 日平均 %@ 時間で、普段の %@ 時間を下回っています",
            .wellnessAdviceSleepShortBody: "不足が続くと回復が遅れ、その後調子に影響します。今週はまず 1 晩から取り戻しましょう。",
            .wellnessAdviceWeekendJetlagTitle: "週末の寝だめ傾向",
            .wellnessAdviceWeekendJetlagEvidence: "週末は平日より平均約 %@ 時間長く睡眠",
            .wellnessAdviceWeekendJetlagBody: "寝だめは平日の不足のサインです。平日の就寝を 15–30 分ずつ前倒ししてみましょう。",
            .wellnessAdviceSleepStableTitle: "睡眠は安定しています",
            .wellnessAdviceSleepStableEvidence: "直近 7 日平均 %@ 時間、リズムも規則的",
            .wellnessAdviceSleepStableBody: "時間もリズムも普段の範囲内です。今のペースを保ちましょう。",
            .wellnessAdviceLoadSpikeTitle: "負荷の増やし方が急です",
            .wellnessAdviceLoadSpikeEvidence: "直近 7 日の運動負荷は月間平均の約 %@ 倍",
            .wellnessAdviceLoadSpikeBody: "短期間の急な増量はけがのリスクと関連します。来週は普段の水準に戻し、低強度を優先しましょう。",
            .wellnessAdviceLoadDropTitle: "運動量が大きく減少",
            .wellnessAdviceLoadDropEvidence: "今週の負荷は普段の 6 割未満",
            .wellnessAdviceLoadDropBody: "一度に取り戻す必要はありません。週 2 回・1 回約 %d 分からリズムを戻しましょう。",
            .wellnessAdviceSedentaryTitle: "活動量が連続して低下",
            .wellnessAdviceSedentaryEvidence: "%d 日連続で歩数が %@ を下回っています",
            .wellnessAdviceSedentaryBody: "今日はまず %@ 歩を目標に。あなた自身の普段の水準から決めた目標です。",
            .wellnessAdviceRecoveryTitle: "回復のサインが弱め",
            .wellnessAdviceRecoveryEvidence: "安静時心拍数が %d 日連続で普段より約 %d bpm 高い状態%@",
            .wellnessAdviceRecoveryBody: "今日と明日は低強度か休息をおすすめします。参考情報です。不調を伴う場合は専門家にご相談ください。",
            .wellnessAdviceRecoveryHRVSuffix: "、心拍変動も低下傾向",
            .wellnessAdviceActiveWeekTitle: "今週の活動量は達成",
            .wellnessAdviceActiveWeekEvidence: "今週のエクササイズ合計 %d 分",
            .wellnessAdviceActiveWeekBody: "WHO 推奨の週 150 分に到達しました。自分を褒めてあげましょう。",
            .routeCollection: "ルート読み込み",
            .routeCollectionMenuTitle: "ルート",
            .routeCollectionEmptyMessage: "読み込んだルートはまだありません",
            .routeCollectionImportSectionTitle: "読み込み",
            .routeCollectionImportSuccess: "GPX ルートを読み込みました",
            .routeCollectionImporting: "GPX を読み込み中",
            .routeCollectionMergeSectionTitle: "結合",
            .routeHeatmap: "軌跡ヒートマップ",
            .heatmapShareMask: "マスク",
            .heatmapShareMaskOpacity: "マスクの濃さ",
            .heatmapShareMonth: "月",
            .heatmapShareNoRoutes: "この期間にはルートがありません",
            .heatmapSharePhoto: "写真",
            .heatmapShareSelectRouteForColor: "先にルートを選択してください",
            .heatmapShareTitle: "ルート集を共有",
            .heatmapShareWeek: "週",
            .heatmapShareYear: "年",
            .routeLoading: "ルートを読み込み中",
            .routeMerge: "ルートを結合",
            .routeMergeCompletedMessage: "結合が完了しました。ルート画面で確認できます。",
            .routeMergeCompletedTitle: "ルートを結合しました",
            .routeMergeDefaultTitle: "結合ルート",
            .routeMergeFailed: "ルートの結合に失敗しました",
            .routeMergeLoading: "ルートを結合中",
            .routeMergeMultipleTitleFormat: "%@ ほか %d 区間",
            .routeMergeNoRoutes: "結合するルートを選択してください。",
            .routeMergeViewRoutes: "見に行く",
            .restorePurchases: "購入を復元",
            .running: "ランニング",
            .satellite: "衛星",
            .share: "共有",
            .sportsCareerAnnualData: "年間",
            .sportsCareerMonthlyData: "月別",
            .sportsCareerOverview: "概要",
            .sportsCareerLocations: "運動した場所",
            .sportsCareerWorldMap: "世界",
            .sportsCareerChinaMap: "中国",
            .sportsCareerCountryCountFormat: "%dか国",
            .sportsCareerCityCountFormat: "%d都市",
            .sportsCareerSummary: "概要",
            .sportsCareerWeeklyData: "今週",
            .sportsCareerWeekDistanceFormat: "%d週目\n%.1f km",
            .sportsCareerWeekTitleWithRangeFormat: "%d週目 · %@-%@",
            .sportTypeCountSummary: "種目別ワークアウト回数",
            .sportTypeTimeSummary: "ワークアウト時間の集計",
            .sportsCareer: "運動履歴",
            .data: "データ",
            .standard: "標準",
            .sportType: "ワークアウト種別",
            .sportTypeSummary: "種目別サマリー",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava は認証済みで、ワークアウトデータを読み取れます。",
            .stravaDataSourceSubtitle: "Strava に記録されたデータを読み取ります。",
            .stravaReauthorizationRequired: "Strava の認証が無効になりました。「その他」画面で Strava をタップして再ログインしてください。",
            .saveLivePhoto: "Live Photoを保存",
            .startTimeFormat: "%@開始",
            .stillOpen: "それでも開く",
            .systemPhotos: "写真",
            .systemMapsNotFound: "システムマップが見つかりません",
            .termsOfUse: "利用規約",
            .totalActivityCountFormat: "%d回",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "合計回数",
            .totalWorkoutDistance: "合計距離",
            .totalWorkoutTime: "合計時間",
            .trailRunning: "トレイルランニング",
            .tools: "ツール",
            .time: "時間",
            .today: "今日",
            .uiSettings: "機能設定",
            .unknownDistance: "不明な距離",
            .unknownDuration: "不明な時間",
            .unknownLocation: "不明な位置",
            .virtualCycling: "バーチャルサイクリング",
            .virtualRunning: "バーチャルランニング",
            .walking: "ウォーキング",
            .walkingHiking: "ウォーキング/ハイキング",
            .widgets: "ウィジェット",
            .widgetSmallWeeklyGoal: "今週のリングデータ",
            .widgetWeeklyChart: "今週の棒グラフ",
            .widgetMonthlyCalendar: "月間カレンダー",
            .widgetAnnualTrajectory: "年間トレンド",
            .widgetLocationMaps: "運動マップ",
            .widgetWorldMap: "世界地図",
            .widgetWorldCountryWorkoutFormat: "%d/%dか国で運動",
            .widgetChinaMap: "中国地図",
            .widgetChinaCityWorkoutFormat: "%d/%d都市で運動",
            .widgetWeeklyGoalDistance: "週間目標距離",
            .kilometers: "km",
            .workoutStart: "ワークアウト開始地点",
            .workoutEnd: "ワークアウト終了地点",
            .endNotFound: "ゴール地点が見つかりません",
            .startNotFound: "スタート地点が見つかりません",
            .yesterday: "昨日",
            .burnedCaloriesFormat: "%.0f kcal 消費",
            .calories: "カロリー",
            .durationHoursFormat: "%d時間",
            .durationHoursMinutesFormat: "%d時間%d分",
            .durationMinutesFormat: "%d分",
            .elevationGainFormat: "獲得標高 %.0f m"
        ],
        .korean: [
            .all: "전체",
            .applyToAll: "전체에 적용",
            .appleFitnessDownloadCTA: "Apple 피트니스를 다운로드하고 운동해 보세요!",
            .appearanceSettings: "화면 모드",
            .appearanceSystem: "시스템 설정 따르기",
            .appLanguage: "앱 언어",
            .appIsUpToDate: "최신 버전입니다",
            .checkForUpdates: "업데이트 확인",
            .checkingForUpdates: "업데이트 확인 중…",
            .updateAvailableTitle: "버전 업데이트",
            .updateCheckFailed: "업데이트를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요",
            .updateDismiss: "확인",
            .updateNow: "업데이트",
            .aspectRatio: "비율",
            .appleHealth: "Apple 건강",
            .appDefault: "기본",
            .activitySummaryPrefix: "운동",
            .newDataSyncing: "새 데이터 동기화 중",
            .cancel: "취소",
            .collage: "콜라주",
            .collageSingleLivePhotoLimit: "콜라주 모드에서는 Live Photo를 한 장만 추가할 수 있어요",
            .collageStyle: "레이아웃",
            .colorBlack: "검정",
            .colorBlue: "파랑",
            .colorCustom: "색상 팔레트",
            .colorGray: "연회색",
            .colorOrange: "주황",
            .colorPink: "분홍",
            .colorWhite: "하양",
            .color: "색상",
            .canvas: "캔버스",
            .cycling: "사이클링",
            .dark: "어두운",
            .dataIntegration: "데이터 연동",
            .dayBeforeYesterday: "그저께",
            .delete: "삭제",
            .deleteRoute: "경로를 삭제할까요?",
            .deleteRouteMessage: "삭제하면 되돌릴 수 없습니다.",
            .debugProAccessLocked: "잠금됨",
            .debugProAccessMockEnabled: "Pro 시뮬레이션 켜기",
            .debugProAccessSimulation: "Pro 상태 시뮬레이션",
            .debugProAccessUnlocked: "잠금 해제됨",
            .debugHomeDataSimulation: "홈 데이터 시뮬레이션",
            .debugSimulateHomeEmptyData: "빈 홈 데이터 시뮬레이션",
            .demoModeEntry: "데모 모드 보기",
            .demoModeExit: "데모 모드 종료",
            .demoModeExitMessage: "종료하면 실제 데이터 모드로 돌아갑니다.",
            .demoModeExitTitle: "데모 모드를 종료할까요?",
            .demoModeTitle: "데모 모드",
            .developerWebsite: "개발자 웹사이트",
            .developerTools: "개발자 도구",
            .disable: "끄기",
            .distanceMetersFormat: "%.0f m",
            .enable: "켜기",
            .estimatedBurnedCaloriesFormat: "약 %.0f kcal 소비",
            .exit: "종료",
            .healthAuthorizationDenied: "건강 데이터 읽기 권한이 없습니다.",
            .healthAuthorizationFailed: "건강 권한 요청 실패",
            .healthAuthorizationProgress: "Apple 건강의 운동, 경로, 운동 지표 읽기 권한을 요청하는 중...",
            .healthAuthorizationSettingsRequiredMessage: "시스템 설정 또는 건강 앱에서 Movinn의 운동, 경로, 운동 지표 읽기 권한을 켜 주세요.",
            .healthAuthorizationSettingsRequiredTitle: "Apple 건강 권한 필요",
            .healthAuthorizationTemporarilyUnavailable: "Apple 건강이 아직 준비되지 않았어요. 잠시 후 다시 시도해 주세요.",
            .healthDataReadAuthorized: "데이터 읽기 권한이 허용되었습니다",
            .healthDataUnavailable: "이 기기는 건강 데이터를 지원하지 않습니다.",
            .homeDataLoadingMessage: "데이터를 불러오는 중입니다. 잠시만 기다려 주세요...",
            .homeNoWorkoutDataMessage: "데이터를 찾지 못했어요. 밖으로 나가 운동해 볼까요!",
            .appleHealthDataSourceSubtitle: "Apple 건강에 기록된 데이터를 읽습니다.",
            .exportGPX: "GPX 내보내기",
            .gpxExportFailed: "GPX 내보내기 실패",
            .gpxExportNoRoute: "이 궤적에는 내보낼 수 있는 경로 지점이 없습니다.",
            .gpxExportRouteName: "Movinn에서 온 경로",
            .gpxExporting: "GPX 내보내는 중",
            .gpxImportInvalidFile: "이 GPX 파일을 해석할 수 없습니다.",
            .gpxImportNoRoute: "이 GPX 파일에 사용할 수 있는 경로가 없습니다.",
            .followPhoto: "따라가기",
            .hiking: "하이킹",
            .iCloudRouteSync: "iCloud 동기화",
            .iCloudRouteSyncAccountChangedMessage: "iCloud 계정이 변경되었습니다. 경로 동기화를 다시 켜 주세요.",
            .iCloudRouteSyncAccountUnavailableMessage: "설정에서 iCloud에 로그인하고 iCloud Drive를 켜 주세요.",
            .iCloudRouteSyncAlreadyEnabled: "iCloud 동기화가 켜져 있습니다",
            .iCloudRouteSyncConfirmMessage: "가져온 경로 데이터를 동기화하고 이후 경로를 가져오거나 삭제할 때 iCloud에 자동으로 동기화합니다.",
            .iCloudRouteSyncConfirmTitle: "가져온 경로를 동기화할까요?",
            .iCloudRouteSyncDisabled: "iCloud 동기화가 꺼졌습니다",
            .iCloudRouteSyncDisableConfirmMessage: "끄면 가져온 경로 데이터 동기화를 중지하고 이후 경로를 가져오거나 삭제할 때 iCloud에 자동으로 동기화하지 않습니다. 이미 iCloud에 동기화된 데이터는 유지됩니다.",
            .iCloudRouteSyncDisableConfirmTitle: "iCloud 동기화를 끌까요?",
            .iCloudRouteSyncEnabled: "iCloud 동기화가 켜졌습니다",
            .iCloudRouteSyncDocumentUnavailableMessage: "iCloud의 경로 파일을 일시적으로 읽을 수 없습니다.",
            .iCloudRouteSyncDriveUnavailableMessage: "iCloud Drive에 일시적으로 접근할 수 없습니다. 잠시 후 다시 시도해 주세요.",
            .iCloudRouteSyncFailed: "iCloud 동기화를 켜지 못했습니다",
            .routeCollectionICloudSyncFooterCompleteFormat: "iCloud 동기화 완료 · 총 %d개 파일",
            .routeCollectionICloudSyncFooterErrorFormat: "iCloud 동기화를 일시적으로 사용할 수 없음 · 미동기화 %d/%d개",
            .routeCollectionICloudSyncFooterPendingFormat: "동기화되지 않은 파일 %d/%d개",
            .routeCollectionICloudSyncFooterPreparing: "iCloud 동기화 상태 확인 중…",
            .mapBackgroundAdjustmentHint: "지도를 두 번 탭해 조정",
            .mapStyle: "지도 스타일",
            .livePhotoSaved: "사진 앱에 저장되었습니다",
            .livePhotoSaving: "Live Photo 생성 중",
            .light: "밝은",
            .more: "더보기",
            .movinnLocalDataPrivacyStatement: "- Movinn은 기본적으로 기기 안에서만 데이터를 읽고 처리합니다. 사용자가 iCloud 동기화를 직접 켠 경우에만 가져온 경로 GPX 파일이 iCloud Drive에 저장됩니다.\n- 전 세계 국가와 일부 도시 데이터베이스를 내장하고 있어 모든 조회는 네트워크를 사용하지 않습니다.",
            .movinnPro: "Movinn Pro",
            .newActivity: "새 활동!",
            .newRoute: "새 경로!",
            .ok: "확인",
            .navigation: "내비게이션",
            .startNavigation: "내비게이션 시작",
            .openEnd: "도착점으로",
            .openPhotos: "사진 앱에서 보기",
            .openStart: "시작점으로",
            .openSettings: "설정 열기",
            .other: "기타",
            .outdoorSwimming: "야외 수영",
            .outdoorWorkout: "야외 운동",
            .photoLibraryFullAccessRequiredMessage: "경로와 사진을 매칭하려면 사진 전체 접근 권한이 필요합니다. 시스템 설정에서 사진 권한을 전체 접근으로 변경해 주세요.",
            .photoLibraryFullAccessRequiredTitle: "사진 전체 접근 권한 필요",
            .photoLibraryReadAuthorized: "사진 읽기 권한이 허용되었습니다",
            .photoSaving: "이미지 저장 중",
            .photoBackgroundAdjustmentHint: "사진을 두 번 탭해 조정",
            .photoMatching: "사진 매칭",
            .privacyPolicy: "개인정보",
            .proCodeRedemption: "코드 등록",
            .proFeatureHeatmap: "경로 히트맵 보기",
            .proFeatureWellnessRecap: "운동 데이터 기반 맞춤 가이드",
            .proFeatureICloudRouteSync: "가져온 경로를 iCloud로 동기화",
            .proFeatureMultiLivePhotoExport: "여러 경로 애니메이션 공유 지원",
            .proFeatureMoreComing: "더 많은 기능 예정",
            .proFeatureRouteMerge: "여러 구간 경로 병합",
            .proFeatureRouteSlope: "경로 경사도 표시",
            .proPaywallSubtitle: "Movinn은 고급 기능으로 운동을 더 편하게 합니다.",
            .proPaywallTitle: "고급 기능 잠금 해제",
            .proProductUnavailable: "구독 상품을 불러올 수 없습니다. 나중에 다시 시도해 주세요.",
            .proPurchaseButton: "영구 잠금 해제",
            .proPurchaseButtonPriceFormat: "영구 잠금 해제 %@",
            .proPurchaseFailed: "구매를 완료하지 못했습니다.",
            .proPurchaseLoading: "처리 중",
            .proPurchaseNotAllowed: "이 기기에서는 앱 내 구매를 사용할 수 없습니다.",
            .proPurchasePending: "구매 확인 대기 중입니다.",
            .proPurchaseSuccess: "Movinn Pro가 활성화되었습니다",
            .proPurchaseUnverified: "구매를 확인하지 못했습니다.",
            .proRestoreNoPurchase: "복원할 구매가 없습니다",
            .proRestoreSuccess: "구매를 복원했습니다",
            .proStatusActive: "고급 기능이 활성화되었습니다",
            .proUnlockedTitle: "고급 기능 잠금 해제됨",
            .queryingLocation: "위치 조회 중",
            .routeBook: "루트북으로 사용",
            .routeBookExit: "루트북 모드를 종료할까요?",
            .routeBookExitMessage: "종료하면 운동 목록으로 돌아갑니다.",
            .routeBookLocationPermissionRequiredMessage: "루트북 모드에서 현재 위치를 표시하려면 시스템 설정에서 Movinn의 위치 사용을 허용해 주세요.",
            .routeBookLocationPermissionRequiredTitle: "위치 권한 필요",
            .route: "경로",
            .routeSlope: "경사도",
            .routeSlopeColorHint: "초록색에 가까운 구간은 완만하고, 빨간색에 가까운 구간은 가파릅니다",
            .routeStyle3DFollowColor: "색상 연동",
            .routeStyle3DSlopeColor: "경사 색상",
            .wellnessRecapSheetTitle: "가이드와 제안",
            .wellnessHeaderTip: "👆 여기를 눌러 운동 데이터 기반 가이드를 확인해 보세요",
            .wellnessRangeThreeDays: "3일",
            .wellnessRangeWeek: "1주",
            .wellnessRangeMonth: "1개월",
            .wellnessRangeHalfYear: "6개월",
            .wellnessRangeYear: "1년",
            .wellnessSectionFacts: "데이터 개요",
            .wellnessSectionTrends: "트렌드",
            .wellnessSectionAdvice: "제안",
            .wellnessChartSleep: "수면 시간(시간)",
            .wellnessChartSteps: "일일 걸음 수",
            .wellnessChartLoad: "운동 부하",
            .wellnessTableHeaderMetric: "지표",
            .wellnessTableHeaderCurrent: "이번",
            .wellnessTableHeaderReference: "참조",
            .wellnessTableHeaderChange: "변화",
            .wellnessMetricSleep: "수면 시간",
            .wellnessMetricSteps: "일평균 걸음",
            .wellnessMetricExercise: "운동 분",
            .wellnessMetricWorkouts: "운동 횟수",
            .wellnessMetricDistance: "운동 거리",
            .wellnessMetricRHR: "안정 심박수",
            .wellnessMetricHRV: "심박 변이도",
            .wellnessAdviceSleepTrendUpTitle: "수면이 좋아지는 중",
            .wellnessAdviceSleepTrendUpEvidence: "이번 기간 평균 수면이 지난 기간보다 약 %@시간 증가",
            .wellnessAdviceSleepTrendUpBody: "의식적인 조정이든 자연스러운 흐름이든 좋은 방향입니다. 유지하세요.",
            .wellnessAdviceSleepTrendDownTitle: "수면이 줄어드는 중",
            .wellnessAdviceSleepTrendDownEvidence: "이번 기간 평균 수면이 지난 기간보다 약 %@시간 감소",
            .wellnessAdviceSleepTrendDownBody: "몇 주간 이어지는 감소는 단일 변동보다 주의가 필요합니다. 이 기간 생활의 변화를 돌아보세요.",
            .wellnessAdviceVolumeUpTitle: "운동량 증가",
            .wellnessAdviceVolumeUpEvidence: "이번 기간 운동량이 지난 기간보다 약 %d%% 증가",
            .wellnessAdviceVolumeUpBody: "늘릴 때는 점진적으로, 회복일도 충분히 확보하세요.",
            .wellnessAdviceVolumeDownTitle: "운동량 감소",
            .wellnessAdviceVolumeDownEvidence: "이번 기간 운동량이 지난 기간보다 약 %d%% 감소",
            .wellnessAdviceVolumeDownBody: "감소 자체는 문제가 아닙니다. 간격이 너무 길어지지 않게 가벼운 한 번부터 시작하세요.",
            .wellnessAdviceConsistencyGoodTitle: "매우 규칙적인 운동 습관",
            .wellnessAdviceConsistencyGoodEvidence: "%d/%d주에 운동 기록 있음",
            .wellnessAdviceConsistencyGoodBody: "규칙성은 장기 효과의 핵심으로, 단발성 강도보다 중요합니다. 계속 유지하세요.",
            .wellnessAdviceConsistencyLowTitle: "규칙성을 높일 여지",
            .wellnessAdviceConsistencyLowEvidence: "운동 기록이 있는 주는 %d/%d주뿐",
            .wellnessAdviceConsistencyLowBody: "가끔의 고강도보다 매주 정해진 시간대의 가벼운 운동이 지속하기 쉽습니다.",
            .wellnessAdvicePBTitle: "기록 경신",
            .wellnessAdvicePBEvidence: "이번 기간 1회 최장 거리 %@km로 지난 기간을 넘어섰습니다",
            .wellnessAdvicePBBody: "거리 기록 경신은 기초가 탄탄해지고 있다는 증거입니다.",
            .wellnessAdviceDaylightTitle: "낮 시간 햇빛 부족",
            .wellnessAdviceDaylightEvidence: "최근 일평균 야외 햇빛 약 %d분",
            .wellnessAdviceDaylightBody: "낮의 자연광은 생체 시계를 맞추는 가장 효과적인 신호입니다. 오전에 15분 나가는 것이 밤에 억지로 일찍 자는 것보다 효과적입니다.",
            .wellnessAdviceMidpointLateTitle: "취침이 전반적으로 늦어짐",
            .wellnessAdviceMidpointLateEvidence: "최근 수면 중간점이 평소보다 약 %d분 늦음",
            .wellnessAdviceMidpointLateBody: "늦어짐은 모르는 사이에 진행됩니다. 오늘 밤 20분만 앞당기는 것이 주말 몰아자기보다 효과적입니다.",
            .wellnessAdviceDeepSleepTitle: "깊은 수면 비율이 낮음",
            .wellnessAdviceDeepSleepEvidence: "최근 깊은 수면이 전체의 약 %d%%",
            .wellnessAdviceDeepSleepBody: "기기의 깊은 수면은 추정치로 참고용입니다. 취침 1시간 전 카페인과 강한 빛을 피하는 것이 가장 직접적입니다.",
            .wellnessAdviceRHRImprovedTitle: "심폐 능력 향상 중",
            .wellnessAdviceRHRImprovedEvidence: "안정 시 심박수가 평소보다 약 %d bpm 낮음(현재 약 %d bpm)",
            .wellnessAdviceRHRImprovedBody: "안정 시 심박수 하락은 유산소 능력 향상의 가장 확실한 신호 중 하나입니다. 최근 훈련이 효과를 내고 있습니다.",
            .wellnessAdviceStepsUpTitle: "일상 활동량 증가",
            .wellnessAdviceStepsUpEvidence: "이번 기간 일평균 걸음이 지난 기간보다 약 %d%% 증가",
            .wellnessAdviceStepsUpBody: "일상 걷기의 증가는 의도적인 훈련보다 지속하기 쉽습니다. 좋은 흐름입니다.",
            .wellnessAdviceStepsDownTitle: "일상 활동량 감소",
            .wellnessAdviceStepsDownEvidence: "이번 기간 일평균 걸음이 지난 기간보다 약 %d%% 감소",
            .wellnessAdviceStepsDownBody: "운동 외의 일상 활동도 똑같이 중요합니다. 출퇴근이나 오후 산책이 가장 되찾기 쉬운 부분입니다.",
            .wellnessAdviceHabitDayTitle: "당신의 운동일은 %@",
            .wellnessAdviceHabitDayEvidence: "운동일 %d회가 %@에 집중",
            .wellnessAdviceHabitDayBody: "고정된 운동일은 가장 저평가된 꾸준함의 기술입니다. \u{201C}할까 말까\u{201D}를 \u{201C}시간 되면 한다\u{201D}로 바꿔 줍니다.",
            .wellnessAdviceStepsConsistentTitle: "걸음 수가 안정적",
            .wellnessAdviceStepsConsistentEvidence: "최근 %2$d일 중 %1$d일이 평소 수준 이상",
            .wellnessAdviceStepsConsistentBody: "안정은 폭발력보다 얻기 어렵습니다. 일상 활동의 기반이 탄탄합니다.",
            .wellnessAdviceHRVHighTitle: "회복 상태 양호",
            .wellnessAdviceHRVHighEvidence: "심박 변이도가 평소보다 약 %d%% 높음",
            .wellnessAdviceHRVHighBody: "몸이 잘 회복되고 있습니다. 고강도 세션을 계획 중이라면 지금이 좋은 타이밍입니다.",
            .wellnessAdviceWorkoutGapTitle: "간격이 길어지는 중",
            .wellnessAdviceWorkoutGapEvidence: "%d일 연속 운동 기록 없음",
            .wellnessAdviceWorkoutGapBody: "평소 운동 습관이 있는 분에게 간격이 길어지면 재시작이 어려워집니다. 오늘은 가벼운 한 번이면 충분합니다.",
            .wellnessAdviceStreakTitle: "연속으로 움직이는 중",
            .wellnessAdviceStreakEvidence: "%d일 연속 운동 기록",
            .wellnessAdviceStreakBody: "좋은 흐름입니다. 회복일도 잊지 마세요—연속 후의 가벼운 날도 훈련의 일부입니다.",
            .wellnessAdviceRHRTrendGoodTitle: "안정 시 심박수 하락 추세",
            .wellnessAdviceRHRTrendGoodEvidence: "이번 기간이 지난 기간보다 약 %d bpm 낮음(현재 약 %d bpm)",
            .wellnessAdviceRHRTrendGoodBody: "장기적인 하락은 유산소 기반이 두터워지고 있다는 신호입니다. 이 추세를 유지하세요.",
            .wellnessAdviceRHRTrendBadTitle: "안정 시 심박수 상승 추세",
            .wellnessAdviceRHRTrendBadEvidence: "이번 기간이 지난 기간보다 약 %d bpm 높음(현재 약 %d bpm)",
            .wellnessAdviceRHRTrendBadBody: "장기적인 상승은 스트레스·수면·회복 부족과 관련될 수 있습니다. 참고용이며, 불편함이 동반되면 전문가와 상담하세요.",
            .wellnessAdviceCarbTitle: "장시간 운동 후엔 탄수화물 먼저",
            .wellnessAdviceCarbEvidence: "이번 기간 60분 이상 운동 %d회, 최장 약 %d분",
            .wellnessAdviceCarbBody: "60분이 넘는 운동은 글리코겐을 크게 소모합니다. 종료 후 1~2시간 이내에 주식류 탄수화물(밥·면·오트밀·과일)을 먹으면 회복 효율이 높아집니다.",
            .wellnessAdviceProteinTitle: "단백질을 저녁에만 몰아 먹지 않기",
            .wellnessAdviceProteinEvidence: "이번 기간 운동 합계 약 %d분",
            .wellnessAdviceProteinBody: "운동 후 20~30g의 단백질(손바닥 크기 육류, 계란 2개, 그릭요거트 1컵 정도)이면 충분합니다. 세 끼에 나누는 편이 더 효과적입니다.",
            .wellnessAdviceHydrationTitle: "수분은 조금씩 자주",
            .wellnessAdviceHydrationEvidence: "이번 기간 일일 최대 활동 소모 약 %d kcal",
            .wellnessAdviceHydrationEvidenceLong: "이번 기간 90분 이상 장시간 운동 있음",
            .wellnessAdviceHydrationBody: "땀을 많이 흘린 뒤 물만 한 번에 많이 마시면 전해질이 희석됩니다. 소량씩 자주, 1시간 이상 운동에는 나트륨이 포함된 음료나 음식을 곁들이세요.",
            .wellnessAdviceLateMealTitle: "잠이 부족하면 식욕이 늘기 쉽습니다",
            .wellnessAdviceLateMealEvidence: "이번 기간 평균 수면 약 %@시간",
            .wellnessAdviceLateMealBody: "수면 부족은 공복감을 높이고 포만감을 약하게 만듭니다. 특히 밤에 두드러집니다. 취침 2시간 전까지 식사를 마치는 편이 참는 것보다 수월합니다.",
            .wellnessAdviceLightWeekTitle: "운동이 적은 시기엔 평소대로",
            .wellnessAdviceLightWeekEvidence: "이번 기간 운동량이 적은 편",
            .wellnessAdviceLightWeekBody: "훈련량이 적은 시기에는 추가 보충식이 필요 없습니다. 단백질과 채소의 기본량만 유지하고, 훈련량이 돌아오면 조정하세요.",
            .wellnessAdviceSleepRoutineTitle: "수면 리듬 양호",
            .wellnessAdviceSleepRoutineEvidence: "이번 기간 평균 수면 약 %@시간",
            .wellnessAdviceSleepRoutineBody: "눈에 띄는 문제는 없습니다. 일정한 취침 시각을 유지하는 것이 가끔의 긴 수면보다 가치 있습니다.",
            .wellnessAdviceMixTitle: "강도에 변화를 줘 보세요",
            .wellnessAdviceMixEvidence: "이번 기간 운동 합계 약 %d분",
            .wellnessAdviceMixBody: "대부분은 편안한 유산소로, 일부만 고강도로—지구력 향상에서 반복 검증된 구성입니다. 전부 중강도가 가장 효율이 낮습니다.",
            .wellnessAdviceRestDayTitle: "회복일도 계획에 넣기",
            .wellnessAdviceRestDayEvidence: "회복도 훈련의 일부입니다",
            .wellnessAdviceRestDayBody: "몸은 쉬는 동안 강해집니다. 주 1~2일 저강도나 완전 휴식을 두면 장기적인 발전이 안정적입니다.",
            .wellnessAdviceCarbNowTitle: "이번 1~2일은 글리코겐 회복부터",
            .wellnessAdviceCarbNowEvidence: "최근 장시간 운동 약 %d분",
            .wellnessAdviceCarbNowBody: "장시간 운동 후 24시간은 단백질보다 탄수화물 보충이 더 중요합니다. 다음 식사에서 주식을 충분히 먹는 편이 닭가슴살을 추가하는 것보다 효과적입니다.",
            .wellnessAdviceProteinNowTitle: "다음 두 끼에 단백질을",
            .wellnessAdviceProteinNowEvidence: "최근 3일 운동 합계 약 %d분",
            .wellnessAdviceProteinNowBody: "운동 직후 1~2일은 근육 회복이 가장 활발합니다. 매 끼니에 한 가지(계란·콩류·생선 등)를 더하는 편이 한 끼에 몰아 먹는 것보다 효과적입니다.",
            .wellnessAdviceFuelGrowthTitle: "운동량이 늘었으니 식사도",
            .wellnessAdviceFuelGrowthEvidence: "주당 약 %d분에 해당하며 지난 기간보다 크게 증가",
            .wellnessAdviceFuelGrowthBody: "운동량이 한 단계 오를 때 흔한 문제는 과식이 아니라 부족한 섭취이며, 훈련할수록 힘이 없는 형태로 나타납니다. 주식과 단백질을 함께 늘리세요.",
            .wellnessAdviceNutritionBaseTitle: "이 운동량에 맞는 식사의 기초",
            .wellnessAdviceNutritionBaseEvidence: "주당 약 %d분에 해당",
            .wellnessAdviceNutritionBaseBody: "이 수준을 유지한다면 매일의 주식·단백질·채소의 안정이 어떤 보충제보다 중요합니다. 장기 컨디션을 결정하는 것은 기본 식사의 일관성입니다.",
            .wellnessAdviceNutritionBaseYearBody: "1년 내내 이 수준을 유지할 수 있는 건 벼락치기가 아니라 지속 가능한 일상 식사 덕분입니다. 안정된 세 끼 구성이 최고의 장기 전략입니다.",
            .wellnessAdviceMilestoneTitle: "이 기간의 마일스톤",
            .wellnessAdviceMilestoneEvidence: "누적 %@km, 운동 %d회",
            .wellnessAdviceMilestoneBody: "이 누적은 한 번 한 번이 쌓인 결과입니다. 돌아보면 계속하는 것 자체가 가장 어려운 부분이었습니다.",
            .wellnessAdviceMilestoneYearBody: "1년 누적은 놀랍지만, 그 내용은 평범하게 나선 한 번 한 번입니다. 그것이 장기적 축적의 모습입니다.",
            .wellnessAdviceSeasonalTitle: "운동량에 계절성이 있습니다",
            .wellnessAdviceSeasonalEvidence: "%@에 가장 활발하고 %@에 가장 적음",
            .wellnessAdviceSeasonalBody: "계절 변동은 자연스럽습니다. 비수기 대안—실내·짧은 시간·다른 종목—을 준비해 두면 기초를 크게 잃지 않습니다.",
            .wellnessAdviceTonightTitle: "오늘 밤은 일찍 자기",
            .wellnessAdviceTonightEvidence: "어젯밤 수면 약 %@시간, 평소는 %@시간",
            .wellnessAdviceTonightBody: "오늘 밤은 %@ 전에 잠자리에 드세요. 평소보다 약 %d분 이릅니다. 부족분은 당일에 채우는 것이 가장 효과적이며, 주말로 미루면 효과가 떨어집니다.",
            .wellnessTipSleep1: "취침 시각보다 기상 시각을 고정하는 편이 실천하기 쉽고 생체 시계도 안정됩니다.",
            .wellnessTipSleep2: "취침 1시간 전 조명을 낮추는 것이 양을 세는 것보다 훨씬 효과적입니다. 빛은 가장 강한 각성 신호입니다.",
            .wellnessTipSleep3: "카페인의 반감기는 약 5시간. 오후 3시 이후의 한 잔이 깊은 수면을 줄이는 원인이 되곤 합니다.",
            .wellnessTipSleep4: "자기 전 온욕 후 체온이 내려가는 과정 자체가 잠드는 신호가 됩니다.",
            .wellnessTipSleep5: "누운 지 20분이 지나도 잠들지 않으면, 일어나 조용한 일을 하다 돌아오는 편이 더 낫습니다.",
            .wellnessTipActivity1: "전날 밤 운동복을 현관에 두는 것은 시작 문턱을 낮추는 가장 검증된 방법입니다.",
            .wellnessTipActivity2: "시간을 줄일지언정 건너뛰지 마세요. 10분의 운동도 습관에는 0보다 훨씬 가치 있습니다.",
            .wellnessTipActivity3: "코스나 종목을 바꾸는 편이 억지로 양을 늘리는 것보다 흥미를 오래 유지시킵니다.",
            .wellnessTipActivity4: "워밍업은 복잡할 필요 없습니다. 처음 5분을 천천히 움직이는 것 자체가 최고의 준비입니다.",
            .wellnessTipActivity5: "주 1회 누군가와 함께 운동하면 지속률이 눈에 띄게 올라갑니다.",
            .wellnessTipNutrition1: "운동 후에는 수분부터. 탈수 상태에서는 식욕 신호가 정확하지 않은 경우가 많습니다.",
            .wellnessTipNutrition2: "과일을 눈에 보이는 곳에 두는 것은 가장 비용이 낮은 식습관 조정입니다.",
            .wellnessTipNutrition3: "훈련일과 휴식일의 식사량이 다른 건 자연스럽습니다. 매일 똑같을 필요는 없습니다.",
            .wellnessTipNutrition4: "가공도가 낮은 탄수화물일수록 포만감과 혈당 변동이 대체로 더 완만합니다.",
            .wellnessTipNutrition5: "저녁을 늦게 먹으면 깊은 수면 시간을 잠식합니다. 취침 2시간 전이 좋은 기준입니다.",
            .wellnessTipRecovery1: "회복은 누워 있는 것만이 아닙니다. 산책이나 스트레칭 같은 저강도 활동이 더 빠른 회복을 돕기도 합니다.",
            .wellnessTipRecovery2: "2주간 이어지는 컨디션 저하는 훈련 외 요인(업무·수면·기분)이 작용하는 경우가 많습니다.",
            .wellnessTipRecovery3: "안정 시 심박수와 심박 변이도는 음주나 컨디션에 크게 좌우됩니다. 하루가 아닌 추세로 보세요.",
            .wellnessTipRecovery4: "다리가 무거울 때는 빈도를 유지하고 강도만 낮추는 편이 완전히 쉬는 것보다 회복이 빠릅니다.",
            .wellnessTipPositive1: "발전은 대개 직선이 아닙니다. 정체기도 강해지는 과정의 일부입니다.",
            .wellnessTipPositive2: "이 상태를 기록해 두면 다음 슬럼프 때 돌아보는 데 큰 도움이 됩니다.",
            .wellnessTipPositive3: "컨디션이 좋을 때일수록 과하게 늘리기 쉽습니다. 다음 주에 여유를 남겨 두세요.",
            .wellnessTipPositive4: "오래 지속되는 운동은 가장 효율적인 운동이 아니라, 당신이 싫어하지 않는 운동입니다.",
            .wellnessSummaryRisk: "이번 주 주의가 필요한 신호가 있습니다. 맨 위 항목을 먼저 확인하세요.",
            .wellnessSummaryAttention: "전반적으로 좋습니다. 몇 가지 조정할 점이 있습니다.",
            .wellnessSummaryGood: "좋은 상태입니다. 지금처럼 유지하세요.",
            .wellnessSummaryCold: "데이터를 수집 중입니다. 먼저 이번 주 기록을 확인하세요.",
            .wellnessFactSleepFormat: "수면: 최근 7일 평균 %@시간 (기록 %d일)",
            .wellnessFactStepsFormat: "걸음 수: 일평균 %@보",
            .wellnessFactWorkoutsFormat: "운동: %d회 · 총 %@km · %d분",
            .wellnessFactExerciseFormat: "운동 시간: 이번 주 합계 %d분",
            .wellnessCoverageNoteFormat: "기록이 없는 날이 있습니다(수면 %d/%d일, 걸음 %d/%d일). 미기록은 0으로 계산하지 않습니다.",
            .wellnessDisclaimer: "위 내용은 개인 데이터 기반의 생활 참고 정보이며 기기 내에서 생성됩니다. 의료 조언이 아닙니다.",
            .wellnessAuthPromptTitle: "내 운동을 더 알아볼까요",
            .wellnessAuthPromptBody: "괜찮으시다면 건강 데이터 읽기를 허용해 주세요. 수면·걸음·운동을 바탕으로 나만의 요약과 제안을 이 기기 안에서 만들어 드립니다. 모든 분석은 기기에서만 이뤄지며 업로드하거나 공유하지 않습니다. 설정은 언제든 바꿀 수 있습니다.",
            .wellnessAuthButton: "네, 해볼게요",
            .wellnessLoading: "이번 주 가이드를 생성하는 중…",
            .wellnessEmptyBody: "데이터를 수집 중입니다. 며칠 기록하면 나만의 요약이 표시됩니다.",
            .wellnessAdviceSleepDebtTitle: "수면 부채 갚기",
            .wellnessAdviceSleepDebtEvidence: "최근 7일간 평소보다 총 약 %@시간 수면 부족",
            .wellnessAdviceSleepDebtBody: "앞으로 3일은 약 %d분 일찍 잠자리에 드세요. 오늘 밤은 %@ 전에 쉬는 것을 권합니다.",
            .wellnessAdviceSleepIrregularTitle: "취침 리듬이 불규칙",
            .wellnessAdviceSleepIrregularEvidence: "최근 7일 취침 시각 변동 약 ±%d분",
            .wellnessAdviceSleepIrregularBody: "시간을 보충하기보다 취침 시각을 고정하는 것이 효과적입니다. %@–%@ 사이 취침을 시도해 보세요.",
            .wellnessAdviceSleepShortTitle: "수면이 계속 부족",
            .wellnessAdviceSleepShortEvidence: "최근 7일 평균 %@시간으로 평소 %@시간보다 부족",
            .wellnessAdviceSleepShortBody: "부족이 이어지면 회복이 느려지고 컨디션에 영향을 줍니다. 이번 주 가장 쉬운 하루부터 되찾으세요.",
            .wellnessAdviceWeekendJetlagTitle: "주말 몰아자기 경향",
            .wellnessAdviceWeekendJetlagEvidence: "주말에 평일보다 평균 약 %@시간 더 수면",
            .wellnessAdviceWeekendJetlagBody: "몰아자기는 평일 수면 부족의 신호입니다. 평일 취침을 15–30분씩 앞당겨 보세요.",
            .wellnessAdviceSleepStableTitle: "수면 상태 안정",
            .wellnessAdviceSleepStableEvidence: "최근 7일 평균 %@시간, 리듬도 규칙적",
            .wellnessAdviceSleepStableBody: "시간과 리듬 모두 평소 범위입니다. 지금 페이스를 유지하세요.",
            .wellnessAdviceLoadSpikeTitle: "이번 주 운동량 증가가 빠름",
            .wellnessAdviceLoadSpikeEvidence: "최근 7일 운동 부하가 월 평균의 약 %@배",
            .wellnessAdviceLoadSpikeBody: "단기간 급격한 증량은 부상 위험과 관련됩니다. 다음 주는 평소 수준으로 줄이고 저강도를 우선하세요.",
            .wellnessAdviceLoadDropTitle: "운동량이 크게 감소",
            .wellnessAdviceLoadDropEvidence: "이번 주 부하가 평소의 60% 미만",
            .wellnessAdviceLoadDropBody: "한 번에 되돌릴 필요는 없습니다. 주 2회, 회당 약 %d분부터 리듬을 되찾으세요.",
            .wellnessAdviceSedentaryTitle: "활동량이 연속 저조",
            .wellnessAdviceSedentaryEvidence: "%d일 연속 걸음 수가 %@보 미만",
            .wellnessAdviceSedentaryBody: "오늘은 %@보를 목표로 하세요. 본인의 평소 수준에 맞춘 목표입니다.",
            .wellnessAdviceRecoveryTitle: "회복 신호가 약함",
            .wellnessAdviceRecoveryEvidence: "안정 시 심박수가 %d일 연속 평소보다 약 %d bpm 높음%@",
            .wellnessAdviceRecoveryBody: "오늘과 내일은 저강도 운동이나 휴식을 권합니다. 참고용이며, 불편함이 동반되면 전문가와 상담하세요.",
            .wellnessAdviceRecoveryHRVSuffix: ", 심박 변이도도 함께 하락",
            .wellnessAdviceActiveWeekTitle: "이번 주 활동 목표 달성",
            .wellnessAdviceActiveWeekEvidence: "이번 주 운동 합계 %d분",
            .wellnessAdviceActiveWeekBody: "WHO 권장 주 150분에 도달했습니다. 스스로를 칭찬해 주세요.",
            .routeCollection: "경로 가져오기",
            .routeCollectionMenuTitle: "경로",
            .routeCollectionEmptyMessage: "아직 가져온 경로가 없습니다",
            .routeCollectionImportSectionTitle: "가져오기",
            .routeCollectionImportSuccess: "GPX 경로를 가져왔습니다",
            .routeCollectionImporting: "GPX 가져오는 중",
            .routeCollectionMergeSectionTitle: "병합",
            .routeHeatmap: "경로 히트맵",
            .heatmapShareMask: "마스크",
            .heatmapShareMaskOpacity: "마스크 투명도",
            .heatmapShareMonth: "월",
            .heatmapShareNoRoutes: "현재 기간에 경로가 없습니다",
            .heatmapSharePhoto: "사진",
            .heatmapShareSelectRouteForColor: "먼저 경로를 선택하세요",
            .heatmapShareTitle: "경로 모음 공유",
            .heatmapShareWeek: "주",
            .heatmapShareYear: "년",
            .routeLoading: "경로 불러오는 중",
            .routeMerge: "경로 병합",
            .routeMergeCompletedMessage: "병합이 완료되었습니다. 경로 화면에서 확인할 수 있어요.",
            .routeMergeCompletedTitle: "경로 병합 완료",
            .routeMergeDefaultTitle: "병합 경로",
            .routeMergeFailed: "경로 병합 실패",
            .routeMergeLoading: "경로 병합 중",
            .routeMergeMultipleTitleFormat: "%@ 외 %d개 구간",
            .routeMergeNoRoutes: "병합할 경로를 선택해 주세요.",
            .routeMergeViewRoutes: "보러가기",
            .restorePurchases: "구매 복원",
            .running: "달리기",
            .satellite: "위성",
            .share: "공유",
            .sportsCareerAnnualData: "연간",
            .sportsCareerMonthlyData: "월간",
            .sportsCareerOverview: "개요",
            .sportsCareerLocations: "운동 장소",
            .sportsCareerWorldMap: "세계",
            .sportsCareerChinaMap: "중국",
            .sportsCareerCountryCountFormat: "%d개 국가",
            .sportsCareerCityCountFormat: "%d개 도시",
            .sportsCareerSummary: "요약",
            .sportsCareerWeeklyData: "이번 주",
            .sportsCareerWeekDistanceFormat: "%d주차\n%.1f km",
            .sportsCareerWeekTitleWithRangeFormat: "%d주차 · %@-%@",
            .sportTypeCountSummary: "운동 유형별 횟수 요약",
            .sportTypeTimeSummary: "운동 시간 요약",
            .sportsCareer: "운동 경력",
            .data: "데이터",
            .standard: "표준",
            .sportType: "운동 유형",
            .sportTypeSummary: "운동 유형 요약",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava 권한을 이미 받았으며 운동 데이터를 읽을 수 있습니다.",
            .stravaDataSourceSubtitle: "Strava에 기록된 데이터를 읽습니다.",
            .stravaReauthorizationRequired: "Strava 인증이 만료되었습니다. 더보기 화면에서 Strava를 눌러 다시 로그인하세요.",
            .saveLivePhoto: "Live Photo 저장",
            .startTimeFormat: "%@ 시작",
            .stillOpen: "그래도 열기",
            .systemPhotos: "사진",
            .systemMapsNotFound: "시스템 지도를 찾을 수 없음",
            .termsOfUse: "이용 약관",
            .totalActivityCountFormat: "%d회",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "총 횟수",
            .totalWorkoutDistance: "총 거리",
            .totalWorkoutTime: "총 시간",
            .trailRunning: "트레일 러닝",
            .tools: "도구",
            .time: "시간",
            .today: "오늘",
            .uiSettings: "기능 설정",
            .unknownDistance: "알 수 없는 거리",
            .unknownDuration: "알 수 없는 시간",
            .unknownLocation: "알 수 없는 위치",
            .virtualCycling: "가상 사이클링",
            .virtualRunning: "가상 달리기",
            .walking: "걷기",
            .walkingHiking: "걷기/하이킹",
            .widgets: "위젯",
            .widgetSmallWeeklyGoal: "이번 주 링 데이터",
            .widgetWeeklyChart: "이번 주 막대 차트",
            .widgetMonthlyCalendar: "월간 달력",
            .widgetAnnualTrajectory: "연간 궤적",
            .widgetLocationMaps: "운동 지도",
            .widgetWorldMap: "세계 지도",
            .widgetWorldCountryWorkoutFormat: "%d/%d개 국가에서 운동",
            .widgetChinaMap: "중국 지도",
            .widgetChinaCityWorkoutFormat: "%d/%d개 도시에서 운동",
            .widgetWeeklyGoalDistance: "주간 목표 거리",
            .kilometers: "km",
            .workoutStart: "운동 시작점",
            .workoutEnd: "운동 종료점",
            .endNotFound: "종료점을 찾을 수 없음",
            .startNotFound: "시작점을 찾을 수 없음",
            .yesterday: "어제",
            .burnedCaloriesFormat: "%.0f kcal 소비",
            .calories: "칼로리",
            .durationHoursFormat: "%d시간",
            .durationHoursMinutesFormat: "%d시간 %d분",
            .durationMinutesFormat: "%d분",
            .elevationGainFormat: "상승 %.0f m"
        ],
        .english: [
            .all: "All",
            .applyToAll: "Apply to All",
            .appleFitnessDownloadCTA: "Download Apple Fitness and get moving!",
            .appearanceSettings: "Appearance",
            .appearanceSystem: "Follow System",
            .appLanguage: "App Language",
            .appIsUpToDate: "You're using the latest version",
            .checkForUpdates: "Check for Updates",
            .checkingForUpdates: "Checking for updates…",
            .updateAvailableTitle: "Version Update",
            .updateCheckFailed: "Unable to check for updates. Please try again later.",
            .updateDismiss: "OK",
            .updateNow: "Update",
            .aspectRatio: "Ratio",
            .appleHealth: "Apple Health",
            .appDefault: "Default",
            .activitySummaryPrefix: "Activity",
            .newDataSyncing: "Syncing new data",
            .cancel: "Cancel",
            .collage: "Collage",
            .collageSingleLivePhotoLimit: "Collage mode allows only one Live Photo",
            .collageStyle: "Layout",
            .colorBlack: "Black",
            .colorBlue: "Blue",
            .colorCustom: "Palette",
            .colorGray: "Light Gray",
            .colorOrange: "Orange",
            .colorPink: "Pink",
            .colorWhite: "White",
            .color: "Color",
            .canvas: "Canvas",
            .cycling: "Cycling",
            .dark: "Dark",
            .dataIntegration: "Data Connections",
            .dayBeforeYesterday: "The Day Before Yesterday",
            .delete: "Delete",
            .deleteRoute: "Delete Route?",
            .deleteRouteMessage: "This cannot be undone.",
            .debugProAccessLocked: "Locked",
            .debugProAccessMockEnabled: "Enable Pro Mock",
            .debugProAccessSimulation: "Simulate Pro Access",
            .debugProAccessUnlocked: "Unlocked",
            .debugHomeDataSimulation: "Home Data Simulation",
            .debugSimulateHomeEmptyData: "Simulate Empty Home Data",
            .demoModeEntry: "View Demo Mode",
            .demoModeExit: "Exit Demo Mode",
            .demoModeExitMessage: "After exiting, the app will return to real data mode.",
            .demoModeExitTitle: "Exit Demo Mode?",
            .demoModeTitle: "Demo Mode",
            .developerWebsite: "Developer Website",
            .developerTools: "Developer Tools",
            .disable: "Disable",
            .distanceMetersFormat: "%.0f m",
            .enable: "Enable",
            .estimatedBurnedCaloriesFormat: "About %.0f kcal burned",
            .exit: "Exit",
            .healthAuthorizationDenied: "Health data read permission has not been granted.",
            .healthAuthorizationFailed: "Health authorization failed",
            .healthAuthorizationProgress: "Requesting Apple Health workout, route, and metric read permissions...",
            .healthAuthorizationSettingsRequiredMessage: "Enable workout, route, and metric read permissions for Movinn in system Settings or the Health app.",
            .healthAuthorizationSettingsRequiredTitle: "Apple Health Permission Required",
            .healthAuthorizationTemporarilyUnavailable: "Apple Health is not ready yet. Please try again in a moment.",
            .healthDataReadAuthorized: "Data read access is authorized",
            .healthDataUnavailable: "Health data is not available on this device.",
            .homeDataLoadingMessage: "Loading data, please wait...",
            .homeNoWorkoutDataMessage: "No workout data found. Time to head out!",
            .appleHealthDataSourceSubtitle: "Read data recorded in Apple Health.",
            .exportGPX: "Export GPX",
            .gpxExportFailed: "GPX export failed",
            .gpxExportNoRoute: "This route does not have exportable route points.",
            .gpxExportRouteName: "Route from Movinn",
            .gpxExporting: "Exporting GPX",
            .gpxImportInvalidFile: "This GPX file could not be parsed.",
            .gpxImportNoRoute: "This GPX file does not contain a usable route.",
            .followPhoto: "Follow",
            .hiking: "Hiking",
            .iCloudRouteSync: "iCloud Sync",
            .iCloudRouteSyncAccountChangedMessage: "Your iCloud account changed. Turn route sync on again for the new account.",
            .iCloudRouteSyncAccountUnavailableMessage: "Sign in to iCloud and turn on iCloud Drive in Settings first.",
            .iCloudRouteSyncAlreadyEnabled: "iCloud sync is already enabled",
            .iCloudRouteSyncConfirmMessage: "This will sync imported route data and automatically update iCloud whenever routes are imported or deleted.",
            .iCloudRouteSyncConfirmTitle: "Sync Imported Routes?",
            .iCloudRouteSyncDisabled: "iCloud sync disabled",
            .iCloudRouteSyncDisableConfirmMessage: "Disabling will stop syncing imported route data. Future route imports or deletions will not update iCloud automatically. Data already synced to iCloud will be kept.",
            .iCloudRouteSyncDisableConfirmTitle: "Disable iCloud Sync?",
            .iCloudRouteSyncEnabled: "iCloud sync enabled",
            .iCloudRouteSyncDocumentUnavailableMessage: "A route file in iCloud is temporarily unavailable.",
            .iCloudRouteSyncDriveUnavailableMessage: "iCloud Drive is temporarily unavailable. Please try again later.",
            .iCloudRouteSyncFailed: "iCloud sync could not be enabled",
            .routeCollectionICloudSyncFooterCompleteFormat: "Synced with iCloud · %d files total",
            .routeCollectionICloudSyncFooterErrorFormat: "iCloud sync unavailable · %d of %d files remaining",
            .routeCollectionICloudSyncFooterPendingFormat: "%d of %d files remaining",
            .routeCollectionICloudSyncFooterPreparing: "Checking iCloud sync status…",
            .mapBackgroundAdjustmentHint: "Double-tap map to adjust",
            .mapStyle: "Map Style",
            .livePhotoSaved: "Saved to Photos",
            .livePhotoSaving: "Creating Live Photo",
            .light: "Light",
            .more: "More",
            .movinnLocalDataPrivacyStatement: "- Movinn reads and processes your data on device by default. Imported GPX routes are saved to your iCloud Drive only when you explicitly enable iCloud sync.\n- Built-in global country and partial city databases power all lookups without network access.",
            .movinnPro: "Movinn Pro",
            .newActivity: "New!",
            .newRoute: "New Route!",
            .ok: "OK",
            .navigation: "Navigation",
            .startNavigation: "Start Navigation",
            .openEnd: "Go to End",
            .openPhotos: "View in Photos",
            .openStart: "Go to Start",
            .openSettings: "Open Settings",
            .other: "Other",
            .outdoorSwimming: "Outdoor Swimming",
            .outdoorWorkout: "Outdoor Workout",
            .photoLibraryFullAccessRequiredMessage: "Full Photos access is required to match photos to routes. Change Photos permission to Full Access in system settings.",
            .photoLibraryFullAccessRequiredTitle: "Full Photos Access Required",
            .photoLibraryReadAuthorized: "Photo access is authorized",
            .photoSaving: "Saving Image",
            .photoBackgroundAdjustmentHint: "Double-tap photo to adjust",
            .photoMatching: "Photo Matching",
            .privacyPolicy: "Privacy",
            .proCodeRedemption: "Redeem Code",
            .proFeatureHeatmap: "View route heatmaps",
            .proFeatureWellnessRecap: "Guidance built from your own activity data",
            .proFeatureICloudRouteSync: "Sync imported routes with iCloud",
            .proFeatureMultiLivePhotoExport: "Share multiple animated routes",
            .proFeatureMoreComing: "More features soon",
            .proFeatureRouteMerge: "Merge route segments",
            .proFeatureRouteSlope: "Show route gradients",
            .proPaywallSubtitle: "Movinn keeps advanced tools ready for easier workouts.",
            .proPaywallTitle: "Unlock Pro Features",
            .proProductUnavailable: "The subscription is unavailable. Please try again later.",
            .proPurchaseButton: "Unlock Forever",
            .proPurchaseButtonPriceFormat: "Unlock Forever %@",
            .proPurchaseFailed: "Purchase could not be completed.",
            .proPurchaseLoading: "Processing",
            .proPurchaseNotAllowed: "In-app purchases are not allowed on this device.",
            .proPurchasePending: "Purchase is pending confirmation.",
            .proPurchaseSuccess: "Movinn Pro is active",
            .proPurchaseUnverified: "Purchase could not be verified.",
            .proRestoreNoPurchase: "No purchase to restore",
            .proRestoreSuccess: "Purchase restored",
            .proStatusActive: "Pro features unlocked",
            .proUnlockedTitle: "Pro Features Unlocked",
            .queryingLocation: "Locating",
            .routeBook: "Use as Route Book",
            .routeBookExit: "Exit Route Book Mode?",
            .routeBookExitMessage: "You will return to the workout list.",
            .routeBookLocationPermissionRequiredMessage: "Allow Movinn to use location in system Settings so your position can be shown in Route Book mode.",
            .routeBookLocationPermissionRequiredTitle: "Location Permission Required",
            .route: "Route",
            .routeSlope: "Slope",
            .routeSlopeColorHint: "Greener sections are gentler; redder sections are steeper",
            .routeStyle3DFollowColor: "Match Color",
            .routeStyle3DSlopeColor: "Slope Colors",
            .wellnessRecapSheetTitle: "Guidance",
            .wellnessHeaderTip: "👆 Tap here for guidance built from your activity",
            .wellnessRangeThreeDays: "3 Days",
            .wellnessRangeWeek: "Week",
            .wellnessRangeMonth: "Month",
            .wellnessRangeHalfYear: "6 Months",
            .wellnessRangeYear: "Year",
            .wellnessSectionFacts: "Overview",
            .wellnessSectionTrends: "Trends",
            .wellnessSectionAdvice: "Advice",
            .wellnessChartSleep: "Sleep (hours)",
            .wellnessChartSteps: "Daily Steps",
            .wellnessChartLoad: "Training Load",
            .wellnessTableHeaderMetric: "Metric",
            .wellnessTableHeaderCurrent: "Current",
            .wellnessTableHeaderReference: "Ref.",
            .wellnessTableHeaderChange: "Change",
            .wellnessMetricSleep: "Sleep",
            .wellnessMetricSteps: "Avg Steps",
            .wellnessMetricExercise: "Exercise Min",
            .wellnessMetricWorkouts: "Workouts",
            .wellnessMetricDistance: "Distance",
            .wellnessMetricRHR: "Resting HR",
            .wellnessMetricHRV: "HRV",
            .wellnessAdviceSleepTrendUpTitle: "Sleep Is Improving",
            .wellnessAdviceSleepTrendUpEvidence: "About %@h more sleep on average than last period",
            .wellnessAdviceSleepTrendUpBody: "Whether by design or by rhythm, this is the right direction. Keep it going.",
            .wellnessAdviceSleepTrendDownTitle: "Sleep Is Slipping",
            .wellnessAdviceSleepTrendDownEvidence: "About %@h less sleep on average than last period",
            .wellnessAdviceSleepTrendDownBody: "A slide lasting weeks matters more than any single night. Think about what changed in your routine.",
            .wellnessAdviceVolumeUpTitle: "Training Volume Is Up",
            .wellnessAdviceVolumeUpEvidence: "About %d%% more exercise than last period",
            .wellnessAdviceVolumeUpBody: "Build gradually as volume rises, and keep enough recovery days.",
            .wellnessAdviceVolumeDownTitle: "Training Volume Is Down",
            .wellnessAdviceVolumeDownEvidence: "About %d%% less exercise than last period",
            .wellnessAdviceVolumeDownBody: "The dip itself isn't a problem — just don't let the gap stretch. Start with one easy session.",
            .wellnessAdviceConsistencyGoodTitle: "Remarkably Consistent",
            .wellnessAdviceConsistencyGoodEvidence: "Workouts recorded in %d of %d weeks",
            .wellnessAdviceConsistencyGoodBody: "Consistency drives long-term gains more than any single hard session. Keep the streak alive.",
            .wellnessAdviceConsistencyLowTitle: "Room for More Consistency",
            .wellnessAdviceConsistencyLowEvidence: "Workouts recorded in only %d of %d weeks",
            .wellnessAdviceConsistencyLowBody: "A small session at a fixed weekly time beats occasional big efforts for staying power.",
            .wellnessAdvicePBTitle: "New Record",
            .wellnessAdvicePBEvidence: "Longest single distance this period: %@ km, beating last period",
            .wellnessAdvicePBBody: "A new distance record means the base is getting stronger.",
            .wellnessAdviceDaylightTitle: "Low on Daylight",
            .wellnessAdviceDaylightEvidence: "About %d minutes of outdoor daylight per day recently",
            .wellnessAdviceDaylightBody: "Daylight is the strongest signal for your body clock. Fifteen minutes outside in the morning beats forcing an early bedtime.",
            .wellnessAdviceMidpointLateTitle: "Sleep Is Drifting Later",
            .wellnessAdviceMidpointLateEvidence: "Sleep midpoint about %d minutes later than your norm",
            .wellnessAdviceMidpointLateBody: "The drift happens without noticing. Pulling bedtime back 20 minutes tonight works better than weekend catch-up.",
            .wellnessAdviceDeepSleepTitle: "Deep Sleep Share Is Low",
            .wellnessAdviceDeepSleepEvidence: "Deep sleep at about %d%% of total recently",
            .wellnessAdviceDeepSleepBody: "Device deep-sleep numbers are estimates. Skipping caffeine and bright screens in the last hour before bed is the most direct lever.",
            .wellnessAdviceRHRImprovedTitle: "Your Engine Is Getting Stronger",
            .wellnessAdviceRHRImprovedEvidence: "Resting heart rate about %d bpm below your norm (now ~%d bpm)",
            .wellnessAdviceRHRImprovedBody: "A falling resting heart rate is one of the most reliable signs of improving aerobic fitness. The training is working.",
            .wellnessAdviceStepsUpTitle: "Everyday Activity Is Up",
            .wellnessAdviceStepsUpEvidence: "Daily steps about %d%% higher than last period",
            .wellnessAdviceStepsUpBody: "Gains in everyday walking tend to stick better than planned workouts. Good momentum.",
            .wellnessAdviceStepsDownTitle: "Everyday Activity Is Down",
            .wellnessAdviceStepsDownEvidence: "Daily steps about %d%% lower than last period",
            .wellnessAdviceStepsDownBody: "Movement outside workouts matters just as much. A walk on the commute or after lunch is the easiest piece to win back.",
            .wellnessAdviceHabitDayTitle: "%@ Is Your Training Day",
            .wellnessAdviceHabitDayEvidence: "%d training days landed on %@",
            .wellnessAdviceHabitDayBody: "A fixed training day is the most underrated consistency trick — it turns \u{201C}should I?\u{201D} into \u{201C}it's time.\u{201D}",
            .wellnessAdviceStepsConsistentTitle: "Steps Are Rock Steady",
            .wellnessAdviceStepsConsistentEvidence: "%1$d of the last %2$d days at or above your norm",
            .wellnessAdviceStepsConsistentBody: "Consistency is rarer than peaks. Your everyday activity base is solid.",
            .wellnessAdviceHRVHighTitle: "Recovery Is Dialed In",
            .wellnessAdviceHRVHighEvidence: "HRV about %d%% above your norm",
            .wellnessAdviceHRVHighBody: "Your body is recovering well. If a hard session is on the plan, now is a good window for it.",
            .wellnessAdviceWorkoutGapTitle: "The Gap Is Stretching",
            .wellnessAdviceWorkoutGapEvidence: "%d days in a row without a workout",
            .wellnessAdviceWorkoutGapBody: "For someone who trains regularly, long gaps make restarting harder. One easy session today is enough.",
            .wellnessAdviceStreakTitle: "On a Streak",
            .wellnessAdviceStreakEvidence: "%d consecutive days with workouts",
            .wellnessAdviceStreakBody: "Great momentum. Just remember recovery days — the easy day after a streak is part of the training too.",
            .wellnessAdviceRHRTrendGoodTitle: "Resting HR Trending Down",
            .wellnessAdviceRHRTrendGoodEvidence: "About %d bpm lower than last period (now ~%d bpm)",
            .wellnessAdviceRHRTrendGoodBody: "A long-term drop in resting heart rate usually means your aerobic base is deepening. Worth keeping up.",
            .wellnessAdviceRHRTrendBadTitle: "Resting HR Trending Up",
            .wellnessAdviceRHRTrendBadEvidence: "About %d bpm higher than last period (now ~%d bpm)",
            .wellnessAdviceRHRTrendBadBody: "A sustained rise can relate to stress, sleep or under-recovery. For reference only — consult a professional if you feel unwell.",
            .wellnessAdviceCarbTitle: "Carbs First After Long Sessions",
            .wellnessAdviceCarbEvidence: "%d sessions over 60 minutes this period, longest about %d min",
            .wellnessAdviceCarbBody: "Sessions past an hour drain glycogen. Eating starchy carbs — rice, pasta, oats or fruit — within one to two hours afterwards restores it fastest.",
            .wellnessAdviceProteinTitle: "Spread Protein Across the Day",
            .wellnessAdviceProteinEvidence: "About %d minutes of training this period",
            .wellnessAdviceProteinBody: "Twenty to thirty grams after a session is enough — a palm of meat, two eggs, or a cup of Greek yoghurt. Spreading it across meals beats loading it all at dinner.",
            .wellnessAdviceHydrationTitle: "Sip Often, Don't Chug",
            .wellnessAdviceHydrationEvidence: "Peak daily active burn of about %d kcal this period",
            .wellnessAdviceHydrationEvidenceLong: "Sessions over 90 minutes this period",
            .wellnessAdviceHydrationBody: "Downing plain water after heavy sweating dilutes electrolytes. Drink small amounts often, and add sodium — a sports drink or salted food — for anything over an hour.",
            .wellnessAdviceLateMealTitle: "Short Sleep Drives Appetite",
            .wellnessAdviceLateMealEvidence: "Averaging about %@h of sleep this period",
            .wellnessAdviceLateMealBody: "Too little sleep raises hunger signals and dulls fullness, most noticeably at night. Finishing meals two hours before bed takes less willpower than resisting later.",
            .wellnessAdviceLightWeekTitle: "Lighter Training, Normal Eating",
            .wellnessAdviceLightWeekEvidence: "Lower training volume this period",
            .wellnessAdviceLightWeekBody: "Low-volume stretches don't call for extra fuelling. Hold your baseline protein and vegetables, and adjust again when volume returns.",
            .wellnessAdviceSleepRoutineTitle: "Sleep Rhythm Is Holding",
            .wellnessAdviceSleepRoutineEvidence: "Averaging about %@h of sleep this period",
            .wellnessAdviceSleepRoutineBody: "Nothing unusual here. Keeping a steady bedtime is worth more than the occasional long night.",
            .wellnessAdviceMixTitle: "Vary Your Intensities",
            .wellnessAdviceMixEvidence: "About %d minutes of training this period",
            .wellnessAdviceMixBody: "Mostly easy aerobic work with a small share of hard efforts is the structure endurance research keeps validating. Living in the middle zone returns the least.",
            .wellnessAdviceRestDayTitle: "Schedule the Recovery Days",
            .wellnessAdviceRestDayEvidence: "Recovery is part of the training",
            .wellnessAdviceRestDayBody: "You get stronger while resting, not while training. One or two easy or full-rest days a week keeps long-term progress steadier.",
            .wellnessAdviceCarbNowTitle: "Refill Glycogen Over the Next Day",
            .wellnessAdviceCarbNowEvidence: "Most recent long session about %d minutes",
            .wellnessAdviceCarbNowBody: "In the 24 hours after a long session, carbs matter more than protein. A proper portion of starch at your next meal does more than adding another chicken breast.",
            .wellnessAdviceProteinNowTitle: "Protein in Your Next Two Meals",
            .wellnessAdviceProteinNowEvidence: "About %d minutes of training in the last three days",
            .wellnessAdviceProteinNowBody: "Muscle repair runs hottest in the day or two after training. One protein source per meal — eggs, tofu, fish — beats loading it all into one sitting.",
            .wellnessAdviceFuelGrowthTitle: "Volume Is Up — Fuelling Should Be Too",
            .wellnessAdviceFuelGrowthEvidence: "Roughly %d minutes per week, well above last period",
            .wellnessAdviceFuelGrowthBody: "When volume steps up, the usual mistake is eating too little, not too much — it shows up as feeling flat the more you train. Raise both carbs and protein to match.",
            .wellnessAdviceNutritionBaseTitle: "The Diet Base for This Volume",
            .wellnessAdviceNutritionBaseEvidence: "Roughly %d minutes per week",
            .wellnessAdviceNutritionBaseBody: "At this volume, steady starch, protein and vegetables across your regular meals matter more than any supplement. Consistency in the basics decides long-term form.",
            .wellnessAdviceNutritionBaseYearBody: "Holding this volume for a full year runs on sustainable everyday eating, not last-minute fixes. A steady three-meal structure is the best long-term plan there is.",
            .wellnessAdviceMilestoneTitle: "Milestone for This Stretch",
            .wellnessAdviceMilestoneEvidence: "%@ km across %d sessions",
            .wellnessAdviceMilestoneBody: "That total was built one session at a time. Looking back, showing up repeatedly was the hard part.",
            .wellnessAdviceMilestoneYearBody: "A year's total looks striking, but it's made entirely of ordinary days you went out anyway. That's what the long game looks like.",
            .wellnessAdviceSeasonalTitle: "Your Training Has Seasons",
            .wellnessAdviceSeasonalEvidence: "Busiest in %@, quietest in %@",
            .wellnessAdviceSeasonalBody: "Seasonal swings are normal. What helps is planning the quiet months — indoors, shorter sessions, or a different sport — so the base doesn't slide too far.",
            .wellnessAdviceTonightTitle: "Head to Bed Early Tonight",
            .wellnessAdviceTonightEvidence: "About %@h last night against your usual %@h",
            .wellnessAdviceTonightBody: "Aim to be in bed by %@ tonight, roughly %d minutes earlier than usual. Closing the gap the same day works best; saving it for the weekend costs you most of the benefit.",
            .wellnessTipSleep1: "A fixed wake time is easier to hold than a fixed bedtime — and it steadies your body clock more.",
            .wellnessTipSleep2: "Dimming the lights an hour before bed beats counting sheep. Light is the strongest wakefulness signal there is.",
            .wellnessTipSleep3: "Caffeine has a half-life of roughly five hours, so the mid-afternoon cup is often what's eating your deep sleep.",
            .wellnessTipSleep4: "A warm bath before bed helps because the temperature drop afterwards is itself a sleep cue.",
            .wellnessTipSleep5: "If you're still awake after 20 minutes, getting up for something quiet and returning works better than lying there.",
            .wellnessTipActivity1: "Laying out your kit the night before is the best-evidenced way to lower the barrier to starting.",
            .wellnessTipActivity2: "Shorten the session rather than skip it — ten minutes is worth far more to the habit than zero.",
            .wellnessTipActivity3: "Changing the route or the sport sustains interest better than forcing the volume up.",
            .wellnessTipActivity4: "A warm-up needn't be elaborate. Going slowly for the first five minutes is the warm-up.",
            .wellnessTipActivity5: "One session a week with someone else measurably improves the odds you keep going.",
            .wellnessTipNutrition1: "Rehydrate before you eat after training — appetite signals are unreliable when you're dehydrated.",
            .wellnessTipNutrition2: "Putting fruit where you can see it is the cheapest dietary change there is.",
            .wellnessTipNutrition3: "Eating differently on training and rest days is normal. It doesn't have to look the same every day.",
            .wellnessTipNutrition4: "Less-processed carbs generally bring steadier fullness and gentler blood-sugar swings.",
            .wellnessTipNutrition5: "A late dinner eats into deep sleep. Two hours before bed is a sensible line.",
            .wellnessTipRecovery1: "Recovery isn't only lying down — walking and stretching often restore you faster than doing nothing.",
            .wellnessTipRecovery2: "A dip lasting two weeks usually traces back to something outside training — work, sleep or mood.",
            .wellnessTipRecovery3: "Resting heart rate and HRV swing with alcohol and illness. Read the trend, not any single day.",
            .wellnessTipRecovery4: "When your legs feel heavy, dropping intensity while keeping frequency gets you back faster than stopping entirely.",
            .wellnessTipPositive1: "Progress is rarely linear. Plateaus are part of getting stronger, not a break from it.",
            .wellnessTipPositive2: "Note this stretch down somewhere — it's worth rereading during the next low patch.",
            .wellnessTipPositive3: "Feeling good is exactly when people overreach. Leave some room in next week's plan.",
            .wellnessTipPositive4: "The training that lasts is usually the kind you don't dislike, not the kind that's most efficient.",
            .wellnessSummaryRisk: "One signal needs your attention this week — see the top item first.",
            .wellnessSummaryAttention: "Looking good overall, with a few things worth tuning.",
            .wellnessSummaryGood: "You're in good shape. Keep it up.",
            .wellnessSummaryCold: "Still gathering data — here are this week's facts.",
            .wellnessFactSleepFormat: "Sleep: %@h average over the last 7 days (%d days recorded)",
            .wellnessFactStepsFormat: "Steps: %@ per day on average",
            .wellnessFactWorkoutsFormat: "Workouts: %d sessions · %@ km · %d min",
            .wellnessFactExerciseFormat: "Exercise time: %d min total this week",
            .wellnessCoverageNoteFormat: "Some days lack records (sleep %d/%d, steps %d/%d). Missing days are never counted as zero.",
            .wellnessDisclaimer: "This is lifestyle guidance based on your own data, generated on-device. It is not medical advice.",
            .wellnessAuthPromptTitle: "Curious About Your Own Patterns?",
            .wellnessAuthPromptBody: "If you'd like, you can let Movinn read your Health data. It builds a summary and suggestions from your sleep, steps and workouts right here on this device — nothing is uploaded, nothing is shared, and you can change your mind any time in Settings.",
            .wellnessAuthButton: "Sure, let's try",
            .wellnessLoading: "Building your weekly guide…",
            .wellnessEmptyBody: "Still gathering data. Record a few days with your device and your personal summary will appear here.",
            .wellnessAdviceSleepDebtTitle: "Pay Back Some Sleep Debt",
            .wellnessAdviceSleepDebtEvidence: "About %@h less sleep than your norm over the last 7 days",
            .wellnessAdviceSleepDebtBody: "Try going to bed about %d minutes earlier for the next 3 nights — tonight, wind down before %@.",
            .wellnessAdviceSleepIrregularTitle: "Irregular Sleep Schedule",
            .wellnessAdviceSleepIrregularEvidence: "Bedtime varied by about ±%d minutes this week",
            .wellnessAdviceSleepIrregularBody: "A fixed bedtime window beats catching up on hours: try falling asleep between %@ and %@.",
            .wellnessAdviceSleepShortTitle: "Consistently Short Sleep",
            .wellnessAdviceSleepShortEvidence: "Averaging %@h recently, below your usual %@h",
            .wellnessAdviceSleepShortBody: "Short sleep slows recovery first, then performance. Start by reclaiming your easiest night this week.",
            .wellnessAdviceWeekendJetlagTitle: "Weekend Catch-Up Sleep",
            .wellnessAdviceWeekendJetlagEvidence: "About %@h more sleep on weekends than weekdays",
            .wellnessAdviceWeekendJetlagBody: "Catching up means weekdays are running a deficit. Nudge weekday bedtime earlier by 15–30 minutes.",
            .wellnessAdviceSleepStableTitle: "Sleep Is Steady",
            .wellnessAdviceSleepStableEvidence: "Averaging %@h with a regular rhythm this week",
            .wellnessAdviceSleepStableBody: "Duration and rhythm are both within your normal range. Keep the current pace.",
            .wellnessAdviceLoadSpikeTitle: "Ramping Up Too Fast",
            .wellnessAdviceLoadSpikeEvidence: "This week's training load is about %@× your monthly norm",
            .wellnessAdviceLoadSpikeBody: "Rapid spikes in load are linked to injury risk. Ease back to your normal level next week and favour low intensity.",
            .wellnessAdviceLoadDropTitle: "Training Has Dropped Off",
            .wellnessAdviceLoadDropEvidence: "This week's load is under 60% of your norm",
            .wellnessAdviceLoadDropBody: "No need to make it all up at once: two sessions of about %d minutes will get the rhythm back.",
            .wellnessAdviceSedentaryTitle: "Activity Running Low",
            .wellnessAdviceSedentaryEvidence: "Steps below %2$@ for %1$d days in a row",
            .wellnessAdviceSedentaryBody: "Aim for %@ steps today — a target based on your own norm, not a generic 10,000.",
            .wellnessAdviceRecoveryTitle: "Weak Recovery Signals",
            .wellnessAdviceRecoveryEvidence: "Resting heart rate about %2$d bpm above your norm for %1$d days%3$@",
            .wellnessAdviceRecoveryBody: "Consider low intensity or rest today and tomorrow. For reference only — consult a professional if you feel unwell.",
            .wellnessAdviceRecoveryHRVSuffix: ", with HRV trending down too",
            .wellnessAdviceActiveWeekTitle: "Active Week — Target Met",
            .wellnessAdviceActiveWeekEvidence: "%d minutes of exercise this week",
            .wellnessAdviceActiveWeekBody: "You've hit the WHO-recommended 150 minutes per week. Take the win.",
            .routeCollection: "Imported Routes",
            .routeCollectionMenuTitle: "Routes",
            .routeCollectionEmptyMessage: "No imported routes yet",
            .routeCollectionImportSectionTitle: "Imported",
            .routeCollectionImportSuccess: "GPX route imported",
            .routeCollectionImporting: "Importing GPX",
            .routeCollectionMergeSectionTitle: "Merged",
            .routeHeatmap: "Route Heatmap",
            .heatmapShareMask: "Mask",
            .heatmapShareMaskOpacity: "Mask Opacity",
            .heatmapShareMonth: "Month",
            .heatmapShareNoRoutes: "No routes in this range",
            .heatmapSharePhoto: "Photo",
            .heatmapShareSelectRouteForColor: "Select a route first",
            .heatmapShareTitle: "Share Route Collection",
            .heatmapShareWeek: "Week",
            .heatmapShareYear: "Year",
            .routeLoading: "Loading Route",
            .routeMerge: "Merge Routes",
            .routeMergeCompletedMessage: "The route has been merged. You can view it on the Routes page.",
            .routeMergeCompletedTitle: "Route Merged",
            .routeMergeDefaultTitle: "Merged Route",
            .routeMergeFailed: "Route merge failed",
            .routeMergeLoading: "Merging Routes",
            .routeMergeMultipleTitleFormat: "%@ and %d segments",
            .routeMergeNoRoutes: "Select the routes you want to merge.",
            .routeMergeViewRoutes: "View Routes",
            .restorePurchases: "Restore Purchase",
            .running: "Running",
            .satellite: "Satellite",
            .share: "Share",
            .sportsCareerAnnualData: "Year",
            .sportsCareerMonthlyData: "Month",
            .sportsCareerOverview: "Overview",
            .sportsCareerLocations: "Workout Places",
            .sportsCareerWorldMap: "World",
            .sportsCareerChinaMap: "China",
            .sportsCareerCountryCountFormat: "%d countries",
            .sportsCareerCityCountFormat: "%d cities",
            .sportsCareerSummary: "Summary",
            .sportsCareerWeeklyData: "This Week",
            .sportsCareerWeekDistanceFormat: "Week %d\n%.1f km",
            .sportsCareerWeekTitleWithRangeFormat: "Week %d · %@-%@",
            .sportTypeCountSummary: "Workout Count by Type",
            .sportTypeTimeSummary: "Workout Time Summary",
            .sportsCareer: "Sports Career",
            .data: "Data",
            .standard: "Standard",
            .sportType: "Sport Type",
            .sportTypeSummary: "Sport Type Summary",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava is already authorized to read your activity data.",
            .stravaDataSourceSubtitle: "Read data recorded in Strava.",
            .stravaReauthorizationRequired: "Strava authorization has expired. Open More and tap Strava to sign in again.",
            .saveLivePhoto: "Save Live Photo",
            .startTimeFormat: "Starts %@",
            .stillOpen: "Open Anyway",
            .systemPhotos: "Photos",
            .systemMapsNotFound: "System Maps not found",
            .termsOfUse: "Terms",
            .totalActivityCountFormat: "%d times",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "Total Count",
            .totalWorkoutDistance: "Total Mileage",
            .totalWorkoutTime: "Total Time",
            .trailRunning: "Trail Running",
            .tools: "Tools",
            .time: "Time",
            .today: "Today",
            .uiSettings: "Feature Settings",
            .unknownDistance: "Unknown Distance",
            .unknownDuration: "Unknown Duration",
            .unknownLocation: "Unknown Location",
            .virtualCycling: "Virtual Cycling",
            .virtualRunning: "Virtual Running",
            .walking: "Walking",
            .walkingHiking: "Walking/Hiking",
            .widgets: "Widgets",
            .widgetSmallWeeklyGoal: "Weekly Ring Data",
            .widgetWeeklyChart: "Weekly Bar Chart",
            .widgetMonthlyCalendar: "Monthly Calendar",
            .widgetAnnualTrajectory: "Annual Trace",
            .widgetLocationMaps: "Workout Maps",
            .widgetWorldMap: "World Map",
            .widgetWorldCountryWorkoutFormat: "Worked out in %d/%d countries",
            .widgetChinaMap: "China Map",
            .widgetChinaCityWorkoutFormat: "Worked out in %d/%d cities",
            .widgetWeeklyGoalDistance: "Weekly Goal Distance",
            .kilometers: "km",
            .workoutStart: "Workout Start",
            .workoutEnd: "Workout End",
            .endNotFound: "End not found",
            .startNotFound: "Start not found",
            .yesterday: "Yesterday",
            .burnedCaloriesFormat: "Burned %.0f kcal",
            .calories: "Calories",
            .durationHoursFormat: "%d hr",
            .durationHoursMinutesFormat: "%d hr %d min",
            .durationMinutesFormat: "%d min",
            .elevationGainFormat: "Gain %.0f m"
        ]
    ]
}
