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
    case cancel
    case cycling
    case dark
    case dataIntegration
    case developerWebsite
    case distanceMetersFormat
    case healthAuthorizationDenied
    case healthAuthorizationFailed
    case healthAuthorizationProgress
    case healthDataUnavailable
    case hiking
    case mapStyle
    case more
    case newActivity
    case ok
    case openStart
    case other
    case outdoorWorkout
    case queryingLocation
    case routeHeatmap
    case running
    case satellite
    case standard
    case sportType
    case strava
    case systemMapsNotFound
    case totalDistanceFormat
    case uiSettings
    case unknownDistance
    case unknownDuration
    case unknownLocation
    case walking
    case walkingHiking
    case workoutStart
    case startNotFound
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
            .cancel: "取消",
            .cycling: "骑行",
            .dark: "暗色",
            .dataIntegration: "数据接入",
            .developerWebsite: "开发者网站",
            .distanceMetersFormat: "%.0f 米",
            .healthAuthorizationDenied: "未获得健康数据读取权限。",
            .healthAuthorizationFailed: "健康授权失败",
            .healthAuthorizationProgress: "正在请求 Apple 健康体能训练、路线和运动指标读取权限...",
            .healthDataUnavailable: "当前设备不支持健康数据。",
            .hiking: "徒步",
            .mapStyle: "地图样式",
            .more: "更多",
            .newActivity: "新活动！",
            .ok: "好",
            .openStart: "去起点",
            .other: "其他",
            .outdoorWorkout: "户外运动",
            .queryingLocation: "位置查询中",
            .routeHeatmap: "轨迹热图",
            .running: "跑步",
            .satellite: "卫星",
            .standard: "标准",
            .sportType: "运动类型",
            .strava: "Strava",
            .systemMapsNotFound: "未找到系统地图",
            .totalDistanceFormat: "总距离：%dKM",
            .uiSettings: "UI 设置",
            .unknownDistance: "未知距离",
            .unknownDuration: "未知时长",
            .unknownLocation: "未知位置",
            .walking: "行走",
            .walkingHiking: "行走/徒步",
            .workoutStart: "运动起点",
            .startNotFound: "未找到起点",
            .burnedCaloriesFormat: "消耗 %.0f 大卡",
            .durationHoursMinutesFormat: "%d小时%d分钟",
            .durationMinutesFormat: "%d分钟"
        ],
        .japanese: [
            .all: "すべて",
            .appLanguage: "アプリの言語",
            .appleHealth: "Appleヘルスケア",
            .appDefault: "デフォルト",
            .cancel: "キャンセル",
            .cycling: "サイクリング",
            .dark: "ダーク",
            .dataIntegration: "データ連携",
            .developerWebsite: "開発者サイト",
            .distanceMetersFormat: "%.0f m",
            .healthAuthorizationDenied: "ヘルスケアデータの読み取り権限がありません。",
            .healthAuthorizationFailed: "ヘルスケア認証に失敗しました",
            .healthAuthorizationProgress: "Appleヘルスケアのワークアウト、ルート、運動指標の読み取り権限を要求しています...",
            .healthDataUnavailable: "このデバイスはヘルスケアデータに対応していません。",
            .hiking: "ハイキング",
            .mapStyle: "地図スタイル",
            .more: "その他",
            .newActivity: "新規",
            .ok: "OK",
            .openStart: "スタートへ",
            .other: "その他",
            .outdoorWorkout: "屋外ワークアウト",
            .queryingLocation: "位置を検索中",
            .routeHeatmap: "軌跡ヒートマップ",
            .running: "ランニング",
            .satellite: "衛星",
            .standard: "標準",
            .sportType: "ワークアウト種別",
            .strava: "Strava",
            .systemMapsNotFound: "システムマップが見つかりません",
            .totalDistanceFormat: "合計距離：%d km",
            .uiSettings: "UI設定",
            .unknownDistance: "不明な距離",
            .unknownDuration: "不明な時間",
            .unknownLocation: "不明な位置",
            .walking: "ウォーキング",
            .walkingHiking: "ウォーキング/ハイキング",
            .workoutStart: "ワークアウト開始地点",
            .startNotFound: "スタート地点が見つかりません",
            .burnedCaloriesFormat: "%.0f kcal 消費",
            .durationHoursMinutesFormat: "%d時間%d分",
            .durationMinutesFormat: "%d分"
        ],
        .korean: [
            .all: "전체",
            .appLanguage: "앱 언어",
            .appleHealth: "Apple 건강",
            .appDefault: "기본",
            .cancel: "취소",
            .cycling: "사이클링",
            .dark: "어두운",
            .dataIntegration: "데이터 연동",
            .developerWebsite: "개발자 웹사이트",
            .distanceMetersFormat: "%.0f m",
            .healthAuthorizationDenied: "건강 데이터 읽기 권한이 없습니다.",
            .healthAuthorizationFailed: "건강 권한 요청 실패",
            .healthAuthorizationProgress: "Apple 건강의 운동, 경로, 운동 지표 읽기 권한을 요청하는 중...",
            .healthDataUnavailable: "이 기기는 건강 데이터를 지원하지 않습니다.",
            .hiking: "하이킹",
            .mapStyle: "지도 스타일",
            .more: "더보기",
            .newActivity: "새 활동!",
            .ok: "확인",
            .openStart: "시작점으로",
            .other: "기타",
            .outdoorWorkout: "야외 운동",
            .queryingLocation: "위치 조회 중",
            .routeHeatmap: "경로 히트맵",
            .running: "달리기",
            .satellite: "위성",
            .standard: "표준",
            .sportType: "운동 유형",
            .strava: "Strava",
            .systemMapsNotFound: "시스템 지도를 찾을 수 없음",
            .totalDistanceFormat: "총 거리: %d km",
            .uiSettings: "UI 설정",
            .unknownDistance: "알 수 없는 거리",
            .unknownDuration: "알 수 없는 시간",
            .unknownLocation: "알 수 없는 위치",
            .walking: "걷기",
            .walkingHiking: "걷기/하이킹",
            .workoutStart: "운동 시작점",
            .startNotFound: "시작점을 찾을 수 없음",
            .burnedCaloriesFormat: "%.0f kcal 소비",
            .durationHoursMinutesFormat: "%d시간 %d분",
            .durationMinutesFormat: "%d분"
        ],
        .english: [
            .all: "All",
            .appLanguage: "App Language",
            .appleHealth: "Apple Health",
            .appDefault: "Default",
            .cancel: "Cancel",
            .cycling: "Cycling",
            .dark: "Dark",
            .dataIntegration: "Data Connections",
            .developerWebsite: "Developer Website",
            .distanceMetersFormat: "%.0f m",
            .healthAuthorizationDenied: "Health data read permission has not been granted.",
            .healthAuthorizationFailed: "Health authorization failed",
            .healthAuthorizationProgress: "Requesting Apple Health workout, route, and metric read permissions...",
            .healthDataUnavailable: "Health data is not available on this device.",
            .hiking: "Hiking",
            .mapStyle: "Map Style",
            .more: "More",
            .newActivity: "New!",
            .ok: "OK",
            .openStart: "Go to Start",
            .other: "Other",
            .outdoorWorkout: "Outdoor Workout",
            .queryingLocation: "Locating",
            .routeHeatmap: "Route Heatmap",
            .running: "Running",
            .satellite: "Satellite",
            .standard: "Standard",
            .sportType: "Sport Type",
            .strava: "Strava",
            .systemMapsNotFound: "System Maps not found",
            .totalDistanceFormat: "Total: %d km",
            .uiSettings: "UI Settings",
            .unknownDistance: "Unknown Distance",
            .unknownDuration: "Unknown Duration",
            .unknownLocation: "Unknown Location",
            .walking: "Walking",
            .walkingHiking: "Walking/Hiking",
            .workoutStart: "Workout Start",
            .startNotFound: "Start not found",
            .burnedCaloriesFormat: "Burned %.0f kcal",
            .durationHoursMinutesFormat: "%d hr %d min",
            .durationMinutesFormat: "%d min"
        ]
    ]
}
