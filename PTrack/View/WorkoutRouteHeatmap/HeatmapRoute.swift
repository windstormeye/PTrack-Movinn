//
//  HeatmapRoute.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import CoreLocation
import MapKit

struct HeatmapRoute {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let boundingMapRect: MKMapRect
    let sportKind: TrackedWorkoutSportKind
    let startYear: Int
}
