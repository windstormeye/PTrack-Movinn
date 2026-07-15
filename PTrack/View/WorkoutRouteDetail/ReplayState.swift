//
//  ReplayState.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import CoreLocation

struct ReplayState {
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    let altitudeMeters: Double?
    let heartRateBeatsPerMinute: Double?
    let powerWatts: Double?
    let temperatureCelsius: Double?
    let gradeRatio: Double?
    let isFacingLeft: Bool

    init(
        coordinate: CLLocationCoordinate2D,
        distanceMeters: CLLocationDistance,
        altitudeMeters: Double?,
        heartRateBeatsPerMinute: Double?,
        powerWatts: Double?,
        temperatureCelsius: Double?,
        gradeRatio: Double? = nil,
        isFacingLeft: Bool
    ) {
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.altitudeMeters = altitudeMeters
        self.heartRateBeatsPerMinute = heartRateBeatsPerMinute
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
        self.gradeRatio = gradeRatio
        self.isFacingLeft = isFacingLeft
    }
}
