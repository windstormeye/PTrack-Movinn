//
//  RouteSlopeGradient.swift
//  PTrack
//
//  Created by Codex on 2026/7/11.
//

import CoreLocation
import Foundation

struct RouteSlopeGradient: Sendable {
    let locations: [Double]
    let normalizedSlopes: [Double?]

    nonisolated static func make(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        maximumStopCount: Int = 128,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> RouteSlopeGradient? {
        guard !isCancelled(),
              distances.count == altitudes.count,
              distances.count > 1,
              maximumStopCount > 1,
              let totalDistance = distances.last,
              totalDistance.isFinite,
              totalDistance >= 20,
              areValidCumulativeDistances(distances, isCancelled: isCancelled),
              let samples = resampledAltitudes(
                altitudes,
                distances: distances,
                totalDistance: totalDistance,
                isCancelled: isCancelled
              ) else {
            return nil
        }

        guard let filteredAltitudes = replacingAltitudeSpikes(
            in: samples.altitudes,
            isCancelled: isCancelled
        ) else {
            return nil
        }
        let sampleSpacing = samples.distances.count > 1
            ? samples.distances[1] - samples.distances[0]
            : 0
        let gradeWindow = max(
            min(max(totalDistance / 200, 40), 120),
            sampleSpacing * 4
        )
        guard let slopes = regressionSlopes(
            altitudes: filteredAltitudes,
            distances: samples.distances,
            window: gradeWindow,
            isCancelled: isCancelled
        ),
        let normalizedSlopes = normalized(slopes, isCancelled: isCancelled) else {
            return nil
        }

        guard let stopIndices = gradientStopIndices(
            distances: samples.distances,
            normalizedSlopes: normalizedSlopes,
            maximumCount: maximumStopCount,
            isCancelled: isCancelled
        ) else {
            return nil
        }
        var locations: [Double] = []
        var stopSlopes: [Double?] = []
        locations.reserveCapacity(stopIndices.count)
        stopSlopes.reserveCapacity(stopIndices.count)
        for (offset, index) in stopIndices.enumerated() {
            if offset.isMultiple(of: 256), isCancelled() {
                return nil
            }
            locations.append(min(max(samples.distances[index] / totalDistance, 0), 1))
            stopSlopes.append(normalizedSlopes[index])
        }
        guard !isCancelled(),
              locations.count > 1 else {
            return nil
        }

        return RouteSlopeGradient(
            locations: locations,
            normalizedSlopes: stopSlopes
        )
    }

    nonisolated func section(
        from startLocation: Double,
        to endLocation: Double
    ) -> RouteSlopeGradient? {
        guard locations.count == normalizedSlopes.count,
              locations.count > 1,
              startLocation.isFinite,
              endLocation.isFinite else {
            return nil
        }

        let lowerBound = min(max(startLocation, 0), 1)
        let upperBound = min(max(endLocation, 0), 1)
        guard upperBound - lowerBound > 0.000_001 else {
            return nil
        }

        var sectionLocations: [Double] = [0]
        var sectionSlopes: [Double?] = [normalizedSlope(at: lowerBound)]
        for index in locations.indices {
            let location = locations[index]
            guard location > lowerBound,
                  location < upperBound else {
                continue
            }

            sectionLocations.append((location - lowerBound) / (upperBound - lowerBound))
            sectionSlopes.append(normalizedSlopes[index])
        }
        sectionLocations.append(1)
        sectionSlopes.append(normalizedSlope(at: upperBound))

        return RouteSlopeGradient(
            locations: sectionLocations,
            normalizedSlopes: sectionSlopes
        )
    }

    private nonisolated func normalizedSlope(at location: Double) -> Double? {
        guard let firstLocation = locations.first,
              let lastLocation = locations.last else {
            return nil
        }
        if location <= firstLocation {
            return normalizedSlopes.first ?? nil
        }
        if location >= lastLocation {
            return normalizedSlopes.last ?? nil
        }

        var lowerIndex = 0
        var upperIndex = locations.count - 1
        while lowerIndex + 1 < upperIndex {
            let middleIndex = (lowerIndex + upperIndex) / 2
            if locations[middleIndex] <= location {
                lowerIndex = middleIndex
            } else {
                upperIndex = middleIndex
            }
        }

        let lowerLocation = locations[lowerIndex]
        let upperLocation = locations[upperIndex]
        guard upperLocation > lowerLocation else {
            return normalizedSlopes[lowerIndex]
        }
        let progress = (location - lowerLocation) / (upperLocation - lowerLocation)
        switch (normalizedSlopes[lowerIndex], normalizedSlopes[upperIndex]) {
        case let (lowerSlope?, upperSlope?):
            return lowerSlope + (upperSlope - lowerSlope) * progress
        case (nil, nil):
            return nil
        case let (lowerSlope?, nil):
            return progress < 0.5 ? lowerSlope : nil
        case let (nil, upperSlope?):
            return progress < 0.5 ? nil : upperSlope
        }
    }

    private struct AltitudeSamples {
        let distances: [CLLocationDistance]
        let altitudes: [Double?]
    }

    private nonisolated static func areValidCumulativeDistances(
        _ distances: [CLLocationDistance],
        isCancelled: @Sendable () -> Bool
    ) -> Bool {
        for index in distances.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return false
            }
            guard distances[index].isFinite,
                  index == 0 || distances[index] >= distances[index - 1] else {
                return false
            }
        }
        return true
    }

    private nonisolated static func resampledAltitudes(
        _ altitudes: [Double?],
        distances: [CLLocationDistance],
        totalDistance: CLLocationDistance,
        isCancelled: @Sendable () -> Bool
    ) -> AltitudeSamples? {
        var validSamples: [(distance: CLLocationDistance, altitude: Double)] = []
        validSamples.reserveCapacity(altitudes.count)
        for index in altitudes.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            guard let altitude = altitudes[index], altitude.isFinite else {
                continue
            }

            let distance = distances[index]
            if let lastSample = validSamples.last,
               abs(lastSample.distance - distance) < 0.001 {
                validSamples[validSamples.count - 1] = (distance, altitude)
            } else {
                validSamples.append((distance, altitude))
            }
        }
        guard validSamples.count >= 3 else {
            return nil
        }

        var positiveSpacings: [CLLocationDistance] = []
        positiveSpacings.reserveCapacity(max(validSamples.count - 1, 0))
        for index in 1..<validSamples.count {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let spacing = validSamples[index].distance - validSamples[index - 1].distance
            if spacing.isFinite, spacing > 0 {
                positiveSpacings.append(spacing)
            }
        }
        positiveSpacings.sort()
        guard !isCancelled() else {
            return nil
        }
        guard !positiveSpacings.isEmpty else {
            return nil
        }

        let medianSpacing = median(of: positiveSpacings)
        let maximumInterpolationGap = max(250, min(medianSpacing * 5, 1_000))
        let preferredStep = min(max(totalDistance / 4_000, 5), 25)
        let sampleCount = min(20_001, max(2, Int(ceil(totalDistance / preferredStep)) + 1))
        let sampleStep = totalDistance / Double(sampleCount - 1)
        var sampleDistances: [CLLocationDistance] = []
        sampleDistances.reserveCapacity(sampleCount)
        for sampleIndex in 0..<sampleCount {
            if sampleIndex.isMultiple(of: 256), isCancelled() {
                return nil
            }
            sampleDistances.append(Double(sampleIndex) * sampleStep)
        }
        var sampleAltitudes = Array<Double?>(repeating: nil, count: sampleCount)
        var upperValidIndex = 1

        for sampleIndex in sampleDistances.indices {
            if sampleIndex.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let distance = sampleDistances[sampleIndex]
            while upperValidIndex < validSamples.count - 1,
                  validSamples[upperValidIndex].distance < distance {
                upperValidIndex += 1
                if upperValidIndex.isMultiple(of: 256), isCancelled() {
                    return nil
                }
            }

            let lowerSample = validSamples[upperValidIndex - 1]
            let upperSample = validSamples[upperValidIndex]
            if abs(distance - lowerSample.distance) <= sampleStep / 2 {
                sampleAltitudes[sampleIndex] = lowerSample.altitude
                continue
            }
            if abs(distance - upperSample.distance) <= sampleStep / 2 {
                sampleAltitudes[sampleIndex] = upperSample.altitude
                continue
            }
            guard distance > lowerSample.distance,
                  distance < upperSample.distance else {
                continue
            }

            let gap = upperSample.distance - lowerSample.distance
            guard gap > 0, gap <= maximumInterpolationGap else {
                continue
            }
            let progress = (distance - lowerSample.distance) / gap
            sampleAltitudes[sampleIndex] = lowerSample.altitude
                + (upperSample.altitude - lowerSample.altitude) * progress
        }

        var validSampleCount = 0
        for index in sampleAltitudes.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            if sampleAltitudes[index] != nil {
                validSampleCount += 1
            }
        }
        let validCoverage = Double(validSampleCount) / Double(sampleCount)
        guard validCoverage >= 0.35 else {
            return nil
        }
        return AltitudeSamples(distances: sampleDistances, altitudes: sampleAltitudes)
    }

    private nonisolated static func replacingAltitudeSpikes(
        in altitudes: [Double?],
        isCancelled: @Sendable () -> Bool
    ) -> [Double?]? {
        guard !isCancelled() else {
            return nil
        }
        guard altitudes.count > 4 else {
            return altitudes
        }

        var filtered = altitudes
        for index in altitudes.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            guard let altitude = altitudes[index] else {
                continue
            }

            let lowerIndex = max(index - 2, 0)
            let upperIndex = min(index + 2, altitudes.count - 1)
            let neighborhood = altitudes[lowerIndex...upperIndex].compactMap { $0 }.sorted()
            guard neighborhood.count >= 3 else {
                continue
            }

            let localMedian = median(of: neighborhood)
            let deviations = neighborhood.map { abs($0 - localMedian) }.sorted()
            let medianDeviation = median(of: deviations)
            let threshold = max(6, 3 * 1.4826 * medianDeviation)
            if abs(altitude - localMedian) > threshold {
                filtered[index] = localMedian
            }
        }
        return filtered
    }

    private nonisolated static func regressionSlopes(
        altitudes: [Double?],
        distances: [CLLocationDistance],
        window: CLLocationDistance,
        isCancelled: @Sendable () -> Bool
    ) -> [Double?]? {
        guard !isCancelled() else {
            return nil
        }
        let halfWindow = window / 2
        var slopes = Array<Double?>(repeating: nil, count: altitudes.count)
        var lowerIndex = 0
        var upperIndex = 0

        for index in altitudes.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            while lowerIndex < index,
                  distances[index] - distances[lowerIndex] > halfWindow {
                lowerIndex += 1
            }
            upperIndex = max(upperIndex, index)
            while upperIndex + 1 < altitudes.count,
                  distances[upperIndex + 1] - distances[index] <= halfWindow {
                upperIndex += 1
            }

            let availablePointCount = upperIndex - lowerIndex + 1
            let requiredPointCount = max(3, Int(ceil(Double(availablePointCount) * 0.6)))
            var pointCount = 0
            var sumX = 0.0
            var sumY = 0.0
            var sumXX = 0.0
            var sumXY = 0.0
            for sampleIndex in lowerIndex...upperIndex {
                guard let altitude = altitudes[sampleIndex] else {
                    continue
                }
                let x = distances[sampleIndex] - distances[index]
                pointCount += 1
                sumX += x
                sumY += altitude
                sumXX += x * x
                sumXY += x * altitude
            }

            guard pointCount >= requiredPointCount else {
                continue
            }
            let count = Double(pointCount)
            let denominator = count * sumXX - sumX * sumX
            guard denominator.isFinite, abs(denominator) > 0.000_001 else {
                continue
            }

            let slope = (count * sumXY - sumX * sumY) / denominator
            guard slope.isFinite else {
                continue
            }
            slopes[index] = min(abs(slope), 1)
        }
        return slopes
    }

    private nonisolated static func normalized(
        _ slopes: [Double?],
        isCancelled: @Sendable () -> Bool
    ) -> [Double?]? {
        var validSlopes: [Double] = []
        validSlopes.reserveCapacity(slopes.count)
        for index in slopes.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            if let slope = slopes[index] {
                validSlopes.append(slope)
            }
        }
        validSlopes.sort()
        guard !isCancelled() else {
            return nil
        }
        let validCoverage = Double(validSlopes.count) / Double(max(slopes.count, 1))
        guard validSlopes.count >= 3, validCoverage >= 0.35 else {
            return nil
        }

        guard let maximumSlope = validSlopes.last,
              maximumSlope >= 0.02 else {
            var normalizedSlopes: [Double?] = []
            normalizedSlopes.reserveCapacity(slopes.count)
            for index in slopes.indices {
                if index.isMultiple(of: 256), isCancelled() {
                    return nil
                }
                normalizedSlopes.append(slopes[index] == nil ? nil : 0)
            }
            return normalizedSlopes
        }

        let steepSlope = max(percentile(0.95, in: validSlopes), 0.02)
        let gentleSlope = 0.01
        let spread = steepSlope - gentleSlope

        var normalizedSlopes: [Double?] = []
        normalizedSlopes.reserveCapacity(slopes.count)
        for index in slopes.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            normalizedSlopes.append(
                slopes[index].map { min(max(($0 - gentleSlope) / spread, 0), 1) }
            )
        }
        return normalizedSlopes
    }

    private nonisolated static func percentile(_ percentile: Double, in values: [Double]) -> Double {
        guard values.count > 1 else {
            return values.first ?? 0
        }

        let position = min(max(percentile, 0), 1) * Double(values.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else {
            return values[lowerIndex]
        }

        let progress = position - Double(lowerIndex)
        return values[lowerIndex] + (values[upperIndex] - values[lowerIndex]) * progress
    }

    private nonisolated static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let middleIndex = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middleIndex - 1] + values[middleIndex]) / 2
        }
        return values[middleIndex]
    }

    private nonisolated static func gradientStopIndices(
        distances: [CLLocationDistance],
        normalizedSlopes: [Double?],
        maximumCount: Int,
        isCancelled: @Sendable () -> Bool
    ) -> [Int]? {
        guard !isCancelled() else {
            return nil
        }
        guard distances.count == normalizedSlopes.count else {
            return nil
        }
        guard distances.count > maximumCount else {
            return Array(distances.indices)
        }
        guard let totalDistance = distances.last,
              totalDistance > 0 else {
            return nil
        }

        var selectedIndices = Set([0, distances.count - 1])
        let availableStopCount = max(maximumCount - selectedIndices.count, 0)
        let refinementReserve = availableStopCount > 0
            ? max(1, Int(ceil(Double(availableStopCount) * 0.25)))
            : 0
        let featureSelectionLimit = max(maximumCount - refinementReserve, selectedIndices.count)
        let spatialBucketCount = min(max(maximumCount / 4, 8), 32)
        guard let significantPeakIndices = significantLocalPeakIndices(
                distances: distances,
                normalizedSlopes: normalizedSlopes,
                totalDistance: totalDistance,
                isCancelled: isCancelled
              ),
              let missingBoundaryPairs = missingDataBoundaryIndexPairs(
                normalizedSlopes: normalizedSlopes,
                isCancelled: isCancelled
              ),
              let thresholdCrossingIndices = colorThresholdCrossingIndices(
                normalizedSlopes: normalizedSlopes,
                isCancelled: isCancelled
              ) else {
            return nil
        }

        var peakGroups: [[Int]] = []
        peakGroups.reserveCapacity(significantPeakIndices.count)
        for (index, peakIndex) in significantPeakIndices.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            peakGroups.append([peakIndex])
        }
        var boundaryGroups: [[Int]] = []
        boundaryGroups.reserveCapacity(missingBoundaryPairs.count)
        for (index, pair) in missingBoundaryPairs.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            boundaryGroups.append([pair.before, pair.after])
        }
        var thresholdGroups: [[Int]] = []
        thresholdGroups.reserveCapacity(thresholdCrossingIndices.count)
        for (index, thresholdIndex) in thresholdCrossingIndices.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            thresholdGroups.append([thresholdIndex])
        }

        guard let distributedPeakGroups = spatiallyDistributedFeatureGroups(
                peakGroups,
                distances: distances,
                totalDistance: totalDistance,
                bucketCount: spatialBucketCount,
                isCancelled: isCancelled
              ),
              let distributedBoundaryGroups = spatiallyDistributedFeatureGroups(
                boundaryGroups,
                distances: distances,
                totalDistance: totalDistance,
                bucketCount: spatialBucketCount,
                isCancelled: isCancelled
              ),
              let distributedThresholdGroups = spatiallyDistributedFeatureGroups(
                thresholdGroups,
                distances: distances,
                totalDistance: totalDistance,
                bucketCount: spatialBucketCount,
                isCancelled: isCancelled
              ) else {
            return nil
        }

        let featureQueues = [
            distributedPeakGroups,
            distributedBoundaryGroups,
            distributedThresholdGroups
        ]
        var missingBoundaryPartnerByIndex: [Int: Int] = [:]
        for (index, pair) in missingBoundaryPairs.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            missingBoundaryPartnerByIndex[pair.before] = pair.after
            missingBoundaryPartnerByIndex[pair.after] = pair.before
        }
        var featureQueueOffsets = Array(repeating: 0, count: featureQueues.count)

        // Give local peaks half of each selection round while still reserving room
        // for missing-data boundaries and color-band transitions. A final quarter
        // of the total budget is kept for interpolation-error and distance coverage.
        let featureSelectionOrder = [0, 1, 0, 2]
        while selectedIndices.count < featureSelectionLimit {
            if isCancelled() {
                return nil
            }
            var madeProgress = false
            for queueIndex in featureSelectionOrder where
                selectedIndices.count < featureSelectionLimit {
                while featureQueueOffsets[queueIndex] < featureQueues[queueIndex].count {
                    if featureQueueOffsets[queueIndex].isMultiple(of: 256), isCancelled() {
                        return nil
                    }
                    var candidateGroup = featureQueues[queueIndex][featureQueueOffsets[queueIndex]]
                    featureQueueOffsets[queueIndex] += 1

                    if queueIndex != 1,
                       let candidateIndex = candidateGroup.first,
                       let boundaryPartner = missingBoundaryPartnerByIndex[candidateIndex] {
                        candidateGroup.append(boundaryPartner)
                    }
                    let unselectedGroup = Array(Set(candidateGroup)).filter {
                        !selectedIndices.contains($0)
                    }
                    guard !unselectedGroup.isEmpty else {
                        continue
                    }
                    guard selectedIndices.count + unselectedGroup.count
                            <= featureSelectionLimit else {
                        // Missing-data boundary pairs are indivisible. If the
                        // remaining feature budget cannot fit a whole group, skip it.
                        continue
                    }
                    selectedIndices.formUnion(unselectedGroup)
                    madeProgress = true
                    break
                }
            }
            if !madeProgress {
                break
            }
        }

        // Do not let refinement accidentally retain just one side of a missing-data
        // boundary that feature selection skipped. Boundary pairs are only added as
        // feature groups above; untouched members are unavailable to single-point
        // refinement.
        var refinementExcludedIndices = Set<Int>()
        for (index, pair) in missingBoundaryPairs.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let hasBefore = selectedIndices.contains(pair.before)
            let hasAfter = selectedIndices.contains(pair.after)
            if !(hasBefore && hasAfter) {
                refinementExcludedIndices.insert(pair.before)
                refinementExcludedIndices.insert(pair.after)
            }
        }

        while selectedIndices.count < maximumCount {
            if isCancelled() {
                return nil
            }
            let sortedIndices = selectedIndices.sorted()
            let nextIndex = nextGradientStopIndex(
                between: sortedIndices,
                distances: distances,
                normalizedSlopes: normalizedSlopes,
                totalDistance: totalDistance,
                excludedIndices: refinementExcludedIndices,
                isCancelled: isCancelled
            )
            if isCancelled() {
                return nil
            }
            guard let nextIndex,
                  selectedIndices.insert(nextIndex).inserted else {
                break
            }
        }
        return selectedIndices.sorted()
    }

    private nonisolated static func spatiallyDistributedFeatureGroups(
        _ prioritizedGroups: [[Int]],
        distances: [CLLocationDistance],
        totalDistance: CLLocationDistance,
        bucketCount: Int,
        isCancelled: @Sendable () -> Bool
    ) -> [[Int]]? {
        guard !isCancelled() else {
            return nil
        }
        guard prioritizedGroups.count > 1,
              bucketCount > 1,
              totalDistance > 0 else {
            return prioritizedGroups
        }

        var buckets = Array(repeating: [[Int]](), count: bucketCount)
        for (index, group) in prioritizedGroups.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            guard let representativeIndex = group.first,
                  distances.indices.contains(representativeIndex) else {
                continue
            }
            let location = min(max(distances[representativeIndex] / totalDistance, 0), 1)
            let bucketIndex = min(Int(location * Double(bucketCount)), bucketCount - 1)
            buckets[bucketIndex].append(group)
        }

        let bucketOrder = spatialBucketOrder(count: bucketCount)
        var bucketOffsets = Array(repeating: 0, count: bucketCount)
        var distributedGroups: [[Int]] = []
        distributedGroups.reserveCapacity(prioritizedGroups.count)
        while distributedGroups.count < prioritizedGroups.count {
            if distributedGroups.count.isMultiple(of: 256), isCancelled() {
                return nil
            }
            var madeProgress = false
            for bucketIndex in bucketOrder where bucketOffsets[bucketIndex] < buckets[bucketIndex].count {
                distributedGroups.append(buckets[bucketIndex][bucketOffsets[bucketIndex]])
                bucketOffsets[bucketIndex] += 1
                madeProgress = true
            }
            if !madeProgress {
                break
            }
        }
        return distributedGroups
    }

    private nonisolated static func spatialBucketOrder(count: Int) -> [Int] {
        guard count > 0 else {
            return []
        }

        var ranges: [(lower: Int, upper: Int)] = [(0, count - 1)]
        var rangeIndex = 0
        var order: [Int] = []
        order.reserveCapacity(count)
        while rangeIndex < ranges.count {
            let range = ranges[rangeIndex]
            rangeIndex += 1
            let middle = (range.lower + range.upper) / 2
            order.append(middle)
            if range.lower < middle {
                ranges.append((range.lower, middle - 1))
            }
            if middle < range.upper {
                ranges.append((middle + 1, range.upper))
            }
        }
        return order
    }

    private nonisolated static func significantLocalPeakIndices(
        distances: [CLLocationDistance],
        normalizedSlopes: [Double?],
        totalDistance: CLLocationDistance,
        isCancelled: @Sendable () -> Bool
    ) -> [Int]? {
        guard !isCancelled() else {
            return nil
        }
        guard normalizedSlopes.count > 2 else {
            return []
        }

        let prominenceWindow = min(max(totalDistance / 650, 120), 400)
        let minimumPeakSeparation = min(max(totalDistance / 4_000, 35), 80)
        var candidates: [(index: Int, score: Double)] = []

        for index in 1..<(normalizedSlopes.count - 1) {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            guard let previousSlope = normalizedSlopes[index - 1],
                  let slope = normalizedSlopes[index],
                  let nextSlope = normalizedSlopes[index + 1],
                  slope >= previousSlope,
                  slope >= nextSlope,
                  slope > previousSlope || slope > nextSlope else {
                continue
            }

            var leftMinimum = slope
            var leftIndex = index - 1
            while true {
                if let candidateSlope = normalizedSlopes[leftIndex] {
                    leftMinimum = min(leftMinimum, candidateSlope)
                }
                if leftIndex == 0
                    || distances[index] - distances[leftIndex - 1] > prominenceWindow {
                    break
                }
                leftIndex -= 1
            }

            var rightMinimum = slope
            var rightIndex = index + 1
            while true {
                if let candidateSlope = normalizedSlopes[rightIndex] {
                    rightMinimum = min(rightMinimum, candidateSlope)
                }
                if rightIndex == normalizedSlopes.count - 1
                    || distances[rightIndex + 1] - distances[index] > prominenceWindow {
                    break
                }
                rightIndex += 1
            }

            let prominence = slope - max(leftMinimum, rightMinimum)
            let minimumProminence = slope >= 0.7 ? 0.025 : 0.055
            guard slope >= 0.18,
                  prominence >= minimumProminence else {
                continue
            }

            candidates.append((
                index: index,
                score: slope + min(prominence * 2, 1)
            ))
        }

        guard !candidates.isEmpty else {
            return []
        }

        // Collapse nearby noise peaks to the strongest representative while
        // allowing distinct 50-300 m efforts to retain their own peak.
        var separatedCandidates: [(index: Int, score: Double)] = []
        for (index, candidate) in candidates.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            guard let lastCandidate = separatedCandidates.last,
                  distances[candidate.index] - distances[lastCandidate.index]
                    < minimumPeakSeparation else {
                separatedCandidates.append(candidate)
                continue
            }
            if candidate.score > lastCandidate.score {
                separatedCandidates[separatedCandidates.count - 1] = candidate
            }
        }

        separatedCandidates.sort {
                if abs($0.score - $1.score) > 0.000_001 {
                    return $0.score > $1.score
                }
                return $0.index < $1.index
            }
        guard !isCancelled() else {
            return nil
        }
        var peakIndices: [Int] = []
        peakIndices.reserveCapacity(separatedCandidates.count)
        for (index, candidate) in separatedCandidates.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            peakIndices.append(candidate.index)
        }
        return peakIndices
    }

    private nonisolated static func missingDataBoundaryIndexPairs(
        normalizedSlopes: [Double?],
        isCancelled: @Sendable () -> Bool
    ) -> [(before: Int, after: Int)]? {
        guard !isCancelled() else {
            return nil
        }
        var pairs: [(before: Int, after: Int)] = []
        pairs.reserveCapacity(normalizedSlopes.count / 16)
        for index in 1..<normalizedSlopes.count {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            if (normalizedSlopes[index - 1] == nil) != (normalizedSlopes[index] == nil) {
                pairs.append((before: index - 1, after: index))
            }
        }
        return pairs
    }

    private nonisolated static func colorThresholdCrossingIndices(
        normalizedSlopes: [Double?],
        isCancelled: @Sendable () -> Bool
    ) -> [Int]? {
        guard !isCancelled() else {
            return nil
        }
        let thresholds = [0.2, 0.4, 0.6, 0.8]
        var candidates: [(index: Int, threshold: Double, change: Double)] = []

        for index in 1..<normalizedSlopes.count {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            guard let previousSlope = normalizedSlopes[index - 1],
                  let slope = normalizedSlopes[index],
                  previousSlope != slope else {
                continue
            }

            let lowerSlope = min(previousSlope, slope)
            let upperSlope = max(previousSlope, slope)
            for threshold in thresholds where threshold > lowerSlope && threshold <= upperSlope {
                let candidateIndex = abs(previousSlope - threshold) <= abs(slope - threshold)
                    ? index - 1
                    : index
                candidates.append((
                    index: candidateIndex,
                    threshold: threshold,
                    change: upperSlope - lowerSlope
                ))
            }
        }

        var bestCandidateByIndex: [Int: (threshold: Double, change: Double)] = [:]
        for (index, candidate) in candidates.enumerated() {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let existingCandidate = bestCandidateByIndex[candidate.index]
            if existingCandidate == nil
                || candidate.threshold > existingCandidate?.threshold ?? 0
                || candidate.threshold == existingCandidate?.threshold
                    && candidate.change > existingCandidate?.change ?? 0 {
                bestCandidateByIndex[candidate.index] = (
                    threshold: candidate.threshold,
                    change: candidate.change
                )
            }
        }

        var bestCandidates: [(index: Int, threshold: Double, change: Double)] = []
        bestCandidates.reserveCapacity(bestCandidateByIndex.count)
        for (offset, candidate) in bestCandidateByIndex.enumerated() {
            if offset.isMultiple(of: 256), isCancelled() {
                return nil
            }
            bestCandidates.append((
                index: candidate.key,
                threshold: candidate.value.threshold,
                change: candidate.value.change
            ))
        }
        bestCandidates.sort {
                if $0.threshold != $1.threshold {
                    return $0.threshold > $1.threshold
                }
                if abs($0.change - $1.change) > 0.000_001 {
                    return $0.change > $1.change
                }
                return $0.index < $1.index
            }
        guard !isCancelled() else {
            return nil
        }
        var indices: [Int] = []
        indices.reserveCapacity(bestCandidates.count)
        for (offset, candidate) in bestCandidates.enumerated() {
            if offset.isMultiple(of: 256), isCancelled() {
                return nil
            }
            indices.append(candidate.index)
        }
        return indices
    }

    private nonisolated static func nextGradientStopIndex(
        between selectedIndices: [Int],
        distances: [CLLocationDistance],
        normalizedSlopes: [Double?],
        totalDistance: CLLocationDistance,
        excludedIndices: Set<Int>,
        isCancelled: @Sendable () -> Bool
    ) -> Int? {
        guard !isCancelled(),
              selectedIndices.count > 1 else {
            return nil
        }

        var bestErrorCandidate: (index: Int, score: Double)?
        var bestDistanceCandidate: (index: Int, distance: CLLocationDistance)?

        var visitedPointCount = 0
        for selectedIndex in 0..<(selectedIndices.count - 1) {
            let lowerIndex = selectedIndices[selectedIndex]
            let upperIndex = selectedIndices[selectedIndex + 1]
            guard upperIndex - lowerIndex > 1 else {
                continue
            }

            let intervalDistance = distances[upperIndex] - distances[lowerIndex]
            guard intervalDistance.isFinite,
                  intervalDistance > 0 else {
                continue
            }

            let lowerSlope = normalizedSlopes[lowerIndex]
            let upperSlope = normalizedSlopes[upperIndex]
            var intervalErrorCandidate: (index: Int, score: Double)?
            var midpointCandidate: (index: Int, distance: CLLocationDistance)?
            let targetDistance = (distances[lowerIndex] + distances[upperIndex]) / 2

            for index in (lowerIndex + 1)..<upperIndex {
                visitedPointCount += 1
                if visitedPointCount.isMultiple(of: 256), isCancelled() {
                    return nil
                }
                guard !excludedIndices.contains(index),
                      let slope = normalizedSlopes[index] else {
                    continue
                }

                let midpointDistance = abs(distances[index] - targetDistance)
                if midpointCandidate == nil
                    || midpointDistance < midpointCandidate?.distance ?? .greatestFiniteMagnitude {
                    midpointCandidate = (index: index, distance: midpointDistance)
                }

                let progress = (distances[index] - distances[lowerIndex]) / intervalDistance
                let expectedSlope: Double
                if let lowerSlope, let upperSlope {
                    expectedSlope = lowerSlope + (upperSlope - lowerSlope) * progress
                } else {
                    expectedSlope = 0
                }
                var error = abs(slope - expectedSlope)
                if slope > expectedSlope {
                    error *= 1.25
                }
                let score = error + slope * 0.015
                if intervalErrorCandidate == nil
                    || score > intervalErrorCandidate?.score ?? -.greatestFiniteMagnitude {
                    intervalErrorCandidate = (index: index, score: score)
                }
            }

            if let intervalErrorCandidate,
               bestErrorCandidate == nil
                || intervalErrorCandidate.score > bestErrorCandidate?.score
                    ?? -.greatestFiniteMagnitude {
                bestErrorCandidate = intervalErrorCandidate
            }
            if let midpointCandidate,
               bestDistanceCandidate == nil
                || intervalDistance > bestDistanceCandidate?.distance ?? 0 {
                bestDistanceCandidate = (
                    index: midpointCandidate.index,
                    distance: intervalDistance
                )
            }
        }

        let minimumMeaningfulError = max(0.012, 1 / Double(max(selectedIndices.count, 1_000)))
        if let bestErrorCandidate,
           bestErrorCandidate.score >= minimumMeaningfulError {
            return bestErrorCandidate.index
        }
        if let bestDistanceCandidate,
           bestDistanceCandidate.distance / totalDistance > 0.000_001 {
            return bestDistanceCandidate.index
        }
        return bestErrorCandidate?.index
    }
}
