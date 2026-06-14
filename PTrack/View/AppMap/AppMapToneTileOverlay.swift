//
//  AppMapToneTileOverlay.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit
import UIKit

final class AppMapToneTileOverlay: MKTileOverlay {
    private static let tileData: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format)
        let image = renderer.image { context in
            UIColor(red: 246 / 255, green: 249 / 255, blue: 248 / 255, alpha: 0.44).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }

        return image.pngData() ?? Data()
    }()

    init() {
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 0
        maximumZ = 22
        canReplaceMapContent = false
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, (any Error)?) -> Void
    ) {
        result(Self.tileData, nil)
    }
}
