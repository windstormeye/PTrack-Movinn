//
//  RouteSlopeOverlayFactory.swift
//  PTrack
//
//  Created by Codex on 2026/7/12.
//

import CoreLocation
import Foundation
import MapKit

struct RouteSlopeOverlayChunk {
    let polyline: MKPolyline
    let gradient: RouteSlopeGradient
}

enum RouteSlopeOverlayFactory {
    static func makeChunks(
        coordinates: [CLLocationCoordinate2D],
        sourceLocations: [Double],
        gradient: RouteSlopeGradient,
        totalDistance: CLLocationDistance,
        preferredChunkDistance: CLLocationDistance,
        maximumChunkCount: Int
    ) -> [RouteSlopeOverlayChunk] {
        guard coordinates.count == sourceLocations.count,
              coordinates.count > 1,
              preferredChunkDistance.isFinite,
              preferredChunkDistance > 0,
              maximumChunkCount > 0,
              zip(sourceLocations, sourceLocations.dropFirst()).allSatisfy({ $1 >= $0 }) else {
            return []
        }

        let segmentCount = coordinates.count - 1
        let preferredChunkCount: Int
        if totalDistance.isFinite,
           totalDistance > 0 {
            let rawChunkCount = ceil(totalDistance / preferredChunkDistance)
            preferredChunkCount = rawChunkCount >= Double(Int.max)
                ? Int.max
                : max(1, Int(rawChunkCount))
        } else {
            preferredChunkCount = 1
        }
        let desiredChunkCount = min(
            preferredChunkCount,
            maximumChunkCount,
            segmentCount
        )

        let boundaryIndices = chunkBoundaryIndices(
            sourceLocations: sourceLocations,
            desiredChunkCount: desiredChunkCount
        )
        var chunks: [RouteSlopeOverlayChunk] = []
        chunks.reserveCapacity(max(boundaryIndices.count - 1, 0))
        for boundaryIndex in 0..<(boundaryIndices.count - 1) {
            let startIndex = boundaryIndices[boundaryIndex]
            let endIndex = boundaryIndices[boundaryIndex + 1]
            guard endIndex > startIndex,
                  let sourceSectionGradient = gradient.section(
                    from: sourceLocations[startIndex],
                    to: sourceLocations[endIndex]
                  ) else {
                continue
            }

            let chunkCoordinates = Array(coordinates[startIndex...endIndex])
            let chunkSourceLocations = Array(sourceLocations[startIndex...endIndex])
            let sectionGradient = remapGradientLocations(
                sourceSectionGradient,
                sourceStartLocation: sourceLocations[startIndex],
                sourceEndLocation: sourceLocations[endIndex],
                coordinates: chunkCoordinates,
                sourceLocations: chunkSourceLocations
            )
            chunks.append(
                RouteSlopeOverlayChunk(
                    polyline: MKPolyline(
                        coordinates: chunkCoordinates,
                        count: chunkCoordinates.count
                    ),
                    gradient: sectionGradient
                )
            )
        }
        return chunks
    }

    private static func chunkBoundaryIndices(
        sourceLocations: [Double],
        desiredChunkCount: Int
    ) -> [Int] {
        var boundaryIndices = [0]
        boundaryIndices.reserveCapacity(desiredChunkCount + 1)
        if desiredChunkCount > 1,
           let firstLocation = sourceLocations.first,
           let lastLocation = sourceLocations.last,
           lastLocation > firstLocation {
            for boundaryIndex in 1..<desiredChunkCount {
                let targetLocation = firstLocation
                    + (lastLocation - firstLocation)
                    * Double(boundaryIndex)
                    / Double(desiredChunkCount)
                var lowerBound = boundaryIndices[boundaryIndices.count - 1] + 1
                var upperBound = sourceLocations.count - 1
                while lowerBound < upperBound {
                    let middleIndex = (lowerBound + upperBound) / 2
                    if sourceLocations[middleIndex] < targetLocation {
                        lowerBound = middleIndex + 1
                    } else {
                        upperBound = middleIndex
                    }
                }
                if lowerBound < sourceLocations.count - 1,
                   sourceLocations[lowerBound] - sourceLocations[boundaryIndices.last ?? 0]
                    > 0.000_001 {
                    boundaryIndices.append(lowerBound)
                }
            }
        }
        if boundaryIndices.last != sourceLocations.count - 1 {
            boundaryIndices.append(sourceLocations.count - 1)
        }
        return boundaryIndices
    }

    private static func remapGradientLocations(
        _ gradient: RouteSlopeGradient,
        sourceStartLocation: Double,
        sourceEndLocation: Double,
        coordinates: [CLLocationCoordinate2D],
        sourceLocations: [Double]
    ) -> RouteSlopeGradient {
        guard coordinates.count == sourceLocations.count,
              coordinates.count > 1,
              gradient.locations.count == gradient.normalizedSlopes.count,
              sourceEndLocation > sourceStartLocation else {
            return gradient
        }

        let mapPoints = coordinates.map(MKMapPoint.init)
        var cumulativeLengths = Array(repeating: 0.0, count: mapPoints.count)
        for index in 1..<mapPoints.count {
            cumulativeLengths[index] = cumulativeLengths[index - 1] + hypot(
                mapPoints[index].x - mapPoints[index - 1].x,
                mapPoints[index].y - mapPoints[index - 1].y
            )
        }
        guard let totalLength = cumulativeLengths.last,
              totalLength.isFinite,
              totalLength > 0 else {
            return gradient
        }

        var mappedLocations: [Double] = []
        mappedLocations.reserveCapacity(gradient.locations.count)
        for localSourceLocation in gradient.locations {
            if localSourceLocation <= 0 {
                mappedLocations.append(0)
                continue
            }
            if localSourceLocation >= 1 {
                mappedLocations.append(1)
                continue
            }

            let sourceLocation = sourceStartLocation
                + (sourceEndLocation - sourceStartLocation) * localSourceLocation
            let upperIndex = firstIndex(
                in: sourceLocations,
                atOrAfter: sourceLocation
            )
            let lowerIndex = max(upperIndex - 1, 0)
            let sourceSpan = sourceLocations[upperIndex] - sourceLocations[lowerIndex]
            let progress: Double
            if sourceSpan > 0 {
                progress = min(
                    max((sourceLocation - sourceLocations[lowerIndex]) / sourceSpan, 0),
                    1
                )
            } else {
                progress = 0
            }
            let mappedLength = cumulativeLengths[lowerIndex]
                + (cumulativeLengths[upperIndex] - cumulativeLengths[lowerIndex]) * progress
            mappedLocations.append(min(max(mappedLength / totalLength, 0), 1))
        }

        guard zip(mappedLocations, mappedLocations.dropFirst()).allSatisfy({ $1 > $0 }) else {
            return gradient
        }
        return RouteSlopeGradient(
            locations: mappedLocations,
            normalizedSlopes: gradient.normalizedSlopes
        )
    }

    private static func firstIndex(
        in locations: [Double],
        atOrAfter target: Double
    ) -> Int {
        var lowerBound = 1
        var upperBound = locations.count - 1
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if locations[middleIndex] < target {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }
        return lowerBound
    }
}
