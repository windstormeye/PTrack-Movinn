//
//  DemoModeSampleData.swift
//  PTrack
//
//  Created by Codex on 2026/7/8.
//

import CoreLocation
import Foundation
import HealthKit

enum DemoModeSampleData {
    static var workouts: [TrackedWorkout] {
        makeWorkouts().sorted { $0.startDate > $1.startDate }
    }

    private static func makeWorkouts() -> [TrackedWorkout] {
        [
            makeChangAnAvenueRun(),
            makeSecondRingRide()
        ]
    }

    private static func makeChangAnAvenueRun() -> TrackedWorkout {
        let startDate = demoDate(daysAgo: 1, hour: 7, minute: 18)
        let duration: TimeInterval = 68 * 60
        let coordinates = routeCoordinates(
            controlPoints: [
                Coordinate(latitude: 39.9077, longitude: 116.3015),
                Coordinate(latitude: 39.9078, longitude: 116.3402),
                Coordinate(latitude: 39.9084, longitude: 116.3848),
                Coordinate(latitude: 39.9087, longitude: 116.3975),
                Coordinate(latitude: 39.9089, longitude: 116.4212),
                Coordinate(latitude: 39.9092, longitude: 116.4758)
            ],
            startDate: startDate,
            duration: duration,
            targetPointCount: 96,
            altitudeBase: 42,
            altitudeAmplitude: 7,
            heartRateBase: 151
        )

        return makeWorkout(
            id: "demo-beijing-changan-avenue",
            activityType: .running,
            stravaSportType: "Run",
            startDate: startDate,
            duration: duration,
            totalEnergyBurnedKilocalories: 620,
            coordinates: coordinates
        )
    }

    private static func makeSecondRingRide() -> TrackedWorkout {
        let startDate = demoDate(daysAgo: 9, hour: 16, minute: 4)
        let duration: TimeInterval = 96 * 60
        let coordinates = routeCoordinates(
            controlPoints: [
                Coordinate(latitude: 39.9493, longitude: 116.3570),
                Coordinate(latitude: 39.9490, longitude: 116.3960),
                Coordinate(latitude: 39.9410, longitude: 116.4330),
                Coordinate(latitude: 39.9080, longitude: 116.4335),
                Coordinate(latitude: 39.8850, longitude: 116.4140),
                Coordinate(latitude: 39.8788, longitude: 116.3930),
                Coordinate(latitude: 39.8840, longitude: 116.3575),
                Coordinate(latitude: 39.9075, longitude: 116.3470),
                Coordinate(latitude: 39.9360, longitude: 116.3480),
                Coordinate(latitude: 39.9493, longitude: 116.3570)
            ],
            startDate: startDate,
            duration: duration,
            targetPointCount: 180,
            altitudeBase: 48,
            altitudeAmplitude: 11,
            heartRateBase: 133
        )

        return makeWorkout(
            id: "demo-beijing-second-ring",
            activityType: .cycling,
            stravaSportType: "Ride",
            startDate: startDate,
            duration: duration,
            totalEnergyBurnedKilocalories: 920,
            coordinates: coordinates
        )
    }

    private static func makeWorkout(
        id: String,
        activityType: HKWorkoutActivityType,
        stravaSportType: String,
        startDate: Date,
        duration: TimeInterval,
        totalEnergyBurnedKilocalories: Double,
        coordinates: [RouteCoordinate]
    ) -> TrackedWorkout {
        let sampledCoordinates = RouteSampler.downsample(coordinates, limit: 1_200)
        let locations = coordinates.map(Self.location)
        let distanceMeters = distanceMeters(for: locations)
        let routeSummary = TrackedRouteSummary(
            locations: locations,
            sampledCoordinateCount: sampledCoordinates.count
        )

        return TrackedWorkout(
            id: id,
            healthDataVersion: TrackedWorkout.currentHealthDataVersion,
            activityTypeRawValue: activityType.rawValue,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            durationSeconds: duration,
            distanceMeters: distanceMeters,
            totalEnergyBurnedKilocalories: totalEnergyBurnedKilocalories,
            sourceRevision: TrackedWorkoutSourceRevision(demoSourceName: "Movinn Demo"),
            device: nil,
            metadata: [
                "demo.mode": TrackedMetadataValue(type: "bool", boolValue: true),
                "strava.sportType": TrackedMetadataValue(type: "string", stringValue: stravaSportType)
            ],
            workoutEvents: nil,
            routeSegments: nil,
            routeSummary: routeSummary,
            quantityMetrics: [
                TrackedWorkoutQuantityMetric(
                    identifier: HKQuantityTypeIdentifier.heartRate.rawValue,
                    unit: "count/min",
                    sum: nil,
                    average: coordinates.compactMap(\.heartRateBeatsPerMinute).average,
                    minimum: coordinates.compactMap(\.heartRateBeatsPerMinute).min(),
                    maximum: coordinates.compactMap(\.heartRateBeatsPerMinute).max()
                )
            ],
            coordinates: sampledCoordinates,
            fullCoordinates: TrackedWorkout.fullCoordinatesIfSampled(
                rawCoordinates: coordinates,
                sampledCoordinates: sampledCoordinates
            )
        )
    }

