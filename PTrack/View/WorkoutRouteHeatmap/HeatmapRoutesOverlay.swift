//
//  HeatmapRoutesOverlay.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import CoreLocation
import MapKit

final class HeatmapRoutesOverlay: NSObject, MKOverlay {
    var renderedRoutes: [HeatmapRenderedRoute] = []

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var boundingMapRect: MKMapRect {
        MKMapRect.world
    }
}
