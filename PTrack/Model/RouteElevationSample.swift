//
//  RouteElevationSample.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import CoreLocation
import Foundation

nonisolated struct RouteElevationSample: Sendable {
    let distanceMeters: CLLocationDistance
    let altitudeMeters: Double
    let heartRateBeatsPerMinute: Double?
    let powerWatts: Double?
    let temperatureCelsius: Double?
    let seriesIdentifier: Int

    init(
        distanceMeters: CLLocationDistance,
        altitudeMeters: Double,
        heartRateBeatsPerMinute: Double? = nil,
        powerWatts: Double? = nil,
        temperatureCelsius: Double? = nil,
        seriesIdentifier: Int = 0
    ) {
        self.distanceMeters = distanceMeters
        self.altitudeMeters = altitudeMeters
        self.heartRateBeatsPerMinute = heartRateBeatsPerMinute
        self.powerWatts = powerWatts
        self.temperatureCelsius = temperatureCelsius
        self.seriesIdentifier = seriesIdentifier
    }
}

nonisolated enum RouteElevationSampler {
    static func downsample(
        _ samples: [RouteElevationSample],
        maximumCount: Int,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> [RouteElevationSample]? {
        guard !isCancelled() else {
            return nil
        }
        guard maximumCount > 0 else {
            return []
        }
        guard samples.count > maximumCount else {
            return samples
        }
        if maximumCount == 1 {
            return samples.first.map { [$0] } ?? []
        }
        if maximumCount == 2 {
            return [samples[0], samples[samples.count - 1]]
        }

        var altitudeMinimumIndex = 0
        var altitudeMaximumIndex = 0
        var heartRatePeak: (index: Int, value: Double)?
        var powerPeak: (index: Int, value: Double)?
        var temperaturePeak: (index: Int, value: Double)?
        var seriesBoundaryIndices: [Int] = []
        seriesBoundaryIndices.reserveCapacity(min(samples.count / 8, maximumCount))

        for index in samples.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let sample = samples[index]
            if sample.altitudeMeters < samples[altitudeMinimumIndex].altitudeMeters {
                altitudeMinimumIndex = index
            }
            if sample.altitudeMeters > samples[altitudeMaximumIndex].altitudeMeters {
                altitudeMaximumIndex = index
            }
            if let value = sample.heartRateBeatsPerMinute,
               value.isFinite,
               value > 0,
               heartRatePeak == nil || value > (heartRatePeak?.value ?? -.greatestFiniteMagnitude) {
                heartRatePeak = (index, value)
            }
            if let value = sample.powerWatts,
               value.isFinite,
               value > 0,
               powerPeak == nil || value > (powerPeak?.value ?? -.greatestFiniteMagnitude) {
                powerPeak = (index, value)
            }
            if let value = sample.temperatureCelsius,
               value.isFinite,
               temperaturePeak == nil || value > (temperaturePeak?.value ?? -.greatestFiniteMagnitude) {
                temperaturePeak = (index, value)
            }
            if index > 0,
               sample.seriesIdentifier != samples[index - 1].seriesIdentifier {
                seriesBoundaryIndices.append(index - 1)
                seriesBoundaryIndices.append(index)
            }
        }

        var selectedIndices = Set<Int>()
        selectedIndices.reserveCapacity(maximumCount)
        let essentialIndices = [
            samples.startIndex,
            samples.index(before: samples.endIndex),
            altitudeMinimumIndex,
            altitudeMaximumIndex,
            heartRatePeak?.index,
            powerPeak?.index,
            temperaturePeak?.index
        ].compactMap { $0 }
        for index in essentialIndices where selectedIndices.count < maximumCount {
            selectedIndices.insert(index)
        }

        let uniqueBoundaryIndices = Array(Set(seriesBoundaryIndices)).sorted()
        let boundaryBudget = min(
            uniqueBoundaryIndices.count,
            maximumCount / 4,
            maximumCount - selectedIndices.count
        )
        insertEvenlySpaced(
            uniqueBoundaryIndices,
            count: boundaryBudget,
            into: &selectedIndices,
            maximumCount: maximumCount
        )

        let remainingForExtrema = maximumCount - selectedIndices.count
        if remainingForExtrema > 0, samples.count > 2 {
            guard addDistanceBucketExtrema(
                samples: samples,
                desiredPointCount: remainingForExtrema,
                selectedIndices: &selectedIndices,
                maximumCount: maximumCount,
                isCancelled: isCancelled
            ) else {
                return nil
            }
        }

        if selectedIndices.count < maximumCount {
            let fillCount = maximumCount - selectedIndices.count
            let firstDistance = samples[0].distanceMeters
            let lastDistance = samples[samples.count - 1].distanceMeters
            let distanceSpan = lastDistance - firstDistance
            let candidateCount = max(fillCount * 2, 2)
            let fillCandidates = (0..<candidateCount).map { position in
                guard distanceSpan > 0 else {
                    return Int(round(
                        Double(samples.count - 1) * Double(position)
                            / Double(max(candidateCount - 1, 1))
                    ))
                }
                let targetDistance = firstDistance
                    + distanceSpan * Double(position) / Double(max(candidateCount - 1, 1))
                return nearestSampleIndex(in: samples, to: targetDistance)
            }
            for index in fillCandidates where selectedIndices.count < maximumCount {
                selectedIndices.insert(index)
            }
        }
        if selectedIndices.count < maximumCount {
            for index in samples.indices where selectedIndices.count < maximumCount {
                selectedIndices.insert(index)
            }
        }

        guard !isCancelled() else {
            return nil
        }
        return selectedIndices.sorted().map { samples[$0] }
    }

    private static func insertEvenlySpaced(
        _ candidates: [Int],
        count: Int,
        into selectedIndices: inout Set<Int>,
        maximumCount: Int
    ) {
        guard count > 0, !candidates.isEmpty else {
            return
        }
        if count >= candidates.count {
            for index in candidates where selectedIndices.count < maximumCount {
                selectedIndices.insert(index)
            }
            return
        }

        for position in 0..<count where selectedIndices.count < maximumCount {
            let candidateIndex = Int(round(
                Double(candidates.count - 1) * Double(position)
                    / Double(max(count - 1, 1))
            ))
            selectedIndices.insert(candidates[candidateIndex])
        }
    }

    private static func addDistanceBucketExtrema(
        samples: [RouteElevationSample],
        desiredPointCount: Int,
        selectedIndices: inout Set<Int>,
        maximumCount: Int,
        isCancelled: @Sendable () -> Bool
    ) -> Bool {
        let interiorCount = samples.count - 2
        let bucketCount = min(max((desiredPointCount + 1) / 2, 1), interiorCount)
        let firstDistance = samples[0].distanceMeters
        let lastDistance = samples[samples.count - 1].distanceMeters
        let distanceSpan = lastDistance - firstDistance

        if distanceSpan <= 0 {
            for bucket in 0..<bucketCount where selectedIndices.count < maximumCount {
                let lowerBound = 1 + interiorCount * bucket / bucketCount
                let upperBound = 1 + interiorCount * (bucket + 1) / bucketCount
                guard insertAltitudeExtrema(
                    samples: samples,
                    range: lowerBound..<upperBound,
                    selectedIndices: &selectedIndices,
                    maximumCount: maximumCount,
                    isCancelled: isCancelled
                ) else {
                    return false
                }
            }
            return !isCancelled()
        }

        var cursor = 1
        let finalInteriorIndex = samples.count - 1
        for bucket in 0..<bucketCount where selectedIndices.count < maximumCount {
            if bucket.isMultiple(of: 128), isCancelled() {
                return false
            }
            let upperDistance = firstDistance
                + distanceSpan * Double(bucket + 1) / Double(bucketCount)
            let lowerIndex = cursor
            while cursor < finalInteriorIndex {
                if cursor.isMultiple(of: 256), isCancelled() {
                    return false
                }
                let isInsideBucket = bucket == bucketCount - 1
                    ? samples[cursor].distanceMeters <= upperDistance
                    : samples[cursor].distanceMeters < upperDistance
                guard isInsideBucket else {
                    break
                }
                cursor += 1
            }
            guard lowerIndex < cursor else {
                continue
            }
            guard insertAltitudeExtrema(
                samples: samples,
                range: lowerIndex..<cursor,
                selectedIndices: &selectedIndices,
                maximumCount: maximumCount,
                isCancelled: isCancelled
            ) else {
                return false
            }
        }
        return !isCancelled()
    }

    private static func insertAltitudeExtrema(
        samples: [RouteElevationSample],
        range: Range<Int>,
        selectedIndices: inout Set<Int>,
        maximumCount: Int,
        isCancelled: @Sendable () -> Bool
    ) -> Bool {
        guard let firstIndex = range.first else {
            return !isCancelled()
        }
        var minimumIndex = firstIndex
        var maximumIndex = firstIndex
        for (offset, index) in range.dropFirst().enumerated() {
            if offset.isMultiple(of: 256), isCancelled() {
                return false
            }
            if samples[index].altitudeMeters < samples[minimumIndex].altitudeMeters {
                minimumIndex = index
            }
            if samples[index].altitudeMeters > samples[maximumIndex].altitudeMeters {
                maximumIndex = index
            }
        }
        for index in [minimumIndex, maximumIndex].sorted()
            where selectedIndices.count < maximumCount {
            selectedIndices.insert(index)
        }
        return !isCancelled()
    }

    private static func nearestSampleIndex(
        in samples: [RouteElevationSample],
        to distance: CLLocationDistance
    ) -> Int {
        var lowerBound = 0
        var upperBound = samples.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if samples[middle].distanceMeters < distance {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        guard lowerBound > 0, lowerBound < samples.count else {
            return min(max(lowerBound, 0), samples.count - 1)
        }
        let previousIndex = lowerBound - 1
        return distance - samples[previousIndex].distanceMeters
            <= samples[lowerBound].distanceMeters - distance
            ? previousIndex
            : lowerBound
    }
}
