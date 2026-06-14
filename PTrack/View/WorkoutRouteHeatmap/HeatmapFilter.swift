//
//  HeatmapFilter.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import HealthKit

enum HeatmapFilter: CaseIterable {
    case walking
    case cycling
    case running
    case all

    var title: String {
        switch self {
        case .walking:
            return "行走/徒步"
        case .cycling:
            return "骑行"
        case .running:
            return "跑步"
        case .all:
            return "全部"
        }
    }

    func includes(_ activityType: HKWorkoutActivityType) -> Bool {
        switch self {
        case .walking:
            return activityType == .walking || activityType == .hiking
        case .cycling:
            return activityType == .cycling
        case .running:
            return activityType == .running
        case .all:
            return true
        }
    }
}
