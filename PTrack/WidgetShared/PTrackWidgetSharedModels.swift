//
//  PTrackWidgetSharedModels.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import Foundation
import SwiftUI
import UIKit

enum PTrackWidgetConstants {
    static let appGroupIdentifier = "group.studio.pj.app.PTrack"
    static let snapshotFileName = "widget-snapshot.json"
    static let worldMapImageFileName = "widget-world-map.png"
    static let worldMapDarkImageFileName = "widget-world-map-dark.png"
    static let worldMapPreviewOutlineImageFileName = "widget-world-map-preview-outline.png"
    static let chinaMapImageFileName = "widget-china-map.png"
    static let chinaMapDarkImageFileName = "widget-china-map-dark.png"
    static let chinaMapPreviewOutlineImageFileName = "widget-china-map-preview-outline.png"
    static let weeklyGoalDistanceMetersKey = "studio.pj.PTrack.widget.weeklyGoalDistanceMeters"
    static let defaultWeeklyGoalDistanceMeters = 200_000.0
}

enum PTrackWidgetKind {
    static let weeklyProgress = "studio.pj.app.PTrack.widget.weeklyProgress"
    static let weeklyChart = "studio.pj.app.PTrack.widget.weeklyChart"
    static let monthlyCalendar = "studio.pj.app.PTrack.widget.monthlyCalendar"
    static let annualTrajectory = "studio.pj.app.PTrack.widget.annualTrajectory"
    static let worldMap = "studio.pj.app.PTrack.widget.worldMap"
    static let chinaMap = "studio.pj.app.PTrack.widget.chinaMap"
}

enum PTrackWidgetPalette {
    static let brand = Color(red: 141 / 255, green: 189 / 255, blue: 0)
    static let background = Color(.systemBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    static let foreground = Color(.label)
    static let secondary = Color(.secondaryLabel)
    static let muted = Color(.systemGray4)
}

enum PTrackWidgetSettingsStore {
    static var weeklyGoalDistanceMeters: Double {
        let value = sharedDefaults.double(forKey: PTrackWidgetConstants.weeklyGoalDistanceMetersKey)
        guard value > 0 else {
            return PTrackWidgetConstants.defaultWeeklyGoalDistanceMeters
        }

        return value
    }

    static var weeklyGoalDistanceKilometers: Double {
        weeklyGoalDistanceMeters / 1_000
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: PTrackWidgetConstants.appGroupIdentifier) ?? .standard
    }
}

nonisolated enum PTrackWidgetLanguage: String {
    case chinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case english = "en"

    static var current: PTrackWidgetLanguage {
        for identifier in Locale.preferredLanguages.map({ $0.lowercased() }) {
            if identifier.hasPrefix("zh") {
                return .chinese
            }
            if identifier.hasPrefix("ja") {
                return .japanese
            }
            if identifier.hasPrefix("ko") {
                return .korean
            }
            if identifier.hasPrefix("en") {
                return .english
            }
        }

        return .english
    }
}

nonisolated enum PTrackWidgetTextKey {
    case widgetSmallWeeklyGoal
    case widgetSmallWeeklyGoalDescription
    case widgetWeeklyChart
    case widgetWeeklyChartDescription
    case widgetMonthlyCalendar
    case widgetMonthlyCalendarDescription
    case widgetAnnualTrajectory
    case widgetAnnualTrajectoryDescription
    case widgetWorldMap
    case widgetWorldMapDescription
    case widgetWorldCountryWorkoutFormat
    case widgetChinaMap
    case widgetChinaMapDescription
    case widgetChinaCityWorkoutFormat
    case goal
    case weeklyDistance
    case weeklyDuration
    case distance
    case duration
}

