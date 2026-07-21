//
//  WorkoutCacheStore.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import Foundation
import OSLog

struct WorkoutCacheSummary: Codable, Equatable {
    let workoutCount: Int
    let totalDistanceMeters: Double
}

struct WorkoutCacheStartupState: Equatable {
    let summary: WorkoutCacheSummary?
    let indexedWorkoutIDs: Set<String>?
    let integrityStatus: WorkoutCacheIntegrityStatus
}

struct WorkoutCacheIntegrityStatus: Equatable {
    let indexedWorkoutCount: Int
    let existingWorkoutFileCount: Int
    let orphanedWorkoutFileCount: Int
    let missingIndexedWorkoutFileCount: Int
    let hasReadableManifest: Bool
    let hasReadableWorkoutDirectory: Bool

    var requiresReconciliation: Bool {
        !hasReadableWorkoutDirectory
            || (!hasReadableManifest && existingWorkoutFileCount > 0)
            || orphanedWorkoutFileCount > 0
            || missingIndexedWorkoutFileCount > 0
            || indexedWorkoutCount != existingWorkoutFileCount
    }
}

struct WorkoutCacheProgressiveLoadResult: Equatable {
    let loadedWorkoutCount: Int
    let discoveredWorkoutFileCount: Int
    let didFinishScanningWorkoutFiles: Bool
}

enum WorkoutCachePersistenceResult: Equatable {
    case success
    case transientFailure
    case reconciliationRequired
    case invalidSnapshot

    var didSucceed: Bool {
        self == .success
    }
}

