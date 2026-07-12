//
//  AppMapStyle.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import MapKit
import UIKit

enum AppMapStyle {
    private struct SlopeColorStop {
        let location: Double
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private static let slopeColorStops: [SlopeColorStop] = [
        SlopeColorStop(location: 0.00, red: 103 / 255, green: 141 / 255, blue: 60 / 255),
        SlopeColorStop(location: 0.18, red: 128 / 255, green: 152 / 255, blue: 70 / 255),
        SlopeColorStop(location: 0.36, red: 156 / 255, green: 158 / 255, blue: 75 / 255),
        SlopeColorStop(location: 0.54, red: 180 / 255, green: 154 / 255, blue: 72 / 255),
        SlopeColorStop(location: 0.70, red: 189 / 255, green: 123 / 255, blue: 70 / 255),
        SlopeColorStop(location: 0.86, red: 182 / 255, green: 90 / 255, blue: 69 / 255),
        SlopeColorStop(location: 1.00, red: 168 / 255, green: 61 / 255, blue: 67 / 255)
    ]

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

    static func makeSlopeRenderer(
        for polyline: MKPolyline,
        gradient: RouteSlopeGradient,
        lineWidth: CGFloat
    ) -> MKGradientPolylineRenderer {
        let renderer = MKGradientPolylineRenderer(polyline: polyline)
        var colors: [UIColor] = []
        colors.reserveCapacity(gradient.normalizedSlopes.count)
        for normalizedSlope in gradient.normalizedSlopes {
            colors.append(slopeColor(for: normalizedSlope))
        }
        let locations = gradient.locations.map { CGFloat($0) }
        renderer.setColors(colors, locations: locations)
        renderer.lineWidth = lineWidth
        renderer.lineJoin = .round
        renderer.lineCap = .round
        renderer.shouldRasterize = true
        return renderer
    }

    static func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let tileOverlay = overlay as? AppMapToneTileOverlay else {
            return nil
        }

        return MKTileOverlayRenderer(tileOverlay: tileOverlay)
    }

    private static func slopeColor(for normalizedSlope: Double?) -> UIColor {
        guard let normalizedSlope else {
            return UIColor(white: 120 / 255, alpha: 1)
        }

        let value = pow(min(max(normalizedSlope, 0), 1), 1.15)
        guard let firstStop = slopeColorStops.first,
              let lastStop = slopeColorStops.last else {
            return .systemGray
        }
        if value <= firstStop.location {
            return UIColor(red: firstStop.red, green: firstStop.green, blue: firstStop.blue, alpha: 1)
        }
        if value >= lastStop.location {
            return UIColor(red: lastStop.red, green: lastStop.green, blue: lastStop.blue, alpha: 1)
        }

        var upperStopIndex = 1
        while upperStopIndex < slopeColorStops.count - 1,
              slopeColorStops[upperStopIndex].location < value {
            upperStopIndex += 1
        }
        let lowerStop = slopeColorStops[upperStopIndex - 1]
        let upperStop = slopeColorStops[upperStopIndex]
        let progress = CGFloat(
            (value - lowerStop.location) / (upperStop.location - lowerStop.location)
        )
        return UIColor(
            red: lowerStop.red + (upperStop.red - lowerStop.red) * progress,
            green: lowerStop.green + (upperStop.green - lowerStop.green) * progress,
            blue: lowerStop.blue + (upperStop.blue - lowerStop.blue) * progress,
            alpha: 1
        )
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
    var drawsRouteStroke = true
    var directionIndicatorColor: UIColor = .black
    var directionIndicatorSpacing: CGFloat = 118
    var directionIndicatorLength: CGFloat = 16
    var directionIndicatorWidth: CGFloat = 21
    var directionIndicatorStrokeWidth: CGFloat = 6
    var minimumZoomScaleForIndicators: MKZoomScale = 0.03
    var minimumRouteLengthForIndicators: CGFloat = 120
    var maximumIndicatorCount = 120

    private struct RouteGeometry {
        let mapPoints: [MKMapPoint]
        let cumulativeLengths: [Double]
        let length: Double
        let chunks: [RouteGeometryChunk]
    }

    private struct RouteGeometryChunk {
        let segmentRange: Range<Int>
        let minimumX: Double
        let maximumX: Double
        let minimumY: Double
        let maximumY: Double

        func intersects(_ mapRect: MKMapRect) -> Bool {
            maximumX >= mapRect.minX
                && minimumX <= mapRect.maxX
                && maximumY >= mapRect.minY
                && minimumY <= mapRect.maxY
        }
    }

    private struct VisibleRouteRange {
        let lowerBound: Double
        var upperBound: Double

        var length: Double {
            max(upperBound - lowerBound, 0)
        }
    }

    private struct IndicatorRun {
        let firstDistance: Double
        let count: Int
    }

    private let routeGeometryLock = NSLock()
    private var cachedRouteGeometry: RouteGeometry?

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        if drawsRouteStroke {
            super.draw(mapRect, zoomScale: zoomScale, in: context)
        }
        drawDirectionIndicators(mapRect: mapRect, zoomScale: zoomScale, in: context)
    }

