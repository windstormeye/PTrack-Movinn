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
            return AppLocalization.text(.walkingHiking)
        case .cycling:
            return AppLocalization.text(.cycling)
        case .running:
            return AppLocalization.text(.running)
        case .all:
            return AppLocalization.text(.all)
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
