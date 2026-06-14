//
//  HeatmapRoutesOverlayRenderer.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit
import UIKit

final class HeatmapRoutesOverlayRenderer: MKOverlayRenderer {
    private let routeOverlay: HeatmapRoutesOverlay

    init(routeOverlay: HeatmapRoutesOverlay) {
        self.routeOverlay = routeOverlay
        super.init(overlay: routeOverlay)
    }

    override func draw(
        _ mapRect: MKMapRect,
        zoomScale: MKZoomScale,
        in context: CGContext
    ) {
        let routes = routeOverlay.renderedRoutes
        guard !routes.isEmpty else {
            return
        }

        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(3 / zoomScale)
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.34).cgColor)

        for route in routes where route.boundingMapRect.intersects(mapRect) {
            draw(route: route, in: context)
        }

        context.restoreGState()
    }

    private func draw(route: HeatmapRenderedRoute, in context: CGContext) {
        guard let firstCoordinate = route.coordinates.first else {
            return
        }

        context.beginPath()
        context.move(to: point(for: MKMapPoint(firstCoordinate)))

        for coordinate in route.coordinates.dropFirst() {
            context.addLine(to: point(for: MKMapPoint(coordinate)))
        }

        context.strokePath()
    }
}
