//
//  RouteElevationSample.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import CoreLocation
import Foundation

struct RouteElevationSample {
    let distanceMeters: CLLocationDistance
    let altitudeMeters: Double
    let heartRateBeatsPerMinute: Double?
    let powerWatts: Double?
    let temperatureCelsius: Double?

    init(
        distanceMeters: CLLocationDistance,
        altitudeMeters: Double,
        heartRateBeatsPerMinute: Double? = nil,
        powerWatts: Double? = nil,
        temperatureCelsius: Double? = nil
    ) {
        self.distanceMeters = distanceMeters
        self.altitudeMeters = altitudeMeters
        self.heartRateBeatsPerMinute = heartRateBeatsPerMinute
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
    }
}
