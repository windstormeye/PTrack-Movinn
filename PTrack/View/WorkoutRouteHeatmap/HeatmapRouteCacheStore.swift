//
//  HeatmapRouteCacheStore.swift
//  PTrack
//
//  Created by Codex on 2026/7/6.
//

import CoreLocation
import Foundation
import HealthKit
import MapKit

struct HeatmapRouteCacheSnapshot {
    let routes: [HeatmapRoute]
    let statisticWorkouts: [TrackedWorkout]
    let isComplete: Bool
}

final class HeatmapRouteCacheStore {
    static let shared = HeatmapRouteCacheStore()

    private static let currentCacheVersion = 2
    private let cacheVersion = HeatmapRouteCacheStore.currentCacheVersion
    private let cacheLock = NSLock()
    private let ioQueue = DispatchQueue(label: "studio.pj.PTrack.heatmap-route-cache", qos: .utility)
    private var hasLoadedDiskCache = false
    private var cachedRoutesByID: [String: CachedHeatmapRoute] = [:]
    private var heatmapRoutesByID: [String: HeatmapRoute] = [:]
    private var statisticWorkoutsByID: [String: TrackedWorkout] = [:]
    private var statisticWorkoutIDs = Set<String>()
    private var isStatisticCacheComplete = false

    private let manifestFileURL: URL
    private let statisticsFileURL: URL
    private let routesDirectoryURL: URL