    private static func routeCoordinates(
        controlPoints: [Coordinate],
        startDate: Date,
        duration: TimeInterval,
        targetPointCount: Int,
        altitudeBase: Double,
        altitudeAmplitude: Double,
        heartRateBase: Double
    ) -> [RouteCoordinate] {
        let points = interpolatedPoints(from: controlPoints, targetPointCount: targetPointCount)
        let denominator = max(points.count - 1, 1)
        return points.enumerated().map { index, point in
            let progress = Double(index) / Double(denominator)
            let timestamp = startDate.addingTimeInterval(duration * progress)
            let wave = sin(progress * Double.pi * 2)
            return RouteCoordinate(
                latitude: point.latitude,
                longitude: point.longitude,
                timestamp: timestamp,
                horizontalAccuracyMeters: 6,
                altitudeMeters: altitudeBase + altitudeAmplitude * wave,
                verticalAccuracyMeters: 8,
                speedMetersPerSecond: nil,
                speedAccuracyMetersPerSecond: nil,
                courseDegrees: nil,
                courseAccuracyDegrees: nil,
                floorLevel: nil,
                heartRateBeatsPerMinute: heartRateBase + 8 * sin(progress * Double.pi * 3),
                powerWatts: nil,
                temperatureCelsius: 24 + 2 * wave
            )
        }
    }

    private static func interpolatedPoints(
        from controlPoints: [Coordinate],
        targetPointCount: Int
    ) -> [Coordinate] {
        guard controlPoints.count > 1 else {
            return controlPoints
        }

        let segmentLengths = zip(controlPoints, controlPoints.dropFirst()).map { start, end in
            CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        }
        let totalLength = max(segmentLengths.reduce(0, +), 1)
        var points: [Coordinate] = []

        for index in 0..<(controlPoints.count - 1) {
            let start = controlPoints[index]
            let end = controlPoints[index + 1]
            let segmentFraction = segmentLengths[index] / totalLength
            let segmentPointCount = max(Int(round(Double(targetPointCount) * segmentFraction)), 2)
            for step in 0..<segmentPointCount {
                if !points.isEmpty, step == 0 {
                    continue
                }

                let progress = Double(step) / Double(max(segmentPointCount - 1, 1))
                points.append(Coordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * progress,
                    longitude: start.longitude + (end.longitude - start.longitude) * progress
                ))
            }
        }

        return points
    }

    private static func demoDate(daysAgo: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let targetDay = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: calendar.component(.year, from: targetDay),
                month: calendar.component(.month, from: targetDay),
                day: calendar.component(.day, from: targetDay),
                hour: hour,
                minute: minute
            )
        ) ?? targetDay
    }

    private nonisolated static func location(for coordinate: RouteCoordinate) -> CLLocation {
        CLLocation(
            coordinate: coordinate.coordinate,
            altitude: coordinate.altitudeMeters ?? 0,
            horizontalAccuracy: coordinate.horizontalAccuracyMeters ?? 8,
            verticalAccuracy: coordinate.verticalAccuracyMeters ?? 10,
            course: coordinate.courseDegrees ?? -1,
            speed: coordinate.speedMetersPerSecond ?? -1,
            timestamp: coordinate.timestamp
        )
    }

    private static func distanceMeters(for locations: [CLLocation]) -> Double {
        guard locations.count > 1 else {
            return 0
        }

        var totalDistance: CLLocationDistance = 0
        var previousLocation = locations[0]
        for location in locations.dropFirst() {
            totalDistance += location.distance(from: previousLocation)
            previousLocation = location
        }
        return totalDistance
    }

    private struct Coordinate {
        let latitude: Double
        let longitude: Double
    }
}

private extension TrackedWorkoutSourceRevision {
    nonisolated init(demoSourceName sourceName: String) {
        self.sourceName = sourceName
        bundleIdentifier = "studio.pj.app.PTrack.demo"
        version = nil
        productType = "Demo"
        operatingSystemVersion = "local"
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else {
            return nil
        }

        return reduce(0, +) / Double(count)
    }
}
