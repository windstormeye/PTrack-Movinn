//
//  TrackedWorkoutHealthData.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import CoreLocation
import Foundation
import HealthKit

struct TrackedWorkoutSourceRevision: Codable {
    let sourceName: String
    let bundleIdentifier: String
    let version: String?
    let productType: String?
    let operatingSystemVersion: String

    nonisolated init(sourceRevision: HKSourceRevision) {
        sourceName = sourceRevision.source.name
        bundleIdentifier = sourceRevision.source.bundleIdentifier
        version = sourceRevision.version
        productType = sourceRevision.productType

        let osVersion = sourceRevision.operatingSystemVersion
        operatingSystemVersion = [
            osVersion.majorVersion,
            osVersion.minorVersion,
            osVersion.patchVersion
        ]
        .map(String.init)
        .joined(separator: ".")
    }
}

struct TrackedWorkoutDevice: Codable {
    let name: String?
    let manufacturer: String?
    let model: String?
    let hardwareVersion: String?
    let firmwareVersion: String?
    let softwareVersion: String?
    let localIdentifier: String?
    let udiDeviceIdentifier: String?

    nonisolated init(device: HKDevice) {
        name = device.name
        manufacturer = device.manufacturer
        model = device.model
        hardwareVersion = device.hardwareVersion
        firmwareVersion = device.firmwareVersion
        softwareVersion = device.softwareVersion
        localIdentifier = device.localIdentifier
        udiDeviceIdentifier = device.udiDeviceIdentifier
    }
}

struct TrackedMetadataValue: Codable {
    let type: String
    let stringValue: String?
    let doubleValue: Double?
    let boolValue: Bool?
    let dateValue: Date?
    let stringArrayValue: [String]?
    let numberArrayValue: [Double]?

    nonisolated init(
        type: String,
        stringValue: String? = nil,
        doubleValue: Double? = nil,
        boolValue: Bool? = nil,
        dateValue: Date? = nil,
        stringArrayValue: [String]? = nil,
        numberArrayValue: [Double]? = nil
    ) {
        self.type = type
        self.stringValue = stringValue
        self.doubleValue = doubleValue
        self.boolValue = boolValue
        self.dateValue = dateValue
        self.stringArrayValue = stringArrayValue
        self.numberArrayValue = numberArrayValue
    }

    nonisolated init?(value: Any) {
        switch value {
        case let string as String:
            self.init(type: "string", stringValue: string)
        case let date as Date:
            self.init(type: "date", dateValue: date)
        case let number as NSNumber:
            if Self.isBoolean(number) {
                self.init(type: "bool", boolValue: number.boolValue)
            } else {
                self.init(type: "number", doubleValue: number.doubleValue)
            }
        case let quantity as HKQuantity:
            self.init(type: "quantity", stringValue: quantity.description)
        case let values as [String]:
            self.init(type: "stringArray", stringArrayValue: values)
        case let values as [NSNumber]:
            self.init(type: "numberArray", numberArrayValue: values.map(\.doubleValue))
        default:
            self.init(type: String(describing: Swift.type(of: value)), stringValue: String(describing: value))
        }
    }

    nonisolated private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
    }
}

enum TrackedMetadata {
    nonisolated static func values(from metadata: [String: Any]?) -> [String: TrackedMetadataValue]? {
        guard let metadata, !metadata.isEmpty else {
            return nil
        }

        let values = metadata.reduce(into: [String: TrackedMetadataValue]()) { partialResult, item in
            if let value = TrackedMetadataValue(value: item.value) {
                partialResult[item.key] = value
            }
        }

        return values.isEmpty ? nil : values
    }
}

struct TrackedWorkoutEvent: Codable {
    let typeRawValue: Int
    let startDate: Date
    let endDate: Date
    let metadata: [String: TrackedMetadataValue]?

    nonisolated init(event: HKWorkoutEvent) {
        typeRawValue = event.type.rawValue
        startDate = event.dateInterval.start
        endDate = event.dateInterval.end
        metadata = TrackedMetadata.values(from: event.metadata)
    }
}

struct TrackedWorkoutRouteSegment: Codable {
    let id: String
    let startDate: Date
    let endDate: Date
    let locationCount: Int
    let sourceRevision: TrackedWorkoutSourceRevision
    let device: TrackedWorkoutDevice?
    let metadata: [String: TrackedMetadataValue]?

    nonisolated init(route: HKWorkoutRoute, locationCount: Int) {
        id = route.uuid.uuidString
        startDate = route.startDate
        endDate = route.endDate
        self.locationCount = locationCount
        sourceRevision = TrackedWorkoutSourceRevision(sourceRevision: route.sourceRevision)
        device = route.device.map(TrackedWorkoutDevice.init)
        metadata = TrackedMetadata.values(from: route.metadata)
    }
}

