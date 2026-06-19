//
//  RouteShareModels.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import Photos
import UIKit

enum RouteSharePreviewModule {
    case route
    case metrics
}

enum RouteSharePreviewBackground {
    case map
    case photo(Int)
}

enum RouteSharePhotoItem {
    case routeMedia(RouteMediaItem)
    case uploaded(UIImage)

    var id: String {
        switch self {
        case .routeMedia(let mediaItem):
            return mediaItem.id
        case .uploaded(let image):
            return "uploaded-\(ObjectIdentifier(image).hashValue)"
        }
    }

    var asset: PHAsset? {
        switch self {
        case .routeMedia(let mediaItem):
            return mediaItem.asset
        case .uploaded:
            return nil
        }
    }

    var isLivePhoto: Bool {
        asset?.mediaSubtypes.contains(.photoLive) == true
    }
}

struct RouteShareLivePhotoExport {
    let photoURL: URL
    let pairedVideoURL: URL
    let directoryURL: URL
}
