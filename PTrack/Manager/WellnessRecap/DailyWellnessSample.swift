//
//  DailyWellnessSample.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  运动回顾引擎的日聚合样本。所有字段 nil = 当天未记录,严禁当 0 处理;
//  唯一例外是 workoutLoad:没有运动记录时负荷确实为 0。

import Foundation

nonisolated struct DailyWellnessSample: Codable, Sendable {
    /// 自然日零点(用户当前时区)。
    let day: Date

    /// 总睡眠时长(分钟,仅统计 asleep 阶段)。
    var sleepDurationMinutes: Double?
    /// 入睡时刻,相对当日 0 点的分钟数(前一晚入睡为负值)。
    var sleepStartMinutes: Double?
    /// 睡眠中点,相对当日 0 点的分钟数。
    var sleepMidpointMinutes: Double?
    /// 深睡时长(分钟)。
    var deepSleepMinutes: Double?

    var stepCount: Double?
    var restingHeartRate: Double?
    var hrvSDNN: Double?
    var activeEnergyKilocalories: Double?
    var exerciseMinutes: Double?
    var daylightMinutes: Double?

    /// Σ(每次运动分钟 × 强度系数)。无运动 = 0。
    var workoutLoad: Double = 0
    var workoutCount: Int = 0
    var workoutMinutes: Double = 0
    var workoutDistanceMeters: Double = 0

    init(day: Date) {
        self.day = day
    }
}
