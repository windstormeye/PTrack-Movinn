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

    var title: String {
        switch activityType {
        case .cycling:
            return "骑行"
        case .hiking:
            return "徒步"
        case .walking:
            return "行走"
        case .running:
            return "跑步"
        default:
            return "户外运动"
        }
    }

    var symbolName: String {
        switch activityType {
        case .cycling:
            return "figure.outdoor.cycle"
        case .hiking, .walking:
            return "figure.walk"
        case .running:
            return "figure.run"
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
            return String(format: "%.0f m", distanceMeters)
        } else {
            return "未知距离"
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
            return "未知时长"
        }

        let totalMinutes = Int(durationSeconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        }
        return "\(max(minutes, 1))分钟"
    }

    var displayCoordinates: [CLLocationCoordinate2D] {
        CoordinateTransformer.displayCoordinates(for: coordinates.map(\.coordinate))
    }

    private func quantityMetric(for identifier: String) -> TrackedWorkoutQuantityMetric? {
        quantityMetrics?.first { $0.identifier == identifier }
    }
}