    private func drawDirectionIndicators(
        mapRect: MKMapRect,
        zoomScale: MKZoomScale,
        in context: CGContext
    ) {
        guard polyline.pointCount > 1,
              zoomScale >= minimumZoomScaleForIndicators,
              zoomScale > 0,
              maximumIndicatorCount > 0,
              directionIndicatorSpacing.isFinite,
              directionIndicatorSpacing > 0 else {
            return
        }

        let geometry = routeGeometry()
        guard geometry.mapPoints.count > 1,
              geometry.length.isFinite,
              geometry.length > 0 else {
            return
        }

        let indicatorScreenLength = max(directionIndicatorLength, lineWidth * 3.8)
        let indicatorScreenWidth = max(directionIndicatorWidth, lineWidth * 4.8)
        let indicatorScreenStrokeWidth = max(directionIndicatorStrokeWidth, lineWidth * 0.95)
        let screenPadding = max(indicatorScreenLength, indicatorScreenWidth)
            + indicatorScreenStrokeWidth
        guard screenPadding.isFinite, screenPadding >= 0 else {
            return
        }
        let mapPadding = Double(screenPadding / zoomScale)
        guard mapPadding.isFinite, mapPadding >= 0 else {
            return
        }
        let visibleMapRect = mapRect.insetBy(dx: -mapPadding, dy: -mapPadding)
        let visibleRouteRanges = visibleRouteRanges(in: visibleMapRect, geometry: geometry)
        guard !visibleRouteRanges.isEmpty else {
            return
        }

        let visibleRouteLength = visibleRouteRanges.reduce(0) { $0 + $1.length }
        let screenVisibleRouteLength = CGFloat(visibleRouteLength) * zoomScale
        guard screenVisibleRouteLength.isFinite,
              screenVisibleRouteLength >= minimumRouteLengthForIndicators else {
            return
        }

        let interval = Double(directionIndicatorSpacing / zoomScale)
        guard interval.isFinite, interval > 0 else {
            return
        }
        let indicatorRuns = indicatorRuns(for: visibleRouteRanges, interval: interval)
        let indicatorCount = min(maximumIndicatorCount, indicatorRuns.totalCount)

        context.saveGState()
        defer { context.restoreGState() }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        var drawnIndicatorCount = 0
        if indicatorCount > 0 {
            var runIndex = 0
            var runStartOrdinal = 0
            for indicatorIndex in 0..<indicatorCount {
                let candidateOrdinal: Int
                if indicatorRuns.totalCount <= indicatorCount {
                    candidateOrdinal = indicatorIndex
                } else {
                    let bucketMidpoint = (Double(indicatorIndex) + 0.5)
                        * Double(indicatorRuns.totalCount)
                        / Double(indicatorCount)
                    candidateOrdinal = min(
                        max(Int(bucketMidpoint), 0),
                        indicatorRuns.totalCount - 1
                    )
                }

                while runIndex < indicatorRuns.runs.count,
                      candidateOrdinal - runStartOrdinal >= indicatorRuns.runs[runIndex].count {
                    runStartOrdinal += indicatorRuns.runs[runIndex].count
                    runIndex += 1
                }
                guard runIndex < indicatorRuns.runs.count else {
                    break
                }

                let run = indicatorRuns.runs[runIndex]
                let targetDistance = run.firstDistance
                    + Double(candidateOrdinal - runStartOrdinal) * interval
                if drawDirectionIndicator(
                    atRouteDistance: targetDistance,
                    visibleMapRect: visibleMapRect,
                    geometry: geometry,
                    zoomScale: zoomScale,
                    in: context
                ) {
                    drawnIndicatorCount += 1
                }
            }
        }

        if drawnIndicatorCount == 0,
           let longestVisibleRange = visibleRouteRanges.max(by: { $0.length < $1.length }) {
            let targetDistance = (longestVisibleRange.lowerBound + longestVisibleRange.upperBound) / 2
            _ = drawDirectionIndicator(
                atRouteDistance: targetDistance,
                visibleMapRect: visibleMapRect,
                geometry: geometry,
                zoomScale: zoomScale,
                in: context
            )
        }
    }

