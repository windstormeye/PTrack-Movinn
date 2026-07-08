//
//  RouteBookMode.swift
//  PTrack
//
//  Created by Codex on 2026/6/17.
//

import Foundation

enum RouteBookMode {
    enum StorageSource: String {
        case workoutCache
        case routeCollection
    }

    struct ActiveSession {
        let routeID: String
        let source: StorageSource?
    }

    static let workoutUserInfoKey = "studio.pj.PTrack.routeBook.workout"
    static let didSelectWorkoutNotification = Notification.Name("studio.pj.PTrack.routeBook.didSelectWorkout")

    private static let isActiveKey = "studio.pj.PTrack.routeBook.isActive"
    private static let activeWorkoutIDKey = "studio.pj.PTrack.routeBook.activeWorkoutID"
    private static let activeStorageSourceKey = "studio.pj.PTrack.routeBook.activeStorageSource"
    private static let snapshotFileName = "active-route-book-workout.json"

    static var activeWorkoutID: String? {
        let workoutID = UserDefaults.standard.string(forKey: activeWorkoutIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return workoutID?.isEmpty == false ? workoutID : nil
    }

    static var activeSession: ActiveSession? {
        guard let routeID = activeWorkoutID else {
            return nil
        }

        let isActive = UserDefaults.standard.object(forKey: isActiveKey) as? Bool ?? true
        guard isActive else {
            return nil
        }

        let source = UserDefaults.standard.string(forKey: activeStorageSourceKey)
            .flatMap(StorageSource.init(rawValue:))
        return ActiveSession(routeID: routeID, source: source)
    }

    static var activeWorkoutSnapshot: TrackedWorkout? {
        guard let activeSession,
              let data = try? Data(contentsOf: snapshotFileURL),
              let workout = try? JSONDecoder().decode(TrackedWorkout.self, from: data),
              workout.id == activeSession.routeID else {
            return nil
        }

        return workout
    }

    static func activate(workoutID: String) {
        UserDefaults.standard.set(workoutID, forKey: activeWorkoutIDKey)
        UserDefaults.standard.set(true, forKey: isActiveKey)
        UserDefaults.standard.removeObject(forKey: activeStorageSourceKey)
        UserDefaults.standard.synchronize()
        try? FileManager.default.removeItem(at: snapshotFileURL)
    }

    static func activate(workout: TrackedWorkout) {
        UserDefaults.standard.set(workout.id, forKey: activeWorkoutIDKey)
        UserDefaults.standard.set(true, forKey: isActiveKey)
        UserDefaults.standard.set(storageSource(for: workout).rawValue, forKey: activeStorageSourceKey)
        UserDefaults.standard.synchronize()
        saveSnapshot(workout)
    }

    static func clearActiveWorkout() {
        UserDefaults.standard.set(false, forKey: isActiveKey)
        UserDefaults.standard.removeObject(forKey: activeWorkoutIDKey)
        UserDefaults.standard.removeObject(forKey: activeStorageSourceKey)
        UserDefaults.standard.synchronize()
        try? FileManager.default.removeItem(at: snapshotFileURL)
    }
}

private extension RouteBookMode {
    static var snapshotFileURL: URL {
        let directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PTrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent(snapshotFileName, isDirectory: false)
    }

    static func saveSnapshot(_ workout: TrackedWorkout) {
        do {
            let data = try JSONEncoder().encode(workout)
            try data.write(to: snapshotFileURL, options: [.atomic])
        } catch {
            print("PTrack RouteBook: failed to save active workout snapshot: \(error)")
        }
    }

    static func storageSource(for workout: TrackedWorkout) -> StorageSource {
        workout.isRouteCollectionSource ? .routeCollection : .workoutCache
    }
}
