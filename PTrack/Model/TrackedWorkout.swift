//
//  TrackedWorkout.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import CoreLocation
import Foundation
import HealthKit
import UIKit

struct TrackedWorkout: Codable {
    nonisolated static let currentHealthDataVersion = 2

    let id: String
    let healthDataVersion: Int?
    let activityTypeRawValue: UInt
    let startDate: Date
    let endDate: Date?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double
    let totalEnergyBurnedKilocalories: Double?
    let sourceRevision: TrackedWorkoutSourceRevision?
    let device: TrackedWorkoutDevice?
    let metadata: [String: TrackedMetadataValue]?
    let workoutEvents: [TrackedWorkoutEvent]?
    let routeSegments: [TrackedWorkoutRouteSegment]?
    let routeSummary: TrackedRouteSummary?
    let quantityMetrics: [TrackedWorkoutQuantityMetric]?
    let coordinates: [RouteCoordinate]

    nonisolated init(
        workout: HKWorkout,
        locations: [CLLocation],
        routeSegments: [TrackedWorkoutRouteSegment] = [],
        quantityMetrics: [TrackedWorkoutQuantityMetric] = []
    ) {
        id = workout.uuid.uuidString
        healthDataVersion = Self.currentHealthDataVersion
        activityTypeRawValue = workout.workoutActivityType.rawValue
        startDate = workout.startDate
        endDate = workout.endDate
        durationSeconds = workout.duration
        distanceMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        totalEnergyBurnedKilocalories = quantityMetrics.first {
            $0.identifier == HKQuantityTypeIdentifier.activeEnergyBurned.rawValue
        }?.sum
        sourceRevision = TrackedWorkoutSourceRevision(sourceRevision: workout.sourceRevision)
        device = workout.device.map(TrackedWorkoutDevice.init)
        metadata = TrackedMetadata.values(from: workout.metadata)

        let events = workout.workoutEvents ?? []
        workoutEvents = events.isEmpty ? nil : events.map(TrackedWorkoutEvent.init)
        self.routeSegments = routeSegments.isEmpty ? nil : routeSegments
        self.quantityMetrics = quantityMetrics.isEmpty ? nil : quantityMetrics

        let sampledCoordinates = RouteSampler.downsample(locations.map(RouteCoordinate.init), limit: 1_200)
        routeSummary = TrackedRouteSummary(
            locations: locations,
            sampledCoordinateCount: sampledCoordinates.count
        )
        coordinates = sampledCoordinates
    }

    var activityType: HKWorkoutActivityType {
        HKWorkoutActivityType(rawValue: activityTypeRawValue) ?? .other
    }

    var needsHealthDataRefresh: Bool {
        healthDataVersion != Self.currentHealthDataVersion
    }

    var stravaActivityID: Int64? {
        if let value = metadata?["strava.id"]?.stringValue,
           let activityID = Int64(value) {
            return activityID
        }

        let idPrefix = "strava-"
        if id.hasPrefix(idPrefix),
           let activityID = Int64(id.dropFirst(idPrefix.count)) {
            return activityID
        }

        let bundlePrefix = "com.strava.activity."
        if let bundleIdentifier = sourceRevision?.bundleIdentifier,
           bundleIdentifier.hasPrefix(bundlePrefix),
           let activityID = Int64(bundleIdentifier.dropFirst(bundlePrefix.count)) {
            return activityID
        }

        return nil
    }

    var isStravaSource: Bool {
        stravaActivityID != nil || sourceRevision?.sourceName == "Strava"
    }

    var stravaSportType: String? {
        metadata?["strava.sportType"]?.stringValue
    }

    var routeDataSourceTitle: String {
        if isStravaSource {
            return AppLocalization.text(.strava)
        }

        return AppLocalization.text(.appleHealth)
    }

    var title: String {
        switch stravaSportType {
        case "Run":
            return AppLocalization.text(.running)
        case "TrailRun":
            return AppLocalization.text(.trailRunning)
        case "Walk":
            return AppLocalization.text(.walking)
        case "Hike":
            return AppLocalization.text(.hiking)
        case "Swim":
            return AppLocalization.text(.outdoorSwimming)
        case "VirtualRide":
            return AppLocalization.text(.virtualCycling)
        case "VirtualRun":
            return AppLocalization.text(.virtualRunning)
        default:
            break
        }

        switch activityType {
        case .cycling:
            return AppLocalization.text(.cycling)
        case .hiking:
            return AppLocalization.text(.hiking)
        case .walking:
            return AppLocalization.text(.walking)
        case .running:
            return AppLocalization.text(.running)
        case .swimming:
            return AppLocalization.text(.outdoorSwimming)
        default:
            return AppLocalization.text(.outdoorWorkout)
        }
    }

    var symbolName: String {
        switch stravaSportType {
        case "TrailRun":
            return "figure.walk.motion"
        case "Hike":
            return "figure.hiking"
        case "VirtualRide":
            return "figure.indoor.cycle"
        default:
            break
        }

        switch activityType {
        case .cycling:
            return "figure.outdoor.cycle"
        case .handCycling:
            return "figure.hand.cycling"
        case .hiking:
            return "figure.hiking"
        case .walking:
            return "figure.walk"
        case .running:
            return "figure.run"
        case .swimming:
            return "figure.open.water.swim"
        case .paddleSports:
            return "figure.paddleboarding"
        case .rowing:
            return "figure.rower"
        case .sailing:
            return "sailboat"
        case .surfingSports:
            return "figure.surfing"
        case .snowSports:
            return "snowflake"
        case .skatingSports:
            return "figure.skating"
        default:
            return "figure.walk"
        }
    }

    var routeColor: UIColor {
        .black
    }

    var activeEnergyBurnedKilocalories: Double? {
        quantityMetric(for: HKQuantityTypeIdentifier.activeEnergyBurned.rawValue)?.sum ?? totalEnergyBurnedKilocalories
    }

    var distanceText: String {
        if distanceMeters >= 1000 {
            return String(format: "%.2f km", distanceMeters / 1000)
        } else if distanceMeters > 0 {
            return AppLocalization.format(.distanceMetersFormat, distanceMeters)
        } else {
            return AppLocalization.text(.unknownDistance)
        }
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startDate)
    }

    var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard let endDate else {
            return formatter.string(from: startDate)
        }

        let endFormatter = DateFormatter()
        endFormatter.dateFormat = Calendar.current.isDate(startDate, inSameDayAs: endDate) ? "HH:mm" : "yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: startDate)) - \(endFormatter.string(from: endDate))"
    }

    var durationText: String {
        guard let durationSeconds, durationSeconds > 0 else {
            return AppLocalization.text(.unknownDuration)
        }

        let totalMinutes = Int(durationSeconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return AppLocalization.format(.durationHoursMinutesFormat, hours, minutes)
        }
        return AppLocalization.format(.durationMinutesFormat, max(minutes, 1))
    }

    var displayCoordinates: [CLLocationCoordinate2D] {
        CoordinateTransformer.displayCoordinates(for: coordinates.map(\.coordinate))
    }

    private func quantityMetric(for identifier: String) -> TrackedWorkoutQuantityMetric? {
        quantityMetrics?.first { $0.identifier == identifier }
    }
}