    private func visibleRouteRanges(
        in visibleMapRect: MKMapRect,
        geometry: RouteGeometry
    ) -> [VisibleRouteRange] {
        guard visibleMapRect.origin.x.isFinite,
              visibleMapRect.origin.y.isFinite,
              visibleMapRect.size.width.isFinite,
              visibleMapRect.size.height.isFinite,
              visibleMapRect.size.width >= 0,
              visibleMapRect.size.height >= 0 else {
            return []
        }

        let mergeTolerance = max(geometry.length, 1) * 1e-12
        var ranges: [VisibleRouteRange] = []
        for chunk in geometry.chunks where chunk.intersects(visibleMapRect) {
            for segmentIndex in chunk.segmentRange {
                let segmentStartDistance = geometry.cumulativeLengths[segmentIndex]
                let segmentEndDistance = geometry.cumulativeLengths[segmentIndex + 1]
                let segmentLength = segmentEndDistance - segmentStartDistance
                guard segmentLength.isFinite, segmentLength > 0,
                      let progressRange = clippedProgressRange(
                        from: geometry.mapPoints[segmentIndex],
                        to: geometry.mapPoints[segmentIndex + 1],
                        inside: visibleMapRect
                      ) else {
                    continue
                }

                let lowerBound = segmentStartDistance + segmentLength * progressRange.lowerBound
                let upperBound = segmentStartDistance + segmentLength * progressRange.upperBound
                guard lowerBound.isFinite,
                      upperBound.isFinite,
                      upperBound > lowerBound else {
                    continue
                }

                if let lastIndex = ranges.indices.last,
                   lowerBound <= ranges[lastIndex].upperBound + mergeTolerance {
                    ranges[lastIndex].upperBound = max(ranges[lastIndex].upperBound, upperBound)
                } else {
                    ranges.append(VisibleRouteRange(lowerBound: lowerBound, upperBound: upperBound))
                }
            }
        }
        return ranges
    }

    private func clippedProgressRange(
        from startPoint: MKMapPoint,
        to endPoint: MKMapPoint,
        inside mapRect: MKMapRect
    ) -> ClosedRange<Double>? {
        guard startPoint.x.isFinite,
              startPoint.y.isFinite,
              endPoint.x.isFinite,
              endPoint.y.isFinite else {
            return nil
        }

        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        let boundaries = [
            (-deltaX, startPoint.x - mapRect.minX),
            (deltaX, mapRect.maxX - startPoint.x),
            (-deltaY, startPoint.y - mapRect.minY),
            (deltaY, mapRect.maxY - startPoint.y)
        ]
        var lowerBound = 0.0
        var upperBound = 1.0

        for (direction, distance) in boundaries {
            if direction == 0 {
                guard distance >= 0 else {
                    return nil
                }
                continue
            }

            let progress = distance / direction
            if direction < 0 {
                guard progress <= upperBound else {
                    return nil
                }
                lowerBound = max(lowerBound, progress)
            } else {
                guard progress >= lowerBound else {
                    return nil
                }
                upperBound = min(upperBound, progress)
            }
        }

        guard lowerBound <= upperBound else {
            return nil
        }
        return min(max(lowerBound, 0), 1)...min(max(upperBound, 0), 1)
    }

    private func indicatorRuns(
        for visibleRouteRanges: [VisibleRouteRange],
        interval: Double
    ) -> (runs: [IndicatorRun], totalCount: Int) {
        let phase = interval / 2
        let rangeTolerance = interval * 1e-9
        var runs: [IndicatorRun] = []
        runs.reserveCapacity(visibleRouteRanges.count)
        var totalCount = 0

        for range in visibleRouteRanges {
            let firstStep = max(ceil((range.lowerBound - phase) / interval), 0)
            let firstDistance = phase + firstStep * interval
            guard firstDistance.isFinite,
                  firstDistance <= range.upperBound + rangeTolerance else {
                continue
            }

            let rawCount = floor(
                max(range.upperBound - firstDistance, 0) / interval
            ) + 1
            let count: Int
            if !rawCount.isFinite || rawCount >= Double(Int.max) {
                count = Int.max
            } else {
                count = max(Int(rawCount), 1)
            }
            runs.append(IndicatorRun(firstDistance: firstDistance, count: count))
            let (sum, overflow) = totalCount.addingReportingOverflow(count)
            totalCount = overflow ? Int.max : sum
        }

        return (runs, totalCount)
    }

