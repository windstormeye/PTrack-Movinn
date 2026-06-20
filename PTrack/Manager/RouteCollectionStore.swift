//
//  RouteCollectionStore.swift
//  PTrack
//
//  Created by Codex on 2026/6/17.
//

import CoreLocation
import Foundation
import HealthKit

final class RouteCollectionStore {
    static let didChangeNotification = Notification.Name("studio.pj.PTrack.routeCollectionDidChange")

    private let directoryURL: URL
    private let manifestFileURL: URL
    private let routesDirectoryURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = baseURL
            .appendingPathComponent("PTrack", isDirectory: true)
            .appendingPathComponent("route-collection", isDirectory: true)
        manifestFileURL = directoryURL.appendingPathComponent("route-index.json")
        routesDirectoryURL = directoryURL.appendingPathComponent("routes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func load() -> [TrackedWorkout] {
        if let splitRoutes = loadSplitCache() {
            return splitRoutes
        }

        return []
    }

    @discardableResult
    func append(_ workout: TrackedWorkout) -> [TrackedWorkout] {
        append([workout])
    }

    @discardableResult
    func append(_ workouts: [TrackedWorkout]) -> [TrackedWorkout] {
        guard !workouts.isEmpty else {
            return load()
        }

        var routes = load()
        routes.append(contentsOf: workouts)
        routes = deduplicated(sorted(routes))
        save(routes)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: routes)
        RouteCollectionCloudSyncCoordinator.shared.handleRoutesAppended(workouts)
        return routes
    }

    func save(_ routes: [TrackedWorkout]) {
        do {
            try FileManager.default.createDirectory(at: routesDirectoryURL, withIntermediateDirectories: true)

            let normalizedRoutes = deduplicated(sorted(routes))
            var currentFileNames = Set<String>()
            var writtenRouteFileCount = 0

            for route in normalizedRoutes {
                let fileURL = routeFileURL(for: route.id)
                currentFileNames.insert(fileURL.lastPathComponent)

                let data = try JSONEncoder().encode(route)
                if (try? Data(contentsOf: fileURL)) != data {
                    try data.write(to: fileURL, options: [.atomic])
                    writtenRouteFileCount += 1
                }
            }

            let removedRouteFileCount = removeStaleRouteFiles(currentFileNames: currentFileNames)
            let manifest = RouteCollectionCacheManifest(
                version: 1,
                routeIDs: normalizedRoutes.map(\.id)
            )
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestFileURL, options: [.atomic])

            print(
                "PTrack Route Collection: saved \(normalizedRoutes.count) routes, written files: \(writtenRouteFileCount), removed files: \(removedRouteFileCount), path: \(routesDirectoryURL.path)"
            )
        } catch {
            print("PTrack Route Collection: failed to save routes: \(error)")
        }
    }

    @discardableResult
    func replace(with routes: [TrackedWorkout]) -> [TrackedWorkout] {
        let normalizedRoutes = deduplicated(sorted(routes))
        guard !routesAreEquivalent(load(), normalizedRoutes) else {
            return normalizedRoutes
        }

        save(normalizedRoutes)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: normalizedRoutes)
        return normalizedRoutes
    }

    @discardableResult
    func delete(_ workout: TrackedWorkout) -> [TrackedWorkout] {
        var routes = load()
        let originalCount = routes.count
        routes.removeAll { $0.id == workout.id }

        guard routes.count != originalCount else {
            return routes
        }

        save(routes)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: routes)
        RouteCollectionCloudSyncCoordinator.shared.handleRouteDeleted(workout)
        return routes
    }

    private func sorted(_ routes: [TrackedWorkout]) -> [TrackedWorkout] {
        routes.sorted {
            let lhsDate = $0.routeCollectionImportedAt ?? $0.startDate
            let rhsDate = $1.routeCollectionImportedAt ?? $1.startDate
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }

            return $0.startDate > $1.startDate
        }
    }

    private func deduplicated(_ routes: [TrackedWorkout]) -> [TrackedWorkout] {
        var seenIDs = Set<String>()
        return routes.filter { seenIDs.insert($0.id).inserted }
    }

    private func loadSplitCache() -> [TrackedWorkout]? {
        let manifest = loadManifest()
        let fileURLs: [URL]

        if let manifest {
            fileURLs = manifest.routeIDs.map(routeFileURL(for:))
        } else {
            fileURLs = existingRouteFileURLs()
            guard !fileURLs.isEmpty else {
                return nil
            }
        }

        var routes: [TrackedWorkout] = []
        routes.reserveCapacity(fileURLs.count)

        for fileURL in fileURLs {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("PTrack Route Collection: missing route cache file: \(fileURL.path)")
                continue
            }

            do {
                let data = try Data(contentsOf: fileURL)
                let route = try JSONDecoder().decode(TrackedWorkout.self, from: data)
                routes.append(route)
            } catch {
                print("PTrack Route Collection: failed to decode route cache file \(fileURL.lastPathComponent): \(error)")
            }
        }

        let sortedRoutes = sorted(routes)
        print(
            "PTrack Route Collection: loaded \(sortedRoutes.count) routes, files: \(fileURLs.count), size: \(Self.formattedByteCount(totalSplitCacheByteCount())), path: \(routesDirectoryURL.path)"
        )
        return sortedRoutes
    }

    private func loadManifest() -> RouteCollectionCacheManifest? {
        guard let data = try? Data(contentsOf: manifestFileURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(RouteCollectionCacheManifest.self, from: data)
        } catch {
            print("PTrack Route Collection: failed to decode route cache manifest: \(error)")
            return nil
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

    private func routeFileURL(for routeID: String) -> URL {
        routesDirectoryURL.appendingPathComponent(Self.routeFileName(for: routeID), isDirectory: false)
    }

    private func removeStaleRouteFiles(currentFileNames: Set<String>) -> Int {
        var removedFileCount = 0
        for fileURL in existingRouteFileURLs() where !currentFileNames.contains(fileURL.lastPathComponent) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                removedFileCount += 1
            } catch {
                print("PTrack Route Collection: failed to remove stale route file \(fileURL.lastPathComponent): \(error)")
            }
        }

        return removedFileCount
    }

    private func totalSplitCacheByteCount() -> Int64 {
        existingRouteFileURLs().reduce(Int64(0)) { total, fileURL in
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values?.fileSize ?? 0)
        }
    }

    private static func routeFileName(for routeID: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let escapedID = routeID.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? routeID
        return "\(escapedID).json"
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func routesAreEquivalent(_ lhs: [TrackedWorkout], _ rhs: [TrackedWorkout]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        let encoder = JSONEncoder()
        return (try? encoder.encode(lhs)) == (try? encoder.encode(rhs))
    }
}

