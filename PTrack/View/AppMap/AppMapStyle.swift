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

final class RouteDirectionPolylineRenderer: MKPolylineRenderer {
    var directionIndicatorColor: UIColor = .black
    var directionIndicatorSpacing: CGFloat = 118
    var directionIndicatorLength: CGFloat = 16
    var directionIndicatorWidth: CGFloat = 21
    var directionIndicatorStrokeWidth: CGFloat = 6
    var minimumZoomScaleForIndicators: MKZoomScale = 0.005
    var minimumRouteLengthForIndicators: CGFloat = 120
    var maximumIndicatorCount = 120

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        drawDirectionIndicators(zoomScale: zoomScale, in: context)
    }

    private func drawDirectionIndicators(zoomScale: MKZoomScale, in context: CGContext) {
        guard polyline.pointCount > 1,
              zoomScale >= minimumZoomScaleForIndicators,
              zoomScale > 0 else {
            return
        }

        let points = routeDrawingPoints()
        let routeLength = totalLength(for: points)
        let screenRouteLength = routeLength * zoomScale
        guard screenRouteLength >= minimumRouteLengthForIndicators else {
            return
        }

        let indicatorCount = min(
            maximumIndicatorCount,
            max(1, Int(screenRouteLength / directionIndicatorSpacing))
        )
        let interval = routeLength / CGFloat(indicatorCount + 1)
        guard interval.isFinite, interval > 0 else {
            return
        }

        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        var nextDistance = interval
        var traversedDistance: CGFloat = 0
        var drawnCount = 0

        for index in 0..<(points.count - 1) {
            let startPoint = points[index]
            let endPoint = points[index + 1]
            let deltaX = endPoint.x - startPoint.x
            let deltaY = endPoint.y - startPoint.y
            let segmentLength = hypot(deltaX, deltaY)
            guard segmentLength.isFinite, segmentLength > 0 else {
                continue
            }

            while nextDistance <= traversedDistance + segmentLength, drawnCount < indicatorCount {
                let distanceInSegment = nextDistance - traversedDistance
                let progress = distanceInSegment / segmentLength
                let tip = CGPoint(
                    x: startPoint.x + deltaX * progress,
                    y: startPoint.y + deltaY * progress
                )
                let unit = CGVector(dx: deltaX / segmentLength, dy: deltaY / segmentLength)
                drawIndicator(
                    at: tip,
                    direction: unit,
                    zoomScale: zoomScale,
                    in: context
                )

                drawnCount += 1
                nextDistance += interval
            }

            traversedDistance += segmentLength
        }

        context.restoreGState()
    }

    private func routeDrawingPoints() -> [CGPoint] {
        let mapPoints = polyline.points()
        return (0..<polyline.pointCount).map { index in
            point(for: mapPoints[index])
        }
    }

    private func totalLength(for points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else {
            return 0
        }

        return (0..<(points.count - 1)).reduce(CGFloat(0)) { length, index in
            let startPoint = points[index]
            let endPoint = points[index + 1]
            return length + hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        }
    }

    private func drawIndicator(
        at tip: CGPoint,
        direction: CGVector,
        zoomScale: MKZoomScale,
        in context: CGContext
    ) {
        let screenLength = max(directionIndicatorLength, lineWidth * 3.8)
        let screenWidth = max(directionIndicatorWidth, lineWidth * 4.8)
        let screenStrokeWidth = max(directionIndicatorStrokeWidth, lineWidth * 0.95)
        let length = screenLength / zoomScale
        let halfWidth = screenWidth / zoomScale / 2
        let strokeWidth = screenStrokeWidth / zoomScale
        guard length.isFinite,
              halfWidth.isFinite,
              strokeWidth.isFinite,
              length > 0,
              halfWidth > 0,
              strokeWidth > 0 else {
            return
        }

        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let adjustedTip = CGPoint(
            x: tip.x + direction.dx * length * 0.16,
            y: tip.y + direction.dy * length * 0.16
        )
        let tailCenter = CGPoint(
            x: adjustedTip.x - direction.dx * length,
            y: adjustedTip.y - direction.dy * length
        )
        let leftPoint = CGPoint(
            x: tailCenter.x + normal.dx * halfWidth,
            y: tailCenter.y + normal.dy * halfWidth
        )
        let rightPoint = CGPoint(
            x: tailCenter.x - normal.dx * halfWidth,
            y: tailCenter.y - normal.dy * halfWidth
        )

        let path = CGMutablePath()
        path.move(to: leftPoint)
        path.addLine(to: adjustedTip)
        path.addLine(to: rightPoint)

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.addPath(path)
        context.setStrokeColor(directionIndicatorColor.cgColor)
        context.setLineWidth(strokeWidth)
        context.strokePath()
        context.restoreGState()
    }
}
