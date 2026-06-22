//
//  HeatmapRoutesOverlay.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import CoreLocation
import MapKit

final class HeatmapRoutesOverlay: NSObject, MKOverlay {
    private let renderedRoutesLock = NSLock()
    private var _renderedRoutes: [HeatmapRenderedRoute] = []

    var renderedRoutes: [HeatmapRenderedRoute] {
        get {
            renderedRoutesLock.lock()
            defer { renderedRoutesLock.unlock() }
            return _renderedRoutes
        }
        set {
            renderedRoutesLock.lock()
            _renderedRoutes = newValue
            renderedRoutesLock.unlock()
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var boundingMapRect: MKMapRect {
        MKMapRect.world
    }
}
