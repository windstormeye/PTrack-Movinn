//
//  RouteSlopeGradient.swift
//  PTrack
//
//  Created by Codex on 2026/7/11.
//

import CoreLocation
import Foundation

nonisolated struct RouteSlopePeak: Sendable {
    let distanceMeters: CLLocationDistance
    let altitudeMeters: Double?
    let gradeRatio: Double
}

nonisolated struct RouteSlopeAnalysis: Sendable {
    let gradient: RouteSlopeGradient
    let distances: [CLLocationDistance]
    let gradeRatios: [Double?]
    let steepestUphill: RouteSlopePeak?

    func gradeRatio(at distanceMeters: CLLocationDistance) -> Double? {
        guard distances.count == gradeRatios.count,
              !distances.isEmpty,
              distanceMeters.isFinite else {
            return nil
        }
        if distanceMeters <= distances[0] {
            return gradeRatios[0]
        }
        if distanceMeters >= distances[distances.count - 1] {
            return gradeRatios[gradeRatios.count - 1]
        }

        var lowerBound = 1
        var upperBound = distances.count - 1
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if distances[middleIndex] < distanceMeters {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }
        let upperIndex = lowerBound
        let lowerIndex = upperIndex - 1
        if abs(distances[upperIndex] - distanceMeters) < 0.000_001 {
            return gradeRatios[upperIndex]
        }
        let span = distances[upperIndex] - distances[lowerIndex]
        guard span > 0 else {
            return gradeRatios[upperIndex]
        }
        let progress = min(
            max((distanceMeters - distances[lowerIndex]) / span, 0),
            1
        )
        switch (gradeRatios[lowerIndex], gradeRatios[upperIndex]) {
        case let (lowerGrade?, upperGrade?):
            return lowerGrade + (upperGrade - lowerGrade) * progress
        case (nil, nil), (_?, nil), (nil, _?):
            return nil
        }
    }
}

struct RouteSlopeGradient: Sendable {
    let locations: [Double]
    let normalizedSlopes: [Double?]

    /// Uses the same opaque gradient renderer as measured slope sections so
    /// missing-data sections keep identical stroke coverage and antialiasing.
    nonisolated static let unavailable = RouteSlopeGradient(
        locations: [0, 1],
        normalizedSlopes: [nil, nil]
    )

