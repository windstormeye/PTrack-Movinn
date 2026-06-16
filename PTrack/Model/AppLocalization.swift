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
    case developerWebsite
    case distanceMetersFormat
    case healthAuthorizationDenied
    case healthAuthorizationFailed
    case healthAuthorizationProgress
    case healthDataReadAuthorized
    case healthDataUnavailable
    case hiking
    case mapStyle
    case more
    case newActivity
    case ok
    case openStart
    case other
    case outdoorSwimming
    case outdoorWorkout
    case queryingLocation
    case routeHeatmap
    case running
    case satellite
    case sportTypeCountSummary
    case sportTypeTimeSummary
    case sportsCareer
    case standard
    case sportType
    case sportTypeSummary
    case strava
    case stravaAuthorizationAlreadyGrantedMessage
    case stravaReauthorizationRequired
    case stillOpen
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
    case startNotFound
    case yesterday
    case dayBeforeYesterday
    case burnedCaloriesFormat
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
            .developerWebsite: "开发者网站",
            .distanceMetersFormat: "%.0f 米",
            .healthAuthorizationDenied: "未获得健康数据读取权限。",
            .healthAuthorizationFailed: "健康授权失败",
            .healthAuthorizationProgress: "正在请求 Apple 健康体能训练、路线和运动指标读取权限...",
            .healthDataReadAuthorized: "已授权读取数据",
            .healthDataUnavailable: "当前设备不支持健康数据。",
            .hiking: "徒步",
            .mapStyle: "地图样式",
            .more: "更多",
            .newActivity: "新活动！",
            .ok: "好",
            .openStart: "去起点",
            .other: "其他",
            .outdoorSwimming: "户外游泳",
            .outdoorWorkout: "户外运动",
            .queryingLocation: "位置查询中",
            .routeHeatmap: "轨迹热图",
            .running: "跑步",
            .satellite: "卫星",
            .sportTypeCountSummary: "不同运动类型的运动次数汇总",
            .sportTypeTimeSummary: "运动时间汇总",
            .sportsCareer: "运动生涯",
            .standard: "标准",
            .sportType: "运动类型",
            .sportTypeSummary: "运动类型汇总",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava 已拿到授权，可以读取你的运动数据。",
            .stravaReauthorizationRequired: "Strava 授权已失效，请进入“更多”页面点击 Strava 重新登录。",
            .stillOpen: "仍要打开",
            .systemMapsNotFound: "未找到系统地图",
            .totalActivityCountFormat: "%d 次",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "运动总次数",
            .totalWorkoutDistance: "运动总距离",
            .totalWorkoutTime: "运动总时间",
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
            .startNotFound: "未找到起点",
            .yesterday: "昨天",
            .dayBeforeYesterday: "前天",
            .burnedCaloriesFormat: "消耗 %.0f 大卡",
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
            .developerWebsite: "開発者サイト",
            .distanceMetersFormat: "%.0f m",
            .healthAuthorizationDenied: "ヘルスケアデータの読み取り権限がありません。",
            .healthAuthorizationFailed: "ヘルスケア認証に失敗しました",
            .healthAuthorizationProgress: "Appleヘルスケアのワークアウト、ルート、運動指標の読み取り権限を要求しています...",
            .healthDataReadAuthorized: "データ読み取りは許可されています",
            .healthDataUnavailable: "このデバイスはヘルスケアデータに対応していません。",
            .hiking: "ハイキング",
            .mapStyle: "地図スタイル",
            .more: "その他",
            .newActivity: "新規",
            .ok: "OK",
            .openStart: "スタートへ",
            .other: "その他",
            .outdoorSwimming: "屋外スイミング",
            .outdoorWorkout: "屋外ワークアウト",
            .queryingLocation: "位置を検索中",
            .routeHeatmap: "軌跡ヒートマップ",
            .running: "ランニング",
            .satellite: "衛星",
            .sportTypeCountSummary: "種目別ワークアウト回数",
            .sportTypeTimeSummary: "ワークアウト時間の集計",
            .sportsCareer: "運動履歴",
            .standard: "標準",
            .sportType: "ワークアウト種別",
            .sportTypeSummary: "種目別サマリー",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava は認証済みで、ワークアウトデータを読み取れます。",
            .stravaReauthorizationRequired: "Strava の認証が無効になりました。「その他」画面で Strava をタップして再ログインしてください。",
            .stillOpen: "それでも開く",
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
            .startNotFound: "スタート地点が見つかりません",
            .yesterday: "昨日",
            .dayBeforeYesterday: "一昨日",
            .burnedCaloriesFormat: "%.0f kcal 消費",
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
            .developerWebsite: "개발자 웹사이트",
            .distanceMetersFormat: "%.0f m",
            .healthAuthorizationDenied: "건강 데이터 읽기 권한이 없습니다.",
            .healthAuthorizationFailed: "건강 권한 요청 실패",
            .healthAuthorizationProgress: "Apple 건강의 운동, 경로, 운동 지표 읽기 권한을 요청하는 중...",
            .healthDataReadAuthorized: "데이터 읽기 권한이 허용되었습니다",
            .healthDataUnavailable: "이 기기는 건강 데이터를 지원하지 않습니다.",
            .hiking: "하이킹",
            .mapStyle: "지도 스타일",
            .more: "더보기",
            .newActivity: "새 활동!",
            .ok: "확인",
            .openStart: "시작점으로",
            .other: "기타",
            .outdoorSwimming: "야외 수영",
            .outdoorWorkout: "야외 운동",
            .queryingLocation: "위치 조회 중",
            .routeHeatmap: "경로 히트맵",
            .running: "달리기",
            .satellite: "위성",
            .sportTypeCountSummary: "운동 유형별 횟수 요약",
            .sportTypeTimeSummary: "운동 시간 요약",
            .sportsCareer: "운동 경력",
            .standard: "표준",
            .sportType: "운동 유형",
            .sportTypeSummary: "운동 유형 요약",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava 권한을 이미 받았으며 운동 데이터를 읽을 수 있습니다.",
            .stravaReauthorizationRequired: "Strava 인증이 만료되었습니다. 더보기 화면에서 Strava를 눌러 다시 로그인하세요.",
            .stillOpen: "그래도 열기",
            .systemMapsNotFound: "시스템 지도를 찾을 수 없음",
            .totalActivityCountFormat: "%d회",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "총 운동 횟수",
            .totalWorkoutDistance: "총 운동 거리",
            .totalWorkoutTime: "총 운동 시간",
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
            .startNotFound: "시작점을 찾을 수 없음",
            .yesterday: "어제",
            .dayBeforeYesterday: "그저께",
            .burnedCaloriesFormat: "%.0f kcal 소비",
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
            .developerWebsite: "Developer Website",
            .distanceMetersFormat: "%.0f m",
            .healthAuthorizationDenied: "Health data read permission has not been granted.",
            .healthAuthorizationFailed: "Health authorization failed",
            .healthAuthorizationProgress: "Requesting Apple Health workout, route, and metric read permissions...",
            .healthDataReadAuthorized: "Data read access is authorized",
            .healthDataUnavailable: "Health data is not available on this device.",
            .hiking: "Hiking",
            .mapStyle: "Map Style",
            .more: "More",
            .newActivity: "New!",
            .ok: "OK",
            .openStart: "Go to Start",
            .other: "Other",
            .outdoorSwimming: "Outdoor Swimming",
            .outdoorWorkout: "Outdoor Workout",
            .queryingLocation: "Locating",
            .routeHeatmap: "Route Heatmap",
            .running: "Running",
            .satellite: "Satellite",
            .sportTypeCountSummary: "Workout Count by Type",
            .sportTypeTimeSummary: "Workout Time Summary",
            .sportsCareer: "Sports Career",
            .standard: "Standard",
            .sportType: "Sport Type",
            .sportTypeSummary: "Sport Type Summary",
            .strava: "Strava",
            .stravaAuthorizationAlreadyGrantedMessage: "Strava is already authorized to read your activity data.",
            .stravaReauthorizationRequired: "Strava authorization has expired. Open More and tap Strava to sign in again.",
            .stillOpen: "Open Anyway",
            .systemMapsNotFound: "System Maps not found",
            .totalActivityCountFormat: "%d times",
            .totalDistanceFormat: "%dkm",
            .totalWorkoutCount: "Total Workouts",
            .totalWorkoutDistance: "Total Distance",
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
            .startNotFound: "Start not found",
            .yesterday: "Yesterday",
            .dayBeforeYesterday: "The Day Before Yesterday",
            .burnedCaloriesFormat: "Burned %.0f kcal",
            .durationHoursMinutesFormat: "%d hr %d min",
            .durationMinutesFormat: "%d min"
        ]
    ]
}
