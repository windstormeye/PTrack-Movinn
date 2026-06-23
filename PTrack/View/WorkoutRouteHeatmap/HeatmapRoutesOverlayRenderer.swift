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
        context.setLineWidth(lineWidth(for: zoomScale))
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.34).cgColor)

        for route in routes where route.boundingMapRect.intersects(mapRect) {
            draw(route: route, in: context)
        }

        context.restoreGState()
    }

    private func draw(route: HeatmapRenderedRoute, in context: CGContext) {
        guard let firstPoint = route.mapPoints.first else {
            return
        }

        context.beginPath()
        context.move(to: point(for: firstPoint))

        for mapPoint in route.mapPoints.dropFirst() {
            context.addLine(to: point(for: mapPoint))
        }

        context.strokePath()
    }

    private func lineWidth(for zoomScale: MKZoomScale) -> CGFloat {
        let screenLineWidth: CGFloat = zoomScale > 0.001 ? 2.0 : 2.4
        return screenLineWidth / max(zoomScale, .leastNonzeroMagnitude)
    }
}
