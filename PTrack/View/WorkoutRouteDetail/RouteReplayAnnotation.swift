//
//  RouteReplayAnnotation.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit

final class RouteReplayAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let emoji: String
    var statusText: String
    var isFacingLeft: Bool

    init(
        coordinate: CLLocationCoordinate2D,
        emoji: String,
        statusText: String,
        isFacingLeft: Bool
    ) {
        self.coordinate = coordinate
        self.emoji = emoji
        self.statusText = statusText
        self.isFacingLeft = isFacingLeft
        super.init()
    }
}
