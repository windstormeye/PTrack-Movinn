//
//  RouteSource.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit

final class RouteSource {
    let points: [MKMapPoint]
    let boundingRect: MKMapRect

    init(points: [MKMapPoint], boundingRect: MKMapRect) {
        self.points = points
        self.boundingRect = boundingRect
    }
}
