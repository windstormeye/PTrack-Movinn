//
//  WorkoutCacheStore.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import Foundation

final class WorkoutCacheStore {
    private let directoryURL: URL
    private let manifestFileURL: URL
    private let workoutsDirectoryURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = baseURL.appendingPathComponent("PTrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        manifestFileURL = directoryURL.appendingPathComponent("tracked-workout-index.json")
        workoutsDirectoryURL = directoryURL.appendingPathComponent("tracked-workouts", isDirectory: true)
    }

    func load(
        batchSize: Int = 0,
        onBatch: (([TrackedWorkout]) -> Void)? = nil
    ) -> [TrackedWorkout] {
        if let splitCacheWorkouts = loadSplitCache(batchSize: batchSize, onBatch: onBatch) {
            return splitCacheWorkouts
        }

        return []
    }

    func save(_ workouts: [TrackedWorkout]) {
        do {
            try FileManager.default.createDirectory(at: workoutsDirectoryURL, withIntermediateDirectories: true)

            var seenIDs = Set<String>()
            let sortedWorkouts = sorted(workouts).filter { seenIDs.insert($0.id).inserted }
            var writtenWorkoutFileCount = 0
            var currentFileNames = Set<String>()

            for workout in sortedWorkouts {
                let fileURL = workoutFileURL(for: workout.id)
                currentFileNames.insert(fileURL.lastPathComponent)

                let data = try JSONEncoder().encode(workout)
                if (try? Data(contentsOf: fileURL)) != data {
                    try data.write(to: fileURL, options: [.atomic])
                    writtenWorkoutFileCount += 1
                }
            }

            let removedWorkoutFileCount = removeStaleWorkoutFiles(currentFileNames: currentFileNames)
            let manifest = WorkoutCacheManifest(
                version: 1,
                workoutIDs: sortedWorkouts.map(\.id)
            )
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestFileURL, options: [.atomic])

            print(
                "PTrack Cache: saved \(sortedWorkouts.count) workouts, Strava: \(sortedWorkouts.compactMap(\.stravaActivityID).count), written files: \(writtenWorkoutFileCount), removed files: \(removedWorkoutFileCount), path: \(workoutsDirectoryURL.path)"
            )
        } catch {
            print("PTrack Cache: failed to save cached workouts: \(error)")
        }
    }

    @discardableResult
    func saveIncremental(
        _ workouts: [TrackedWorkout],
        dirtyWorkoutIDs: Set<String>,
        deletedWorkoutIDs: Set<String>
    ) -> Bool {
        do {
            try FileManager.default.createDirectory(at: workoutsDirectoryURL, withIntermediateDirectories: true)

            var seenIDs = Set<String>()
            let sortedWorkouts = sorted(workouts).filter { seenIDs.insert($0.id).inserted }
            let workoutsByID = Dictionary(uniqueKeysWithValues: sortedWorkouts.map { ($0.id, $0) })
            let idsToWrite = dirtyWorkoutIDs.subtracting(deletedWorkoutIDs)
            var writtenWorkoutFileCount = 0
            var removedWorkoutFileCount = 0

            for workoutID in deletedWorkoutIDs {
                if removeWorkoutFile(for: workoutID) {
                    removedWorkoutFileCount += 1
                }
            }

            for workoutID in idsToWrite {
                guard let workout = workoutsByID[workoutID] else {
                    continue
                }

                let fileURL = workoutFileURL(for: workout.id)
                let data = try JSONEncoder().encode(workout)
                try data.write(to: fileURL, options: [.atomic])
                writtenWorkoutFileCount += 1
            }

            let manifest = WorkoutCacheManifest(
                version: 1,
                workoutIDs: sortedWorkouts.map(\.id)
            )
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestFileURL, options: [.atomic])

            print(
                "PTrack Cache: incrementally saved \(sortedWorkouts.count) workouts, dirty: \(dirtyWorkoutIDs.count), deleted: \(deletedWorkoutIDs.count), written files: \(writtenWorkoutFileCount), removed files: \(removedWorkoutFileCount)"
            )
            return true
        } catch {
            print("PTrack Cache: failed to incrementally save cached workouts: \(error)")
            return false
        }
    }

    private func loadSplitCache(
        batchSize: Int = 0,
        onBatch: (([TrackedWorkout]) -> Void)? = nil
    ) -> [TrackedWorkout]? {
        let manifest = loadManifest()
        let fileURLs: [URL]
        let shouldPublishBatches = batchSize > 0 && onBatch != nil

        if let manifest {
            fileURLs = manifest.workoutIDs.map(workoutFileURL(for:))
        } else {
            fileURLs = existingWorkoutFileURLs()
            guard !fileURLs.isEmpty else {
                return nil
            }
        }

        var workouts: [TrackedWorkout] = []
        var batchWorkouts: [TrackedWorkout] = []
        workouts.reserveCapacity(fileURLs.count)
        if shouldPublishBatches {
            batchWorkouts.reserveCapacity(batchSize)
        }

        for fileURL in fileURLs {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("PTrack Cache: missing workout cache file: \(fileURL.path)")
                continue
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let workout = try JSONDecoder().decode(TrackedWorkout.self, from: data)
                workouts.append(workout)

                if shouldPublishBatches {
                    batchWorkouts.append(workout)
                    if batchWorkouts.count >= batchSize {
                        onBatch?(batchWorkouts)
                        batchWorkouts.removeAll(keepingCapacity: true)
                    }
                }
            } catch {
                print("PTrack Cache: failed to decode workout cache file \(fileURL.lastPathComponent): \(error)")
            }
        }

        if shouldPublishBatches, !batchWorkouts.isEmpty {
            onBatch?(batchWorkouts)
        }

        let sortedWorkouts = sorted(workouts)
        print(
            "PTrack Cache: loaded \(sortedWorkouts.count) workouts, Strava: \(sortedWorkouts.compactMap(\.stravaActivityID).count), files: \(fileURLs.count), size: \(Self.formattedByteCount(totalSplitCacheByteCount())), path: \(workoutsDirectoryURL.path)"
        )
        return sortedWorkouts
    }

    private func loadManifest() -> WorkoutCacheManifest? {
        guard let data = try? Data(contentsOf: manifestFileURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(WorkoutCacheManifest.self, from: data)
        } catch {
            print("PTrack Cache: failed to decode cache manifest: \(error)")
            return nil
        }
    }

    private func existingWorkoutFileURLs() -> [URL] {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: workoutsDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return fileURLs
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func removeStaleWorkoutFiles(currentFileNames: Set<String>) -> Int {
        var removedFileCount = 0
        for fileURL in existingWorkoutFileURLs() where !currentFileNames.contains(fileURL.lastPathComponent) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                removedFileCount += 1
            } catch {
                print("PTrack Cache: failed to remove stale workout cache file \(fileURL.lastPathComponent): \(error)")
            }
        }
        return removedFileCount
    }

    private func removeWorkoutFile(for id: String) -> Bool {
        let fileURL = workoutFileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            print("PTrack Cache: failed to remove workout cache file \(fileURL.lastPathComponent): \(error)")
            return false
        }
    }

    private func workoutFileURL(for id: String) -> URL {
        workoutsDirectoryURL
            .appendingPathComponent(safeFileName(for: id), isDirectory: false)
            .appendingPathExtension("json")
    }

    private func safeFileName(for id: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let fileName = id.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()

        return fileName.isEmpty ? "unknown-workout" : fileName
    }

    private func totalSplitCacheByteCount() -> Int64 {
        let workoutFilesByteCount = existingWorkoutFileURLs().reduce(Int64(0)) { partialResult, fileURL in
            partialResult + byteCount(for: fileURL)
        }

        return workoutFilesByteCount + byteCount(for: manifestFileURL)
    }

    private func byteCount(for fileURL: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }

        return size.int64Value
    }

    private func sorted(_ workouts: [TrackedWorkout]) -> [TrackedWorkout] {
        workouts.sorted { $0.startDate > $1.startDate }
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

private struct WorkoutCacheManifest: Codable {
    let version: Int
    let workoutIDs: [String]
}