final class WorkoutCacheStore {
    private let directoryURL: URL
    private let manifestFileURL: URL
    private let workoutsDirectoryURL: URL
    private let quarantineDirectoryURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = baseURL.appendingPathComponent("PTrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        manifestFileURL = directoryURL.appendingPathComponent("tracked-workout-index.json")
        workoutsDirectoryURL = directoryURL.appendingPathComponent("tracked-workouts", isDirectory: true)
        quarantineDirectoryURL = directoryURL.appendingPathComponent(
            "tracked-workouts-quarantine",
            isDirectory: true
        )
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

    @discardableResult
    func loadProgressively(
        batchSize: Int,
        shouldContinue: () -> Bool = { true },
        onBatch: ([TrackedWorkout]) -> Void
    ) -> WorkoutCacheProgressiveLoadResult {
        loadSplitCacheProgressively(
            batchSize: batchSize,
            shouldContinue: shouldContinue,
            onBatch: onBatch
        )
    }

    func loadStartupState() -> WorkoutCacheStartupState {
        let manifest = loadManifest()
        let existingFileURLs: [URL]
        do {
            existingFileURLs = try existingWorkoutFileURLs()
        } catch {
            PTrackLog.cache.debug("PTrack Cache: failed to inspect workout-file inventory: \(error)")
            // The inventory is unverified, but a readable manifest whose
            // summary count matches its own committed ID set remains the best
            // stable display snapshot. Keep it while scheduling reconciliation
            // instead of immediately falling back to a transient partial load.
            let retainedSummary = manifest.flatMap { manifest in
                let uniqueWorkoutIDs = Set(manifest.workoutIDs)
                return uniqueWorkoutIDs.count == manifest.workoutIDs.count
                    && manifest.summary?.workoutCount == uniqueWorkoutIDs.count
                    ? manifest.summary
                    : nil
            }
            return WorkoutCacheStartupState(
                summary: retainedSummary,
                indexedWorkoutIDs: manifest.map { Set($0.workoutIDs) },
                integrityStatus: WorkoutCacheIntegrityStatus(
                    indexedWorkoutCount: manifest?.workoutIDs.count ?? 0,
                    existingWorkoutFileCount: 0,
                    orphanedWorkoutFileCount: 0,
                    missingIndexedWorkoutFileCount: manifest?.workoutIDs.count ?? 0,
                    hasReadableManifest: manifest != nil,
                    hasReadableWorkoutDirectory: false
                )
            )
        }

        let existingFileNames = Set(existingFileURLs.map(\.lastPathComponent))
        guard let manifest else {
            return WorkoutCacheStartupState(
                summary: nil,
                indexedWorkoutIDs: nil,
                integrityStatus: WorkoutCacheIntegrityStatus(
                    indexedWorkoutCount: 0,
                    existingWorkoutFileCount: existingFileNames.count,
                    orphanedWorkoutFileCount: existingFileNames.count,
                    missingIndexedWorkoutFileCount: 0,
                    hasReadableManifest: false,
                    hasReadableWorkoutDirectory: true
                )
            )
        }

        let indexedFileNames = Set(manifest.workoutIDs.map {
            workoutFileURL(for: $0).lastPathComponent
        })
        let integrityStatus = WorkoutCacheIntegrityStatus(
            indexedWorkoutCount: manifest.workoutIDs.count,
            existingWorkoutFileCount: existingFileNames.count,
            orphanedWorkoutFileCount: existingFileNames.subtracting(indexedFileNames).count,
            missingIndexedWorkoutFileCount: indexedFileNames.subtracting(existingFileNames).count,
            hasReadableManifest: true,
            hasReadableWorkoutDirectory: true
        )
        // Even when the directory inventory disagrees, an internally
        // consistent committed summary remains the stable UI baseline while
        // source reconciliation repairs the missing/orphaned files.
        let uniqueWorkoutIDs = Set(manifest.workoutIDs)
        let summary = uniqueWorkoutIDs.count == manifest.workoutIDs.count
            && manifest.summary?.workoutCount == uniqueWorkoutIDs.count
            ? manifest.summary
            : nil
        if !integrityStatus.requiresReconciliation, summary == nil {
            PTrackLog.cache.debug("PTrack Cache: ignored stale or missing summary in an otherwise readable manifest")
        }
        return WorkoutCacheStartupState(
            summary: summary,
            indexedWorkoutIDs: Set(manifest.workoutIDs),
            integrityStatus: integrityStatus
        )
    }

    func loadCachedWorkoutIDs() -> [String]? {
        guard let manifest = loadManifest(),
              isManifestConsistentWithWorkoutFiles(manifest) else {
            return nil
        }

        return manifest.workoutIDs
    }

    func loadWorkout(id: String) -> TrackedWorkout? {
        let fileURL = workoutFileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let workout = try autoreleasepool {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(TrackedWorkout.self, from: data)
            }
            guard workout.id == id else {
                PTrackLog.cache.debug("PTrack Cache: ignored cache file whose embedded workout ID did not match \(id)")
                return nil
            }
            return workout
        } catch {
            PTrackLog.cache.debug("PTrack Cache: failed to decode workout cache file \(fileURL.lastPathComponent): \(error)")
            return nil
        }
    }

