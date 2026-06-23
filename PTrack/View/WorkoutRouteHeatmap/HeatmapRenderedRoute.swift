//
//  HeatmapRenderedRoute.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import CoreLocation
import MapKit

struct HeatmapRenderedRoute {
    let id: String
    let mapPoints: [MKMapPoint]
    let boundingMapRect: MKMapRect
    let pointLimit: Int
}
