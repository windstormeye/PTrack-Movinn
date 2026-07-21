//
//  RouteSlopePolylineRenderer.swift
//  PTrack
//
//  Created by Codex on 2026/7/19.
//

import MapKit
import UIKit

/// Draws slope colors without relying on `MKGradientPolylineRenderer`'s
/// per-overlay rasterization choices. The stroke width is expressed in screen
/// points, so every route chunk has the same visible width at a given zoom.
final class RouteSlopePolylineRenderer: MKOverlayRenderer {
    private struct ColorStop {
        let location: Double
        let color: CGColor
    }

    private struct RenderSegment {
        let startMapPoint: MKMapPoint
        let endMapPoint: MKMapPoint
        let boundingMapRect: MKMapRect
        let gradient: CGGradient

        func intersects(_ mapRect: MKMapRect) -> Bool {
            boundingMapRect.minX <= mapRect.maxX
                && boundingMapRect.maxX >= mapRect.minX
                && boundingMapRect.minY <= mapRect.maxY
                && boundingMapRect.maxY >= mapRect.minY
        }
    }

    private struct SolidRenderChunk {
        let mapPoints: [MKMapPoint]
        let boundingMapRect: MKMapRect

        func intersects(_ mapRect: MKMapRect) -> Bool {
            boundingMapRect.minX <= mapRect.maxX
                && boundingMapRect.maxX >= mapRect.minX
                && boundingMapRect.minY <= mapRect.maxY
                && boundingMapRect.maxY >= mapRect.minY
        }
    }

    private let screenLineWidth: CGFloat
    private let solidColor: CGColor?
    private let solidRenderChunks: [SolidRenderChunk]
    private let renderSegments: [RenderSegment]

    init(
        polyline: MKPolyline,
        colors: [UIColor],
        locations: [Double],
        screenLineWidth: CGFloat
    ) {
        self.screenLineWidth = screenLineWidth.isFinite
            ? max(screenLineWidth, 0)
            : 0
        let mapPoints = Self.distinctMapPoints(in: polyline)
        let colorStops = Self.makeColorStops(
            colors: colors,
            locations: locations
        )
        if let colorStops,
           let constantColor = Self.constantColor(in: colorStops) {
            self.solidColor = constantColor
            self.solidRenderChunks = Self.makeSolidRenderChunks(
                mapPoints: mapPoints
            )
            self.renderSegments = []
        } else {
            self.solidColor = nil
            self.solidRenderChunks = []
            self.renderSegments = colorStops.map {
                Self.makeRenderSegments(
                    mapPoints: mapPoints,
                    colorStops: $0
                )
            } ?? []
        }
        super.init(overlay: polyline)
    }

    override func draw(
        _ mapRect: MKMapRect,
        zoomScale: MKZoomScale,
        in context: CGContext
    ) {
        guard screenLineWidth > 0,
              zoomScale.isFinite,
              zoomScale > 0,
              !renderSegments.isEmpty || !solidRenderChunks.isEmpty else {
            return
        }

        // MKOverlayRenderer's drawing space is scaled by `zoomScale`. Dividing
        // here keeps the final on-screen stroke exactly `screenLineWidth` points.
        let drawingLineWidth = screenLineWidth / zoomScale
        let visibleMapRect = mapRect.insetBy(
            dx: -Double(drawingLineWidth),
            dy: -Double(drawingLineWidth)
        )

        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(drawingLineWidth)

        if let solidColor {
            drawSolidRoute(
                color: solidColor,
                visibleMapRect: visibleMapRect,
                in: context
            )
        } else {
            for segment in renderSegments where segment.intersects(visibleMapRect) {
                draw(segment, in: context)
            }
        }

        context.restoreGState()
    }