    @discardableResult
    func saveIncremental(
        _ workouts: [TrackedWorkout],
        dirtyWorkoutIDs: Set<String>,
        deletedWorkoutIDs: Set<String>
    ) -> WorkoutCachePersistenceResult {
        do {
            try FileManager.default.createDirectory(at: workoutsDirectoryURL, withIntermediateDirectories: true)

            var seenIDs = Set<String>()
            let sortedWorkouts = sorted(workouts)
            guard sortedWorkouts.allSatisfy({ seenIDs.insert($0.id).inserted }) else {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "the authoritative snapshot contained duplicate workout IDs"
                )
            }
            let workoutsByID = Dictionary(uniqueKeysWithValues: sortedWorkouts.map { ($0.id, $0) })
            let idsToWrite = dirtyWorkoutIDs.subtracting(deletedWorkoutIDs)
            let snapshotWorkoutIDs = Set(sortedWorkouts.map(\.id))
            let snapshotFileNames = Set(sortedWorkouts.map {
                workoutFileURL(for: $0.id).lastPathComponent
            })
            let explicitlyDeletedFileNames = Set(deletedWorkoutIDs.map {
                workoutFileURL(for: $0).lastPathComponent
            })

            guard snapshotFileNames.count == snapshotWorkoutIDs.count else {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "multiple workout IDs resolved to the same cache filename"
                )
            }
            guard explicitlyDeletedFileNames.isDisjoint(with: snapshotFileNames) else {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "a deleted workout ID resolved to the filename of a retained workout"
                )
            }

            let unknownExistingFileNames = Set(try existingWorkoutFileURLs().map(\.lastPathComponent))
                .subtracting(snapshotFileNames)
                .subtracting(explicitlyDeletedFileNames)
            guard unknownExistingFileNames.isEmpty else {
                throw WorkoutCacheValidationError.reconciliationRequired(
                    "\(unknownExistingFileNames.count) on-disk workout file(s) were absent from the authoritative snapshot"
                )
            }

            let deletedWorkoutIDsStillInSnapshot = deletedWorkoutIDs
                .intersection(snapshotWorkoutIDs)
            guard deletedWorkoutIDsStillInSnapshot.isEmpty else {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "\(deletedWorkoutIDsStillInSnapshot.count) deleted workout(s) were still present in the snapshot"
                )
            }

            let missingDirtyWorkoutIDs = idsToWrite.subtracting(snapshotWorkoutIDs)
            guard missingDirtyWorkoutIDs.isEmpty else {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "\(missingDirtyWorkoutIDs.count) dirty workout(s) were absent from the snapshot"
                )
            }

            if let previousManifest = loadManifest() {
                let retainedWorkoutIDs = Set(previousManifest.workoutIDs)
                    .subtracting(deletedWorkoutIDs)
                let unintentionallyMissingWorkoutIDs = retainedWorkoutIDs
                    .subtracting(snapshotWorkoutIDs)
                guard unintentionallyMissingWorkoutIDs.isEmpty else {
                    throw WorkoutCacheValidationError.reconciliationRequired(
                        "the save would drop \(unintentionallyMissingWorkoutIDs.count) indexed workout(s) without explicit deletion"
                    )
                }
            } else {
                let existingWorkoutFileCount = try existingWorkoutFileURLs().count
                guard existingWorkoutFileCount == 0 else {
                    throw WorkoutCacheValidationError.reconciliationRequired(
                        "the manifest is unavailable while \(existingWorkoutFileCount) workout file(s) still exist"
                    )
                }
            }

            var writtenWorkoutFileCount = 0
            var removedWorkoutFileCount = 0

            // Persist replacements and additions before removing old records. If
            // the process is interrupted, recovery can safely reconcile an extra
            // file; deleting the old record first could lose both sides.
            for workoutID in idsToWrite {
                guard let workout = workoutsByID[workoutID] else {
                    throw WorkoutCacheValidationError.invalidSnapshot(
                        "dirty workout \(workoutID) was unavailable during persistence"
                    )
                }

                let fileURL = workoutFileURL(for: workout.id)
                let data: Data
                do {
                    data = try JSONEncoder().encode(workout)
                } catch {
                    throw WorkoutCacheValidationError.invalidSnapshot(
                        "workout \(workoutID) could not be encoded: \(error)"
                    )
                }
                try data.write(to: fileURL, options: [.atomic])
                writtenWorkoutFileCount += 1
            }

            for workoutID in deletedWorkoutIDs {
                if try removeWorkoutFileIfPresent(for: workoutID) {
                    removedWorkoutFileCount += 1
                }
            }

            let resultingFileNames = Set(try existingWorkoutFileURLs().map(\.lastPathComponent))
            guard resultingFileNames == snapshotFileNames else {
                throw WorkoutCacheValidationError.reconciliationRequired(
                    "the authoritative snapshot expected \(snapshotFileNames.count) file(s), but disk contained \(resultingFileNames.count)"
                )
            }

            let manifest = WorkoutCacheManifest(
                version: 2,
                workoutIDs: sortedWorkouts.map(\.id),
                summary: Self.summary(for: sortedWorkouts)
            )
            let manifestData: Data
            do {
                manifestData = try JSONEncoder().encode(manifest)
            } catch {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "the cache manifest could not be encoded: \(error)"
                )
            }
            try manifestData.write(to: manifestFileURL, options: [.atomic])

            PTrackLog.cache.debug(
                "PTrack Cache: incrementally saved \(sortedWorkouts.count) workouts, dirty: \(dirtyWorkoutIDs.count), deleted: \(deletedWorkoutIDs.count), written files: \(writtenWorkoutFileCount), removed files: \(removedWorkoutFileCount)"
            )
            return .success
        } catch let error as WorkoutCacheValidationError {
            PTrackLog.cache.debug("PTrack Cache: rejected incremental save because \(error.reason)")
            return error.persistenceResult
        } catch {
            PTrackLog.cache.debug("PTrack Cache: failed to incrementally save cached workouts: \(error)")
            return .transientFailure
        }
    }

    @discardableResult
    func rebuildManifestAfterCompleteLoad(
        for workouts: [TrackedWorkout]
    ) -> WorkoutCachePersistenceResult {
        var quarantinedMoves: [(originalURL: URL, quarantineURL: URL)] = []
        do {
            try FileManager.default.createDirectory(at: workoutsDirectoryURL, withIntermediateDirectories: true)

            var seenIDs = Set<String>()
            let sortedWorkouts = sorted(workouts)
            guard sortedWorkouts.allSatisfy({ seenIDs.insert($0.id).inserted }) else {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "the complete cache snapshot contained duplicate workout IDs"
                )
            }

            // This method is called only after every recoverable cache file has
            // been decoded. Keep files absent from the complete snapshot in a
            // quarantine instead of deleting them; the data remains available
            // for diagnosis or manual recovery while no longer poisoning the
            // authoritative workout-file inventory.
            let retainedFileNames = Set(sortedWorkouts.map {
                workoutFileURL(for: $0.id).lastPathComponent
            })
            guard retainedFileNames.count == sortedWorkouts.count else {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "multiple workout IDs resolved to the same cache filename"
                )
            }

            let existingFileURLs = try existingWorkoutFileURLs()
            let existingFileNames = Set(existingFileURLs.map(\.lastPathComponent))
            let missingRetainedFileNames = retainedFileNames.subtracting(existingFileNames)
            guard missingRetainedFileNames.isEmpty else {
                throw WorkoutCacheValidationError.reconciliationRequired(
                    "the complete snapshot referenced \(missingRetainedFileNames.count) missing workout file(s)"
                )
            }

            let filesToQuarantine = existingFileURLs.filter {
                !retainedFileNames.contains($0.lastPathComponent)
            }
            let manifest = WorkoutCacheManifest(
                version: 2,
                workoutIDs: sortedWorkouts.map(\.id),
                summary: Self.summary(for: sortedWorkouts)
            )
            let manifestData: Data
            do {
                manifestData = try JSONEncoder().encode(manifest)
            } catch {
                throw WorkoutCacheValidationError.invalidSnapshot(
                    "the rebuilt cache manifest could not be encoded: \(error)"
                )
            }

            // Commit the retained-ID manifest before moving obsolete files. If
            // the process dies between these phases, startup sees harmless
            // orphan files and recovers them; moving first could leave the old
            // manifest pointing at files that are only reachable in quarantine.
            try manifestData.write(to: manifestFileURL, options: [.atomic])

            if !filesToQuarantine.isEmpty {
                try FileManager.default.createDirectory(
                    at: quarantineDirectoryURL,
                    withIntermediateDirectories: true
                )
            }
            for fileURL in filesToQuarantine {
                let quarantineURL = quarantineDirectoryURL.appendingPathComponent(
                    "\(UUID().uuidString)-\(fileURL.lastPathComponent)",
                    isDirectory: false
                )
                try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
                quarantinedMoves.append((fileURL, quarantineURL))
            }

            let remainingFileNames = Set(try existingWorkoutFileURLs().map(\.lastPathComponent))
            guard remainingFileNames == retainedFileNames else {
                throw WorkoutCacheValidationError.reconciliationRequired(
                    "the rebuilt inventory expected \(retainedFileNames.count) file(s), but found \(remainingFileNames.count)"
                )
            }

            PTrackLog.cache.debug(
                "PTrack Cache: rebuilt manifest after complete load, workouts: \(sortedWorkouts.count), quarantined obsolete files: \(filesToQuarantine.count)"
            )
            return .success
        } catch let error as WorkoutCacheValidationError {
            rollbackQuarantinedFiles(quarantinedMoves)
            PTrackLog.cache.debug("PTrack Cache: rejected manifest rebuild because \(error.reason)")
            return error.persistenceResult
        } catch {
            rollbackQuarantinedFiles(quarantinedMoves)
            PTrackLog.cache.debug("PTrack Cache: failed to rebuild manifest after complete load: \(error)")
            return .transientFailure
        }
    }

    private func loadSplitCache(
        batchSize: Int = 0,
        onBatch: (([TrackedWorkout]) -> Void)? = nil
    ) -> [TrackedWorkout]? {
        let fileURLs: [URL]
        do {
            fileURLs = try splitCacheWorkoutFileURLs()
        } catch {
            PTrackLog.cache.debug("PTrack Cache: failed to read workout-file inventory while loading: \(error)")
            return nil
        }
        let shouldPublishBatches = batchSize > 0 && onBatch != nil

        var workouts: [TrackedWorkout] = []
        var batchWorkouts: [TrackedWorkout] = []
        workouts.reserveCapacity(fileURLs.count)
        if shouldPublishBatches {
            batchWorkouts.reserveCapacity(batchSize)
        }

        for fileURL in fileURLs {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                PTrackLog.cache.debug("PTrack Cache: missing workout cache file: \(fileURL.path)")
                continue
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let workout = try JSONDecoder().decode(TrackedWorkout.self, from: data)
                guard workoutFileURL(for: workout.id).lastPathComponent == fileURL.lastPathComponent else {
                    PTrackLog.cache.debug(
                        "PTrack Cache: ignored workout cache file with mismatched embedded ID: \(fileURL.lastPathComponent)"
                    )
                    continue
                }
                workouts.append(workout)

                if shouldPublishBatches {
                    batchWorkouts.append(workout)
                    if batchWorkouts.count >= batchSize {
                        onBatch?(batchWorkouts)
                        batchWorkouts.removeAll(keepingCapacity: true)
                    }
                }
            } catch {
                PTrackLog.cache.debug("PTrack Cache: failed to decode workout cache file \(fileURL.lastPathComponent): \(error)")
            }
        }

        if shouldPublishBatches, !batchWorkouts.isEmpty {
            onBatch?(batchWorkouts)
        }

        let sortedWorkouts = sorted(workouts)
        PTrackLog.cache.debug(
            "PTrack Cache: loaded \(sortedWorkouts.count) workouts, Strava: \(sortedWorkouts.compactMap(\.stravaActivityID).count), files: \(fileURLs.count), size: \(Self.formattedByteCount(self.totalSplitCacheByteCount())), path: \(self.workoutsDirectoryURL.path)"
        )
        return sortedWorkouts
    }

    private func loadSplitCacheProgressively(
        batchSize: Int,
        shouldContinue: () -> Bool,
        onBatch: ([TrackedWorkout]) -> Void
    ) -> WorkoutCacheProgressiveLoadResult {
        let fileURLs: [URL]
        do {
            fileURLs = try splitCacheWorkoutFileURLs()
        } catch {
            PTrackLog.cache.debug("PTrack Cache: failed to read workout-file inventory while loading progressively: \(error)")
            return WorkoutCacheProgressiveLoadResult(
                loadedWorkoutCount: 0,
                discoveredWorkoutFileCount: 0,
                didFinishScanningWorkoutFiles: false
            )
        }

        let resolvedBatchSize = max(batchSize, 1)
        var loadedCount = 0
        var didFinishScanningWorkoutFiles = true
        var batchWorkouts: [TrackedWorkout] = []
        batchWorkouts.reserveCapacity(resolvedBatchSize)

        for fileURL in fileURLs {
            guard shouldContinue() else {
                didFinishScanningWorkoutFiles = false
                break
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                PTrackLog.cache.debug("PTrack Cache: missing workout cache file: \(fileURL.path)")
                continue
            }

            let workout: TrackedWorkout?
            do {
                workout = try autoreleasepool {
                    let data = try Data(contentsOf: fileURL)
                    return try JSONDecoder().decode(TrackedWorkout.self, from: data)
                }
            } catch {
                PTrackLog.cache.debug("PTrack Cache: failed to decode workout cache file \(fileURL.lastPathComponent): \(error)")
                continue
            }

            guard let workout else {
                continue
            }

            guard workoutFileURL(for: workout.id).lastPathComponent == fileURL.lastPathComponent else {
                PTrackLog.cache.debug(
                    "PTrack Cache: ignored workout cache file with mismatched embedded ID: \(fileURL.lastPathComponent)"
                )
                continue
            }

            loadedCount += 1
            batchWorkouts.append(workout)
            if batchWorkouts.count >= resolvedBatchSize {
                onBatch(batchWorkouts)
                batchWorkouts.removeAll(keepingCapacity: true)
            }
        }

        if didFinishScanningWorkoutFiles, !batchWorkouts.isEmpty {
            onBatch(batchWorkouts)
        }

        PTrackLog.cache.debug(
            "PTrack Cache: progressively loaded \(loadedCount) workouts, files: \(fileURLs.count), size: \(Self.formattedByteCount(self.totalSplitCacheByteCount())), path: \(self.workoutsDirectoryURL.path)"
        )
        return WorkoutCacheProgressiveLoadResult(
            loadedWorkoutCount: loadedCount,
            discoveredWorkoutFileCount: fileURLs.count,
            didFinishScanningWorkoutFiles: didFinishScanningWorkoutFiles
        )
    }

    private func splitCacheWorkoutFileURLs() throws -> [URL] {
        let existingFileURLs = try existingWorkoutFileURLs()
        guard let manifest = loadManifest() else {
            if !existingFileURLs.isEmpty {
                PTrackLog.cache.debug(
                    "PTrack Cache: manifest unavailable; recovering \(existingFileURLs.count) workout file(s) directly from disk"
                )
            }
            return existingFileURLs
        }

        var seenFileNames = Set<String>()
        var resolvedFileURLs: [URL] = []
        resolvedFileURLs.reserveCapacity(max(manifest.workoutIDs.count, existingFileURLs.count))

        for workoutID in manifest.workoutIDs {
            let fileURL = workoutFileURL(for: workoutID)
            guard seenFileNames.insert(fileURL.lastPathComponent).inserted else {
                continue
            }
            resolvedFileURLs.append(fileURL)
        }

        let orphanedFileURLs = existingFileURLs.filter {
            seenFileNames.insert($0.lastPathComponent).inserted
        }
        if !orphanedFileURLs.isEmpty {
            resolvedFileURLs.append(contentsOf: orphanedFileURLs)
        }

        let existingFileNames = Set(existingFileURLs.map(\.lastPathComponent))
        let indexedFileNames = Set(manifest.workoutIDs.map {
            workoutFileURL(for: $0).lastPathComponent
        })
        let missingIndexedFileCount = indexedFileNames.subtracting(existingFileNames).count
        if !orphanedFileURLs.isEmpty || missingIndexedFileCount > 0 {
            PTrackLog.cache.debug(
                "PTrack Cache: cache index mismatch detected, orphaned files: \(orphanedFileURLs.count), missing indexed files: \(missingIndexedFileCount); loading every recoverable file"
            )
        }

        return resolvedFileURLs
    }

    private func isManifestConsistentWithWorkoutFiles(_ manifest: WorkoutCacheManifest) -> Bool {
        let existingFileNames: Set<String>
        do {
            existingFileNames = Set(try existingWorkoutFileURLs().map(\.lastPathComponent))
        } catch {
            PTrackLog.cache.debug("PTrack Cache: could not validate manifest because workout-file inventory was unreadable: \(error)")
            return false
        }
        let indexedFileNames = Set(manifest.workoutIDs.map {
            workoutFileURL(for: $0).lastPathComponent
        })
        let isConsistent = manifest.workoutIDs.count == indexedFileNames.count
            && indexedFileNames == existingFileNames

        if !isConsistent {
            let orphanedFileCount = existingFileNames.subtracting(indexedFileNames).count
            let missingIndexedFileCount = indexedFileNames.subtracting(existingFileNames).count
            PTrackLog.cache.debug(
                "PTrack Cache: manifest is not authoritative, indexed: \(manifest.workoutIDs.count), files: \(existingFileNames.count), orphaned: \(orphanedFileCount), missing: \(missingIndexedFileCount)"
            )
        }

        return isConsistent
    }

    private func loadManifest() -> WorkoutCacheManifest? {
        guard let data = try? Data(contentsOf: manifestFileURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(WorkoutCacheManifest.self, from: data)
        } catch {
            PTrackLog.cache.debug("PTrack Cache: failed to decode cache manifest: \(error)")
            return nil
        }
    }

    private func existingWorkoutFileURLs() throws -> [URL] {
        // Ensure a genuinely empty first-run cache is distinguishable from an
        // inaccessible directory. If creation or access fails, propagate the
        // error instead of turning it into an authoritative empty inventory.
        try FileManager.default.createDirectory(
            at: workoutsDirectoryURL,
            withIntermediateDirectories: true
        )

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: workoutsDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return fileURLs
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func removeWorkoutFileIfPresent(for id: String) throws -> Bool {
        let fileURL = workoutFileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }

        try FileManager.default.removeItem(at: fileURL)
        return true
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
        let fileURLs: [URL]
        do {
            fileURLs = try existingWorkoutFileURLs()
        } catch {
            PTrackLog.cache.debug("PTrack Cache: could not calculate cache size because workout-file inventory was unreadable: \(error)")
            return byteCount(for: manifestFileURL)
        }

        let workoutFilesByteCount = fileURLs.reduce(Int64(0)) { partialResult, fileURL in
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

    private static func summary(for workouts: [TrackedWorkout]) -> WorkoutCacheSummary {
        WorkoutCacheSummary(
            workoutCount: workouts.count,
            totalDistanceMeters: workouts.reduce(0) { $0 + $1.distanceMeters }
        )
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func rollbackQuarantinedFiles(
        _ quarantinedMoves: [(originalURL: URL, quarantineURL: URL)]
    ) {
        for move in quarantinedMoves.reversed() {
            guard FileManager.default.fileExists(atPath: move.quarantineURL.path),
                  !FileManager.default.fileExists(atPath: move.originalURL.path) else {
                continue
            }

            do {
                try FileManager.default.moveItem(
                    at: move.quarantineURL,
                    to: move.originalURL
                )
            } catch {
                PTrackLog.cache.debug(
                    "PTrack Cache: failed to roll back quarantined file \(move.quarantineURL.lastPathComponent): \(error)"
                )
            }
        }
    }

}

private struct WorkoutCacheManifest: Codable {
    let version: Int
    let workoutIDs: [String]
    let summary: WorkoutCacheSummary?
}

private enum WorkoutCacheValidationError: Error {
    case reconciliationRequired(String)
    case invalidSnapshot(String)

    var reason: String {
        switch self {
        case .reconciliationRequired(let reason), .invalidSnapshot(let reason):
            return reason
        }
    }

    var persistenceResult: WorkoutCachePersistenceResult {
        switch self {
        case .reconciliationRequired:
            return .reconciliationRequired
        case .invalidSnapshot:
            return .invalidSnapshot
        }
    }
}
