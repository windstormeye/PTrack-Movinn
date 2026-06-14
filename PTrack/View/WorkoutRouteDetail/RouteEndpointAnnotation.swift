//
//  RouteEndpointAnnotation.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit

final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let kind: RouteEndpointKind

    init(coordinate: CLLocationCoordinate2D, kind: RouteEndpointKind) {
        self.coordinate = coordinate
        self.kind = kind
        super.init()
    }
}
