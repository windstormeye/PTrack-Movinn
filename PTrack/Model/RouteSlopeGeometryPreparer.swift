//
//  RouteSlopeGeometryPreparer.swift
//  PTrack
//
//  Created by Codex on 2026/7/12.
//

import CoreLocation
import Foundation
import MapKit

/// A monotonic cancellation token that can safely be shared between the main
/// thread and route-preparation workers.
nonisolated final class RouteSlopePreparationCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Geometry and source-distance positions ready for slope overlay rendering.
/// `sourceLocations` always corresponds one-to-one with `coordinates` and is
/// normalized to the source route's cumulative distance range.
nonisolated struct RouteSlopePreparedGeometry: @unchecked Sendable {
    let coordinates: [CLLocationCoordinate2D]
    let sourceLocations: [Double]
}

/// Builds a bounded slope-rendering geometry directly from the source route.
///
/// The preparer constructs one best-first Ramer-Douglas-Peucker split tree.
/// Every accepted split exposes its two child ranges, so multiple turns inside
/// the same part of the route can be retained instead of keeping only one turn
/// per distance bucket. Each range is scanned at most once.
nonisolated enum RouteSlopeGeometryPreparer {
    private struct SplitCandidate {
        let startIndex: Int
        let endIndex: Int
        let splitIndex: Int
        let squaredError: Double
    }

    private enum CandidateSearchResult {
        case candidate(SplitCandidate)
        case noCandidate
        case cancelled
    }

    private struct CandidateMaxHeap {
        private var storage: [SplitCandidate] = []

        var maximum: SplitCandidate? {
            storage.first
        }

        mutating func insert(_ candidate: SplitCandidate) {
            storage.append(candidate)
            var childIndex = storage.count - 1
            while childIndex > 0 {
                let parentIndex = (childIndex - 1) / 2
                guard Self.hasHigherPriority(storage[childIndex], than: storage[parentIndex]) else {
                    break
                }
                storage.swapAt(childIndex, parentIndex)
                childIndex = parentIndex
            }
        }

        mutating func removeMaximum() -> SplitCandidate? {
            guard !storage.isEmpty else {
                return nil
            }
            guard storage.count > 1 else {
                return storage.removeLast()
            }

            let maximum = storage[0]
            storage[0] = storage.removeLast()
            var parentIndex = 0
            while true {
                let leftChildIndex = parentIndex * 2 + 1
                guard leftChildIndex < storage.count else {
                    break
                }
                let rightChildIndex = leftChildIndex + 1
                let preferredChildIndex: Int
                if rightChildIndex < storage.count,
                   Self.hasHigherPriority(storage[rightChildIndex], than: storage[leftChildIndex]) {
                    preferredChildIndex = rightChildIndex
                } else {
                    preferredChildIndex = leftChildIndex
                }
                guard Self.hasHigherPriority(storage[preferredChildIndex], than: storage[parentIndex]) else {
                    break
                }
                storage.swapAt(parentIndex, preferredChildIndex)
                parentIndex = preferredChildIndex
            }
            return maximum
        }

        private static func hasHigherPriority(
            _ lhs: SplitCandidate,
            than rhs: SplitCandidate
        ) -> Bool {
            if lhs.squaredError != rhs.squaredError {
                return lhs.squaredError > rhs.squaredError
            }
            if lhs.startIndex != rhs.startIndex {
                return lhs.startIndex < rhs.startIndex
            }
            return lhs.splitIndex < rhs.splitIndex
        }
    }

    /// Prepares geometry using a thread-safe cancellation token.
    nonisolated static func prepare(
        coordinates: [CLLocationCoordinate2D],
        cumulativeDistances: [CLLocationDistance],
        toleranceMeters: CLLocationDistance = 4,
        maximumCount: Int = 1_200,
        cancellationToken: RouteSlopePreparationCancellationToken? = nil
    ) -> RouteSlopePreparedGeometry? {
        prepare(
            coordinates: coordinates,
            cumulativeDistances: cumulativeDistances,
            toleranceMeters: toleranceMeters,
            maximumCount: maximumCount,
            isCancelled: { cancellationToken?.isCancelled ?? false }
        )
    }

    /// Prepares geometry using a caller-provided cancellation check. The check
    /// should be fast, thread-safe, and monotonic once it returns `true`.
    nonisolated static func prepare(
        coordinates: [CLLocationCoordinate2D],
        cumulativeDistances: [CLLocationDistance],
        toleranceMeters: CLLocationDistance = 4,
        maximumCount: Int = 1_200,
        isCancelled: @Sendable () -> Bool
    ) -> RouteSlopePreparedGeometry? {
        guard coordinates.count == cumulativeDistances.count,
              coordinates.count > 1,
              maximumCount > 1,
              toleranceMeters.isFinite,
              toleranceMeters >= 0,
              !isCancelled(),
              let firstDistance = cumulativeDistances.first,
              let lastDistance = cumulativeDistances.last,
              firstDistance.isFinite,
              lastDistance.isFinite,
              lastDistance > firstDistance else {
            return nil
        }

        var previousDistance = firstDistance
        for index in cumulativeDistances.indices.dropFirst() {
            if shouldCheckCancellation(at: index), isCancelled() {
                return nil
            }
            let distance = cumulativeDistances[index]
            guard distance.isFinite, distance >= previousDistance else {
                return nil
            }
            previousDistance = distance
        }

        var mapPoints: [MKMapPoint] = []
        mapPoints.reserveCapacity(coordinates.count)
        for index in coordinates.indices {
            if shouldCheckCancellation(at: index), isCancelled() {
                return nil
            }
            let coordinate = coordinates[index]
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                return nil
            }
            let mapPoint = MKMapPoint(coordinate)
            guard mapPoint.x.isFinite, mapPoint.y.isFinite else {
                return nil
            }
            mapPoints.append(mapPoint)
        }

        let referenceLatitude = coordinates[coordinates.count / 2].latitude
        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(referenceLatitude)
        guard mapPointsPerMeter.isFinite, mapPointsPerMeter > 0 else {
            return nil
        }
        let tolerance = toleranceMeters * mapPointsPerMeter
        let squaredTolerance = tolerance * tolerance
        guard squaredTolerance.isFinite else {
            return nil
        }

        let retainedLimit = min(maximumCount, coordinates.count)
        var isRetained = Array(repeating: false, count: coordinates.count)
        var candidates = CandidateMaxHeap()

        let rootSearchResult = splitCandidate(
            mapPoints: mapPoints,
            startIndex: 0,
            endIndex: mapPoints.count - 1,
            isCancelled: isCancelled
        )
        switch rootSearchResult {
        case .cancelled:
            return nil
        case let .candidate(candidate) where candidate.squaredError <= squaredTolerance:
            isRetained[0] = true
            isRetained[coordinates.count - 1] = true
        case .candidate, .noCandidate:
            let boundaryIndices = initialRangeBoundaryIndices(
                pointCount: coordinates.count,
                retainedLimit: retainedLimit
            )
            for index in boundaryIndices {
                isRetained[index] = true
            }

            if boundaryIndices.count == 2,
               case let .candidate(candidate) = rootSearchResult {
                candidates.insert(candidate)
            } else if boundaryIndices.count > 1 {
                for boundaryIndex in 0..<(boundaryIndices.count - 1) {
                    switch splitCandidate(
                        mapPoints: mapPoints,
                        startIndex: boundaryIndices[boundaryIndex],
                        endIndex: boundaryIndices[boundaryIndex + 1],
                        isCancelled: isCancelled
                    ) {
                    case let .candidate(candidate):
                        candidates.insert(candidate)
                    case .noCandidate:
                        break
                    case .cancelled:
                        return nil
                    }
                }
            }
        }
        var retainedCount = isRetained.lazy.filter { $0 }.count

        while retainedCount < retainedLimit,
              let maximumCandidate = candidates.maximum,
              maximumCandidate.squaredError > squaredTolerance {
            if isCancelled() {
                return nil
            }
            guard let candidate = candidates.removeMaximum() else {
                break
            }

            isRetained[candidate.splitIndex] = true
            retainedCount += 1

            switch splitCandidate(
                mapPoints: mapPoints,
                startIndex: candidate.startIndex,
                endIndex: candidate.splitIndex,
                isCancelled: isCancelled
            ) {
            case let .candidate(childCandidate):
                candidates.insert(childCandidate)
            case .noCandidate:
                break
            case .cancelled:
                return nil
            }

            switch splitCandidate(
                mapPoints: mapPoints,
                startIndex: candidate.splitIndex,
                endIndex: candidate.endIndex,
                isCancelled: isCancelled
            ) {
            case let .candidate(childCandidate):
                candidates.insert(childCandidate)
            case .noCandidate:
                break
            case .cancelled:
                return nil
            }
        }

        guard !isCancelled() else {
            return nil
        }

        let distanceSpan = lastDistance - firstDistance
        var preparedCoordinates: [CLLocationCoordinate2D] = []
        var sourceLocations: [Double] = []
        preparedCoordinates.reserveCapacity(retainedCount)
        sourceLocations.reserveCapacity(retainedCount)
        for index in coordinates.indices where isRetained[index] {
            if shouldCheckCancellation(at: index), isCancelled() {
                return nil
            }
            preparedCoordinates.append(coordinates[index])
            sourceLocations.append(
                min(max((cumulativeDistances[index] - firstDistance) / distanceSpan, 0), 1)
            )
        }

        guard preparedCoordinates.count == sourceLocations.count,
              preparedCoordinates.count > 1 else {
            return nil
        }
        return RouteSlopePreparedGeometry(
            coordinates: preparedCoordinates,
            sourceLocations: sourceLocations
        )
    }

    /// Very large source routes start from a small set of index-balanced ranges.
    /// The heap still chooses the highest-error split globally, while no candidate
    /// scan can repeatedly cover the full source array in a pathological tree.
    private nonisolated static func initialRangeBoundaryIndices(
        pointCount: Int,
        retainedLimit: Int
    ) -> [Int] {
        guard pointCount > 1, retainedLimit > 1 else {
            return Array(0..<min(pointCount, retainedLimit))
        }

        let isLargeSourceRoute = pointCount > retainedLimit
            && pointCount / retainedLimit >= 4
        let rangeCount = isLargeSourceRoute
            ? min(64, max(retainedLimit / 16, 1), pointCount - 1)
            : 1
        let lastIndex = pointCount - 1
        var boundaryIndices: [Int] = []
        boundaryIndices.reserveCapacity(rangeCount + 1)
        for rangeIndex in 0...rangeCount {
            let index = lastIndex * rangeIndex / rangeCount
            if boundaryIndices.last != index {
                boundaryIndices.append(index)
            }
        }
        return boundaryIndices
    }

    private nonisolated static func splitCandidate(
        mapPoints: [MKMapPoint],
        startIndex: Int,
        endIndex: Int,
        isCancelled: @Sendable () -> Bool
    ) -> CandidateSearchResult {
        guard endIndex - startIndex > 1 else {
            return .noCandidate
        }

        let startPoint = mapPoints[startIndex]
        let endPoint = mapPoints[endIndex]
        let midpointIndex = (startIndex + endIndex) / 2
        var farthestIndex = startIndex + 1
        var farthestSquaredDistance = -Double.infinity

        for index in (startIndex + 1)..<endIndex {
            if shouldCheckCancellation(at: index - startIndex), isCancelled() {
                return .cancelled
            }
            let squaredDistance = squaredDistance(
                from: mapPoints[index],
                toSegmentStart: startPoint,
                end: endPoint
            )
            let comparisonTolerance = farthestSquaredDistance.isFinite
                ? max(abs(farthestSquaredDistance) * 1e-12, 1e-9)
                : 0
            if squaredDistance > farthestSquaredDistance + comparisonTolerance
                || abs(squaredDistance - farthestSquaredDistance) <= comparisonTolerance
                    && abs(index - midpointIndex) < abs(farthestIndex - midpointIndex) {
                farthestSquaredDistance = squaredDistance
                farthestIndex = index
            }
        }

        guard farthestSquaredDistance.isFinite, farthestSquaredDistance >= 0 else {
            return .noCandidate
        }
        return .candidate(SplitCandidate(
            startIndex: startIndex,
            endIndex: endIndex,
            splitIndex: farthestIndex,
            squaredError: farthestSquaredDistance
        ))
    }

    private nonisolated static func squaredDistance(
        from point: MKMapPoint,
        toSegmentStart startPoint: MKMapPoint,
        end endPoint: MKMapPoint
    ) -> Double {
        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        let segmentLengthSquared = deltaX * deltaX + deltaY * deltaY
        guard segmentLengthSquared.isFinite, segmentLengthSquared > 0 else {
            let pointDeltaX = point.x - startPoint.x
            let pointDeltaY = point.y - startPoint.y
            return pointDeltaX * pointDeltaX + pointDeltaY * pointDeltaY
        }

        let projection = min(
            max(
                ((point.x - startPoint.x) * deltaX + (point.y - startPoint.y) * deltaY)
                    / segmentLengthSquared,
                0
            ),
            1
        )
        let closestX = startPoint.x + deltaX * projection
        let closestY = startPoint.y + deltaY * projection
        let distanceX = point.x - closestX
        let distanceY = point.y - closestY
        return distanceX * distanceX + distanceY * distanceY
    }

    private nonisolated static func shouldCheckCancellation(at index: Int) -> Bool {
        index & 0xFF == 0
    }
}
