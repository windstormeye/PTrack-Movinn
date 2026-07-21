//
//  RouteViewportDistanceResolver.swift
//  PTrack
//
//  Created by Codex on 2026/7/12.
//

import CoreLocation
import MapKit

enum RouteViewportDistanceResolver {
    nonisolated static let segmentBoundaryDistance: CLLocationDistance = 0.01

    struct PreparedGeometry: Sendable {
        let coordinates: [CLLocationCoordinate2D]
        let mapPoints: [MKMapPoint]
        let cumulativeDistances: [CLLocationDistance]
        let segmentStartIndices: Set<Int>
        let segmentDistanceRanges: [ClosedRange<CLLocationDistance>]
        let segmentBoundingMapRects: [MKMapRect]
        let sourceSegmentIndices: [Int]

        init(
            coordinates: [CLLocationCoordinate2D],
            mapPoints: [MKMapPoint]? = nil,
            cumulativeDistances: [CLLocationDistance],
            segmentStartIndices: Set<Int>,
            segmentDistanceRanges: [ClosedRange<CLLocationDistance>] = [],
            segmentBoundingMapRects: [MKMapRect] = [],
            sourceSegmentIndices: [Int] = []
        ) {
            self.coordinates = coordinates
            self.mapPoints = mapPoints ?? coordinates.map(MKMapPoint.init)
            self.cumulativeDistances = cumulativeDistances
            self.segmentStartIndices = segmentStartIndices
            self.segmentDistanceRanges = segmentDistanceRanges
            self.segmentBoundingMapRects = segmentBoundingMapRects
            self.sourceSegmentIndices = sourceSegmentIndices
        }
    }

    nonisolated static func segmentBoundaryDistanceRanges(
        cumulativeDistances: [CLLocationDistance],
        segmentStartIndices: Set<Int>
    ) -> [ClosedRange<CLLocationDistance>] {
        segmentStartIndices.sorted().compactMap { index in
            guard index > 0,
                  index < cumulativeDistances.count else {
                return nil
            }
            let lowerBound = cumulativeDistances[index - 1]
            let upperBound = cumulativeDistances[index]
            guard lowerBound.isFinite,
                  upperBound.isFinite,
                  upperBound > lowerBound else {
                return nil
            }
            return lowerBound...upperBound
        }
    }