    @discardableResult
    private func drawDirectionIndicator(
        atRouteDistance targetDistance: Double,
        visibleMapRect: MKMapRect,
        geometry: RouteGeometry,
        zoomScale: MKZoomScale,
        in context: CGContext
    ) -> Bool {
        guard let segmentIndex = routeSegmentIndex(
            containing: targetDistance,
            geometry: geometry
        ) else {
            return false
        }
        let segmentStartDistance = geometry.cumulativeLengths[segmentIndex]
        let segmentEndDistance = geometry.cumulativeLengths[segmentIndex + 1]
        let segmentLength = segmentEndDistance - segmentStartDistance
        guard segmentLength.isFinite, segmentLength > 0 else {
            return false
        }

        let progress = min(
            max((targetDistance - segmentStartDistance) / segmentLength, 0),
            1
        )
        let startMapPoint = geometry.mapPoints[segmentIndex]
        let endMapPoint = geometry.mapPoints[segmentIndex + 1]
        let tipMapPoint = MKMapPoint(
            x: startMapPoint.x + (endMapPoint.x - startMapPoint.x) * progress,
            y: startMapPoint.y + (endMapPoint.y - startMapPoint.y) * progress
        )
        guard visibleMapRect.contains(tipMapPoint) else {
            return false
        }

        let startPoint = point(for: startMapPoint)
        let endPoint = point(for: endMapPoint)
        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        let drawingSegmentLength = hypot(deltaX, deltaY)
        guard drawingSegmentLength.isFinite, drawingSegmentLength > 0 else {
            return false
        }

        drawIndicator(
            at: point(for: tipMapPoint),
            direction: CGVector(
                dx: deltaX / drawingSegmentLength,
                dy: deltaY / drawingSegmentLength
            ),
            zoomScale: zoomScale,
            in: context
        )
        return true
    }

    private func routeGeometry() -> RouteGeometry {
        routeGeometryLock.lock()
        defer { routeGeometryLock.unlock() }
        if let cachedRouteGeometry {
            return cachedRouteGeometry
        }

        let sourcePoints = polyline.points()
        var mapPoints: [MKMapPoint] = []
        mapPoints.reserveCapacity(polyline.pointCount)
        for index in 0..<polyline.pointCount {
            mapPoints.append(sourcePoints[index])
        }

        var cumulativeLengths = Array(repeating: 0.0, count: mapPoints.count)
        if mapPoints.count > 1 {
            for index in 1..<mapPoints.count {
                let previousPoint = mapPoints[index - 1]
                let currentPoint = mapPoints[index]
                cumulativeLengths[index] = cumulativeLengths[index - 1] + hypot(
                    currentPoint.x - previousPoint.x,
                    currentPoint.y - previousPoint.y
                )
            }
        }

        let geometry = RouteGeometry(
            mapPoints: mapPoints,
            cumulativeLengths: cumulativeLengths,
            length: cumulativeLengths.last ?? 0,
            chunks: routeGeometryChunks(for: mapPoints)
        )
        cachedRouteGeometry = geometry
        return geometry
    }

    private func routeGeometryChunks(for mapPoints: [MKMapPoint]) -> [RouteGeometryChunk] {
        let segmentCount = max(mapPoints.count - 1, 0)
        guard segmentCount > 0 else {
            return []
        }

        let preferredSegmentCount = 64
        var chunks: [RouteGeometryChunk] = []
        chunks.reserveCapacity((segmentCount + preferredSegmentCount - 1) / preferredSegmentCount)
        var firstSegmentIndex = 0
        while firstSegmentIndex < segmentCount {
            let endSegmentIndex = min(firstSegmentIndex + preferredSegmentCount, segmentCount)
            var minimumX = Double.greatestFiniteMagnitude
            var maximumX = -Double.greatestFiniteMagnitude
            var minimumY = Double.greatestFiniteMagnitude
            var maximumY = -Double.greatestFiniteMagnitude
            for pointIndex in firstSegmentIndex...endSegmentIndex {
                let mapPoint = mapPoints[pointIndex]
                minimumX = min(minimumX, mapPoint.x)
                maximumX = max(maximumX, mapPoint.x)
                minimumY = min(minimumY, mapPoint.y)
                maximumY = max(maximumY, mapPoint.y)
            }
            chunks.append(
                RouteGeometryChunk(
                    segmentRange: firstSegmentIndex..<endSegmentIndex,
                    minimumX: minimumX,
                    maximumX: maximumX,
                    minimumY: minimumY,
                    maximumY: maximumY
                )
            )
            firstSegmentIndex = endSegmentIndex
        }
        return chunks
    }

    private func routeSegmentIndex(
        containing distance: Double,
        geometry: RouteGeometry
    ) -> Int? {
        guard geometry.cumulativeLengths.count > 1,
              distance.isFinite,
              distance >= 0,
              distance <= geometry.length else {
            return nil
        }

        var lowerBound = 1
        var upperBound = geometry.cumulativeLengths.count - 1
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if geometry.cumulativeLengths[middleIndex] < distance {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }
        return min(max(lowerBound - 1, 0), geometry.mapPoints.count - 2)
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
