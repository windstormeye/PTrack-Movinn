//
//  AppMapStyle.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit
import UIKit

enum AppMapStyle {
    static func apply(to mapView: MKMapView) {
        mapView.overrideUserInterfaceStyle = .light
        mapView.pointOfInterestFilter = .excludingAll
        mapView.backgroundColor = .systemBackground

        if #available(iOS 16.0, *) {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .muted
            configuration.pointOfInterestFilter = .excludingAll
            mapView.preferredConfiguration = configuration
        } else {
            mapView.mapType = .mutedStandard
        }
    }

    static func makeToneOverlay() -> AppMapToneTileOverlay {
        AppMapToneTileOverlay()
    }

    static func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let tileOverlay = overlay as? AppMapToneTileOverlay else {
            return nil
        }

        return MKTileOverlayRenderer(tileOverlay: tileOverlay)
    }
}
