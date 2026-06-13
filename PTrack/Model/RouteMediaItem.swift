//
//  RouteMediaItem.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import CoreLocation
import Foundation
import Photos

struct RouteMediaItem {
    let asset: PHAsset
    let coordinate: CLLocationCoordinate2D
    let distanceFromRoute: CLLocationDistance

    var id: String {
        asset.localIdentifier
    }

    var isVideo: Bool {
        asset.mediaType == .video
    }

    var isLivePhoto: Bool {
        asset.mediaSubtypes.contains(.photoLive)
    }
}
