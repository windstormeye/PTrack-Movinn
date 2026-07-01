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
    case collage
}

enum RouteShareCanvasAspectRatio: CaseIterable {
    case followPhoto
    case portrait3x4
    case landscape4x3
    case landscape16x9
    case portrait9x16

    static let fallbackHeightMultiplier: CGFloat = 4.0 / 3.0

    var title: String {
        switch self {
        case .followPhoto:
            return AppLocalization.text(.followPhoto)
        case .portrait3x4:
            return "3:4"
        case .landscape4x3:
            return "4:3"
        case .landscape16x9:
            return "16:9"
        case .portrait9x16:
            return "9:16"
        }
    }

    func heightMultiplier(followingPhotoHeightMultiplier: CGFloat?) -> CGFloat {
        switch self {
        case .followPhoto:
            return followingPhotoHeightMultiplier ?? Self.fallbackHeightMultiplier
        case .portrait3x4:
            return 4.0 / 3.0
        case .landscape4x3:
            return 3.0 / 4.0
        case .landscape16x9:
            return 9.0 / 16.0
        case .portrait9x16:
            return 16.0 / 9.0
        }
    }
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

    var heightMultiplier: CGFloat? {
        let size: CGSize
        switch self {
        case .routeMedia(let mediaItem):
            size = CGSize(width: mediaItem.asset.pixelWidth, height: mediaItem.asset.pixelHeight)
        case .uploaded(let image):
            size = image.size
        }

        guard size.width > 0, size.height > 0 else {
            return nil
        }

        return size.height / size.width
    }
}

struct RouteShareLivePhotoExport {
    let photoURL: URL
    let pairedVideoURL: URL
    let directoryURL: URL
}

struct RouteShareLivePhotoVideoSource {
    let asset: PHAsset
    let backgroundTransform: RouteShareBackgroundRenderTransform
    let clippingPath: UIBezierPath?
}

struct RouteShareBackgroundRenderTransform {
    let scale: CGFloat
    let translation: CGPoint
    let rotation: CGFloat
}