private struct RouteCollectionCacheManifest: Codable {
    let version: Int
    let routeIDs: [String]
}

enum SharedRouteImportInbox {
    static let appGroupIdentifier = "group.studio.pj.app.PTrack"
    static let pendingRoutesDidChangeNotification = Notification.Name("studio.pj.PTrack.pendingSharedRoutesDidChange")
    static let openRouteCollectionNotification = Notification.Name("studio.pj.PTrack.openRouteCollection")

    private static let unseenRouteKey = "studio.pj.PTrack.routeCollection.hasUnseenSharedRoute"
    private static let newRouteIDsKey = "studio.pj.PTrack.routeCollection.newRouteIDs"
    private static let routeCollectionOpenRequestKey = "studio.pj.PTrack.routeCollection.openRequestPending"
    private static let pendingDirectoryName = "PendingRoutes"

    static var hasUnseenRoute: Bool {
        sharedDefaults.bool(forKey: unseenRouteKey)
    }

    static var hasNewRouteBadges: Bool {
        !newRouteIDs.isEmpty
    }

    static var hasPendingRouteCollectionOpenRequest: Bool {
        sharedDefaults.bool(forKey: routeCollectionOpenRequestKey)
    }

    static func hasNewRouteBadge(for workout: TrackedWorkout) -> Bool {
        newRouteIDs.contains(workout.id)
    }

