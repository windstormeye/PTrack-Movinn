//
//  WorkoutCacheStore.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import Foundation

final class WorkoutCacheStore {
    private let fileURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directoryURL = baseURL.appendingPathComponent("PTrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("tracked-workouts.json")
    }

    func load() -> [TrackedWorkout] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        do {
            let workouts = try JSONDecoder().decode([TrackedWorkout].self, from: data)
            return sorted(workouts)
        } catch {
            print("PTrack Cache: failed to decode cached workouts: \(error)")
            return []
        }
    }

    func save(_ workouts: [TrackedWorkout]) {
        do {
            let data = try JSONEncoder().encode(sorted(workouts))
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("PTrack Cache: failed to save cached workouts: \(error)")
        }
    }

    private func sorted(_ workouts: [TrackedWorkout]) -> [TrackedWorkout] {
        workouts.sorted { $0.startDate > $1.startDate }
    }
}
