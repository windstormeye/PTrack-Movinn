//
//  WellnessRecapModels.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//

import Foundation

// MARK: - Range

nonisolated enum WellnessRecapRange: String, Codable, CaseIterable, Sendable {
    case threeDays
    case week
    case month
    case halfYear
    case year

    /// 评估窗口天数。
    var evaluationDays: Int {
        switch self {
        case .threeDays: return 3
        case .week: return 7
        case .month: return 30
        case .halfYear: return 182
        case .year: return 365
        }
    }

    /// 需要拉取的总天数(评估窗 + 基线/上一期 + 余量)。
    var fetchDays: Int {
        switch self {
        case .threeDays, .week: return 42
        case .month: return 90
        case .halfYear: return 370
        case .year: return 735
        }
    }

    /// 长周期走"本期 vs 上一期"对比,短周期走 28 天基线。
    var isLongTerm: Bool {
        switch self {
        case .threeDays, .week: return false
        case .month, .halfYear, .year: return true
        }
    }

    /// 图表分桶粒度。
    var chartGranularity: ChartGranularity {
        switch self {
        case .threeDays, .week, .month: return .daily
        case .halfYear: return .weekly
        case .year: return .monthly
        }
    }

    var titleKey: AppTextKey {
        switch self {
        case .threeDays: return .wellnessRangeThreeDays
        case .week: return .wellnessRangeWeek
        case .month: return .wellnessRangeMonth
        case .halfYear: return .wellnessRangeHalfYear
        case .year: return .wellnessRangeYear
        }
    }

    nonisolated enum ChartGranularity: String, Codable, Sendable {
        case daily
        case weekly
        case monthly
    }
}

// MARK: - Advice

nonisolated enum RecapAdviceCategory: String, Codable, Sendable {
    case sleep
    case activity
    case nutrition
    case recovery
    case risk
    case positive
}

nonisolated struct RecapAdvice: Codable, Sendable {
    let category: RecapAdviceCategory
    let priority: Int
    let evidence: String
    let title: String
    let body: String
    /// 附带的知识点,渲染为品牌色小圆点开头的独立一行。
    var tip: String?
    let score: Double
}

// MARK: - Blocks

nonisolated struct RecapChartPoint: Codable, Sendable {
    let label: String
    /// nil = 该桶未记录,图表留空。
    let value: Double?
}

nonisolated struct RecapChartData: Codable, Sendable {
    let title: String
    let points: [RecapChartPoint]
    /// 基线/上一期参考线,可空。
    let baseline: Double?
}

nonisolated struct RecapMetricRow: Codable, Sendable {
    let name: String
    let current: String
    let reference: String
    let delta: String
    /// +1 = 向好,-1 = 变差,0 = 中性;控制变化列颜色。
    let deltaDirection: Int
}

/// 指导页内容块,从上到下顺序渲染;文本块走打字机,图表/表格淡入。
nonisolated enum RecapBlock: Codable, Sendable {
    case heading(String)
    case paragraph(String)
    case metricTable([RecapMetricRow])
    case chart(RecapChartData)
    case advice(RecapAdvice)
    case footnote(String)
}

// MARK: - Report

nonisolated struct WellnessRecapReport: Codable, Sendable {
    let periodID: String
    let range: WellnessRecapRange
    let generatedAt: Date
    let languageCode: String
    let summary: String
    let blocks: [RecapBlock]
}