    static func markNewRouteAvailable(for routes: [TrackedWorkout] = []) {
        if !routes.isEmpty {
            var ids = newRouteIDs
            ids.formUnion(routes.map(\.id))
            setNewRouteIDs(ids)
        }

        sharedDefaults.set(true, forKey: unseenRouteKey)
        NotificationCenter.default.post(name: pendingRoutesDidChangeNotification, object: nil)
    }

    static func requestRouteCollectionOpen() {
        sharedDefaults.set(true, forKey: routeCollectionOpenRequestKey)
        NotificationCenter.default.post(name: openRouteCollectionNotification, object: nil)
    }

    @discardableResult
    static func consumeRouteCollectionOpenRequest() -> Bool {
        guard hasPendingRouteCollectionOpenRequest else {
            return false
        }

        sharedDefaults.set(false, forKey: routeCollectionOpenRequestKey)
        return true
    }

    static func markRoutePromptSeen() {
        guard hasUnseenRoute else {
            return
        }

        sharedDefaults.set(false, forKey: unseenRouteKey)
        NotificationCenter.default.post(name: pendingRoutesDidChangeNotification, object: nil)
    }

    static func clearNewRouteBadge(for workout: TrackedWorkout) {
        var ids = newRouteIDs
        guard ids.remove(workout.id) != nil else {
            return
        }

        setNewRouteIDs(ids)
        NotificationCenter.default.post(name: pendingRoutesDidChangeNotification, object: nil)
    }

    static func clearRouteImportIndicators() {
        let hadUnseenRoute = hasUnseenRoute
        let hadNewRouteBadges = hasNewRouteBadges
        guard hadUnseenRoute || hadNewRouteBadges else {
            return
        }

        sharedDefaults.set(false, forKey: unseenRouteKey)
        setNewRouteIDs([])
        NotificationCenter.default.post(name: pendingRoutesDidChangeNotification, object: nil)
    }

    static func pendingGPXFileURLs() -> [URL] {
        guard let directoryURL = pendingDirectoryURL,
              let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return fileURLs
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @discardableResult
    static func importPendingRoutes(store: RouteCollectionStore = RouteCollectionStore()) -> [TrackedWorkout] {
        let pendingFiles = pendingGPXFileURLs()
        guard !pendingFiles.isEmpty else {
            return []
        }

        var importedRoutes: [TrackedWorkout] = []
        for fileURL in pendingFiles {
            do {
                let route = try makeRoute(fromGPXAt: fileURL)
                importedRoutes.append(route)
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("PTrack Route Collection: failed to import shared GPX \(fileURL.lastPathComponent): \(error)")
                try? FileManager.default.removeItem(at: fileURL)
            }
        }

        guard !importedRoutes.isEmpty else {
            return []
        }

        store.append(importedRoutes)
        markNewRouteAvailable(for: importedRoutes)
        return importedRoutes
    }

    static func makeRoute(fromGPXAt fileURL: URL, importedAt: Date = Date()) throws -> TrackedWorkout {
        let data = try Data(contentsOf: fileURL)
        let parsedRoute = try GPXRouteParser.parse(data: data, fallbackDate: importedAt)
        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
        return TrackedWorkout(
            routeCollectionID: UUID().uuidString,
            title: parsedRoute.title?.nilIfBlank ?? fallbackTitle,
            sourceName: TrackedWorkout.routeCollectionImportSourceName,
            sourceURL: fileURL,
            importedAt: importedAt,
            coordinates: parsedRoute.coordinates
        )
    }

    static var pendingDirectoryURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            let fallbackURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PTrack", isDirectory: true)
                .appendingPathComponent("SharedRouteImports", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallbackURL, withIntermediateDirectories: true)
            return fallbackURL
        }