    nonisolated static func make(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        sourceGradeRatios: [Double?]? = nil,
        sourceCumulativeDistances: [CLLocationDistance?]? = nil,
        maximumStopCount: Int = 128,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> RouteSlopeGradient? {
        analyze(
            distances: distances,
            altitudes: altitudes,
            sourceGradeRatios: sourceGradeRatios,
            sourceCumulativeDistances: sourceCumulativeDistances,
            maximumStopCount: maximumStopCount,
            isCancelled: isCancelled
        )?.gradient
    }

    nonisolated static func analyze(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        sourceGradeRatios: [Double?]? = nil,
        sourceCumulativeDistances: [CLLocationDistance?]? = nil,
        maximumStopCount: Int = 128,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> RouteSlopeAnalysis? {
        guard !isCancelled(),
              distances.count == altitudes.count,
              distances.count > 1,
              maximumStopCount > 1,
              let totalDistance = distances.last,
              totalDistance.isFinite,
              totalDistance >= 20,
              areValidCumulativeDistances(distances, isCancelled: isCancelled) else {
            return nil
        }
        let validatedSourceGrades = validatedSourceGradeRatios(
            sourceGradeRatios,
            sourceCumulativeDistances: sourceCumulativeDistances,
            fallbackDistances: distances,
            isCancelled: isCancelled
        )
        guard !isCancelled() else {
            return nil
        }

        let samples: AltitudeSamples
        if let altitudeSamples = resampledAltitudes(
                altitudes,
                distances: distances,
                totalDistance: totalDistance,
                isCancelled: isCancelled
              ) {
            samples = altitudeSamples
        } else {
            guard !isCancelled(),
                  validatedSourceGrades != nil,
                  let sampleDistances = uniformSampleDistances(
                      totalDistance: totalDistance,
                      isCancelled: isCancelled
                  ) else {
                return nil
            }
            samples = AltitudeSamples(
                distances: sampleDistances,
                altitudes: Array(repeating: nil, count: sampleDistances.count)
            )
        }

        guard let filteredAltitudes = replacingAltitudeSpikes(
            in: samples.altitudes,
            isCancelled: isCancelled
        ) else {
            return nil
        }
        let resampledSourceGrades: [Double?]?
        if let validatedSourceGrades {
            guard let sourceGrades = resampledGradeRatios(
                validatedSourceGrades,
                distances: distances,
                sampleDistances: samples.distances,
                isCancelled: isCancelled
            ) else {
                return nil
            }
            resampledSourceGrades = sourceGrades
        } else {
            resampledSourceGrades = nil
        }

        let slopes: [Double?]
        if let resampledSourceGrades {
            var derivedSlopeMask = Array(
                repeating: false,
                count: resampledSourceGrades.count
            )
            var requiresDerivedSlopes = false
            for index in resampledSourceGrades.indices {
                if index.isMultiple(of: 256), isCancelled() {
                    return nil
                }
                if resampledSourceGrades[index] == nil {
                    derivedSlopeMask[index] = true
                    requiresDerivedSlopes = true
                }
            }

            // A complete native grade stream is already the most faithful source.
            // Only run the altitude regression at samples where that stream has a
            // gap, instead of deriving and immediately discarding a full profile.
            if !requiresDerivedSlopes {
                slopes = resampledSourceGrades
            } else {
                guard let derivedSlopes = regressionSlopes(
                    altitudes: filteredAltitudes,
                    distances: samples.distances,
                    window: gradeWindow(
                        totalDistance: totalDistance,
                        sampleDistances: samples.distances
                    ),
                    requiredSamples: derivedSlopeMask,
                    isCancelled: isCancelled
                ) else {
                    return nil
                }
                var mergedSlopes: [Double?] = []
                mergedSlopes.reserveCapacity(derivedSlopes.count)
                for index in derivedSlopes.indices {
                    if index.isMultiple(of: 256), isCancelled() {
                        return nil
                    }
                    mergedSlopes.append(
                        resampledSourceGrades[index] ?? derivedSlopes[index]
                    )
                }
                slopes = mergedSlopes
            }
        } else {
            guard let derivedSlopes = regressionSlopes(
                altitudes: filteredAltitudes,
                distances: samples.distances,
                window: gradeWindow(
                    totalDistance: totalDistance,
                    sampleDistances: samples.distances
                ),
                isCancelled: isCancelled
            ) else {
                return nil
            }
            slopes = derivedSlopes
        }
        return makeAnalysis(
            distances: samples.distances,
            filteredAltitudes: filteredAltitudes,
            slopes: slopes,
            totalDistance: totalDistance,
            maximumStopCount: maximumStopCount,
            isCancelled: isCancelled
        )
    }

    private nonisolated static func gradeWindow(
        totalDistance: CLLocationDistance,
        sampleDistances: [CLLocationDistance]
    ) -> CLLocationDistance {
        let sampleSpacing = sampleDistances.count > 1
            ? sampleDistances[1] - sampleDistances[0]
            : 0
        return max(
            min(max(totalDistance / 200, 40), 120),
            sampleSpacing * 4
        )
    }

    private nonisolated static func makeAnalysis(
        distances: [CLLocationDistance],
        filteredAltitudes: [Double?],
        slopes: [Double?],
        totalDistance: CLLocationDistance,
        maximumStopCount: Int,
        isCancelled: @Sendable () -> Bool
    ) -> RouteSlopeAnalysis? {
        guard let normalizedSlopes = normalized(slopes, isCancelled: isCancelled),
              let stopIndices = gradientStopIndices(
                  distances: distances,
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
            locations.append(min(max(distances[index] / totalDistance, 0), 1))
            stopSlopes.append(normalizedSlopes[index])
        }
        guard !isCancelled(),
              locations.count > 1 else {
            return nil
        }

        // The color profile and live dashboard keep the responsive local grade,
        // while the chart marker represents a sustained climb. Selecting the raw
        // pointwise maximum lets a bridge lip or a few noisy altitude samples beat
        // a clearly steeper main climb in the elevation overview.
        let steepestUphill = sustainedUphillPeak(
            distances: distances,
            altitudes: filteredAltitudes,
            slopes: slopes,
            isCancelled: isCancelled
        )
        guard !isCancelled() else {
            return nil
        }

        return RouteSlopeAnalysis(
            gradient: RouteSlopeGradient(
                locations: locations,
                normalizedSlopes: stopSlopes
            ),
            distances: distances,
            gradeRatios: slopes,
            steepestUphill: steepestUphill
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

    private nonisolated static func uniformSampleDistances(
        totalDistance: CLLocationDistance,
        isCancelled: @Sendable () -> Bool
    ) -> [CLLocationDistance]? {
        let preferredStep = min(max(totalDistance / 4_000, 5), 25)
        let sampleCount = min(
            20_001,
            max(2, Int(ceil(totalDistance / preferredStep)) + 1)
        )
        let sampleStep = totalDistance / Double(sampleCount - 1)
        var sampleDistances: [CLLocationDistance] = []
        sampleDistances.reserveCapacity(sampleCount)
        for sampleIndex in 0..<sampleCount {
            if sampleIndex.isMultiple(of: 256), isCancelled() {
                return nil
            }
            sampleDistances.append(Double(sampleIndex) * sampleStep)
        }
        return sampleDistances
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
        guard let sampleDistances = uniformSampleDistances(
            totalDistance: totalDistance,
            isCancelled: isCancelled
        ) else {
            return nil
        }
        let sampleCount = sampleDistances.count
        let sampleStep = totalDistance / Double(sampleCount - 1)
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
            let lowerDistance = abs(distance - lowerSample.distance)
            let upperDistance = abs(distance - upperSample.distance)
            if min(lowerDistance, upperDistance) <= sampleStep / 2 {
                // Dense source data can put both neighbors inside the snapping
                // tolerance. Pick the genuinely nearest sample; on an exact tie,
                // consistently keep the earlier one.
                sampleAltitudes[sampleIndex] = lowerDistance <= upperDistance
                    ? lowerSample.altitude
                    : upperSample.altitude
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

    private nonisolated static func validatedSourceGradeRatios(
        _ gradeRatios: [Double?]?,
        sourceCumulativeDistances: [CLLocationDistance?]?,
        fallbackDistances: [CLLocationDistance],
        isCancelled: @Sendable () -> Bool
    ) -> [Double?]? {
        guard let gradeRatios,
              gradeRatios.count == fallbackDistances.count,
              gradeRatios.count >= 3,
              !isCancelled() else {
            return nil
        }

        var sanitizedGrades: [Double?] = []
        sanitizedGrades.reserveCapacity(gradeRatios.count)
        var validGradeCount = 0
        for index in gradeRatios.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            if let gradeRatio = gradeRatios[index],
               gradeRatio.isFinite,
               (-1...1).contains(gradeRatio) {
                sanitizedGrades.append(gradeRatio)
                validGradeCount += 1
            } else {
                sanitizedGrades.append(nil)
            }
        }
        let validCoverage = Double(validGradeCount) / Double(gradeRatios.count)
        guard validGradeCount >= 3,
              validCoverage >= 0.35 else {
            return nil
        }

        if let sourceCumulativeDistances {
            guard sourceCumulativeDistances.count == fallbackDistances.count else {
                return nil
            }
            let providedDistanceCount = sourceCumulativeDistances.reduce(into: 0) {
                count, distance in
                if distance != nil {
                    count += 1
                }
            }
            if providedDistanceCount > 0 {
                guard providedDistanceCount == sourceCumulativeDistances.count,
                      let firstDistance = sourceCumulativeDistances[0],
                      firstDistance.isFinite,
                      firstDistance >= 0 else {
                    return nil
                }
                var previousDistance = firstDistance
                var strictlyIncreasingCount = 0
                for index in 1..<sourceCumulativeDistances.count {
                    if index.isMultiple(of: 256), isCancelled() {
                        return nil
                    }
                    guard let distance = sourceCumulativeDistances[index],
                          distance.isFinite,
                          distance >= 0,
                          distance >= previousDistance - 0.01 else {
                        return nil
                    }
                    if distance > previousDistance + 0.001 {
                        strictlyIncreasingCount += 1
                    }
                    previousDistance = max(previousDistance, distance)
                }
                guard strictlyIncreasingCount > 0,
                      previousDistance - firstDistance >= 20 else {
                    return nil
                }
            }
        }
        return sanitizedGrades
    }

    private nonisolated static func resampledGradeRatios(
        _ gradeRatios: [Double?],
        distances: [CLLocationDistance],
        sampleDistances: [CLLocationDistance],
        isCancelled: @Sendable () -> Bool
    ) -> [Double?]? {
        guard gradeRatios.count == distances.count,
              !sampleDistances.isEmpty,
              !isCancelled() else {
            return nil
        }

        var samples: [(distance: CLLocationDistance, gradeRatio: Double?)] = []
        samples.reserveCapacity(gradeRatios.count)
        for index in gradeRatios.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let gradeRatio = gradeRatios[index].flatMap {
                $0.isFinite && (-1...1).contains($0) ? $0 : nil
            }
            if let lastSample = samples.last,
               abs(lastSample.distance - distances[index]) < 0.001 {
                if let gradeRatio {
                    samples[samples.count - 1].gradeRatio = gradeRatio
                }
            } else {
                samples.append((distances[index], gradeRatio))
            }
        }

        var result = Array<Double?>(repeating: nil, count: sampleDistances.count)
        guard samples.count >= 2 else {
            return result
        }

        var positiveSpacings: [CLLocationDistance] = []
        positiveSpacings.reserveCapacity(samples.count - 1)
        for index in 1..<samples.count {
            let spacing = samples[index].distance - samples[index - 1].distance
            if spacing.isFinite, spacing > 0 {
                positiveSpacings.append(spacing)
            }
        }
        positiveSpacings.sort()
        guard !isCancelled() else {
            return nil
        }
        guard !positiveSpacings.isEmpty else {
            return result
        }

        let medianSpacing = median(of: positiveSpacings)
        let maximumInterpolationGap = max(250, min(medianSpacing * 5, 1_000))
        let matchingTolerance = 0.001
        var upperValidIndex = 1

        for sampleIndex in sampleDistances.indices {
            if sampleIndex.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let distance = sampleDistances[sampleIndex]
            while upperValidIndex < samples.count - 1,
                  samples[upperValidIndex].distance < distance {
                upperValidIndex += 1
            }

            let lowerSample = samples[upperValidIndex - 1]
            let upperSample = samples[upperValidIndex]
            if abs(distance - lowerSample.distance) <= matchingTolerance {
                result[sampleIndex] = lowerSample.gradeRatio
                continue
            }
            if abs(distance - upperSample.distance) <= matchingTolerance {
                result[sampleIndex] = upperSample.gradeRatio
                continue
            }
            guard distance > lowerSample.distance,
                  distance < upperSample.distance else {
                continue
            }

            let gap = upperSample.distance - lowerSample.distance
            guard gap > 0,
                  gap <= maximumInterpolationGap,
                  let lowerGrade = lowerSample.gradeRatio,
                  let upperGrade = upperSample.gradeRatio else {
                continue
            }
            let progress = (distance - lowerSample.distance) / gap
            result[sampleIndex] = lowerGrade + (upperGrade - lowerGrade) * progress
        }
        return result
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
        requiredSamples: [Bool]? = nil,
        isCancelled: @Sendable () -> Bool
    ) -> [Double?]? {
        guard altitudes.count == distances.count,
              requiredSamples == nil || requiredSamples?.count == altitudes.count,
              !isCancelled() else {
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
            if let requiredSamples, !requiredSamples[index] {
                continue
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
            // Keep the signed physical grade for the replay dashboard. The
            // green-to-red map palette still clamps descents to its baseline
            // later when these values are normalized for color rendering.
            slopes[index] = min(max(slope, -1), 1)
        }
        return slopes
    }

    private nonisolated static func sustainedUphillPeak(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        slopes: [Double?],
        isCancelled: @Sendable () -> Bool
    ) -> RouteSlopePeak? {
        guard distances.count == altitudes.count,
              distances.count == slopes.count,
              distances.count > 1 else {
            return nil
        }
        // The marker represents the steepest sustained 275 m, while the map and
        // live dashboard continue using the responsive 40-120 m profile above.
        // Signed distance integration naturally cancels a short bump that rises
        // and falls again inside the window.
        let window: CLLocationDistance = 275
        let halfWindow = window / 2
        var bestCandidate: (distance: CLLocationDistance, gradeRatio: Double)?
        var runStartIndex = 0
        while runStartIndex < slopes.count {
            while runStartIndex < slopes.count, slopes[runStartIndex] == nil {
                runStartIndex += 1
            }
            guard runStartIndex < slopes.count else {
                break
            }
            var runEndIndex = runStartIndex
            while runEndIndex + 1 < slopes.count,
                  slopes[runEndIndex + 1] != nil {
                runEndIndex += 1
            }

            if distances[runEndIndex] - distances[runStartIndex] >= window {
                for index in runStartIndex...runEndIndex {
                    if index.isMultiple(of: 256), isCancelled() {
                        return nil
                    }
                    let latestLowerDistance = distances[runEndIndex] - window
                    let lowerDistance = min(
                        max(
                            distances[index] - halfWindow,
                            distances[runStartIndex]
                        ),
                        latestLowerDistance
                    )
                    let upperDistance = lowerDistance + window
                    guard let integratedGrade = integratedGradeRatio(
                              from: lowerDistance,
                              to: upperDistance,
                              distances: distances,
                              slopes: slopes,
                              within: runStartIndex...runEndIndex
                          ) else {
                        continue
                    }
                    let averageGrade = integratedGrade / window
                    guard averageGrade.isFinite,
                          averageGrade > 0 else {
                        continue
                    }
                    if bestCandidate == nil
                        || averageGrade > (bestCandidate?.gradeRatio
                            ?? -.greatestFiniteMagnitude) {
                        bestCandidate = (
                            lowerDistance + halfWindow,
                            averageGrade
                        )
                    }
                }
            }
            runStartIndex = runEndIndex + 1
        }

        guard let bestCandidate else {
            return nil
        }
        return RouteSlopePeak(
            distanceMeters: bestCandidate.distance,
            altitudeMeters: interpolatedAltitude(
                at: bestCandidate.distance,
                distances: distances,
                altitudes: altitudes
            ),
            gradeRatio: bestCandidate.gradeRatio
        )
    }

    private nonisolated static func interpolatedAltitude(
        at distance: CLLocationDistance,
        distances: [CLLocationDistance],
        altitudes: [Double?]
    ) -> Double? {
        guard distances.count == altitudes.count,
              !distances.isEmpty,
              distance >= distances[0],
              distance <= distances[distances.count - 1] else {
            return nil
        }
        var lowerBound = 0
        var upperBound = distances.count - 1
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if distances[middleIndex] < distance {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }
        let upperIndex = lowerBound
        if abs(distances[upperIndex] - distance) < 0.000_001 {
            return altitudes[upperIndex]
        }
        guard upperIndex > 0,
              let lowerAltitude = altitudes[upperIndex - 1],
              let upperAltitude = altitudes[upperIndex] else {
            return nil
        }
        let span = distances[upperIndex] - distances[upperIndex - 1]
        guard span > 0 else {
            return upperAltitude
        }
        let progress = (distance - distances[upperIndex - 1]) / span
        return lowerAltitude + (upperAltitude - lowerAltitude) * progress
    }

    private nonisolated static func integratedGradeRatio(
        from lowerDistance: CLLocationDistance,
        to upperDistance: CLLocationDistance,
        distances: [CLLocationDistance],
        slopes: [Double?],
        within range: ClosedRange<Int>
    ) -> Double? {
        guard lowerDistance < upperDistance,
              range.lowerBound >= 0,
              range.upperBound < distances.count,
              range.upperBound < slopes.count,
              lowerDistance >= distances[range.lowerBound],
              upperDistance <= distances[range.upperBound] else {
            return nil
        }

        func firstIndex(atOrAfter targetDistance: CLLocationDistance) -> Int {
            var lowerBound = range.lowerBound
            var upperBound = range.upperBound
            while lowerBound < upperBound {
                let middleIndex = (lowerBound + upperBound) / 2
                if distances[middleIndex] < targetDistance {
                    lowerBound = middleIndex + 1
                } else {
                    upperBound = middleIndex
                }
            }
            return lowerBound
        }

        func gradeRatio(at targetDistance: CLLocationDistance) -> Double? {
            let upperIndex = firstIndex(atOrAfter: targetDistance)
            if abs(distances[upperIndex] - targetDistance) < 0.000_001 {
                return slopes[upperIndex]
            }
            guard upperIndex > range.lowerBound,
                  let lowerGrade = slopes[upperIndex - 1],
                  let upperGrade = slopes[upperIndex] else {
                return nil
            }
            let span = distances[upperIndex] - distances[upperIndex - 1]
            guard span > 0 else {
                return upperGrade
            }
            let progress = (targetDistance - distances[upperIndex - 1]) / span
            return lowerGrade + (upperGrade - lowerGrade) * progress
        }

        guard var previousGrade = gradeRatio(at: lowerDistance),
              let finalGrade = gradeRatio(at: upperDistance) else {
            return nil
        }
        var previousDistance = lowerDistance
        var integratedGrade = 0.0
        var index = firstIndex(atOrAfter: lowerDistance)
        if distances[index] <= lowerDistance + 0.000_001 {
            index += 1
        }
        while index <= range.upperBound,
              distances[index] < upperDistance {
            guard let grade = slopes[index] else {
                return nil
            }
            let distance = distances[index]
            integratedGrade += (previousGrade + grade) * 0.5
                * (distance - previousDistance)
            previousDistance = distance
            previousGrade = grade
            index += 1
        }
        integratedGrade += (previousGrade + finalGrade) * 0.5
            * (upperDistance - previousDistance)
        return integratedGrade
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
        guard !isCancelled() else {
            return nil
        }
        let validCoverage = Double(validSlopes.count) / Double(max(slopes.count, 1))
        guard validSlopes.count >= 3, validCoverage >= 0.35 else {
            return nil
        }

        guard let maximumSlope = validSlopes.max(),
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

        let gentleSlope = 0.01
        // Use one physical grade scale for every route segment. Adaptive
        // per-segment percentiles made identical climbs change color at an
        // HKWorkoutRoute/GPX boundary.
        let steepSlope = 0.12
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
