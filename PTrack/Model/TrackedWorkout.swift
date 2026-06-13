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
    let id: String
    let activityTypeRawValue: UInt
    let startDate: Date
    let endDate: Date?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double
    let coordinates: [RouteCoordinate]

    init(workout: HKWorkout, locations: [CLLocation]) {
        id = workout.uuid.uuidString
        activityTypeRawValue = workout.workoutActivityType.rawValue
        startDate = workout.startDate
        endDate = workout.endDate
        durationSeconds = workout.duration
        distanceMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        coordinates = RouteSampler.downsample(locations.map(RouteCoordinate.init), limit: 1_200)
    }

    var activityType: HKWorkoutActivityType {
        HKWorkoutActivityType(rawValue: activityTypeRawValue) ?? .other
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
        switch activityType {
        case .cycling:
            return .systemRed
        case .hiking, .walking:
            return .systemGreen
        case .running:
            return .systemYellow
        default:
            return .systemBlue
        }
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
        coordinates.map { CoordinateTransformer.displayCoordinate(for: $0.coordinate) }
    }
}