        let pendingURL = containerURL.appendingPathComponent(pendingDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        return pendingURL
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    private static var newRouteIDs: Set<String> {
        Set(sharedDefaults.stringArray(forKey: newRouteIDsKey) ?? [])
    }

    private static func setNewRouteIDs(_ ids: Set<String>) {
        sharedDefaults.set(Array(ids).sorted(), forKey: newRouteIDsKey)
    }
}

extension TrackedWorkout {
    nonisolated static let routeCollectionImportSourceName = "GPX"
    nonisolated static let routeCollectionMergeSourceName = "Route Merge"

    nonisolated init(
        routeCollectionID: String,
        title: String,
        sourceName: String,
        sourceURL: URL?,
        importedAt: Date,
        coordinates rawCoordinates: [RouteCoordinate],
        distanceMeters distanceMetersOverride: Double? = nil,
        durationSeconds durationSecondsOverride: TimeInterval? = nil,
        startDate startDateOverride: Date? = nil,
        activityTypeRawValue activityTypeRawValueOverride: UInt? = nil,
        additionalMetadata: [String: TrackedMetadataValue] = [:]
    ) {
        let sampledCoordinates = RouteSampler.downsample(rawCoordinates, limit: 1_200)
        let startDate = startDateOverride ?? rawCoordinates.first?.timestamp ?? importedAt
        let computedEndDate = rawCoordinates.last?.timestamp
        let computedDurationSeconds = computedEndDate.map { max($0.timeIntervalSince(startDate), 0) }
        let durationSeconds = durationSecondsOverride ?? computedDurationSeconds
        let endDate = durationSeconds.map { startDate.addingTimeInterval($0) } ?? computedEndDate
        let distanceMeters = distanceMetersOverride ?? Self.routeCollectionDistanceMeters(for: rawCoordinates)
        var metadata = Self.routeCollectionMetadata(
            id: routeCollectionID,
            title: title,
            sourceName: sourceName,
            sourceURL: sourceURL,
            importedAt: importedAt
        )
        metadata.merge(additionalMetadata) { _, newValue in newValue }

        id = "route-collection-\(routeCollectionID)"
        healthDataVersion = Self.currentHealthDataVersion
        activityTypeRawValue = activityTypeRawValueOverride ?? HKWorkoutActivityType.other.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        totalEnergyBurnedKilocalories = nil
        sourceRevision = TrackedWorkoutSourceRevision(routeCollectionSourceName: sourceName)
        device = nil
        self.metadata = metadata
        workoutEvents = nil
        routeSegments = nil
        routeSummary = TrackedRouteSummary(
            routeCollectionCoordinates: rawCoordinates,
            sampledCoordinateCount: sampledCoordinates.count,
            measuredDistanceMeters: distanceMeters
        )
        quantityMetrics = nil
        coordinates = sampledCoordinates
        fullCoordinates = Self.fullCoordinatesIfSampled(
            rawCoordinates: rawCoordinates,
            sampledCoordinates: sampledCoordinates
        )
    }

    var isRouteCollectionSource: Bool {
        metadata?["routeCollection.id"]?.stringValue != nil
            || sourceRevision?.bundleIdentifier == "studio.pj.app.PTrack.routeCollection"
    }

    var isMergedRouteCollectionSource: Bool {
        routeCollectionSourceName == Self.routeCollectionMergeSourceName
    }

    var routeCollectionSourceName: String? {
        metadata?["routeCollection.sourceName"]?.stringValue ?? sourceRevision?.productType
    }

    var routeCollectionTitle: String? {
        metadata?["routeCollection.title"]?.stringValue?.nilIfBlank
    }

    var routeCollectionImportedAt: Date? {
        metadata?["routeCollection.importedAt"]?.dateValue
    }

    var routeCollectionMergeStartCoordinate: CLLocationCoordinate2D? {
        routeCollectionMergeCoordinate(
            latitudeKey: "routeCollection.merge.startLatitude",
            longitudeKey: "routeCollection.merge.startLongitude"
        )
    }

    var routeCollectionMergeEndCoordinate: CLLocationCoordinate2D? {
        routeCollectionMergeCoordinate(
            latitudeKey: "routeCollection.merge.endLatitude",
            longitudeKey: "routeCollection.merge.endLongitude"
        )
    }

