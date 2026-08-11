//
//  WellnessBaseline.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  稳健统计工具:中位数 / MAD / EWMA。所有函数忽略 nil(未记录 ≠ 0)。

import Foundation

nonisolated enum WellnessBaseline {
    /// MAD → 正态等效标准差的换算系数。
    static let madToSigma = 1.4826

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// 稳健标准差(基于绝对中位差)。
    static func robustSigma(_ values: [Double]) -> Double? {
        guard let medianValue = median(values) else {
            return nil
        }
        let deviations = values.map { abs($0 - medianValue) }
        guard let mad = median(deviations) else {
            return nil
        }
        return mad * madToSigma
    }

    /// 指数加权均值,alpha 默认 0.3,时间升序输入。
    static func ewma(_ values: [Double], alpha: Double = 0.3) -> Double? {
        guard let first = values.first else {
            return nil
        }
        var result = first
        for value in values.dropFirst() {
            result = alpha * value + (1 - alpha) * result
        }
        return result
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let meanValue = mean(values) else {
            return nil
        }
        let variance = values.reduce(0) { $0 + ($1 - meanValue) * ($1 - meanValue) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    /// 睡眠时刻归一化:把"相对 0 点的分钟数"折到 [-360, 1080) 区间,
    /// 避免 23:30(=-30)与 00:30(=30)被算出巨大差值。
    static func normalizedClockMinutes(_ minutes: Double) -> Double {
        var value = minutes
        while value >= 18 * 60 {
            value -= 24 * 60
        }
        while value < -6 * 60 {
            value += 24 * 60
        }
        return value
    }
}
