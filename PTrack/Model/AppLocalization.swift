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
    case appleHealth
    case appDefault
    case activitySummaryPrefix
    case cancel
    case cycling
    case dark
    case dataIntegration
    case dayBeforeYesterday
    case developerWebsite
    case distanceMetersFormat
    case exit
    case healthAuthorizationDenied
    case healthAuthorizationFailed
    case healthAuthorizationProgress
    case healthAuthorizationSettingsRequiredMessage
    case healthAuthorizationSettingsRequiredTitle
    case healthDataReadAuthorized
    case healthDataUnavailable
    case appleHealthDataSourceSubtitle
    case hiking
    case mapStyle
    case more
    case movinnLocalDataPrivacyStatement
    case newActivity
    case ok
    case navigation
    case openEnd
    case openStart
    case openSettings
    case other
    case outdoorSwimming
    case outdoorWorkout
    case photoLibraryFullAccessRequiredMessage
    case photoLibraryFullAccessRequiredTitle
    case photoLibraryReadAuthorized
    case photoMatching
    case queryingLocation
    case routeBook
    case routeBookExit
    case routeBookExitMessage
    case routeBookLocationPermissionRequiredMessage
    case routeBookLocationPermissionRequiredTitle
    case routeHeatmap
    case running
    case satellite
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
    case standard
    case sportType
    case sportTypeSummary
    case strava
    case stravaAuthorizationAlreadyGrantedMessage
    case stravaDataSourceSubtitle
    case stravaReauthorizationRequired
    case stillOpen
    case systemPhotos
    case systemMapsNotFound
    case totalActivityCountFormat
    case totalDistanceFormat
    case totalWorkoutCount
    case totalWorkoutDistance
    case totalWorkoutTime
    case trailRunning
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
            .appleHealth: "苹果健康",
            .appDefault: "默认",
            .activitySummaryPrefix: "运动",
            .cancel: "取消",
            .cycling: "骑行",
            .dark: "暗色",
            .dataIntegration: "数据接入",
            .dayBeforeYesterday: "前天",
            .developerWebsite: "开发者网站",
            .distanceMetersFormat: "%.0f 米",
            .exit: "退出",
            .healthAuthorizationDenied: "未获得健康数据读取权限。",
            .healthAuthorizationFailed: "健康授权失败",
            .healthAuthorizationProgress: "正在请求 Apple 健康体能训练、路线和运动指标读取权限...",
            .healthAuthorizationSettingsRequiredMessage: "请在系统设置或健康 App 中为 Movinn 打开体能训练、路线和运动指标读取权限。",
            .healthAuthorizationSettingsRequiredTitle: "需要 Apple 健康权限",
            .healthDataReadAuthorized: "已授权读取数据",
            .healthDataUnavailable: "当前设备不支持健康数据。",
            .appleHealthDataSourceSubtitle: "读取 Apple 健康中记录的数据。",
            .hiking: "徒步",
            .mapStyle: "地图样式",
            .more: "更多",
            .movinnLocalDataPrivacyStatement: "- Movinn 只读取你的数据做可视化，绝不上传数据，所有功能均在本地完成。\n- 内置了全球国家和部分城市数据库，所有查询均不联网。",
            .newActivity: "新活动！",
            .ok: "好",
            .navigation: "导航",
            .openEnd: "去终点",
            .openStart: "去起点",
            .openSettings: "打开设置",
            .other: "其他",
            .outdoorSwimming: "户外游泳",
            .outdoorWorkout: "户外运动",
            .photoLibraryFullAccessRequiredMessage: "只有完整访问权限才能为轨迹匹配照片。请在系统设置中把照片权限改为“完全访问”。",
            .photoLibraryFullAccessRequiredTitle: "需要完整相册权限",
            .photoLibraryReadAuthorized: "已授权读取相册",
            .photoMatching: "照片匹配",
            .queryingLocation: "位置查询中",
            .routeBook: "路书",
            .routeBookExit: "退出路书模式？",
            .routeBookExitMessage: "退出后将回到运动列表。",
            .routeBookLocationPermissionRequiredMessage: "请在系统设置中允许 Movinn 使用位置，这样才能在路书模式下显示你的位置。",
            .routeBookLocationPermissionRequiredTitle: "需要位置权限",
            .routeHeatmap: "轨迹热图",
            .running: "跑步",
            .satellite: "卫星",
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
            .standard: "标准",
            .sportType: "运动类型",
            .sportTypeSummary: "运动类型汇总",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava 已拿到授权，可以读取你的运动数据。",
            .stravaDataSourceSubtitle: "读取 Strava 中记录的数据。",
            .stravaReauthorizationRequired: "Strava 授权已失效，请进入“更多”页面点击 Strava 重新登录。",
            .stillOpen: "仍要打开",
            .systemPhotos: "系统相册",
            .systemMapsNotFound: "未找到系统地图",
            .totalActivityCountFormat: "%d 次",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "总次数",
            .totalWorkoutDistance: "总里程",
            .totalWorkoutTime: "总时间",
            .trailRunning: "越野跑",
            .today: "今天",
            .uiSettings: "UI 设置",
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
            .durationMinutesFormat: "%d分钟"
        ],
        .japanese: [
            .all: "すべて",
            .appLanguage: "アプリの言語",
            .appleHealth: "Appleヘルスケア",
            .appDefault: "デフォルト",
            .activitySummaryPrefix: "運動",
            .cancel: "キャンセル",
            .cycling: "サイクリング",
            .dark: "ダーク",
            .dataIntegration: "データ連携",
            .dayBeforeYesterday: "一昨日",
            .developerWebsite: "開発者サイト",
            .distanceMetersFormat: "%.0f m",
            .exit: "終了",
            .healthAuthorizationDenied: "ヘルスケアデータの読み取り権限がありません。",
            .healthAuthorizationFailed: "ヘルスケア認証に失敗しました",
            .healthAuthorizationProgress: "Appleヘルスケアのワークアウト、ルート、運動指標の読み取り権限を要求しています...",
            .healthAuthorizationSettingsRequiredMessage: "システム設定またはヘルスケア App で、Movinn のワークアウト、ルート、運動指標の読み取り権限を有効にしてください。",
            .healthAuthorizationSettingsRequiredTitle: "Appleヘルスケアの権限が必要です",
            .healthDataReadAuthorized: "データ読み取りは許可されています",
            .healthDataUnavailable: "このデバイスはヘルスケアデータに対応していません。",
            .appleHealthDataSourceSubtitle: "Appleヘルスケアに記録されたデータを読み取ります。",
            .hiking: "ハイキング",
            .mapStyle: "地図スタイル",
            .more: "その他",
            .movinnLocalDataPrivacyStatement: "- Movinn は可視化のためだけにあなたのデータを読み取り、データをアップロードせず、すべての機能をローカルで完了します。\n- 世界の国と一部都市のデータベースを内蔵しており、すべての検索はネットワークを使いません。",
            .newActivity: "新規",
            .ok: "OK",
            .navigation: "ナビゲーション",
            .openEnd: "ゴールへ",
            .openStart: "スタートへ",
            .openSettings: "設定を開く",
            .other: "その他",
            .outdoorSwimming: "屋外スイミング",
            .outdoorWorkout: "屋外ワークアウト",
            .photoLibraryFullAccessRequiredMessage: "ルートに写真を照合するには、写真へのフルアクセスが必要です。システム設定で写真の権限を「フルアクセス」に変更してください。",
            .photoLibraryFullAccessRequiredTitle: "写真へのフルアクセスが必要です",
            .photoLibraryReadAuthorized: "写真の読み取りは許可されています",
            .photoMatching: "写真照合",
            .queryingLocation: "位置を検索中",
            .routeBook: "ルートブック",
            .routeBookExit: "ルートブックモードを終了しますか？",
            .routeBookExitMessage: "終了するとワークアウト一覧に戻ります。",
            .routeBookLocationPermissionRequiredMessage: "ルートブックモードで現在地を表示するには、システム設定で Movinn の位置情報利用を許可してください。",
            .routeBookLocationPermissionRequiredTitle: "位置情報の許可が必要です",
            .routeHeatmap: "軌跡ヒートマップ",
            .running: "ランニング",
            .satellite: "衛星",
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
            .standard: "標準",
            .sportType: "ワークアウト種別",
            .sportTypeSummary: "種目別サマリー",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava は認証済みで、ワークアウトデータを読み取れます。",
            .stravaDataSourceSubtitle: "Strava に記録されたデータを読み取ります。",
            .stravaReauthorizationRequired: "Strava の認証が無効になりました。「その他」画面で Strava をタップして再ログインしてください。",
            .stillOpen: "それでも開く",
            .systemPhotos: "写真",
            .systemMapsNotFound: "システムマップが見つかりません",
            .totalActivityCountFormat: "%d回",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "合計回数",
            .totalWorkoutDistance: "合計距離",
            .totalWorkoutTime: "合計時間",
            .trailRunning: "トレイルランニング",
            .today: "今日",
            .uiSettings: "UI設定",
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
            .durationMinutesFormat: "%d分"
        ],
        .korean: [
            .all: "전체",
            .appLanguage: "앱 언어",
            .appleHealth: "Apple 건강",
            .appDefault: "기본",
            .activitySummaryPrefix: "운동",
            .cancel: "취소",
            .cycling: "사이클링",
            .dark: "어두운",
            .dataIntegration: "데이터 연동",
            .dayBeforeYesterday: "그저께",
            .developerWebsite: "개발자 웹사이트",
            .distanceMetersFormat: "%.0f m",
            .exit: "종료",
            .healthAuthorizationDenied: "건강 데이터 읽기 권한이 없습니다.",
            .healthAuthorizationFailed: "건강 권한 요청 실패",
            .healthAuthorizationProgress: "Apple 건강의 운동, 경로, 운동 지표 읽기 권한을 요청하는 중...",
            .healthAuthorizationSettingsRequiredMessage: "시스템 설정 또는 건강 앱에서 Movinn의 운동, 경로, 운동 지표 읽기 권한을 켜 주세요.",
            .healthAuthorizationSettingsRequiredTitle: "Apple 건강 권한 필요",
            .healthDataReadAuthorized: "데이터 읽기 권한이 허용되었습니다",
            .healthDataUnavailable: "이 기기는 건강 데이터를 지원하지 않습니다.",
            .appleHealthDataSourceSubtitle: "Apple 건강에 기록된 데이터를 읽습니다.",
            .hiking: "하이킹",
            .mapStyle: "지도 스타일",
            .more: "더보기",
            .movinnLocalDataPrivacyStatement: "- Movinn은 시각화를 위해서만 데이터를 읽으며 데이터를 업로드하지 않고, 모든 기능은 로컬에서 완료됩니다.\n- 전 세계 국가와 일부 도시 데이터베이스를 내장하고 있어 모든 조회는 네트워크를 사용하지 않습니다.",
            .newActivity: "새 활동!",
            .ok: "확인",
            .navigation: "내비게이션",
            .openEnd: "도착점으로",
            .openStart: "시작점으로",
            .openSettings: "설정 열기",
            .other: "기타",
            .outdoorSwimming: "야외 수영",
            .outdoorWorkout: "야외 운동",
            .photoLibraryFullAccessRequiredMessage: "경로와 사진을 매칭하려면 사진 전체 접근 권한이 필요합니다. 시스템 설정에서 사진 권한을 전체 접근으로 변경해 주세요.",
            .photoLibraryFullAccessRequiredTitle: "사진 전체 접근 권한 필요",
            .photoLibraryReadAuthorized: "사진 읽기 권한이 허용되었습니다",
            .photoMatching: "사진 매칭",
            .queryingLocation: "위치 조회 중",
            .routeBook: "루트북",
            .routeBookExit: "루트북 모드를 종료할까요?",
            .routeBookExitMessage: "종료하면 운동 목록으로 돌아갑니다.",
            .routeBookLocationPermissionRequiredMessage: "루트북 모드에서 현재 위치를 표시하려면 시스템 설정에서 Movinn의 위치 사용을 허용해 주세요.",
            .routeBookLocationPermissionRequiredTitle: "위치 권한 필요",
            .routeHeatmap: "경로 히트맵",
            .running: "달리기",
            .satellite: "위성",
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
            .standard: "표준",
            .sportType: "운동 유형",
            .sportTypeSummary: "운동 유형 요약",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava 권한을 이미 받았으며 운동 데이터를 읽을 수 있습니다.",
            .stravaDataSourceSubtitle: "Strava에 기록된 데이터를 읽습니다.",
            .stravaReauthorizationRequired: "Strava 인증이 만료되었습니다. 더보기 화면에서 Strava를 눌러 다시 로그인하세요.",
            .stillOpen: "그래도 열기",
            .systemPhotos: "사진",
            .systemMapsNotFound: "시스템 지도를 찾을 수 없음",
            .totalActivityCountFormat: "%d회",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "총 횟수",
            .totalWorkoutDistance: "총 거리",
            .totalWorkoutTime: "총 시간",
            .trailRunning: "트레일 러닝",
            .today: "오늘",
            .uiSettings: "UI 설정",
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
            .durationMinutesFormat: "%d분"
        ],
        .english: [
            .all: "All",
            .appLanguage: "App Language",
            .appleHealth: "Apple Health",
            .appDefault: "Default",
            .activitySummaryPrefix: "Activity",
            .cancel: "Cancel",
            .cycling: "Cycling",
            .dark: "Dark",
            .dataIntegration: "Data Connections",
            .dayBeforeYesterday: "The Day Before Yesterday",
            .developerWebsite: "Developer Website",
            .distanceMetersFormat: "%.0f m",
            .exit: "Exit",
            .healthAuthorizationDenied: "Health data read permission has not been granted.",
            .healthAuthorizationFailed: "Health authorization failed",
            .healthAuthorizationProgress: "Requesting Apple Health workout, route, and metric read permissions...",
            .healthAuthorizationSettingsRequiredMessage: "Enable workout, route, and metric read permissions for Movinn in system Settings or the Health app.",
            .healthAuthorizationSettingsRequiredTitle: "Apple Health Permission Required",
            .healthDataReadAuthorized: "Data read access is authorized",
            .healthDataUnavailable: "Health data is not available on this device.",
            .appleHealthDataSourceSubtitle: "Read data recorded in Apple Health.",
            .hiking: "Hiking",
            .mapStyle: "Map Style",
            .more: "More",
            .movinnLocalDataPrivacyStatement: "- Movinn only reads your data for visualization, never uploads data, and completes every feature locally.\n- Built-in global country and partial city databases power all lookups without network access.",
            .newActivity: "New!",
            .ok: "OK",
            .navigation: "Navigation",
            .openEnd: "Go to End",
            .openStart: "Go to Start",
            .openSettings: "Open Settings",
            .other: "Other",
            .outdoorSwimming: "Outdoor Swimming",
            .outdoorWorkout: "Outdoor Workout",
            .photoLibraryFullAccessRequiredMessage: "Full Photos access is required to match photos to routes. Change Photos permission to Full Access in system settings.",
            .photoLibraryFullAccessRequiredTitle: "Full Photos Access Required",
            .photoLibraryReadAuthorized: "Photo access is authorized",
            .photoMatching: "Photo Matching",
            .queryingLocation: "Locating",
            .routeBook: "Route Book",
            .routeBookExit: "Exit Route Book Mode?",
            .routeBookExitMessage: "You will return to the workout list.",
            .routeBookLocationPermissionRequiredMessage: "Allow Movinn to use location in system Settings so your position can be shown in Route Book mode.",
            .routeBookLocationPermissionRequiredTitle: "Location Permission Required",
            .routeHeatmap: "Route Heatmap",
            .running: "Running",
            .satellite: "Satellite",
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
            .standard: "Standard",
            .sportType: "Sport Type",
            .sportTypeSummary: "Sport Type Summary",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava is already authorized to read your activity data.",
            .stravaDataSourceSubtitle: "Read data recorded in Strava.",
            .stravaReauthorizationRequired: "Strava authorization has expired. Open More and tap Strava to sign in again.",
            .stillOpen: "Open Anyway",
            .systemPhotos: "Photos",
            .systemMapsNotFound: "System Maps not found",
            .totalActivityCountFormat: "%d times",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "Total Count",
            .totalWorkoutDistance: "Total Mileage",
            .totalWorkoutTime: "Total Time",
            .trailRunning: "Trail Running",
            .today: "Today",
            .uiSettings: "UI Settings",
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
            .durationMinutesFormat: "%d min"
        ]
    ]
}