    private init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directoryURL = baseURL.appendingPathComponent("PTrack", isDirectory: true)
        manifestFileURL = directoryURL.appendingPathComponent("heatmap-route-index.json")
        statisticsFileURL = directoryURL.appendingPathComponent("heatmap-statistics.json")
        routesDirectoryURL = directoryURL
            .appendingPathComponent("heatmap-routes", isDirectory: true)
        try? FileManager.default.createDirectory(at: routesDirectoryURL, withIntermediateDirectories: true)
    }

    func prewarmCompleteRouteCache() {
        ioQueue.async { [weak self] in
            self?.loadDiskCacheIfNeeded()
        }
    }

    func cachedRouteSnapshot(currentWorkoutIDs: Set<String>?) -> HeatmapRouteCacheSnapshot {
        loadDiskCacheIfNeeded()

        let manifest = loadManifest()
        let manifestRouteOrder = Dictionary(
            uniqueKeysWithValues: (manifest?.routeIDs ?? []).enumerated().map { ($0.element, $0.offset) }
        )

        cacheLock.lock()
        let routes = heatmapRoutesByID.values
            .sorted { lhs, rhs in
                let lhsOrder = manifestRouteOrder[lhs.id] ?? Int.max
                let rhsOrder = manifestRouteOrder[rhs.id] ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }

                return lhs.id < rhs.id
        }
        let cachedRouteIDs = Set(routes.map(\.id))
        let statisticWorkouts = statisticWorkoutsByID.values
            .sorted { $0.startDate > $1.startDate }
        cacheLock.unlock()

        let isRouteCacheComplete = Self.isManifestComplete(
            manifest,
            currentWorkoutIDs: currentWorkoutIDs,
            cachedRouteIDs: cachedRouteIDs
        )
        let isStatisticCacheComplete = Self.isStatisticsComplete(
            workoutIDs: statisticWorkoutIDs,
            isComplete: isStatisticCacheComplete,
            currentWorkoutIDs: currentWorkoutIDs
        )
        return HeatmapRouteCacheSnapshot(
            routes: routes,
            statisticWorkouts: statisticWorkouts,
            isComplete: isRouteCacheComplete && isStatisticCacheComplete
        )
    }

    func cachedRoute(
        for workout: TrackedWorkout,
        samplingRatio: Double,
        maximumPointCount: Int
    ) -> HeatmapRoute? {
        loadDiskCacheIfNeeded()

        let signature = HeatmapRouteSignature(
            workout: workout,
            samplingRatio: samplingRatio,
            maximumPointCount: maximumPointCount
        )

        cacheLock.lock()
        let cachedRoute = cachedRoutesByID[workout.id]
        let heatmapRoute = heatmapRoutesByID[workout.id]
        cacheLock.unlock()

        guard cachedRoute?.version == cacheVersion,
              cachedRoute?.signature == signature else {
            return nil
        }

        if let heatmapRoute {
            return heatmapRoute
        }

        guard let route = cachedRoute?.heatmapRoute() else {
            return nil
        }

        cacheLock.lock()
        heatmapRoutesByID[workout.id] = route
        cacheLock.unlock()
        return route
    }

    func store(
        _ route: HeatmapRoute,
        for workout: TrackedWorkout,
        samplingRatio: Double,
        maximumPointCount: Int
    ) {
        let cachedRoute = CachedHeatmapRoute(
            version: cacheVersion,
            route: route,
            signature: HeatmapRouteSignature(
                workout: workout,
                samplingRatio: samplingRatio,
                maximumPointCount: maximumPointCount
            )
        )

        cacheLock.lock()
        cachedRoutesByID[route.id] = cachedRoute
        heatmapRoutesByID[route.id] = route
        cacheLock.unlock()

        ioQueue.sync {
            writeRoute(cachedRoute)
        }
    }

    func removeRoute(id: String) {
        cacheLock.lock()
        cachedRoutesByID.removeValue(forKey: id)
        heatmapRoutesByID.removeValue(forKey: id)
        statisticWorkoutsByID.removeValue(forKey: id)
        let statisticWorkouts = sortedStatisticWorkouts()
        let cachedStatisticWorkoutIDs = statisticWorkoutIDs
        let isStatisticCacheComplete = isStatisticCacheComplete
        cacheLock.unlock()

        let fileURL = routeFileURL(for: id)
        ioQueue.async { [statisticWorkouts, cachedStatisticWorkoutIDs, isStatisticCacheComplete] in
            self.removeManifestIfNeeded()
            self.writeStatistics(
                statisticWorkouts,
                workoutIDs: cachedStatisticWorkoutIDs,
                isComplete: isStatisticCacheComplete
            )
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return
            }

            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("PTrack Heatmap Cache: failed to remove route \(id): \(error)")
            }
        }
    }

    func storeStatisticWorkouts(
        _ workouts: [TrackedWorkout],
        processedWorkoutIDs: Set<String>,
        isComplete: Bool
    ) {
        guard !workouts.isEmpty else {
            return
        }

        loadDiskCacheIfNeeded()

        cacheLock.lock()
        for workout in workouts {
            statisticWorkoutsByID[workout.id] = workout
        }
        statisticWorkoutIDs.formUnion(processedWorkoutIDs)
        isStatisticCacheComplete = isComplete
        let statisticWorkouts = sortedStatisticWorkouts()
        let cachedStatisticWorkoutIDs = statisticWorkoutIDs
        cacheLock.unlock()

        ioQueue.sync {
            writeStatistics(
                statisticWorkouts,
                workoutIDs: cachedStatisticWorkoutIDs,
                isComplete: isComplete
            )
        }
    }

    func markStatisticWorkoutsComplete(workoutIDs: Set<String>) {
        loadDiskCacheIfNeeded()

        cacheLock.lock()
        statisticWorkoutIDs.formUnion(workoutIDs)
        isStatisticCacheComplete = true
        let statisticWorkouts = sortedStatisticWorkouts()
        let cachedStatisticWorkoutIDs = statisticWorkoutIDs
        cacheLock.unlock()

        ioQueue.sync {
            writeStatistics(
                statisticWorkouts,
                workoutIDs: cachedStatisticWorkoutIDs,
                isComplete: true
            )
        }
    }

    func markRouteSetComplete(workoutIDs: Set<String>) {
        writeRouteSetManifest(workoutIDs: workoutIDs, isComplete: true)
    }

    func markRouteSetProgress(workoutIDs: Set<String>) {
        writeRouteSetManifest(workoutIDs: workoutIDs, isComplete: false)
    }

    private func writeRouteSetManifest(workoutIDs: Set<String>, isComplete: Bool) {
        loadDiskCacheIfNeeded()

        cacheLock.lock()
        let routeIDs = cachedRoutesByID.keys
            .filter { workoutIDs.contains($0) }
            .sorted()
        cacheLock.unlock()

        let manifest = CachedHeatmapRouteManifest(
            version: cacheVersion,
            updatedAt: Date(),
            workoutIDs: workoutIDs.sorted(),
            routeIDs: routeIDs,
            isComplete: isComplete
        )
        ioQueue.sync {
            writeManifest(manifest)
        }
    }

    private func writeRoute(_ route: CachedHeatmapRoute) {
        do {
            try FileManager.default.createDirectory(
                at: routesDirectoryURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(route)
            try data.write(to: routeFileURL(for: route.id), options: [.atomic])
        } catch {
            print("PTrack Heatmap Cache: failed to store route \(route.id): \(error)")
        }
    }

    private func writeManifest(_ manifest: CachedHeatmapRouteManifest) {
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: manifestFileURL, options: [.atomic])
        } catch {
            print("PTrack Heatmap Cache: failed to write route manifest: \(error)")
        }
    }

    private func writeStatistics(
        _ workouts: [TrackedWorkout],
        workoutIDs: Set<String>,
        isComplete: Bool
    ) {
        do {
            let statistics = CachedHeatmapStatistics(
                version: cacheVersion,
                updatedAt: Date(),
                workoutIDs: workoutIDs.sorted(),
                workouts: workouts,
                isComplete: isComplete
            )
            let data = try JSONEncoder().encode(statistics)
            try data.write(to: statisticsFileURL, options: [.atomic])
        } catch {
            print("PTrack Heatmap Cache: failed to write statistics: \(error)")
        }
    }

    private static func isManifestComplete(
        _ manifest: CachedHeatmapRouteManifest?,
        currentWorkoutIDs: Set<String>?,
        cachedRouteIDs: Set<String>
    ) -> Bool {
        guard let manifest,
              manifest.version == currentCacheVersion,
              manifest.isComplete == true else {
            return false
        }

        let manifestWorkoutIDs = Set(manifest.workoutIDs)
        if let currentWorkoutIDs,
           !currentWorkoutIDs.isSubset(of: manifestWorkoutIDs) {
            return false
        }

        let expectedRouteIDs = Set(manifest.routeIDs).filter {
            currentWorkoutIDs?.contains($0) ?? true
        }
        return expectedRouteIDs.isSubset(of: cachedRouteIDs)
    }

    private static func isStatisticsComplete(
        workoutIDs: Set<String>,
        isComplete: Bool,
        currentWorkoutIDs: Set<String>?
    ) -> Bool {
        guard isComplete else {
            return false
        }

        guard let currentWorkoutIDs else {
            return !workoutIDs.isEmpty
        }

        return currentWorkoutIDs.isSubset(of: workoutIDs)
    }

    func pruneRoutes(keeping validWorkoutIDs: Set<String>) {
        loadDiskCacheIfNeeded()

        cacheLock.lock()
        let staleIDs = Set(cachedRoutesByID.keys).subtracting(validWorkoutIDs)
        let staleStatisticIDs = Set(statisticWorkoutsByID.keys).subtracting(validWorkoutIDs)
        statisticWorkoutIDs = statisticWorkoutIDs.intersection(validWorkoutIDs)
        for routeID in staleIDs {
            cachedRoutesByID.removeValue(forKey: routeID)
            heatmapRoutesByID.removeValue(forKey: routeID)
        }
        for workoutID in staleStatisticIDs {
            statisticWorkoutsByID.removeValue(forKey: workoutID)
        }
        let statisticWorkouts = sortedStatisticWorkouts()
        let cachedStatisticWorkoutIDs = statisticWorkoutIDs
        let isStatisticCacheComplete = isStatisticCacheComplete
        cacheLock.unlock()

        guard !staleIDs.isEmpty || !staleStatisticIDs.isEmpty else {
            return
        }

        ioQueue.async { [staleIDs, statisticWorkouts, cachedStatisticWorkoutIDs, isStatisticCacheComplete] in
            self.writeStatistics(
                statisticWorkouts,
                workoutIDs: cachedStatisticWorkoutIDs,
                isComplete: isStatisticCacheComplete
            )
            for routeID in staleIDs {
                let fileURL = self.routeFileURL(for: routeID)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    continue
                }

                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    print("PTrack Heatmap Cache: failed to prune route \(routeID): \(error)")
                }
            }
        }
    }

    private func loadDiskCacheIfNeeded() {
        cacheLock.lock()
        guard !hasLoadedDiskCache else {
            cacheLock.unlock()
            return
        }

        hasLoadedDiskCache = true
        let fileURLs = existingRouteFileURLs()
        var loadedCachedRoutes: [String: CachedHeatmapRoute] = [:]
        var loadedHeatmapRoutes: [String: HeatmapRoute] = [:]
        let loadedStatistics = loadStatistics()
        loadedCachedRoutes.reserveCapacity(fileURLs.count)
        loadedHeatmapRoutes.reserveCapacity(fileURLs.count)

        for fileURL in fileURLs {
            do {
                let data = try Data(contentsOf: fileURL)
                let cachedRoute = try JSONDecoder().decode(CachedHeatmapRoute.self, from: data)
                guard cachedRoute.version == cacheVersion,
                      let heatmapRoute = cachedRoute.heatmapRoute() else {
                    continue
                }

                loadedCachedRoutes[cachedRoute.id] = cachedRoute
                loadedHeatmapRoutes[cachedRoute.id] = heatmapRoute
            } catch {
                print("PTrack Heatmap Cache: failed to decode route \(fileURL.lastPathComponent): \(error)")
            }
        }

        cachedRoutesByID.merge(loadedCachedRoutes) { current, _ in current }
        heatmapRoutesByID.merge(loadedHeatmapRoutes) { current, _ in current }
        statisticWorkoutsByID.merge(loadedStatistics.workoutsByID) { current, _ in current }
        statisticWorkoutIDs.formUnion(loadedStatistics.workoutIDs)
        isStatisticCacheComplete = loadedStatistics.isComplete
        cacheLock.unlock()
    }

    private func loadStatistics() -> (
        workoutsByID: [String: TrackedWorkout],
        workoutIDs: Set<String>,
        isComplete: Bool
    ) {
        guard let data = try? Data(contentsOf: statisticsFileURL) else {
            return ([:], [], false)
        }

        do {
            let statistics = try JSONDecoder().decode(CachedHeatmapStatistics.self, from: data)
            guard statistics.version == cacheVersion else {
                return ([:], [], false)
            }

            let workoutsByID = Dictionary(
                statistics.workouts.map { ($0.id, $0) },
                uniquingKeysWith: { current, _ in current }
            )
            let workoutIDs = Set(statistics.workoutIDs ?? Array(workoutsByID.keys))
            return (
                workoutsByID,
                workoutIDs,
                statistics.isComplete ?? false
            )
        } catch {
            print("PTrack Heatmap Cache: failed to decode statistics: \(error)")
            return ([:], [], false)
        }
    }

    private func loadManifest() -> CachedHeatmapRouteManifest? {
        guard let data = try? Data(contentsOf: manifestFileURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(CachedHeatmapRouteManifest.self, from: data)
        } catch {
            print("PTrack Heatmap Cache: failed to decode route manifest: \(error)")
            return nil
        }
    }

    private func removeManifestIfNeeded() {
        guard FileManager.default.fileExists(atPath: manifestFileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: manifestFileURL)
        } catch {
            print("PTrack Heatmap Cache: failed to remove route manifest: \(error)")
        }
    }

    private func existingRouteFileURLs() -> [URL] {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: routesDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return fileURLs
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func routeFileURL(for id: String) -> URL {
        routesDirectoryURL
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

    private func sortedStatisticWorkouts() -> [TrackedWorkout] {
        statisticWorkoutsByID.values.sorted { $0.startDate > $1.startDate }
    }
}

nonisolated private struct CachedHeatmapStatistics: Codable {
    let version: Int
    let updatedAt: Date
    let workoutIDs: [String]?
    let workouts: [TrackedWorkout]
    let isComplete: Bool?
}

nonisolated private struct CachedHeatmapRouteManifest: Codable {
    let version: Int
    let updatedAt: Date
    let workoutIDs: [String]
    let routeIDs: [String]
    let isComplete: Bool?
}

nonisolated private struct CachedHeatmapRoute: Codable {
    let version: Int
    let id: String
    let coordinates: [CachedHeatmapCoordinate]
    let boundingMapRect: CachedHeatmapMapRect
    let sportKindRawValue: String
    let startYear: Int
    let signature: HeatmapRouteSignature

    init(
        version: Int,
        route: HeatmapRoute,
        signature: HeatmapRouteSignature
    ) {
        self.version = version
        id = route.id
        coordinates = route.coordinates.map(CachedHeatmapCoordinate.init)
        boundingMapRect = CachedHeatmapMapRect(route.boundingMapRect)
        sportKindRawValue = route.sportKind.rawValue
        startYear = route.startYear
        self.signature = signature
    }

    func heatmapRoute() -> HeatmapRoute? {
        guard let sportKind = TrackedWorkoutSportKind(rawValue: sportKindRawValue) else {
            return nil
        }

        let coordinates = coordinates.map(\.coordinate)
        guard coordinates.count > 1 else {
            return nil
        }

        return HeatmapRoute(
            id: id,
            coordinates: coordinates,
            boundingMapRect: boundingMapRect.mapRect,
            sportKind: sportKind,
            startYear: startYear
        )
    }
}

nonisolated private struct HeatmapRouteSignature: Codable, Equatable {
    let workoutID: String
    let sportKindRawValue: String
    let startDate: Date
    let distanceMeters: Int
    let durationSeconds: Int?
    let coordinateCount: Int
    let firstCoordinate: CachedHeatmapCoordinate?
    let middleCoordinate: CachedHeatmapCoordinate?
    let lastCoordinate: CachedHeatmapCoordinate?
    let coordinateFingerprint: UInt64
    let samplingRatioKey: Int
    let maximumPointCount: Int

    init(
        workout: TrackedWorkout,
        samplingRatio: Double,
        maximumPointCount: Int
    ) {
        let sourceCoordinates = workout.coordinates
        workoutID = workout.id
        sportKindRawValue = Self.sportKindRawValue(for: workout)
        startDate = workout.startDate
        distanceMeters = Int(workout.distanceMeters.rounded())
        durationSeconds = workout.durationSeconds.map { Int($0.rounded()) }
        coordinateCount = sourceCoordinates.count
        firstCoordinate = sourceCoordinates.first.map { CachedHeatmapCoordinate($0.coordinate) }
        middleCoordinate = sourceCoordinates.isEmpty
            ? nil
            : CachedHeatmapCoordinate(sourceCoordinates[sourceCoordinates.count / 2].coordinate)
        lastCoordinate = sourceCoordinates.last.map { CachedHeatmapCoordinate($0.coordinate) }
        coordinateFingerprint = Self.coordinateFingerprint(for: sourceCoordinates)
        samplingRatioKey = Int((samplingRatio * 1_000).rounded())
        self.maximumPointCount = maximumPointCount
    }

    private static func coordinateFingerprint(for coordinates: [RouteCoordinate]) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for coordinate in coordinates {
            combine(quantized(coordinate.latitude), into: &hash)
            combine(quantized(coordinate.longitude), into: &hash)
        }
        return hash
    }

    private static func quantized(_ value: Double) -> Int64 {
        guard value.isFinite else {
            return 0
        }

        return Int64((value * 10_000_000).rounded())
    }

    private static func combine(_ value: Int64, into hash: inout UInt64) {
        hash ^= UInt64(bitPattern: value)
        hash &*= 1_099_511_628_211
    }

    private static func sportKindRawValue(for workout: TrackedWorkout) -> String {
        switch workout.metadata?["strava.sportType"]?.stringValue {
        case "Run":
            return TrackedWorkoutSportKind.running.rawValue
        case "TrailRun":
            return TrackedWorkoutSportKind.trailRunning.rawValue
        case "Walk":
            return TrackedWorkoutSportKind.walking.rawValue
        case "Hike":
            return TrackedWorkoutSportKind.hiking.rawValue
        case "Swim":
            return TrackedWorkoutSportKind.outdoorSwimming.rawValue
        case "VirtualRide":
            return TrackedWorkoutSportKind.virtualCycling.rawValue
        case "VirtualRun":
            return TrackedWorkoutSportKind.virtualRunning.rawValue
        default:
            break
        }

        switch HKWorkoutActivityType(rawValue: workout.activityTypeRawValue) ?? .other {
        case .cycling:
            return TrackedWorkoutSportKind.cycling.rawValue
        case .hiking:
            return TrackedWorkoutSportKind.hiking.rawValue
        case .walking:
            return TrackedWorkoutSportKind.walking.rawValue
        case .running:
            return TrackedWorkoutSportKind.running.rawValue
        case .swimming:
            return TrackedWorkoutSportKind.outdoorSwimming.rawValue
        default:
            return TrackedWorkoutSportKind.outdoorWorkout.rawValue
        }
    }
}

nonisolated private struct CachedHeatmapCoordinate: Codable, Equatable {
    let latitude: Int
    let longitude: Int

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = Int((coordinate.latitude * 10_000_000).rounded())
        longitude = Int((coordinate.longitude * 10_000_000).rounded())
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double(latitude) / 10_000_000,
            longitude: Double(longitude) / 10_000_000
        )
    }
}

nonisolated private struct CachedHeatmapMapRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ mapRect: MKMapRect) {
        x = mapRect.origin.x
        y = mapRect.origin.y
        width = mapRect.size.width
        height = mapRect.size.height
    }

    var mapRect: MKMapRect {
        MKMapRect(x: x, y: y, width: width, height: height)
    }
}
