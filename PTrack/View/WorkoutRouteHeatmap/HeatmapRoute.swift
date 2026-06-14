//
//  HeatmapRoute.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import CoreLocation
import HealthKit
import MapKit

struct HeatmapRoute {
    let coordinates: [CLLocationCoordinate2D]
    let boundingMapRect: MKMapRect
    let activityType: HKWorkoutActivityType
}
