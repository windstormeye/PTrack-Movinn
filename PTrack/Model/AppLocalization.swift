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
    case appLanguage
    case aspectRatio
    case appleHealth
    case appDefault
    case activitySummaryPrefix
    case cancel
    case collage
    case collageSingleLivePhotoLimit
    case collageStyle
    case color
    case cycling
    case dark
    case dataIntegration
    case dayBeforeYesterday
    case delete
    case deleteRoute
    case deleteRouteMessage
    case developerWebsite
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
    case gpxExportFailed
    case gpxExportNoRoute
    case gpxExportRouteName
    case gpxExporting
    case gpxImportInvalidFile
    case gpxImportNoRoute
    case followPhoto
    case hiking
    case iCloudRouteSync
    case iCloudRouteSyncAlreadyEnabled
    case iCloudRouteSyncConfirmMessage
    case iCloudRouteSyncConfirmTitle
    case iCloudRouteSyncDisabled
    case iCloudRouteSyncDisableConfirmMessage
    case iCloudRouteSyncDisableConfirmTitle
    case iCloudRouteSyncEnabled
    case iCloudRouteSyncFailed
    case routeCollectionICloudSyncComplete
    case routeCollectionICloudSyncProgressFormat
    case mapStyle
    case livePhotoSaved
    case livePhotoSaving
    case more
    case movinnLocalDataPrivacyStatement
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
    case queryingLocation
    case routeBook
    case routeBookExit
    case routeBookExitMessage
    case routeBookLocationPermissionRequiredMessage
    case routeBookLocationPermissionRequiredTitle
    case route
    case routeCollection
    case routeCollectionMenuTitle
    case routeCollectionEmptyMessage
    case routeCollectionImportSectionTitle
    case routeCollectionImportSuccess
    case routeCollectionImporting
    case routeCollectionMergeSectionTitle
    case routeHeatmap
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
    case totalActivityCountFormat
    case totalDistanceFormat
    case totalWorkoutCount
    case totalWorkoutDistance
    case totalWorkoutTime
    case trailRunning
    case tools
    case today
    case uiSettings
    case unknownDistance
    case unknownDuration
    case unknownLocation
    case virtualCycling
    case virtualRunning
    case walking
    case walkingHiking
    case workoutStart
    case workoutEnd
    case endNotFound
    case startNotFound
    case yesterday
    case burnedCaloriesFormat
    case durationHoursFormat
    case durationHoursMinutesFormat
    case durationMinutesFormat
    case elevationGainFormat
}

final class AppLanguageStore {
    static let shared = AppLanguageStore()
    static let languageDidChangeNotification = Notification.Name("studio.pj.PTrack.languageDidChange")