    nonisolated static func boundingMapRect(
        for coordinates: [CLLocationCoordinate2D],
        isCancelled: @Sendable () -> Bool = { false }
    ) -> MKMapRect? {
        var boundingRect = MKMapRect.null
        var previousUnwrappedX: Double?
        for (index, coordinate) in coordinates.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let point = MKMapPoint(coordinate)
            guard point.x.isFinite, point.y.isFinite else {
                continue
            }
            let unwrappedPoint = previousUnwrappedX.map {
                wrappedMapPoint(point, nearX: $0)
            } ?? point
            previousUnwrappedX = unwrappedPoint.x
            let pointRect = MKMapRect(
                x: unwrappedPoint.x,
                y: unwrappedPoint.y,
                width: 0,
                height: 0
            )
            boundingRect = boundingRect.isNull
                ? pointRect
                : boundingRect.union(pointRect)
        }
        return boundingRect.isNull || isCancelled() ? nil : boundingRect
    }

    static func prepareGeometry(
        coordinates: [CLLocationCoordinate2D],
        cumulativeDistances: [CLLocationDistance],
        segmentStartIndices: Set<Int>,
        maximumCount: Int = 4_096,
        toleranceMeters: CLLocationDistance = 3,
        allowsSinglePointRepresentatives: Bool = true,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> PreparedGeometry? {
        guard coordinates.count == cumulativeDistances.count,
              coordinates.count > 1,
              maximumCount > 1,
              !isCancelled() else {
            return nil
        }

        let segmentStarts = segmentStartIndices
            .filter { $0 > 0 && $0 < coordinates.count }
            .sorted()
        let boundaries = [0] + segmentStarts + [coordinates.count]
        let allSegmentRanges = zip(boundaries, boundaries.dropFirst())
            .compactMap { lowerBound, upperBound -> Range<Int>? in
                guard lowerBound < upperBound else {
                    return nil
                }
                return lowerBound..<upperBound
            }
        let minimumRequiredCount = allSegmentRanges.reduce(0) {
            $0 + ($1.count > 1 ? 2 : 1)
        }
        let segmentRanges: [Range<Int>]
        let usesSinglePointRepresentatives: Bool
        if minimumRequiredCount <= maximumCount {
            segmentRanges = allSegmentRanges
            usesSinglePointRepresentatives = false
        } else if allowsSinglePointRepresentatives,
                  allSegmentRanges.count <= maximumCount {
            segmentRanges = allSegmentRanges
            usesSinglePointRepresentatives = true
        } else {
            // A malformed/imported file can contain thousands of tiny trkseg
            // elements. Keeping every pair would defeat the viewport LOD cap,
            // so retain evenly distributed segments and never connect them.
            if allowsSinglePointRepresentatives {
                let selectedIndices = evenlySpacedIndices(
                    totalCount: allSegmentRanges.count,
                    limit: maximumCount
                )
                segmentRanges = selectedIndices.map { allSegmentRanges[$0] }
            } else {
                let drawableRanges = allSegmentRanges.filter { $0.count > 1 }
                let selectedIndices = evenlySpacedIndices(
                    totalCount: drawableRanges.count,
                    limit: max(maximumCount / 2, 1)
                )
                segmentRanges = selectedIndices.map { drawableRanges[$0] }
            }
            usesSinglePointRepresentatives = allowsSinglePointRepresentatives
        }

        var preparedCoordinates: [CLLocationCoordinate2D] = []
        var preparedDistances: [CLLocationDistance] = []
        var preparedSegmentStarts = Set<Int>()
        var preparedSegmentDistanceRanges: [ClosedRange<CLLocationDistance>] = []
        var preparedSegmentBoundingMapRects: [MKMapRect] = []
        let sourceSegmentIndexByLowerBound = Dictionary(
            uniqueKeysWithValues: allSegmentRanges.enumerated().map {
                ($0.element.lowerBound, $0.offset)
            }
        )
        let preparedSourceSegmentIndices = segmentRanges.compactMap {
            sourceSegmentIndexByLowerBound[$0.lowerBound]
        }
        preparedCoordinates.reserveCapacity(min(coordinates.count, maximumCount))
        preparedDistances.reserveCapacity(min(cumulativeDistances.count, maximumCount))
        var remainingBudget = maximumCount
        var remainingSourcePointCount = segmentRanges.reduce(0) { $0 + $1.count }
        var minimumCountSuffix = Array(repeating: 0, count: segmentRanges.count + 1)
        for index in segmentRanges.indices.reversed() {
            minimumCountSuffix[index] = minimumCountSuffix[index + 1]
                + (usesSinglePointRepresentatives
                    ? 1
                    : (segmentRanges[index].count > 1 ? 2 : 1))
        }

        for (segmentOffset, range) in segmentRanges.enumerated() {
            if isCancelled() {
                return nil
            }
            let lowerBound = range.lowerBound
            let upperBound = range.upperBound
            if segmentOffset > 0, !preparedCoordinates.isEmpty {
                preparedSegmentStarts.insert(preparedCoordinates.count)
            }

            let pointCount = upperBound - lowerBound
            let firstSourceDistance = cumulativeDistances[lowerBound]
            let lastSourceDistance = cumulativeDistances[upperBound - 1]
            let sourceDistanceLowerBound = min(firstSourceDistance, lastSourceDistance)
            let sourceDistanceUpperBound = max(firstSourceDistance, lastSourceDistance)
            preparedSegmentDistanceRanges.append(
                sourceDistanceLowerBound...sourceDistanceUpperBound
            )
            var segmentBoundingRect = MKMapRect.null
            for (offset, index) in range.enumerated() {
                if offset.isMultiple(of: 256), isCancelled() {
                    return nil
                }
                let point = MKMapPoint(coordinates[index])
                let pointRect = MKMapRect(
                    x: point.x,
                    y: point.y,
                    width: 0,
                    height: 0
                )
                segmentBoundingRect = segmentBoundingRect.isNull
                    ? pointRect
                    : segmentBoundingRect.union(pointRect)
            }
            preparedSegmentBoundingMapRects.append(segmentBoundingRect)
            let minimumPointCount = usesSinglePointRepresentatives
                ? 1
                : (pointCount > 1 ? 2 : 1)
            let minimumRemainingCount = minimumCountSuffix[segmentOffset + 1]
            let proportionalCount = Int(round(
                Double(remainingBudget) * Double(pointCount)
                    / Double(max(remainingSourcePointCount, 1))
            ))
            let segmentMaximumCount = min(
                pointCount,
                max(
                    minimumPointCount,
                    min(proportionalCount, remainingBudget - minimumRemainingCount)
                )
            )
            remainingBudget -= segmentMaximumCount
            remainingSourcePointCount -= pointCount

            if segmentMaximumCount == 1 {
                let representativeIndex = lowerBound + (pointCount - 1) / 2
                preparedCoordinates.append(coordinates[representativeIndex])
                preparedDistances.append(cumulativeDistances[representativeIndex])
                continue
            }
            guard pointCount > 1 else {
                preparedCoordinates.append(coordinates[lowerBound])
                preparedDistances.append(cumulativeDistances[lowerBound])
                continue
            }

            let segmentCoordinates = Array(coordinates[lowerBound..<upperBound])
            let segmentDistances = Array(cumulativeDistances[lowerBound..<upperBound])
            guard let firstDistance = segmentDistances.first,
                  let lastDistance = segmentDistances.last else {
                return nil
            }
            if lastDistance <= firstDistance {
                preparedCoordinates.append(segmentCoordinates[0])
                preparedDistances.append(firstDistance)
                preparedCoordinates.append(segmentCoordinates[pointCount - 1])
                preparedDistances.append(lastDistance)
                continue
            }
            if pointCount <= segmentMaximumCount {
                preparedCoordinates.append(contentsOf: segmentCoordinates)
                preparedDistances.append(contentsOf: segmentDistances)
                continue
            }

            guard let simplified = RouteSlopeGeometryPreparer.prepare(
                coordinates: segmentCoordinates,
                cumulativeDistances: segmentDistances,
                toleranceMeters: toleranceMeters,
                maximumCount: segmentMaximumCount,
                isCancelled: isCancelled
            ) else {
                return nil
            }
            let distanceSpan = lastDistance - firstDistance
            preparedCoordinates.append(contentsOf: simplified.coordinates)
            preparedDistances.append(contentsOf: simplified.sourceLocations.map {
                firstDistance + distanceSpan * $0
            })
        }

        guard preparedCoordinates.count == preparedDistances.count,
              preparedCoordinates.count > 1,
              !isCancelled() else {
            return nil
        }
        return PreparedGeometry(
            coordinates: preparedCoordinates,
            mapPoints: preparedCoordinates.map(MKMapPoint.init),
            cumulativeDistances: preparedDistances,
            segmentStartIndices: preparedSegmentStarts,
            segmentDistanceRanges: preparedSegmentDistanceRanges,
            segmentBoundingMapRects: preparedSegmentBoundingMapRects,
            sourceSegmentIndices: preparedSourceSegmentIndices
        )
    }

    private static func evenlySpacedIndices(
        totalCount: Int,
        limit: Int
    ) -> [Int] {
        guard totalCount > 0, limit > 0 else {
            return []
        }
        guard totalCount > limit else {
            return Array(0..<totalCount)
        }
        guard limit > 1 else {
            return [0]
        }

        var indices: [Int] = []
        indices.reserveCapacity(limit)
        for offset in 0..<limit {
            let index = Int(round(
                Double(totalCount - 1) * Double(offset) / Double(limit - 1)
            ))
            if indices.last != index {
                indices.append(index)
            }
        }
        return indices
    }

    static func displayPolylines(
        coordinates: [CLLocationCoordinate2D],
        segmentStartIndices: Set<Int>,
        includedSegmentIndices: Set<Int>? = nil
    ) -> [MKPolyline] {
        guard coordinates.count > 1 else {
            return []
        }

        let segmentStarts = segmentStartIndices
            .filter { $0 > 0 && $0 < coordinates.count }
            .sorted()
        guard !segmentStarts.isEmpty else {
            guard includedSegmentIndices?.contains(0) != false else {
                return []
            }
            return [MKPolyline(coordinates: coordinates, count: coordinates.count)]
        }

        var polylines: [MKPolyline] = []
        var lowerBound = 0
        for (segmentIndex, upperBound) in (segmentStarts + [coordinates.count]).enumerated() {
            let segmentCoordinates = Array(coordinates[lowerBound..<upperBound])
            if segmentCoordinates.count > 1,
               includedSegmentIndices?.contains(segmentIndex) != false {
                polylines.append(MKPolyline(
                    coordinates: segmentCoordinates,
                    count: segmentCoordinates.count
                ))
            }
            lowerBound = upperBound
        }
        return polylines
    }

    struct FocusedRange {
        let visibleDistanceRange: ClosedRange<CLLocationDistance>
        let contextDistanceRange: ClosedRange<CLLocationDistance>
    }

    private struct VisibleRange {
        var distanceRange: ClosedRange<CLLocationDistance>
        let contextDistanceRange: ClosedRange<CLLocationDistance>
        var centerDistanceSquared: Double
    }

    static func focusedVisibleRange(
        coordinates: [CLLocationCoordinate2D],
        mapPoints: [MKMapPoint] = [],
        cumulativeDistances: [CLLocationDistance],
        mapView: MKMapView,
        visibleBounds: CGRect,
        segmentStartIndices: Set<Int> = [],
        segmentDistanceRanges: [ClosedRange<CLLocationDistance>] = [],
        segmentBoundingMapRects: [MKMapRect] = [],
        preferredDistance: CLLocationDistance? = nil
    ) -> FocusedRange? {
        guard visibleBounds.origin.x.isFinite,
              visibleBounds.origin.y.isFinite,
              visibleBounds.size.width.isFinite,
              visibleBounds.size.height.isFinite,
              visibleBounds.size.width > 0,
              visibleBounds.size.height > 0 else {
            return nil
        }
        guard let clippingRect = visibleMapRect(
            for: visibleBounds,
            mapView: mapView
        ) else {
            return nil
        }
        let preparedMapPoints = mapPoints.count == coordinates.count
            ? mapPoints
            : coordinates.map(MKMapPoint.init)
        let ranges = visibleRanges(
            mapPoints: preparedMapPoints,
            cumulativeDistances: cumulativeDistances,
            visibleMapRect: clippingRect,
            segmentStartIndices: segmentStartIndices,
            segmentDistanceRanges: segmentDistanceRanges,
            segmentBoundingMapRects: segmentBoundingMapRects
        )
        guard !ranges.isEmpty else {
            return nil
        }

        if let totalDistance = cumulativeDistances.last,
           totalDistance > 0 {
            let visibleDistance = ranges.reduce(0) { partialResult, range in
                partialResult + range.distanceRange.upperBound - range.distanceRange.lowerBound
            }
            let endpointTolerance = max(totalDistance * 0.000_001, 0.5)
            let includesRouteStart = ranges.contains {
                $0.distanceRange.lowerBound <= endpointTolerance
            }
            let includesRouteEnd = ranges.contains {
                $0.distanceRange.upperBound >= totalDistance - endpointTolerance
            }
            if includesRouteStart,
               includesRouteEnd,
               visibleDistance >= totalDistance * 0.9 {
                return FocusedRange(
                    visibleDistanceRange: 0...totalDistance,
                    contextDistanceRange: 0...totalDistance
                )
            }
        }

        guard let focusedRange = ranges.min(by: { lhs, rhs in
            if abs(lhs.centerDistanceSquared - rhs.centerDistanceSquared) > 0.000_001 {
                return lhs.centerDistanceSquared < rhs.centerDistanceSquared
            }
            let lhsSpan = lhs.distanceRange.upperBound - lhs.distanceRange.lowerBound
            let rhsSpan = rhs.distanceRange.upperBound - rhs.distanceRange.lowerBound
            return lhsSpan > rhsSpan
        }) else {
            return nil
        }

        if let preferredDistance,
           preferredDistance.isFinite,
           let preferredRange = ranges
               .filter({ $0.distanceRange.contains(preferredDistance) })
               .min(by: { $0.centerDistanceSquared < $1.centerDistanceSquared }) {
            let focusTolerance = min(
                clippingRect.size.width,
                clippingRect.size.height
            ) * 0.08
            let preferredCenterDistance = sqrt(preferredRange.centerDistanceSquared)
            let focusedCenterDistance = sqrt(focusedRange.centerDistanceSquared)
            if preferredCenterDistance <= focusedCenterDistance + focusTolerance {
                return FocusedRange(
                    visibleDistanceRange: preferredRange.distanceRange,
                    contextDistanceRange: preferredRange.contextDistanceRange
                )
            }
        }

        return FocusedRange(
            visibleDistanceRange: focusedRange.distanceRange,
            contextDistanceRange: focusedRange.contextDistanceRange
        )
    }

    private static func visibleRanges(
        mapPoints: [MKMapPoint],
        cumulativeDistances: [CLLocationDistance],
        visibleMapRect: MKMapRect,
        segmentStartIndices: Set<Int>,
        segmentDistanceRanges: [ClosedRange<CLLocationDistance>],
        segmentBoundingMapRects: [MKMapRect]
    ) -> [VisibleRange] {
        guard mapPoints.count == cumulativeDistances.count,
              mapPoints.count > 1,
              isValid(visibleMapRect) else {
            return []
        }

        let totalDistance = cumulativeDistances.last ?? 0
        let mergeTolerance = max(totalDistance, 1) * 1e-9
        let mapCenter = MKMapPoint(
            x: visibleMapRect.origin.x + visibleMapRect.size.width / 2,
            y: visibleMapRect.origin.y + visibleMapRect.size.height / 2
        )
        var ranges: [VisibleRange] = []
        ranges.reserveCapacity(4)
        let orderedSegmentStarts = segmentStartIndices
            .filter { $0 > 0 && $0 < mapPoints.count }
            .sorted()
        let preparedBoundaries = [0] + orderedSegmentStarts + [mapPoints.count]
        let preparedSegmentCount = orderedSegmentStarts.count + 1
        let hasPreparedContexts = segmentDistanceRanges.count == preparedSegmentCount
        let hasPreparedBounds = segmentBoundingMapRects.count == preparedSegmentCount
        let worldWidth = MKMapSize.world.width
        let canUsePreparedBounds = hasPreparedBounds
            && visibleMapRect.minX >= 0
            && visibleMapRect.maxX <= worldWidth

        for (preparedSegmentIndex, bounds) in zip(
            preparedBoundaries,
            preparedBoundaries.dropFirst()
        ).enumerated() {
            let lowerIndex = bounds.0
            let upperIndex = bounds.1
            guard lowerIndex < upperIndex else {
                continue
            }
            let fallbackContextRange = cumulativeDistances[lowerIndex]...cumulativeDistances[upperIndex - 1]
            let contextDistanceRange = hasPreparedContexts
                ? segmentDistanceRanges[preparedSegmentIndex]
                : fallbackContextRange
            let segmentBounds = canUsePreparedBounds
                ? segmentBoundingMapRects[preparedSegmentIndex]
                : boundingMapRect(for: mapPoints[lowerIndex..<upperIndex].map {
                    wrappedMapPoint($0, nearX: mapCenter.x)
                })
            guard segmentBounds.map({ mapRectsOverlap($0, visibleMapRect) }) != false else {
                continue
            }

            if upperIndex - lowerIndex == 1 {
                let point = wrappedMapPoint(
                    mapPoints[lowerIndex],
                    nearX: mapCenter.x
                )
                guard visibleMapRect.contains(point)
                        || segmentBounds.map({ mapRectsOverlap($0, visibleMapRect) }) == true,
                      contextDistanceRange.upperBound > contextDistanceRange.lowerBound else {
                    continue
                }
                let focusPoint: MKMapPoint
                if let segmentBounds {
                    focusPoint = MKMapPoint(
                        x: min(max(mapCenter.x, segmentBounds.minX), segmentBounds.maxX),
                        y: min(max(mapCenter.y, segmentBounds.minY), segmentBounds.maxY)
                    )
                } else {
                    focusPoint = point
                }
                let deltaX = focusPoint.x - mapCenter.x
                let deltaY = focusPoint.y - mapCenter.y
                ranges.append(VisibleRange(
                    distanceRange: contextDistanceRange,
                    contextDistanceRange: contextDistanceRange,
                    centerDistanceSquared: deltaX * deltaX + deltaY * deltaY
                ))
                continue
            }

            for segmentIndex in lowerIndex..<(upperIndex - 1) {
                let startPoint = wrappedMapPoint(
                    mapPoints[segmentIndex],
                    nearX: mapCenter.x
                )
                let endPoint = wrappedMapPoint(
                    mapPoints[segmentIndex + 1],
                    nearX: startPoint.x
                )
                let startDistance = cumulativeDistances[segmentIndex]
                let endDistance = cumulativeDistances[segmentIndex + 1]
                let segmentDistance = endDistance - startDistance
                guard segmentDistance.isFinite,
                      segmentDistance > 0,
                      let progressRange = clippedProgressRange(
                          from: startPoint,
                          to: endPoint,
                          inside: visibleMapRect
                      ) else {
                    continue
                }

                let lowerBound = startDistance
                    + segmentDistance * progressRange.lowerBound
                let upperBound = startDistance
                    + segmentDistance * progressRange.upperBound
                guard lowerBound.isFinite,
                      upperBound.isFinite,
                      upperBound > lowerBound else {
                    continue
                }
                let centerDistanceSquared = closestDistanceSquared(
                    from: mapCenter,
                    toSegmentFrom: startPoint,
                    to: endPoint,
                    progressRange: progressRange
                )
                if let lastRange = ranges.last,
                   lastRange.contextDistanceRange.lowerBound
                    == contextDistanceRange.lowerBound,
                   lastRange.contextDistanceRange.upperBound
                    == contextDistanceRange.upperBound,
                   lowerBound <= lastRange.distanceRange.upperBound + mergeTolerance {
                    let mergedUpperBound = max(
                        lastRange.distanceRange.upperBound,
                        upperBound
                    )
                    ranges[ranges.count - 1] = VisibleRange(
                        distanceRange: lastRange.distanceRange.lowerBound...mergedUpperBound,
                        contextDistanceRange: contextDistanceRange,
                        centerDistanceSquared: min(
                            lastRange.centerDistanceSquared,
                            centerDistanceSquared
                        )
                    )
                } else {
                    ranges.append(VisibleRange(
                        distanceRange: lowerBound...upperBound,
                        contextDistanceRange: contextDistanceRange,
                        centerDistanceSquared: centerDistanceSquared
                    ))
                }
            }
        }
        return ranges
    }

    private static func visibleMapRect(
        for visibleBounds: CGRect,
        mapView: MKMapView
    ) -> MKMapRect? {
        let worldWidth = MKMapSize.world.width
        let mapBounds = mapView.bounds
        let fullVisibleMapRect = mapView.visibleMapRect
        if worldWidth.isFinite,
           worldWidth > 0,
           mapBounds.width > 0,
           mapBounds.height > 0,
           isValid(fullVisibleMapRect) {
            let horizontalFraction = Double(visibleBounds.width / mapBounds.width)
            let targetVisibleWidth = fullVisibleMapRect.width * horizontalFraction
            if targetVisibleWidth >= worldWidth / 2,
               let wideVisibleMapRect = proportionalVisibleMapRect(
                   for: visibleBounds,
                   mapBounds: mapBounds,
                   fullVisibleMapRect: fullVisibleMapRect
               ) {
                return wideVisibleMapRect
            }
        }

        let screenCorners = [
            CGPoint(x: visibleBounds.minX, y: visibleBounds.minY),
            CGPoint(x: visibleBounds.maxX, y: visibleBounds.minY),
            CGPoint(x: visibleBounds.minX, y: visibleBounds.maxY),
            CGPoint(x: visibleBounds.maxX, y: visibleBounds.maxY)
        ]
        let mapPoints = screenCorners.compactMap { point -> MKMapPoint? in
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                return nil
            }
            let mapPoint = MKMapPoint(coordinate)
            return mapPoint.x.isFinite && mapPoint.y.isFinite ? mapPoint : nil
        }
        guard mapPoints.count == screenCorners.count,
              let referenceX = mapPoints.first?.x else {
            return nil
        }
        return boundingMapRect(for: mapPoints.map {
            wrappedMapPoint($0, nearX: referenceX)
        })
    }

    private static func proportionalVisibleMapRect(
        for visibleBounds: CGRect,
        mapBounds: CGRect,
        fullVisibleMapRect: MKMapRect
    ) -> MKMapRect? {
        let clippedBounds = visibleBounds.intersection(mapBounds)
        guard !clippedBounds.isNull,
              !clippedBounds.isEmpty,
              mapBounds.width > 0,
              mapBounds.height > 0 else {
            return nil
        }

        let horizontalScale = fullVisibleMapRect.width / Double(mapBounds.width)
        let verticalScale = fullVisibleMapRect.height / Double(mapBounds.height)
        let result = MKMapRect(
            x: fullVisibleMapRect.minX
                + Double(clippedBounds.minX - mapBounds.minX) * horizontalScale,
            y: fullVisibleMapRect.minY
                + Double(clippedBounds.minY - mapBounds.minY) * verticalScale,
            width: Double(clippedBounds.width) * horizontalScale,
            height: Double(clippedBounds.height) * verticalScale
        )
        return isValid(result) ? result : nil
    }

    nonisolated private static func wrappedMapPoint(
        _ point: MKMapPoint,
        nearX referenceX: Double
    ) -> MKMapPoint {
        let worldWidth = MKMapSize.world.width
        guard worldWidth.isFinite, worldWidth > 0 else {
            return point
        }
        let worldOffset = ((referenceX - point.x) / worldWidth).rounded()
        let x = point.x + worldOffset * worldWidth
        return MKMapPoint(x: x, y: point.y)
    }

    private static func boundingMapRect(
        for mapPoints: [MKMapPoint]
    ) -> MKMapRect? {
        guard let firstPoint = mapPoints.first else {
            return nil
        }
        var minimumX = firstPoint.x
        var maximumX = firstPoint.x
        var minimumY = firstPoint.y
        var maximumY = firstPoint.y
        for point in mapPoints.dropFirst() {
            minimumX = min(minimumX, point.x)
            maximumX = max(maximumX, point.x)
            minimumY = min(minimumY, point.y)
            maximumY = max(maximumY, point.y)
        }
        return MKMapRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    private static func mapRectsOverlap(_ lhs: MKMapRect, _ rhs: MKMapRect) -> Bool {
        !lhs.isNull
            && !rhs.isNull
            && lhs.maxX >= rhs.minX
            && lhs.minX <= rhs.maxX
            && lhs.maxY >= rhs.minY
            && lhs.minY <= rhs.maxY
    }

    private static func closestDistanceSquared(
        from point: MKMapPoint,
        toSegmentFrom startPoint: MKMapPoint,
        to endPoint: MKMapPoint,
        progressRange: ClosedRange<Double>
    ) -> Double {
        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        let segmentLengthSquared = deltaX * deltaX + deltaY * deltaY
        let progress: Double
        if segmentLengthSquared > 0 {
            let projectedProgress = (
                (point.x - startPoint.x) * deltaX
                    + (point.y - startPoint.y) * deltaY
            ) / segmentLengthSquared
            progress = min(
                max(projectedProgress, progressRange.lowerBound),
                progressRange.upperBound
            )
        } else {
            progress = progressRange.lowerBound
        }

        let closestX = startPoint.x + deltaX * progress
        let closestY = startPoint.y + deltaY * progress
        let distanceX = point.x - closestX
        let distanceY = point.y - closestY
        return distanceX * distanceX + distanceY * distanceY
    }

    private static func isValid(_ mapRect: MKMapRect) -> Bool {
        mapRect.origin.x.isFinite
            && mapRect.origin.y.isFinite
            && mapRect.size.width.isFinite
            && mapRect.size.height.isFinite
            && mapRect.size.width >= 0
            && mapRect.size.height >= 0
    }

    private static func clippedProgressRange(
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
}
