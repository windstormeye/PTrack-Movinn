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
    let altitudeMeters: Double?
    let verticalAccuracyMeters: Double?

    nonisolated init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        altitudeMeters = location.verticalAccuracy >= 0 ? location.altitude : nil
        verticalAccuracyMeters = location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasAltitude: Bool {
        altitudeMeters != nil
    }
}
