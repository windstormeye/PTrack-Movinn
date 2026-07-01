//
//  RouteMediaItem.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import CoreLocation
import Foundation
import Photos
import UIKit

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

enum RouteMediaThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 180
        cache.totalCostLimit = 36 * 1024 * 1024
        return cache
    }()

    static func image(for assetID: String) -> UIImage? {
        cache.object(forKey: assetID as NSString)
    }

    static func store(_ image: UIImage, for assetID: String) {
        cache.setObject(image, forKey: assetID as NSString, cost: cost(for: image))
    }

    static func removeAllImages() {
        cache.removeAllObjects()
    }

    private static func cost(for image: UIImage) -> Int {
        let pixelWidth = max(Int(image.size.width * image.scale), 1)
        let pixelHeight = max(Int(image.size.height * image.scale), 1)
        return pixelWidth * pixelHeight * 4
    }
}
