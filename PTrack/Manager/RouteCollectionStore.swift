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
    private let fileURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = baseURL
            .appendingPathComponent("PTrack", isDirectory: true)
            .appendingPathComponent("route-collection", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("routes.json")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func load() -> [TrackedWorkout] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        do {
            return sorted(try JSONDecoder().decode([TrackedWorkout].self, from: data))
        } catch {
            print("PTrack Route Collection: failed to decode routes: \(error)")
            return []
        }
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
        return routes
    }

    func save(_ routes: [TrackedWorkout]) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(deduplicated(sorted(routes)))
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("PTrack Route Collection: failed to save routes: \(error)")
        }
    }

    private func sorted(_ routes: [TrackedWorkout]) -> [TrackedWorkout] {
        routes.sorted { $0.startDate > $1.startDate }
    }

    private func deduplicated(_ routes: [TrackedWorkout]) -> [TrackedWorkout] {
        var seenIDs = Set<String>()
        return routes.filter { seenIDs.insert($0.id).inserted }
    }
}

enum SharedRouteImportInbox {
    static let appGroupIdentifier = "group.studio.pj.app.PTrack"
    static let pendingRoutesDidChangeNotification = Notification.Name("studio.pj.PTrack.pendingSharedRoutesDidChange")
    static let openRouteCollectionNotification = Notification.Name("studio.pj.PTrack.openRouteCollection")

    private static let unseenRouteKey = "studio.pj.PTrack.routeCollection.hasUnseenSharedRoute"
    private static let pendingDirectoryName = "PendingRoutes"

    static var hasUnseenRoute: Bool {
        sharedDefaults.bool(forKey: unseenRouteKey)
    }

    static func markNewRouteAvailable() {
        sharedDefaults.set(true, forKey: unseenRouteKey)
        NotificationCenter.default.post(name: pendingRoutesDidChangeNotification, object: nil)
    }

    static func markRoutePromptSeen() {
        guard hasUnseenRoute else {
            return
        }

        sharedDefaults.set(false, forKey: unseenRouteKey)
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
        markNewRouteAvailable()
        return importedRoutes
    }

    static func makeRoute(fromGPXAt fileURL: URL, importedAt: Date = Date()) throws -> TrackedWorkout {
        let data = try Data(contentsOf: fileURL)
        let parsedRoute = try GPXRouteParser.parse(data: data, fallbackDate: importedAt)
        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
        return TrackedWorkout(
            routeCollectionID: UUID().uuidString,
            title: parsedRoute.title?.nilIfBlank ?? fallbackTitle,
            sourceName: "GPX",
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
}

extension TrackedWorkout {
    nonisolated init(
        routeCollectionID: String,
        title: String,
        sourceName: String,
        sourceURL: URL?,
        importedAt: Date,
        coordinates rawCoordinates: [RouteCoordinate]
    ) {
        let sampledCoordinates = RouteSampler.downsample(rawCoordinates, limit: 1_200)
        let startDate = rawCoordinates.first?.timestamp ?? importedAt
        let endDate = rawCoordinates.last?.timestamp
        let distanceMeters = Self.routeCollectionDistanceMeters(for: rawCoordinates)
        let durationSeconds = endDate.map { max($0.timeIntervalSince(startDate), 0) }
        let metadata = Self.routeCollectionMetadata(
            id: routeCollectionID,
            title: title,
            sourceName: sourceName,
            sourceURL: sourceURL,
            importedAt: importedAt
        )

        id = "route-collection-\(routeCollectionID)"
        healthDataVersion = Self.currentHealthDataVersion
        activityTypeRawValue = HKWorkoutActivityType.other.rawValue
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
    }

    var isRouteCollectionSource: Bool {
        metadata?["routeCollection.id"]?.stringValue != nil
            || sourceRevision?.bundleIdentifier == "studio.pj.app.PTrack.routeCollection"
    }

    var routeCollectionTitle: String? {
        metadata?["routeCollection.title"]?.stringValue?.nilIfBlank
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
        self.sourceName = "Route Collection"
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