    private let defaults: UserDefaults
    private let key = "studio.pj.PTrack.appLanguage"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var language: AppLanguage {
        get {
            guard let rawValue = defaults.string(forKey: key),
                  let language = AppLanguage(rawValue: rawValue) else {
                return .chinese
            }

            return language
        }
        set {
            guard newValue != language else {
                return
            }

            defaults.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: newValue)
        }
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
            .appLanguage: "App 语言",
            .aspectRatio: "比例",
            .appleHealth: "苹果健康",
            .appDefault: "默认",
            .activitySummaryPrefix: "运动",
            .cancel: "取消",
            .collage: "拼图",
            .collageSingleLivePhotoLimit: "拼图模式只允许加入一张 Live 图",
            .collageStyle: "样式",
            .color: "颜色",
            .cycling: "骑行",
            .dark: "暗色",
            .dataIntegration: "数据接入",
            .dayBeforeYesterday: "前天",
            .delete: "删除",
            .deleteRoute: "删除路线？",
            .deleteRouteMessage: "删除后无法恢复。",
            .developerWebsite: "开发者网站",
            .disable: "关闭",
            .distanceMetersFormat: "%.0f 米",
            .enable: "开启",
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
            .iCloudRouteSyncAlreadyEnabled: "iCloud 同步已开启",
            .iCloudRouteSyncConfirmMessage: "确认后会同步导入路线数据，并在之后导入或删除路线时自动同步 iCloud。",
            .iCloudRouteSyncConfirmTitle: "确认同步导入路线数据？",
            .iCloudRouteSyncDisabled: "已关闭 iCloud 同步",
            .iCloudRouteSyncDisableConfirmMessage: "关闭后将停止同步导入路线数据，之后导入或删除路线不会自动同步 iCloud。已同步到 iCloud 的数据会保留。",
            .iCloudRouteSyncDisableConfirmTitle: "关闭 iCloud 同步？",
            .iCloudRouteSyncEnabled: "已开启 iCloud 同步",
            .iCloudRouteSyncFailed: "iCloud 同步开启失败",
            .routeCollectionICloudSyncComplete: "iCloud 同步完成",
            .routeCollectionICloudSyncProgressFormat: "%d/%d iCloud 同步中",
            .mapStyle: "地图样式",
            .livePhotoSaved: "已保存到相册",
            .livePhotoSaving: "正在生成 Live Photo",
            .more: "更多",
            .movinnLocalDataPrivacyStatement: "- Movinn 只读取你的数据做可视化，绝不上传数据，所有功能均在本地完成。\n- 内置了全球国家和部分城市数据库，所有查询均不联网。",
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
            .photoBackgroundAdjustmentHint: "双击照片空白区域可调整显示范围",
            .photoMatching: "照片匹配",
            .queryingLocation: "位置查询中",
            .routeBook: "作为路书",
            .routeBookExit: "退出作为路书？",
            .routeBookExitMessage: "退出后将回到运动列表。",
            .routeBookLocationPermissionRequiredMessage: "请在系统设置中允许 Movinn 使用位置，这样才能在作为路书时显示你的位置。",
            .routeBookLocationPermissionRequiredTitle: "需要位置权限",
            .route: "轨迹",
            .routeCollection: "导入路线",
            .routeCollectionMenuTitle: "路线",
            .routeCollectionEmptyMessage: "还没有导入路线",
            .routeCollectionImportSectionTitle: "导入",
            .routeCollectionImportSuccess: "已导入 GPX 路线",
            .routeCollectionImporting: "正在导入 GPX",
            .routeCollectionMergeSectionTitle: "合并",
            .routeHeatmap: "轨迹热图",
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
            .totalActivityCountFormat: "%d 次",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "总次数",
            .totalWorkoutDistance: "总里程",
            .totalWorkoutTime: "总时间",
            .trailRunning: "越野跑",
            .tools: "工具",
            .today: "今天",
            .uiSettings: "功能设置",
            .unknownDistance: "未知距离",
            .unknownDuration: "未知时长",
            .unknownLocation: "未知位置",
            .virtualCycling: "虚拟骑行",
            .virtualRunning: "虚拟跑步",
            .walking: "行走",
            .walkingHiking: "行走/徒步",
            .workoutStart: "运动起点",
            .workoutEnd: "运动终点",
            .endNotFound: "未找到终点",
            .startNotFound: "未找到起点",
            .yesterday: "昨天",
            .burnedCaloriesFormat: "消耗 %.0f 大卡",
            .durationHoursFormat: "%d小时",
            .durationHoursMinutesFormat: "%d小时%d分钟",
            .durationMinutesFormat: "%d分钟",
            .elevationGainFormat: "爬升 %.0f 米"
        ],
        .japanese: [
            .all: "すべて",
            .appLanguage: "アプリの言語",
            .aspectRatio: "比率",
            .appleHealth: "Appleヘルスケア",
            .appDefault: "デフォルト",
            .activitySummaryPrefix: "運動",
            .cancel: "キャンセル",
            .collage: "コラージュ",
            .collageSingleLivePhotoLimit: "コラージュモードでは Live Photo は1枚だけ追加できます",
            .collageStyle: "レイアウト",
            .color: "カラー",
            .cycling: "サイクリング",
            .dark: "ダーク",
            .dataIntegration: "データ連携",
            .dayBeforeYesterday: "一昨日",
            .delete: "削除",
            .deleteRoute: "ルートを削除しますか？",
            .deleteRouteMessage: "削除すると元に戻せません。",
            .developerWebsite: "開発者サイト",
            .disable: "オフにする",
            .distanceMetersFormat: "%.0f m",
            .enable: "オンにする",
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
            .iCloudRouteSyncAlreadyEnabled: "iCloud同期はオンです",
            .iCloudRouteSyncConfirmMessage: "読み込んだルートのデータを同期し、今後ルートを読み込むか削除したときに iCloud へ自動同期します。",
            .iCloudRouteSyncConfirmTitle: "読み込んだルートを同期しますか？",
            .iCloudRouteSyncDisabled: "iCloud同期をオフにしました",
            .iCloudRouteSyncDisableConfirmMessage: "オフにすると読み込んだルートの同期を停止し、今後ルートを読み込むか削除したときに iCloud へ自動同期しません。すでに iCloud に同期されたデータは保持されます。",
            .iCloudRouteSyncDisableConfirmTitle: "iCloud同期をオフにしますか？",
            .iCloudRouteSyncEnabled: "iCloud同期をオンにしました",
            .iCloudRouteSyncFailed: "iCloud同期をオンにできませんでした",
            .routeCollectionICloudSyncComplete: "iCloud同期完了",
            .routeCollectionICloudSyncProgressFormat: "%d/%d iCloud同期中",
            .mapStyle: "地図スタイル",
            .livePhotoSaved: "写真に保存しました",
            .livePhotoSaving: "Live Photoを生成中",
            .more: "その他",
            .movinnLocalDataPrivacyStatement: "- Movinn は可視化のためだけにあなたのデータを読み取り、データをアップロードせず、すべての機能をローカルで完了します。\n- 世界の国と一部都市のデータベースを内蔵しており、すべての検索はネットワークを使いません。",
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
            .photoBackgroundAdjustmentHint: "写真の空白部分をダブルタップして表示範囲を調整できます",
            .photoMatching: "写真照合",
            .queryingLocation: "位置を検索中",
            .routeBook: "ルートブックとして使う",
            .routeBookExit: "ルートブックモードを終了しますか？",
            .routeBookExitMessage: "終了するとワークアウト一覧に戻ります。",
            .routeBookLocationPermissionRequiredMessage: "ルートブックモードで現在地を表示するには、システム設定で Movinn の位置情報利用を許可してください。",
            .routeBookLocationPermissionRequiredTitle: "位置情報の許可が必要です",
            .route: "ルート",
            .routeCollection: "ルート読み込み",
            .routeCollectionMenuTitle: "ルート",
            .routeCollectionEmptyMessage: "読み込んだルートはまだありません",
            .routeCollectionImportSectionTitle: "読み込み",
            .routeCollectionImportSuccess: "GPX ルートを読み込みました",
            .routeCollectionImporting: "GPX を読み込み中",
            .routeCollectionMergeSectionTitle: "結合",
            .routeHeatmap: "軌跡ヒートマップ",
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
            .totalActivityCountFormat: "%d回",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "合計回数",
            .totalWorkoutDistance: "合計距離",
            .totalWorkoutTime: "合計時間",
            .trailRunning: "トレイルランニング",
            .tools: "ツール",
            .today: "今日",
            .uiSettings: "機能設定",
            .unknownDistance: "不明な距離",
            .unknownDuration: "不明な時間",
            .unknownLocation: "不明な位置",
            .virtualCycling: "バーチャルサイクリング",
            .virtualRunning: "バーチャルランニング",
            .walking: "ウォーキング",
            .walkingHiking: "ウォーキング/ハイキング",
            .workoutStart: "ワークアウト開始地点",
            .workoutEnd: "ワークアウト終了地点",
            .endNotFound: "ゴール地点が見つかりません",
            .startNotFound: "スタート地点が見つかりません",
            .yesterday: "昨日",
            .burnedCaloriesFormat: "%.0f kcal 消費",
            .durationHoursFormat: "%d時間",
            .durationHoursMinutesFormat: "%d時間%d分",
            .durationMinutesFormat: "%d分",
            .elevationGainFormat: "獲得標高 %.0f m"
        ],
        .korean: [
            .all: "전체",
            .appLanguage: "앱 언어",
            .aspectRatio: "비율",
            .appleHealth: "Apple 건강",
            .appDefault: "기본",
            .activitySummaryPrefix: "운동",
            .cancel: "취소",
            .collage: "콜라주",
            .collageSingleLivePhotoLimit: "콜라주 모드에서는 Live Photo를 한 장만 추가할 수 있어요",
            .collageStyle: "레이아웃",
            .color: "색상",
            .cycling: "사이클링",
            .dark: "어두운",
            .dataIntegration: "데이터 연동",
            .dayBeforeYesterday: "그저께",
            .delete: "삭제",
            .deleteRoute: "경로를 삭제할까요?",
            .deleteRouteMessage: "삭제하면 되돌릴 수 없습니다.",
            .developerWebsite: "개발자 웹사이트",
            .disable: "끄기",
            .distanceMetersFormat: "%.0f m",
            .enable: "켜기",
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
            .iCloudRouteSyncAlreadyEnabled: "iCloud 동기화가 켜져 있습니다",
            .iCloudRouteSyncConfirmMessage: "가져온 경로 데이터를 동기화하고 이후 경로를 가져오거나 삭제할 때 iCloud에 자동으로 동기화합니다.",
            .iCloudRouteSyncConfirmTitle: "가져온 경로를 동기화할까요?",
            .iCloudRouteSyncDisabled: "iCloud 동기화가 꺼졌습니다",
            .iCloudRouteSyncDisableConfirmMessage: "끄면 가져온 경로 데이터 동기화를 중지하고 이후 경로를 가져오거나 삭제할 때 iCloud에 자동으로 동기화하지 않습니다. 이미 iCloud에 동기화된 데이터는 유지됩니다.",
            .iCloudRouteSyncDisableConfirmTitle: "iCloud 동기화를 끌까요?",
            .iCloudRouteSyncEnabled: "iCloud 동기화가 켜졌습니다",
            .iCloudRouteSyncFailed: "iCloud 동기화를 켜지 못했습니다",
            .routeCollectionICloudSyncComplete: "iCloud 동기화 완료",
            .routeCollectionICloudSyncProgressFormat: "%d/%d iCloud 동기화 중",
            .mapStyle: "지도 스타일",
            .livePhotoSaved: "사진 앱에 저장되었습니다",
            .livePhotoSaving: "Live Photo 생성 중",
            .more: "더보기",
            .movinnLocalDataPrivacyStatement: "- Movinn은 시각화를 위해서만 데이터를 읽으며 데이터를 업로드하지 않고, 모든 기능은 로컬에서 완료됩니다.\n- 전 세계 국가와 일부 도시 데이터베이스를 내장하고 있어 모든 조회는 네트워크를 사용하지 않습니다.",
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
            .photoBackgroundAdjustmentHint: "사진의 빈 영역을 두 번 탭하면 표시 범위를 조정할 수 있습니다",
            .photoMatching: "사진 매칭",
            .queryingLocation: "위치 조회 중",
            .routeBook: "루트북으로 사용",
            .routeBookExit: "루트북 모드를 종료할까요?",
            .routeBookExitMessage: "종료하면 운동 목록으로 돌아갑니다.",
            .routeBookLocationPermissionRequiredMessage: "루트북 모드에서 현재 위치를 표시하려면 시스템 설정에서 Movinn의 위치 사용을 허용해 주세요.",
            .routeBookLocationPermissionRequiredTitle: "위치 권한 필요",
            .route: "경로",
            .routeCollection: "경로 가져오기",
            .routeCollectionMenuTitle: "경로",
            .routeCollectionEmptyMessage: "아직 가져온 경로가 없습니다",
            .routeCollectionImportSectionTitle: "가져오기",
            .routeCollectionImportSuccess: "GPX 경로를 가져왔습니다",
            .routeCollectionImporting: "GPX 가져오는 중",
            .routeCollectionMergeSectionTitle: "병합",
            .routeHeatmap: "경로 히트맵",
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
            .totalActivityCountFormat: "%d회",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "총 횟수",
            .totalWorkoutDistance: "총 거리",
            .totalWorkoutTime: "총 시간",
            .trailRunning: "트레일 러닝",
            .tools: "도구",
            .today: "오늘",
            .uiSettings: "기능 설정",
            .unknownDistance: "알 수 없는 거리",
            .unknownDuration: "알 수 없는 시간",
            .unknownLocation: "알 수 없는 위치",
            .virtualCycling: "가상 사이클링",
            .virtualRunning: "가상 달리기",
            .walking: "걷기",
            .walkingHiking: "걷기/하이킹",
            .workoutStart: "운동 시작점",
            .workoutEnd: "운동 종료점",
            .endNotFound: "종료점을 찾을 수 없음",
            .startNotFound: "시작점을 찾을 수 없음",
            .yesterday: "어제",
            .burnedCaloriesFormat: "%.0f kcal 소비",
            .durationHoursFormat: "%d시간",
            .durationHoursMinutesFormat: "%d시간 %d분",
            .durationMinutesFormat: "%d분",
            .elevationGainFormat: "상승 %.0f m"
        ],
        .english: [
            .all: "All",
            .appLanguage: "App Language",
            .aspectRatio: "Ratio",
            .appleHealth: "Apple Health",
            .appDefault: "Default",
            .activitySummaryPrefix: "Activity",
            .cancel: "Cancel",
            .collage: "Collage",
            .collageSingleLivePhotoLimit: "Collage mode allows only one Live Photo",
            .collageStyle: "Layout",
            .color: "Color",
            .cycling: "Cycling",
            .dark: "Dark",
            .dataIntegration: "Data Connections",
            .dayBeforeYesterday: "The Day Before Yesterday",
            .delete: "Delete",
            .deleteRoute: "Delete Route?",
            .deleteRouteMessage: "This cannot be undone.",
            .developerWebsite: "Developer Website",
            .disable: "Disable",
            .distanceMetersFormat: "%.0f m",
            .enable: "Enable",
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
            .iCloudRouteSyncAlreadyEnabled: "iCloud sync is already enabled",
            .iCloudRouteSyncConfirmMessage: "This will sync imported route data and automatically update iCloud whenever routes are imported or deleted.",
            .iCloudRouteSyncConfirmTitle: "Sync Imported Routes?",
            .iCloudRouteSyncDisabled: "iCloud sync disabled",
            .iCloudRouteSyncDisableConfirmMessage: "Disabling will stop syncing imported route data. Future route imports or deletions will not update iCloud automatically. Data already synced to iCloud will be kept.",
            .iCloudRouteSyncDisableConfirmTitle: "Disable iCloud Sync?",
            .iCloudRouteSyncEnabled: "iCloud sync enabled",
            .iCloudRouteSyncFailed: "iCloud sync could not be enabled",
            .routeCollectionICloudSyncComplete: "iCloud sync complete",
            .routeCollectionICloudSyncProgressFormat: "%d/%d syncing with iCloud",
            .mapStyle: "Map Style",
            .livePhotoSaved: "Saved to Photos",
            .livePhotoSaving: "Creating Live Photo",
            .more: "More",
            .movinnLocalDataPrivacyStatement: "- Movinn only reads your data for visualization, never uploads data, and completes every feature locally.\n- Built-in global country and partial city databases power all lookups without network access.",
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
            .photoBackgroundAdjustmentHint: "Double-tap empty photo space to adjust the visible area",
            .photoMatching: "Photo Matching",
            .queryingLocation: "Locating",
            .routeBook: "Use as Route Book",
            .routeBookExit: "Exit Route Book Mode?",
            .routeBookExitMessage: "You will return to the workout list.",
            .routeBookLocationPermissionRequiredMessage: "Allow Movinn to use location in system Settings so your position can be shown in Route Book mode.",
            .routeBookLocationPermissionRequiredTitle: "Location Permission Required",
            .route: "Route",
            .routeCollection: "Imported Routes",
            .routeCollectionMenuTitle: "Routes",
            .routeCollectionEmptyMessage: "No imported routes yet",
            .routeCollectionImportSectionTitle: "Imported",
            .routeCollectionImportSuccess: "GPX route imported",
            .routeCollectionImporting: "Importing GPX",
            .routeCollectionMergeSectionTitle: "Merged",
            .routeHeatmap: "Route Heatmap",
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
            .totalActivityCountFormat: "%d times",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "Total Count",
            .totalWorkoutDistance: "Total Mileage",
            .totalWorkoutTime: "Total Time",
            .trailRunning: "Trail Running",
            .tools: "Tools",
            .today: "Today",
            .uiSettings: "Feature Settings",
            .unknownDistance: "Unknown Distance",
            .unknownDuration: "Unknown Duration",
            .unknownLocation: "Unknown Location",
            .virtualCycling: "Virtual Cycling",
            .virtualRunning: "Virtual Running",
            .walking: "Walking",
            .walkingHiking: "Walking/Hiking",
            .workoutStart: "Workout Start",
            .workoutEnd: "Workout End",
            .endNotFound: "End not found",
            .startNotFound: "Start not found",
            .yesterday: "Yesterday",
            .burnedCaloriesFormat: "Burned %.0f kcal",
            .durationHoursFormat: "%d hr",
            .durationHoursMinutesFormat: "%d hr %d min",
            .durationMinutesFormat: "%d min",
            .elevationGainFormat: "Gain %.0f m"
        ]
    ]
}
