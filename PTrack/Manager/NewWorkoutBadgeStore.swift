//
//  NewWorkoutBadgeStore.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import Foundation

final class NewWorkoutBadgeStore {
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let idsKey = "studio.pj.PTrack.newWorkoutBadge.ids"
    private let dayKey = "studio.pj.PTrack.newWorkoutBadge.day"
    private let didCompleteInitialSyncKey = "studio.pj.PTrack.newWorkoutBadge.didCompleteInitialSync"
    private var workoutIDs: Set<String>

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar

        let currentDayKey = Self.dayKey(for: Date(), calendar: calendar)
        if defaults.string(forKey: dayKey) == currentDayKey {
            workoutIDs = Set(defaults.stringArray(forKey: idsKey) ?? [])
        } else {
            workoutIDs = []
            defaults.set(currentDayKey, forKey: dayKey)
            defaults.set([], forKey: idsKey)
        }
    }

    func contains(_ workout: TrackedWorkout) -> Bool {
        pruneIfNeeded()
        guard calendar.isDateInToday(workout.startDate) else {
            return false
        }

        return workoutIDs.contains(workout.id)
    }

    @discardableResult
    func markIfNeeded(_ workout: TrackedWorkout) -> Bool {
        pruneIfNeeded()
        guard defaults.bool(forKey: didCompleteInitialSyncKey),
              calendar.isDateInToday(workout.startDate) else {
            return false
        }

        let inserted = workoutIDs.insert(workout.id).inserted
        if inserted {
            save()
        }
        return inserted
    }

    @discardableResult
    func markSeen(_ workout: TrackedWorkout) -> Bool {
        pruneIfNeeded()
        let removed = workoutIDs.remove(workout.id) != nil
        if removed {
            save()
        }
        return removed
    }

    func markInitialSyncCompleted() {
        guard !defaults.bool(forKey: didCompleteInitialSyncKey) else {
            return
        }

        defaults.set(true, forKey: didCompleteInitialSyncKey)
    }

    private func pruneIfNeeded() {
        let currentDayKey = Self.dayKey(for: Date(), calendar: calendar)
        guard defaults.string(forKey: dayKey) != currentDayKey else {
            return
        }

        workoutIDs.removeAll()
        defaults.set(currentDayKey, forKey: dayKey)
        save()
    }

    private func save() {
        defaults.set(Array(workoutIDs), forKey: idsKey)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
