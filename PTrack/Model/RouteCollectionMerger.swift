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
        let mergedSegmentCoordinateCounts = orderedWorkouts.flatMap(segmentCoordinateCounts)

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
            segmentCoordinateCounts: mergedSegmentCoordinateCounts,
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
            // Recompute collection routes from their canonical segment
            // boundaries. Older merged/GPX caches may contain a summary that
            // accidentally included the jump between segments.
            if !workout.isRouteCollectionSource, workout.distanceMeters > 0 {
                return total + workout.distanceMeters
            }

            return total + distanceMeters(for: workout)
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

    private static func distanceMeters(for workout: TrackedWorkout) -> Double {
        let coordinates = workout.routeDetailCoordinates
        guard coordinates.count > 1 else {
            return 0
        }

        let segmentStartIndices = workout.routeDetailSegmentStartIndices
        var totalDistance: CLLocationDistance = 0
        var previousLocation = CLLocation(
            latitude: coordinates[0].latitude,
            longitude: coordinates[0].longitude
        )

        for index in 1..<coordinates.count {
            let coordinate = coordinates[index]
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if !segmentStartIndices.contains(index) {
                totalDistance += location.distance(from: previousLocation)
            }
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

        let photoDateRanges = workouts.flatMap(originalPhotoDateRanges)
        let segmentStartDates = photoDateRanges.map { $0.start.timeIntervalSince1970 }
        let segmentEndDates = photoDateRanges.map { $0.end.timeIntervalSince1970 }

        metadata["routeCollection.merge.segmentStartDates"] = TrackedMetadataValue(
            type: "numberArray",
            numberArrayValue: segmentStartDates
        )
        metadata["routeCollection.merge.segmentEndDates"] = TrackedMetadataValue(
            type: "numberArray",
            numberArrayValue: segmentEndDates
        )
        metadata["routeCollection.merge.segmentCoordinateCounts"] = TrackedMetadataValue(
            type: "numberArray",
            numberArrayValue: workouts.flatMap(segmentCoordinateCounts).map(Double.init)
        )

        let mergedElevationGainMeters = workouts.reduce(0) { total, workout in
            if workout.isRouteCollectionSource {
                return total + elevationGainMeters(for: workout)
            }
            return total + (workout.displayElevationGainMeters ?? elevationGainMeters(for: workout))
        }
        if mergedElevationGainMeters > 0 {
            metadata["routeCollection.merge.elevationGainMeters"] = TrackedMetadataValue(
                type: "number",
                doubleValue: mergedElevationGainMeters
            )
        }

        return metadata
    }

    private nonisolated static func originalPhotoDateRanges(
        for workout: TrackedWorkout
    ) -> [(start: Date, end: Date)] {
        let nestedDateRanges = workout.routeCollectionMergePhotoDateRanges
        if workout.isMergedRouteCollectionSource, !nestedDateRanges.isEmpty {
            return nestedDateRanges
        }

        let startDate = workout.startDate
        let candidateEndDate = workout.endDate
            ?? startDate.addingTimeInterval(max(workout.durationSeconds ?? 0, 0))
        return [(startDate, max(candidateEndDate, startDate))]
    }

    private nonisolated static func segmentCoordinateCounts(
        for workout: TrackedWorkout
    ) -> [Int] {
        let coordinateCount = workout.routeDetailCoordinates.count
        guard coordinateCount > 0 else {
            return []
        }

        let boundaries = [0] + workout.routeDetailSegmentStartIndices
            .filter { $0 > 0 && $0 < coordinateCount }
            .sorted() + [coordinateCount]
        return zip(boundaries, boundaries.dropFirst()).compactMap {
            lowerBound, upperBound in
            let count = upperBound - lowerBound
            return count > 0 ? count : nil
        }
    }

    private static func elevationGainMeters(for workout: TrackedWorkout) -> Double {
        let coordinates = workout.routeDetailCoordinates
        guard coordinates.count > 1 else {
            return 0
        }

        let segmentStartIndices = workout.routeDetailSegmentStartIndices
        var gain: Double = 0
        var previousAltitude: Double?

        for (index, coordinate) in coordinates.enumerated() {
            if segmentStartIndices.contains(index) {
                previousAltitude = nil
            }

            guard let altitude = coordinate.altitudeMeters,
                  altitude.isFinite else {
                previousAltitude = nil
                continue
            }

            if let previousAltitude {
                let delta = altitude - previousAltitude
                if delta > 0 {
                    gain += delta
                }
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
            sourceDistanceMeters: sourceDistanceMeters,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            altitudeMeters: altitudeMeters,
            verticalAccuracyMeters: verticalAccuracyMeters,
            gradeRatio: gradeRatio,
            speedMetersPerSecond: speedMetersPerSecond,
            speedAccuracyMetersPerSecond: speedAccuracyMetersPerSecond,
            courseDegrees: courseDegrees,
            courseAccuracyDegrees: courseAccuracyDegrees,
            floorLevel: floorLevel,
            heartRateBeatsPerMinute: heartRateBeatsPerMinute,
            powerWatts: powerWatts,
            temperatureCelsius: temperatureCelsius
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
