//
//  RouteCollectionMerger.swift
//  PTrack
//
//  Created by Codex on 2026/6/20.
//

import CoreLocation
import Foundation

enum RouteCollectionMergerError: LocalizedError {
    case noRoutes
    case noRoutePoints

    var errorDescription: String? {
        switch self {
        case .noRoutes:
            return AppLocalization.text(.routeMergeNoRoutes)
        case .noRoutePoints:
            return AppLocalization.text(.gpxExportNoRoute)
        }
    }
}

enum RouteCollectionMerger {
    static func mergedRoute(
        from workouts: [TrackedWorkout],
        importedAt: Date = Date()
    ) throws -> TrackedWorkout {
        guard !workouts.isEmpty else {
            throw RouteCollectionMergerError.noRoutes
        }

        let orderedWorkouts = orderedWorkouts(from: workouts)
        let mergedCoordinates = normalizedMergedCoordinates(from: orderedWorkouts)

        guard !mergedCoordinates.isEmpty else {
            throw RouteCollectionMergerError.noRoutePoints
        }

        return TrackedWorkout(
            routeCollectionID: UUID().uuidString,
            title: mergedTitle(for: orderedWorkouts),
            sourceName: TrackedWorkout.routeCollectionMergeSourceName,
            sourceURL: nil,
            importedAt: importedAt,
            coordinates: mergedCoordinates,
            distanceMeters: totalDistanceMeters(for: orderedWorkouts),
            durationSeconds: totalDurationSeconds(for: orderedWorkouts),
            startDate: orderedWorkouts.first?.startDate,
            activityTypeRawValue: orderedWorkouts.first?.activityTypeRawValue,
            additionalMetadata: mergeMetadata(for: orderedWorkouts)
        )
    }

    private static func orderedWorkouts(from workouts: [TrackedWorkout]) -> [TrackedWorkout] {
        workouts
            .enumerated()
            .filter { !$0.element.routeDetailCoordinates.isEmpty }
            .sorted { lhs, rhs in
                if lhs.element.startDate != rhs.element.startDate {
                    return lhs.element.startDate < rhs.element.startDate
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func normalizedMergedCoordinates(from workouts: [TrackedWorkout]) -> [RouteCoordinate] {
        var mergedCoordinates: [RouteCoordinate] = []

        for workout in workouts {
            let sourceCoordinates = workout.routeDetailCoordinates
            guard let sourceStart = sourceCoordinates.first?.timestamp else {
                continue
            }

            let targetStart = mergedCoordinates.last?.timestamp ?? sourceStart

            for coordinate in sourceCoordinates {
                let elapsed = max(coordinate.timestamp.timeIntervalSince(sourceStart), 0)
                let normalizedTimestamp = targetStart.addingTimeInterval(elapsed)
                let normalizedCoordinate = coordinate.copy(timestamp: normalizedTimestamp)
                mergedCoordinates.append(normalizedCoordinate)
            }
        }

        return mergedCoordinates
    }

    private static func totalDistanceMeters(for workouts: [TrackedWorkout]) -> Double {
        workouts.reduce(0) { total, workout in
            if workout.distanceMeters > 0 {
                return total + workout.distanceMeters
            }

            return total + distanceMeters(for: workout.routeDetailCoordinates)
        }
    }

    private static func totalDurationSeconds(for workouts: [TrackedWorkout]) -> TimeInterval {
        workouts.reduce(0) { total, workout in
            if let durationSeconds = workout.durationSeconds, durationSeconds > 0 {
                return total + durationSeconds
            }

            guard let startDate = workout.routeDetailCoordinates.first?.timestamp,
                  let endDate = workout.routeDetailCoordinates.last?.timestamp else {
                return total
            }

            return total + max(endDate.timeIntervalSince(startDate), 0)
        }
    }

    private static func distanceMeters(for coordinates: [RouteCoordinate]) -> Double {
        guard coordinates.count > 1 else {
            return 0
        }

        var totalDistance: CLLocationDistance = 0
        var previousLocation = CLLocation(
            latitude: coordinates[0].latitude,
            longitude: coordinates[0].longitude
        )

        for coordinate in coordinates.dropFirst() {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            totalDistance += location.distance(from: previousLocation)
            previousLocation = location
        }

        return totalDistance
    }

    private static func mergeMetadata(for workouts: [TrackedWorkout]) -> [String: TrackedMetadataValue] {
        var metadata: [String: TrackedMetadataValue] = [:]

        if let startCoordinate = workouts.first?.routeDetailCoordinates.first?.coordinate {
            metadata["routeCollection.merge.startLatitude"] = TrackedMetadataValue(
                type: "number",
                doubleValue: startCoordinate.latitude
            )
            metadata["routeCollection.merge.startLongitude"] = TrackedMetadataValue(
                type: "number",
                doubleValue: startCoordinate.longitude
            )
        }

        if let endCoordinate = workouts.last?.routeDetailCoordinates.last?.coordinate {
            metadata["routeCollection.merge.endLatitude"] = TrackedMetadataValue(
                type: "number",
                doubleValue: endCoordinate.latitude
            )
            metadata["routeCollection.merge.endLongitude"] = TrackedMetadataValue(
                type: "number",
                doubleValue: endCoordinate.longitude
            )
        }

        let segmentStartDates = workouts.map { workout in
            workout.startDate.timeIntervalSince1970
        }
        let segmentEndDates = workouts.map { workout in
            let endDate = workout.endDate
                ?? workout.startDate.addingTimeInterval(workout.durationSeconds ?? 0)
            return endDate.timeIntervalSince1970
        }

        metadata["routeCollection.merge.segmentStartDates"] = TrackedMetadataValue(
            type: "numberArray",
            numberArrayValue: segmentStartDates
        )
        metadata["routeCollection.merge.segmentEndDates"] = TrackedMetadataValue(
            type: "numberArray",
            numberArrayValue: segmentEndDates
        )

        let mergedElevationGainMeters = workouts.reduce(0) { total, workout in
            total + (workout.displayElevationGainMeters ?? elevationGainMeters(for: workout.routeDetailCoordinates))
        }
        if mergedElevationGainMeters > 0 {
            metadata["routeCollection.merge.elevationGainMeters"] = TrackedMetadataValue(
                type: "number",
                doubleValue: mergedElevationGainMeters
            )
        }

        return metadata
    }

    private static func elevationGainMeters(for coordinates: [RouteCoordinate]) -> Double {
        let altitudes = coordinates.compactMap(\.altitudeMeters)
        guard altitudes.count > 1 else {
            return 0
        }

        var gain: Double = 0
        var previousAltitude = altitudes[0]
        for altitude in altitudes.dropFirst() {
            let delta = altitude - previousAltitude
            if delta > 0 {
                gain += delta
            }
            previousAltitude = altitude
        }
        return gain
    }

    private static func mergedTitle(for workouts: [TrackedWorkout]) -> String {
        workouts.first?.title.nilIfBlank ?? AppLocalization.text(.routeMergeDefaultTitle)
    }
}

private extension RouteCoordinate {
    func copy(timestamp: Date) -> RouteCoordinate {
        RouteCoordinate(
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            altitudeMeters: altitudeMeters,
            verticalAccuracyMeters: verticalAccuracyMeters,
            speedMetersPerSecond: speedMetersPerSecond,
            speedAccuracyMetersPerSecond: speedAccuracyMetersPerSecond,
            courseDegrees: courseDegrees,
            courseAccuracyDegrees: courseAccuracyDegrees,
            floorLevel: floorLevel
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
