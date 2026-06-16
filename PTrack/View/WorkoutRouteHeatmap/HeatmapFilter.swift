//
//  HeatmapFilter.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

enum HeatmapFilter: String, CaseIterable, Hashable {
    case cycling
    case virtualCycling
    case running
    case virtualRunning
    case trailRunning
    case walking
    case hiking
    case outdoorSwimming
    case outdoorWorkout

    var title: String {
        switch self {
        case .cycling:
            return TrackedWorkoutSportKind.cycling.title
        case .virtualCycling:
            return TrackedWorkoutSportKind.virtualCycling.title
        case .running:
            return TrackedWorkoutSportKind.running.title
        case .virtualRunning:
            return TrackedWorkoutSportKind.virtualRunning.title
        case .trailRunning:
            return TrackedWorkoutSportKind.trailRunning.title
        case .walking:
            return TrackedWorkoutSportKind.walking.title
        case .hiking:
            return TrackedWorkoutSportKind.hiking.title
        case .outdoorSwimming:
            return TrackedWorkoutSportKind.outdoorSwimming.title
        case .outdoorWorkout:
            return TrackedWorkoutSportKind.outdoorWorkout.title
        }
    }

    var image: UIImage? {
        return UIImage(systemName: sportKind.symbolName)
    }

    func includes(_ sportKind: TrackedWorkoutSportKind) -> Bool {
        sportKind == self.sportKind
    }

    private var sportKind: TrackedWorkoutSportKind {
        switch self {
        case .cycling:
            return .cycling
        case .virtualCycling:
            return .virtualCycling
        case .running:
            return .running
        case .virtualRunning:
            return .virtualRunning
        case .trailRunning:
            return .trailRunning
        case .walking:
            return .walking
        case .hiking:
            return .hiking
        case .outdoorSwimming:
            return .outdoorSwimming
        case .outdoorWorkout:
            return .outdoorWorkout
        }
    }
}

final class HeatmapFilterStore {
    static let shared = HeatmapFilterStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selectedFilters() -> Set<HeatmapFilter> {
        guard let deselectedRawValues = defaults.array(forKey: Keys.deselectedFilters) as? [String] else {
            return Set(HeatmapFilter.allCases)
        }

        let deselectedFilters = Set(deselectedRawValues.compactMap(HeatmapFilter.init(rawValue:)))
        return Set(HeatmapFilter.allCases).subtracting(deselectedFilters)
    }

    func setSelectedFilters(_ selectedFilters: Set<HeatmapFilter>) {
        let deselectedRawValues = Set(HeatmapFilter.allCases)
            .subtracting(selectedFilters)
            .map(\.rawValue)
            .sorted()
        defaults.set(deselectedRawValues, forKey: Keys.deselectedFilters)
    }

    private enum Keys {
        static let deselectedFilters = "studio.pj.PTrack.heatmap.deselectedFilters"
    }
}
