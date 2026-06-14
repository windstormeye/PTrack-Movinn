//
//  RouteMediaAnnotation.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit

final class RouteMediaAnnotation: NSObject, MKAnnotation {
    let mediaItem: RouteMediaItem
    let coordinate: CLLocationCoordinate2D

    init(mediaItem: RouteMediaItem) {
        self.mediaItem = mediaItem
        coordinate = mediaItem.coordinate
        super.init()
    }
}