nonisolated struct PTrackWidgetText {
    let language: PTrackWidgetLanguage

    init(languageRawValue _: String?) {
        language = .current
    }

    static var current: PTrackWidgetText {
        PTrackWidgetText(languageRawValue: nil)
    }

    func text(_ key: PTrackWidgetTextKey) -> String {
        Self.translations[language]?[key] ?? Self.translations[.english]?[key] ?? ""
    }

    func format(_ key: PTrackWidgetTextKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    var placeholderWeekdayTitles: [String] {
        switch language {
        case .chinese:
            return ["一", "二", "三", "四", "五", "六", "日"]
        case .japanese:
            return ["月", "火", "水", "木", "金", "土", "日"]
        case .korean:
            return ["월", "화", "수", "목", "금", "토", "일"]
        case .english:
            return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        }
    }

    func weekdayTitle(at index: Int) -> String {
        let titles = placeholderWeekdayTitles
        guard titles.indices.contains(index) else {
            return ""
        }

        return titles[index]
    }

    var placeholderMonthTitle: String {
        monthTitle(for: .now)
    }

    func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)

        switch language {
        case .chinese, .japanese:
            formatter.dateFormat = "yyyy年M月"
        case .korean:
            formatter.dateFormat = "yyyy년 M월"
        case .english:
            formatter.dateFormat = "MMMM yyyy"
        }

        return formatter.string(from: date)
    }

    func durationText(_ seconds: Double) -> String {
        let totalMinutes = max(Int(seconds / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        switch language {
        case .chinese:
            if hours > 0, minutes > 0 {
                return "\(hours)小时\(minutes)分"
            }
            if hours > 0 {
                return "\(hours)小时"
            }
            return "\(minutes)分"
        case .japanese:
            if hours > 0, minutes > 0 {
                return "\(hours)時間\(minutes)分"
            }
            if hours > 0 {
                return "\(hours)時間"
            }
            return "\(minutes)分"
        case .korean:
            if hours > 0, minutes > 0 {
                return "\(hours)시간 \(minutes)분"
            }
            if hours > 0 {
                return "\(hours)시간"
            }
            return "\(minutes)분"
        case .english:
            if hours > 0, minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            if hours > 0 {
                return "\(hours)h"
            }
            return "\(minutes)m"
        }
    }

    private static let translations: [PTrackWidgetLanguage: [PTrackWidgetTextKey: String]] = [
        .chinese: [
            .widgetSmallWeeklyGoal: "本周圆环数据",
            .widgetSmallWeeklyGoalDescription: "显示本周运动距离、时间和周目标进度。",
            .widgetWeeklyChart: "本周柱状图",
            .widgetWeeklyChartDescription: "显示本周每天的运动距离和时间。",
            .widgetMonthlyCalendar: "月度日历",
            .widgetMonthlyCalendarDescription: "显示本月运动日历。",
            .widgetAnnualTrajectory: "年度轨迹",
            .widgetAnnualTrajectoryDescription: "显示今年和去年每周运动曲线。",
            .widgetWorldMap: "世界地图",
            .widgetWorldMapDescription: "点亮运动过的世界地图区域。",
            .widgetWorldCountryWorkoutFormat: "去过 %d/%d 个国家运动",
            .widgetChinaMap: "中国地图",
            .widgetChinaMapDescription: "点亮运动过的中国地图区域。",
            .widgetChinaCityWorkoutFormat: "去过 %d/%d 个城市运动",
            .goal: "目标",
            .weeklyDistance: "距离",
            .weeklyDuration: "时间",
            .distance: "距离",
            .duration: "时间"
        ],
        .japanese: [
            .widgetSmallWeeklyGoal: "今週のリングデータ",
            .widgetSmallWeeklyGoalDescription: "今週の距離、時間、週間目標の進捗を表示します。",
            .widgetWeeklyChart: "今週の棒グラフ",
            .widgetWeeklyChartDescription: "今週の毎日の距離と時間を表示します。",
            .widgetMonthlyCalendar: "月間カレンダー",
            .widgetMonthlyCalendarDescription: "今月の運動カレンダーを表示します。",
            .widgetAnnualTrajectory: "年間トレンド",
            .widgetAnnualTrajectoryDescription: "今年と去年の週ごとの運動曲線を表示します。",
            .widgetWorldMap: "世界地図",
            .widgetWorldMapDescription: "運動した世界の地域をハイライトします。",
            .widgetWorldCountryWorkoutFormat: "%d/%dか国で運動",
            .widgetChinaMap: "中国地図",
            .widgetChinaMapDescription: "運動した中国の地域をハイライトします。",
            .widgetChinaCityWorkoutFormat: "%d/%d都市で運動",
            .goal: "目標",
            .weeklyDistance: "距離",
            .weeklyDuration: "時間",
            .distance: "距離",
            .duration: "時間"
        ],
        .korean: [
            .widgetSmallWeeklyGoal: "이번 주 링 데이터",
            .widgetSmallWeeklyGoalDescription: "이번 주 거리, 시간, 주간 목표 진행률을 표시합니다.",
            .widgetWeeklyChart: "이번 주 막대 차트",
            .widgetWeeklyChartDescription: "이번 주 매일의 거리와 시간을 표시합니다.",
            .widgetMonthlyCalendar: "월간 달력",
            .widgetMonthlyCalendarDescription: "이번 달 운동 달력을 표시합니다.",
            .widgetAnnualTrajectory: "연간 궤적",
            .widgetAnnualTrajectoryDescription: "올해와 작년의 주간 운동 곡선을 표시합니다.",
            .widgetWorldMap: "세계 지도",
            .widgetWorldMapDescription: "운동한 세계 지역을 밝게 표시합니다.",
            .widgetWorldCountryWorkoutFormat: "%d/%d개 국가에서 운동",
            .widgetChinaMap: "중국 지도",
            .widgetChinaMapDescription: "운동한 중국 지역을 밝게 표시합니다.",
            .widgetChinaCityWorkoutFormat: "%d/%d개 도시에서 운동",
            .goal: "목표",
            .weeklyDistance: "거리",
            .weeklyDuration: "시간",
            .distance: "거리",
            .duration: "시간"
        ],
        .english: [
            .widgetSmallWeeklyGoal: "Weekly Ring Data",
            .widgetSmallWeeklyGoalDescription: "Shows this week's distance, time, and goal progress.",
            .widgetWeeklyChart: "Weekly Bar Chart",
            .widgetWeeklyChartDescription: "Shows daily distance and time for this week.",
            .widgetMonthlyCalendar: "Monthly Calendar",
            .widgetMonthlyCalendarDescription: "Shows this month's workout calendar.",
            .widgetAnnualTrajectory: "Annual Trace",
            .widgetAnnualTrajectoryDescription: "Shows weekly curves for this year and last year.",
            .widgetWorldMap: "World Map",
            .widgetWorldMapDescription: "Highlights world regions where you have worked out.",
            .widgetWorldCountryWorkoutFormat: "Worked out in %d/%d countries",
            .widgetChinaMap: "China Map",
            .widgetChinaMapDescription: "Highlights China regions where you have worked out.",
            .widgetChinaCityWorkoutFormat: "Worked out in %d/%d cities",
            .goal: "Goal",
            .weeklyDistance: "Distance",
            .weeklyDuration: "Time",
            .distance: "Distance",
            .duration: "Time"
        ]
    ]
}

nonisolated struct PTrackWidgetSnapshot: Codable {
    struct WeekSummary: Codable {
        let distanceMeters: Double
        let durationSeconds: TimeInterval
    }

    struct WeeklyRow: Codable, Identifiable {
        var id: Int { index }
        let index: Int
        let title: String
        let distanceMeters: Double
        let durationSeconds: TimeInterval
    }

    struct MonthDay: Codable, Identifiable {
        let id = UUID()
        let day: Int
        let isCurrentMonth: Bool
        let isToday: Bool
        let symbolNames: [String]

        enum CodingKeys: CodingKey {
            case day
            case isCurrentMonth
            case isToday
            case symbolNames
        }
    }

    struct MonthCalendar: Codable {
        let title: String
        let summaryDistanceMeters: Double
        let summaryDurationSeconds: TimeInterval
        let weekdayTitles: [String]
        let days: [MonthDay]
    }

    struct AnnualSeries: Codable, Identifiable {
        var id: Int { year }
        let year: Int
        let weeklyDistanceMeters: [Double]
        let weeklyDurationSeconds: [TimeInterval]
        let visibleWeekCount: Int
        let totalDistanceMeters: Double
        let totalDurationSeconds: TimeInterval
    }

    let generatedAt: Date
    let languageRawValue: String?
    let weekSummary: WeekSummary
    let weeklyRows: [WeeklyRow]
    let monthCalendar: MonthCalendar
    let annualSeries: [AnnualSeries]
    let worldMapImageFileName: String?
    let worldMapDarkImageFileName: String?
    let worldMapPreviewOutlineImageFileName: String?
    let worldVisitedCountryCount: Int?
    let worldTotalCountryCount: Int?
    let chinaMapImageFileName: String?
    let chinaMapDarkImageFileName: String?
    let chinaMapPreviewOutlineImageFileName: String?
    let chinaVisitedCityCount: Int?
    let chinaTotalCityCount: Int?

    var text: PTrackWidgetText {
        PTrackWidgetText(languageRawValue: languageRawValue)
    }

    static var placeholder: PTrackWidgetSnapshot {
        let text = PTrackWidgetText.current
        let weeklyRows = text.placeholderWeekdayTitles.enumerated().map { index, title in
            WeeklyRow(
                index: index,
                title: title,
                distanceMeters: [12_000, 18_500, 0, 32_000, 16_000, 28_000, 21_000][index],
                durationSeconds: [2_800, 4_100, 0, 6_400, 3_600, 5_500, 4_700][index]
            )
        }
        let days = (0..<42).map { index in
            MonthDay(
                day: index < 3 ? 29 + index : (index - 2),
                isCurrentMonth: index >= 3 && index < 34,
                isToday: index == 22,
                symbolNames: [6, 10, 13, 19, 22, 27, 31].contains(index) ? ["figure.outdoor.cycle"] : []
            )
        }
        let currentValues: [Double] = [0, 8_000, 22_000, 12_000, 28_000, 36_000, 18_000, 42_000, 31_000, 46_000, 54_000, 38_000]
        let previousValues: [Double] = [12_000, 16_000, 9_000, 24_000, 18_000, 30_000, 22_000, 34_000, 26_000, 39_000, 33_000, 44_000]

        return PTrackWidgetSnapshot(
            generatedAt: .now,
            languageRawValue: text.language.rawValue,
            weekSummary: WeekSummary(
                distanceMeters: weeklyRows.reduce(0) { $0 + $1.distanceMeters },
                durationSeconds: weeklyRows.reduce(0) { $0 + $1.durationSeconds }
            ),
            weeklyRows: weeklyRows,
            monthCalendar: MonthCalendar(
                title: text.placeholderMonthTitle,
                summaryDistanceMeters: 181_000,
                summaryDurationSeconds: 42_000,
                weekdayTitles: text.placeholderWeekdayTitles,
                days: days
            ),
            annualSeries: [
                AnnualSeries(
                    year: 2026,
                    weeklyDistanceMeters: currentValues,
                    weeklyDurationSeconds: currentValues.map { $0 / 4 },
                    visibleWeekCount: currentValues.count,
                    totalDistanceMeters: currentValues.reduce(0, +),
                    totalDurationSeconds: currentValues.reduce(0) { $0 + $1 / 4 }
                ),
                AnnualSeries(
                    year: 2025,
                    weeklyDistanceMeters: previousValues,
                    weeklyDurationSeconds: previousValues.map { $0 / 4 },
                    visibleWeekCount: previousValues.count,
                    totalDistanceMeters: previousValues.reduce(0, +),
                    totalDurationSeconds: previousValues.reduce(0) { $0 + $1 / 4 }
                )
            ],
            worldMapImageFileName: nil,
            worldMapDarkImageFileName: nil,
            worldMapPreviewOutlineImageFileName: nil,
            worldVisitedCountryCount: 12,
            worldTotalCountryCount: 177,
            chinaMapImageFileName: nil,
            chinaMapDarkImageFileName: nil,
            chinaMapPreviewOutlineImageFileName: nil,
            chinaVisitedCityCount: 8,
            chinaTotalCityCount: 371
        )
    }
}

enum PTrackWidgetSnapshotReader {
    static func loadSnapshot() -> PTrackWidgetSnapshot {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PTrackWidgetConstants.appGroupIdentifier
        ) else {
            return .placeholder
        }

        let fileURL = containerURL.appendingPathComponent(PTrackWidgetConstants.snapshotFileName)
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(PTrackWidgetSnapshot.self, from: data) else {
            return .placeholder
        }

        return snapshot
    }

    static func image(fileName: String?) -> UIImage? {
        guard let fileName,
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: PTrackWidgetConstants.appGroupIdentifier
              ) else {
            return nil
        }

        return UIImage(contentsOfFile: containerURL.appendingPathComponent(fileName).path)
    }
}

func compactDistanceText(_ meters: Double) -> String {
    let kilometers = max(meters, 0) / 1_000
    if kilometers >= 100 {
        return "\(Int(kilometers.rounded())) km"
    }

    if kilometers >= 10 {
        return String(format: "%.1f km", kilometers)
    }

    if kilometers > 0 {
        return String(format: "%.2f km", kilometers)
    }

    return "0 km"
}

func compactDurationText(_ seconds: Double, text: PTrackWidgetText) -> String {
    text.durationText(seconds)
}
