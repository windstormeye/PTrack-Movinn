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
    let isFacingLeft: Bool
}