    private func draw(_ segment: RenderSegment, in context: CGContext) {
        let startPoint = point(for: segment.startMapPoint)
        let endPoint = point(for: segment.endMapPoint)

        context.saveGState()
        context.beginPath()
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(
            segment.gradient,
            start: startPoint,
            end: endPoint,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    private func drawSolidRoute(
        color: CGColor,
        visibleMapRect: MKMapRect,
        in context: CGContext
    ) {
        var hasVisiblePath = false
        context.beginPath()
        for chunk in solidRenderChunks where chunk.intersects(visibleMapRect) {
            guard let firstMapPoint = chunk.mapPoints.first else {
                continue
            }
            hasVisiblePath = true
            context.move(to: point(for: firstMapPoint))
            for mapPoint in chunk.mapPoints.dropFirst() {
                context.addLine(to: point(for: mapPoint))
            }
        }
        guard hasVisiblePath else {
            return
        }
        context.setStrokeColor(color)
        context.strokePath()
    }

    private static func makeRenderSegments(
        mapPoints: [MKMapPoint],
        colorStops: [ColorStop]
    ) -> [RenderSegment] {
        guard mapPoints.count > 1 else {
            return []
        }

        var cumulativeLengths = Array(repeating: 0.0, count: mapPoints.count)
        for index in 1..<mapPoints.count {
            cumulativeLengths[index] = cumulativeLengths[index - 1]
                + distance(from: mapPoints[index - 1], to: mapPoints[index])
        }
        guard let totalLength = cumulativeLengths.last,
              totalLength.isFinite,
              totalLength > 0 else {
            return []
        }

        let vertexLocations = cumulativeLengths.map { $0 / totalLength }
        let breakpoints = mergedBreakpoints(
            vertexLocations: vertexLocations,
            colorStops: colorStops
        )
        guard breakpoints.count > 1 else {
            return []
        }

        var segments: [RenderSegment] = []
        segments.reserveCapacity(breakpoints.count - 1)
        for index in 1..<breakpoints.count {
            let startLocation = breakpoints[index - 1]
            let endLocation = breakpoints[index]
            guard endLocation > startLocation else {
                continue
            }

            let startMapPoint = interpolatedMapPoint(
                at: startLocation,
                mapPoints: mapPoints,
                cumulativeLengths: cumulativeLengths,
                totalLength: totalLength
            )
            let endMapPoint = interpolatedMapPoint(
                at: endLocation,
                mapPoints: mapPoints,
                cumulativeLengths: cumulativeLengths,
                totalLength: totalLength
            )
            guard distance(from: startMapPoint, to: endMapPoint) > 0,
                  let startColor = interpolatedColor(
                    at: startLocation,
                    colorStops: colorStops
                  ),
                  let endColor = interpolatedColor(
                    at: endLocation,
                    colorStops: colorStops
                  ),
                  let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [startColor, endColor] as CFArray,
                    locations: [0, 1]
                  ) else {
                continue
            }

            segments.append(
                RenderSegment(
                    startMapPoint: startMapPoint,
                    endMapPoint: endMapPoint,
                    boundingMapRect: boundingMapRect(
                        from: startMapPoint,
                        to: endMapPoint
                    ),
                    gradient: gradient
                )
            )
        }
        return segments
    }

    private static func makeSolidRenderChunks(
        mapPoints: [MKMapPoint]
    ) -> [SolidRenderChunk] {
        guard mapPoints.count > 1 else {
            return []
        }

        let preferredSegmentCount = 128
        var chunks: [SolidRenderChunk] = []
        chunks.reserveCapacity(
            (mapPoints.count - 1 + preferredSegmentCount - 1)
                / preferredSegmentCount
        )
        var startIndex = 0
        while startIndex < mapPoints.count - 1 {
            let endIndex = min(
                startIndex + preferredSegmentCount,
                mapPoints.count - 1
            )
            let chunkMapPoints = Array(mapPoints[startIndex...endIndex])
            chunks.append(
                SolidRenderChunk(
                    mapPoints: chunkMapPoints,
                    boundingMapRect: boundingMapRect(for: chunkMapPoints)
                )
            )
            startIndex = endIndex
        }
        return chunks
    }

    private static func distinctMapPoints(in polyline: MKPolyline) -> [MKMapPoint] {
        guard polyline.pointCount > 0 else {
            return []
        }

        let sourcePoints = polyline.points()
        var mapPoints: [MKMapPoint] = []
        mapPoints.reserveCapacity(polyline.pointCount)
        for index in 0..<polyline.pointCount {
            let mapPoint = sourcePoints[index]
            if let previousMapPoint = mapPoints.last,
               distance(from: previousMapPoint, to: mapPoint) == 0 {
                continue
            }
            mapPoints.append(mapPoint)
        }
        return mapPoints
    }

    private static func makeColorStops(
        colors: [UIColor],
        locations: [Double]
    ) -> [ColorStop]? {
        guard colors.count == locations.count,
              colors.count > 1,
              locations.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              zip(locations, locations.dropFirst()).allSatisfy({ $1 > $0 }) else {
            return nil
        }

        var colorStops: [ColorStop] = []
        colorStops.reserveCapacity(colors.count + 2)
        for (color, location) in zip(colors, locations) {
            guard let color = color.convertedToSRGB() else {
                return nil
            }
            colorStops.append(
                ColorStop(
                    location: location,
                    color: color
                )
            )
        }

        guard let firstStop = colorStops.first,
              let lastStop = colorStops.last else {
            return nil
        }
        if firstStop.location > 0 {
            colorStops.insert(
                ColorStop(location: 0, color: firstStop.color),
                at: 0
            )
        }
        if lastStop.location < 1 {
            colorStops.append(
                ColorStop(location: 1, color: lastStop.color)
            )
        }
        return colorStops
    }

    private static func constantColor(in colorStops: [ColorStop]) -> CGColor? {
        guard let firstColor = colorStops.first?.color,
              colorStops.dropFirst().allSatisfy({
                firstColor == $0.color
              }) else {
            return nil
        }
        return firstColor
    }

    private static func mergedBreakpoints(
        vertexLocations: [Double],
        colorStops: [ColorStop]
    ) -> [Double] {
        let sortedLocations = (
            vertexLocations + colorStops.map(\.location) + [0, 1]
        ).sorted()
        var breakpoints: [Double] = []
        breakpoints.reserveCapacity(sortedLocations.count)
        for location in sortedLocations {
            let clampedLocation = min(max(location, 0), 1)
            if let previousLocation = breakpoints.last,
               abs(clampedLocation - previousLocation) <= 0.000_000_001 {
                continue
            }
            breakpoints.append(clampedLocation)
        }
        return breakpoints
    }

    private static func interpolatedMapPoint(
        at location: Double,
        mapPoints: [MKMapPoint],
        cumulativeLengths: [Double],
        totalLength: Double
    ) -> MKMapPoint {
        if location <= 0 {
            return mapPoints[0]
        }
        if location >= 1 {
            return mapPoints[mapPoints.count - 1]
        }

        let targetLength = location * totalLength
        let upperIndex = firstIndex(
            in: cumulativeLengths,
            atOrAfter: targetLength
        )
        let lowerIndex = upperIndex - 1
        let segmentLength = cumulativeLengths[upperIndex]
            - cumulativeLengths[lowerIndex]
        let progress = segmentLength > 0
            ? (targetLength - cumulativeLengths[lowerIndex]) / segmentLength
            : 0
        let startMapPoint = mapPoints[lowerIndex]
        let endMapPoint = mapPoints[upperIndex]
        return MKMapPoint(
            x: startMapPoint.x + (endMapPoint.x - startMapPoint.x) * progress,
            y: startMapPoint.y + (endMapPoint.y - startMapPoint.y) * progress
        )
    }

    private static func interpolatedColor(
        at location: Double,
        colorStops: [ColorStop]
    ) -> CGColor? {
        guard let firstStop = colorStops.first,
              let lastStop = colorStops.last else {
            return nil
        }
        if location <= firstStop.location {
            return firstStop.color
        }
        if location >= lastStop.location {
            return lastStop.color
        }

        let upperIndex = firstIndex(
            in: colorStops.map(\.location),
            atOrAfter: location
        )
        let lowerStop = colorStops[upperIndex - 1]
        let upperStop = colorStops[upperIndex]
        let span = upperStop.location - lowerStop.location
        let progress = span > 0
            ? (location - lowerStop.location) / span
            : 0
        return interpolate(
            from: lowerStop.color,
            to: upperStop.color,
            progress: CGFloat(progress)
        )
    }

    private static func interpolate(
        from startColor: CGColor,
        to endColor: CGColor,
        progress: CGFloat
    ) -> CGColor? {
        guard let startComponents = startColor.components,
              let endComponents = endColor.components,
              startComponents.count >= 4,
              endComponents.count >= 4,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let progress = min(max(progress, 0), 1)
        let components = (0..<4).map { index in
            startComponents[index]
                + (endComponents[index] - startComponents[index]) * progress
        }
        return CGColor(colorSpace: colorSpace, components: components)
    }

    private static func firstIndex(
        in values: [Double],
        atOrAfter target: Double
    ) -> Int {
        var lowerBound = 1
        var upperBound = values.count - 1
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if values[middleIndex] < target {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }
        return lowerBound
    }

    private static func distance(
        from startMapPoint: MKMapPoint,
        to endMapPoint: MKMapPoint
    ) -> Double {
        hypot(
            endMapPoint.x - startMapPoint.x,
            endMapPoint.y - startMapPoint.y
        )
    }

    private static func boundingMapRect(
        from startMapPoint: MKMapPoint,
        to endMapPoint: MKMapPoint
    ) -> MKMapRect {
        MKMapRect(
            x: min(startMapPoint.x, endMapPoint.x),
            y: min(startMapPoint.y, endMapPoint.y),
            width: abs(endMapPoint.x - startMapPoint.x),
            height: abs(endMapPoint.y - startMapPoint.y)
        )
    }

    private static func boundingMapRect(
        for mapPoints: [MKMapPoint]
    ) -> MKMapRect {
        guard let firstMapPoint = mapPoints.first else {
            return .null
        }
        var minimumX = firstMapPoint.x
        var maximumX = firstMapPoint.x
        var minimumY = firstMapPoint.y
        var maximumY = firstMapPoint.y
        for mapPoint in mapPoints.dropFirst() {
            minimumX = min(minimumX, mapPoint.x)
            maximumX = max(maximumX, mapPoint.x)
            minimumY = min(minimumY, mapPoint.y)
            maximumY = max(maximumY, mapPoint.y)
        }
        return MKMapRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }
}

private extension UIColor {
    func convertedToSRGB() -> CGColor? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        return CGColor(
            colorSpace: colorSpace,
            components: [red, green, blue, alpha]
        )
    }
}