struct TrackedWorkoutQuantityMetric: Codable {
    let identifier: String
    let unit: String
    let sum: Double?
    let average: Double?
    let minimum: Double?
    let maximum: Double?

    nonisolated init(
        identifier: String,
        unit: String,
        sum: Double?,
        average: Double?,
        minimum: Double?,
        maximum: Double?
    ) {
        self.identifier = identifier
        self.unit = unit
        self.sum = sum
        self.average = average
        self.minimum = minimum
        self.maximum = maximum
    }

    nonisolated var hasValues: Bool {
        sum != nil || average != nil || minimum != nil || maximum != nil
    }
}

struct TrackedRouteSummary: Codable {
    let rawLocationCount: Int
    let sampledCoordinateCount: Int
    let measuredDistanceMeters: Double?
    let minimumAltitudeMeters: Double?
    let maximumAltitudeMeters: Double?
    let elevationGainMeters: Double?
    let elevationLossMeters: Double?
    let averageSpeedMetersPerSecond: Double?
    let maximumSpeedMetersPerSecond: Double?

    nonisolated init(
        locations: [CLLocation],
        routeSegments: [TrackedWorkoutRouteSegment] = [],
        sampledCoordinateCount: Int
    ) {
        rawLocationCount = locations.count
        self.sampledCoordinateCount = sampledCoordinateCount

        let locationSegments = Self.locationSegments(
            locations: locations,
            routeSegments: routeSegments
        )
        measuredDistanceMeters = Self.measuredDistance(for: locationSegments)

        let altitudeValues = locations
            .filter { $0.verticalAccuracy >= 0 }
            .map(\.altitude)

        minimumAltitudeMeters = altitudeValues.min()
        maximumAltitudeMeters = altitudeValues.max()

        let altitudeSegments = locationSegments.map { segment in
            segment
                .filter { $0.verticalAccuracy >= 0 }
                .map(\.altitude)
        }
        let elevationChange = Self.elevationChange(for: altitudeSegments)
        elevationGainMeters = elevationChange.gain
        elevationLossMeters = elevationChange.loss

        let speedValues = locations
            .filter { $0.speed >= 0 }
            .map(\.speed)

        if speedValues.isEmpty {
            averageSpeedMetersPerSecond = nil
            maximumSpeedMetersPerSecond = nil
        } else {
            averageSpeedMetersPerSecond = speedValues.reduce(0, +) / Double(speedValues.count)
            maximumSpeedMetersPerSecond = speedValues.max()
        }
    }

    /// Returns location slices only when every count describes the flattened
    /// array exactly. Falling back to one continuous slice keeps malformed or
    /// legacy data usable without risking out-of-bounds segment boundaries.
    nonisolated private static func locationSegments(
        locations: [CLLocation],
        routeSegments: [TrackedWorkoutRouteSegment]
    ) -> [ArraySlice<CLLocation>] {
        guard !routeSegments.isEmpty,
              routeSegments.allSatisfy({ $0.locationCount >= 0 }) else {
            return [locations[...]]
        }

        var locationCount = 0
        for segment in routeSegments {
            let (updatedCount, overflow) = locationCount.addingReportingOverflow(segment.locationCount)
            guard !overflow else {
                return [locations[...]]
            }
            locationCount = updatedCount
        }
        guard locationCount == locations.count else {
            return [locations[...]]
        }

        var lowerBound = locations.startIndex
        return routeSegments.map { segment in
            let upperBound = lowerBound + segment.locationCount
            defer { lowerBound = upperBound }
            return locations[lowerBound..<upperBound]
        }
    }

    nonisolated private static func measuredDistance(
        for locationSegments: [ArraySlice<CLLocation>]
    ) -> Double? {
        var totalDistance: CLLocationDistance = 0
        var hasMeasurableSegment = false

        for locations in locationSegments where locations.count > 1 {
            hasMeasurableSegment = true
            var previousLocation = locations[locations.startIndex]

            for location in locations.dropFirst() {
                totalDistance += location.distance(from: previousLocation)
                previousLocation = location
            }
        }

        guard hasMeasurableSegment else {
            return nil
        }

        return totalDistance
    }

    nonisolated private static func elevationChange(
        for altitudeSegments: [[Double]]
    ) -> (gain: Double?, loss: Double?) {
        var gain: Double = 0
        var loss: Double = 0
        var hasMeasurableSegment = false

        for altitudes in altitudeSegments where altitudes.count > 1 {
            hasMeasurableSegment = true
            var previousAltitude = altitudes[0]

            for altitude in altitudes.dropFirst() {
                let delta = altitude - previousAltitude
                if delta > 0 {
                    gain += delta
                } else {
                    loss += abs(delta)
                }
                previousAltitude = altitude
            }
        }

        guard hasMeasurableSegment else {
            return (nil, nil)
        }

        return (gain, loss)
    }
}
