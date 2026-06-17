//
//  RouteBookMode.swift
//  PTrack
//
//  Created by Codex on 2026/6/17.
//

import Foundation

enum RouteBookMode {
    static let workoutUserInfoKey = "studio.pj.PTrack.routeBook.workout"
    static let didSelectWorkoutNotification = Notification.Name("studio.pj.PTrack.routeBook.didSelectWorkout")

    private static let activeWorkoutIDKey = "studio.pj.PTrack.routeBook.activeWorkoutID"

    static var activeWorkoutID: String? {
        let workoutID = UserDefaults.standard.string(forKey: activeWorkoutIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return workoutID?.isEmpty == false ? workoutID : nil
    }

    static func activate(workoutID: String) {
        UserDefaults.standard.set(workoutID, forKey: activeWorkoutIDKey)
    }

    static func clearActiveWorkout() {
        UserDefaults.standard.removeObject(forKey: activeWorkoutIDKey)
    }
}