    var routeCollectionMergePhotoDateRanges: [(start: Date, end: Date)] {
        guard isMergedRouteCollectionSource,
              let startValues = metadata?["routeCollection.merge.segmentStartDates"]?.numberArrayValue,
              let endValues = metadata?["routeCollection.merge.segmentEndDates"]?.numberArrayValue else {
            return []
        }

        return zip(startValues, endValues).compactMap { startValue, endValue in
            let startDate = Date(timeIntervalSince1970: startValue)
            let endDate = Date(timeIntervalSince1970: endValue)
            guard endDate >= startDate else {
                return nil
            }

            return (startDate, endDate)
        }
    }

    private nonisolated static func routeCollectionMetadata(
        id: String,
        title: String,
        sourceName: String,
        sourceURL: URL?,
        importedAt: Date
    ) -> [String: TrackedMetadataValue] {
        var metadata: [String: TrackedMetadataValue] = [
            "routeCollection.id": TrackedMetadataValue(type: "string", stringValue: id),
            "routeCollection.title": TrackedMetadataValue(type: "string", stringValue: title),
            "routeCollection.sourceName": TrackedMetadataValue(type: "string", stringValue: sourceName),
            "routeCollection.importedAt": TrackedMetadataValue(type: "date", dateValue: importedAt)
        ]

        if let sourceURL {
            metadata["routeCollection.sourceURL"] = TrackedMetadataValue(
                type: "string",
                stringValue: sourceURL.absoluteString
            )
        }

        return metadata
    }

    private func routeCollectionMergeCoordinate(
        latitudeKey: String,
        longitudeKey: String
    ) -> CLLocationCoordinate2D? {
        guard let latitude = metadata?[latitudeKey]?.doubleValue,
              let longitude = metadata?[longitudeKey]?.doubleValue else {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        return coordinate
    }

    private nonisolated static func routeCollectionDistanceMeters(for coordinates: [RouteCoordinate]) -> Double {
        guard coordinates.count > 1 else {
            return 0
        }

        var totalDistance: CLLocationDistance = 0
        var previousLocation = CLLocation(
            latitude: coordinates[0].latitude,
            longitude: coordinates[0].longitude
        )

        for coordinate in coordinates.dropFirst() {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            totalDistance += location.distance(from: previousLocation)
            previousLocation = location
        }

        return totalDistance
    }
}

extension TrackedWorkoutSourceRevision {
    nonisolated init(routeCollectionSourceName sourceName: String) {
        self.sourceName = "Imported Routes"
        bundleIdentifier = "studio.pj.app.PTrack.routeCollection"
        version = nil
        productType = sourceName
        operatingSystemVersion = "local"
    }
}

extension TrackedRouteSummary {
    nonisolated init(
        routeCollectionCoordinates coordinates: [RouteCoordinate],
        sampledCoordinateCount: Int,
        measuredDistanceMeters: Double?
    ) {
        rawLocationCount = coordinates.count
        self.sampledCoordinateCount = sampledCoordinateCount
        self.measuredDistanceMeters = measuredDistanceMeters

        let altitudes = coordinates.compactMap(\.altitudeMeters)
        minimumAltitudeMeters = altitudes.min()
        maximumAltitudeMeters = altitudes.max()

        let elevationChange = Self.routeCollectionElevationChange(for: altitudes)
        elevationGainMeters = elevationChange.gain
        elevationLossMeters = elevationChange.loss
        averageSpeedMetersPerSecond = nil
        maximumSpeedMetersPerSecond = nil
    }

    private nonisolated static func routeCollectionElevationChange(for altitudes: [Double]) -> (gain: Double?, loss: Double?) {
        guard altitudes.count > 1 else {
            return (nil, nil)
        }

        var gain: Double = 0
        var loss: Double = 0
        var previousAltitude = altitudes[0]

        for altitude in altitudes.dropFirst() {
            let delta = altitude - previousAltitude
            if delta > 0 {
                gain += delta
            } else {
                loss += abs(delta)
            }
            previousAltitude = altitude
        }

        return (gain, loss)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
