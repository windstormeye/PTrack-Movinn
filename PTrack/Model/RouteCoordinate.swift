//
//  RouteCoordinate.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import CoreLocation
import Foundation

struct RouteCoordinate: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    /// Source-provided cumulative distance along the route, when available.
    let sourceDistanceMeters: Double?
    let horizontalAccuracyMeters: Double?
    let altitudeMeters: Double?
    let verticalAccuracyMeters: Double?
    /// Signed physical grade ratio. For example, `0.12` represents a 12% climb.
    let gradeRatio: Double?
    let speedMetersPerSecond: Double?
    let speedAccuracyMetersPerSecond: Double?
    let courseDegrees: Double?
    let courseAccuracyDegrees: Double?
    let floorLevel: Int?
    let heartRateBeatsPerMinute: Double?
    let powerWatts: Double?
    let temperatureCelsius: Double?

    nonisolated init(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        sourceDistanceMeters: Double? = nil,
        horizontalAccuracyMeters: Double? = nil,
        altitudeMeters: Double? = nil,
        verticalAccuracyMeters: Double? = nil,
        gradeRatio: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        speedAccuracyMetersPerSecond: Double? = nil,
        courseDegrees: Double? = nil,
        courseAccuracyDegrees: Double? = nil,
        floorLevel: Int? = nil,
        heartRateBeatsPerMinute: Double? = nil,
        powerWatts: Double? = nil,
        temperatureCelsius: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.sourceDistanceMeters = sourceDistanceMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.altitudeMeters = altitudeMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.gradeRatio = gradeRatio
        self.speedMetersPerSecond = speedMetersPerSecond
        self.speedAccuracyMetersPerSecond = speedAccuracyMetersPerSecond
        self.courseDegrees = courseDegrees
        self.courseAccuracyDegrees = courseAccuracyDegrees
        self.floorLevel = floorLevel
        self.heartRateBeatsPerMinute = heartRateBeatsPerMinute
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
    }

    nonisolated init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        sourceDistanceMeters = nil
        horizontalAccuracyMeters = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        altitudeMeters = location.verticalAccuracy >= 0 ? location.altitude : nil
        verticalAccuracyMeters = location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
        gradeRatio = nil
        speedMetersPerSecond = location.speed >= 0 ? location.speed : nil
        speedAccuracyMetersPerSecond = location.speedAccuracy >= 0 ? location.speedAccuracy : nil
        courseDegrees = location.course >= 0 ? location.course : nil
        courseAccuracyDegrees = location.courseAccuracy >= 0 ? location.courseAccuracy : nil
        floorLevel = location.floor?.level
        heartRateBeatsPerMinute = nil
        powerWatts = nil
        temperatureCelsius = nil
    }

    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    nonisolated var hasAltitude: Bool {
        altitudeMeters != nil
    }
}
