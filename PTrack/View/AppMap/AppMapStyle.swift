//
//  AppMapStyle.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit
import UIKit

enum AppMapStyle {
    static let appDefaultToneOverlayColor = UIColor(red: 246 / 255, green: 249 / 255, blue: 248 / 255, alpha: 0.44)

    static func apply(_ style: AppMapDisplayStyle = .appDefault, to mapView: MKMapView) {
        mapView.backgroundColor = .systemBackground

        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = configuration(for: style)
        } else {
            mapView.mapType = mapType(for: style)
        }

        switch style {
        case .appDefault, .standard, .satellite:
            mapView.overrideUserInterfaceStyle = .light
        case .dark:
            mapView.overrideUserInterfaceStyle = .dark
        }

        switch style {
        case .appDefault:
            mapView.pointOfInterestFilter = .excludingAll
        case .standard, .satellite, .dark:
            mapView.pointOfInterestFilter = .includingAll
        }
    }

    static func apply(_ style: AppMapDisplayStyle = .appDefault, to options: MKMapSnapshotter.Options) {
        if #available(iOS 17.0, *) {
            options.preferredConfiguration = configuration(for: style)
        } else {
            options.mapType = mapType(for: style)
        }

        switch style {
        case .appDefault:
            options.pointOfInterestFilter = .excludingAll
        case .standard, .satellite, .dark:
            options.pointOfInterestFilter = .includingAll
        }
    }

    static func setToneOverlay(
        _ overlay: AppMapToneTileOverlay,
        visible: Bool,
        on mapView: MKMapView
    ) {
        let isVisible = mapView.overlays.contains { $0 === overlay }

        if visible, !isVisible {
            mapView.addOverlay(overlay, level: .aboveRoads)
        } else if !visible, isVisible {
            mapView.removeOverlay(overlay)
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

    @available(iOS 16.0, *)
    private static func configuration(for style: AppMapDisplayStyle) -> MKMapConfiguration {
        switch style {
        case .appDefault:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .muted
            configuration.pointOfInterestFilter = .excludingAll
            return configuration
        case .standard:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .default
            configuration.pointOfInterestFilter = .includingAll
            return configuration
        case .satellite:
            let configuration = MKImageryMapConfiguration(elevationStyle: .flat)
            return configuration
        case .dark:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .default
            configuration.pointOfInterestFilter = .includingAll
            return configuration
        }
    }

    private static func mapType(for style: AppMapDisplayStyle) -> MKMapType {
        switch style {
        case .appDefault:
            return .mutedStandard
        case .standard, .dark:
            return .standard
        case .satellite:
            return .satellite
        }
    }
}
