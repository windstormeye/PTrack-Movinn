//
//  WorkoutRouteHeatmapViewController+MKMapViewDelegate.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit
import UIKit

extension WorkoutRouteHeatmapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let tileOverlay = overlay as? HeatmapToneTileOverlay {
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }

        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.black.withAlphaComponent(0.34)
            renderer.lineWidth = 3
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        return MKOverlayRenderer(overlay: overlay)
    }
}
