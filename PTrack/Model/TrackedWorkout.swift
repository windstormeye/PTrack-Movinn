//
//  TrackedWorkout.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import CoreLocation
import Foundation
import HealthKit
import UIKit

enum TrackedWorkoutSportKind: String, CaseIterable, Codable, Hashable {
    case cycling
    case hiking
    case outdoorSwimming
    case outdoorWorkout
    case running
    case trailRunning
    case virtualCycling
    case virtualRunning
    case walking

    var title: String {
        switch self {
        case .cycling:
            return AppLocalization.text(.cycling)
        case .hiking:
            return AppLocalization.text(.hiking)
        case .outdoorSwimming:
            return AppLocalization.text(.outdoorSwimming)
        case .outdoorWorkout:
            return AppLocalization.text(.outdoorWorkout)
        case .running:
            return AppLocalization.text(.running)
        case .trailRunning:
            return AppLocalization.text(.trailRunning)
        case .virtualCycling:
            return AppLocalization.text(.virtualCycling)
        case .virtualRunning:
            return AppLocalization.text(.virtualRunning)
        case .walking:
            return AppLocalization.text(.walking)
        }
    }

    var symbolName: String {
        switch self {
        case .cycling:
            return "figure.outdoor.cycle"
        case .hiking:
            return "figure.hiking"
        case .outdoorSwimming:
            return "figure.open.water.swim"
        case .outdoorWorkout:
            return "figure.walk"
        case .running:
            return "figure.run"
        case .trailRunning:
            return "figure.walk.motion"
        case .virtualCycling:
            return "figure.indoor.cycle"
        case .virtualRunning:
            return "figure.run"
        case .walking:
            return "figure.walk"
        }
    }
}

struct TrackedWorkout: Codable {
    nonisolated static let currentHealthDataVersion = 2

    let id: String
    let healthDataVersion: Int?
    let activityTypeRawValue: UInt
    let startDate: Date
    let endDate: Date?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double
    let totalEnergyBurnedKilocalories: Double?
    let sourceRevision: TrackedWorkoutSourceRevision?
    let device: TrackedWorkoutDevice?
    let metadata: [String: TrackedMetadataValue]?
    let workoutEvents: [TrackedWorkoutEvent]?
    let routeSegments: [TrackedWorkoutRouteSegment]?
    let routeSummary: TrackedRouteSummary?
    let quantityMetrics: [TrackedWorkoutQuantityMetric]?
    let coordinates: [RouteCoordinate]
    let fullCoordinates: [RouteCoordinate]?

    nonisolated init(
        id: String,
        healthDataVersion: Int?,
        activityTypeRawValue: UInt,
        startDate: Date,
        endDate: Date?,
        durationSeconds: TimeInterval?,
        distanceMeters: Double,
        totalEnergyBurnedKilocalories: Double?,
        sourceRevision: TrackedWorkoutSourceRevision?,
        device: TrackedWorkoutDevice?,
        metadata: [String: TrackedMetadataValue]?,
        workoutEvents: [TrackedWorkoutEvent]?,
        routeSegments: [TrackedWorkoutRouteSegment]?,
        routeSummary: TrackedRouteSummary?,
        quantityMetrics: [TrackedWorkoutQuantityMetric]?,
        coordinates: [RouteCoordinate],
        fullCoordinates: [RouteCoordinate]?
    ) {
        self.id = id
        self.healthDataVersion = healthDataVersion
        self.activityTypeRawValue = activityTypeRawValue
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.totalEnergyBurnedKilocalories = totalEnergyBurnedKilocalories
        self.sourceRevision = sourceRevision
        self.device = device
        self.metadata = metadata
        self.workoutEvents = workoutEvents
        self.routeSegments = routeSegments
        self.routeSummary = routeSummary
        self.quantityMetrics = quantityMetrics
        self.coordinates = coordinates
        self.fullCoordinates = fullCoordinates
    }

    nonisolated init(
        workout: HKWorkout,
        locations: [CLLocation],
        routeSegments: [TrackedWorkoutRouteSegment] = [],
        quantityMetrics: [TrackedWorkoutQuantityMetric] = []
    ) {
        id = workout.uuid.uuidString
        healthDataVersion = Self.currentHealthDataVersion
        activityTypeRawValue = workout.workoutActivityType.rawValue
        startDate = workout.startDate
        endDate = workout.endDate
        durationSeconds = workout.duration
        distanceMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        totalEnergyBurnedKilocalories = quantityMetrics.first {
            $0.identifier == HKQuantityTypeIdentifier.activeEnergyBurned.rawValue
        }?.sum
        sourceRevision = TrackedWorkoutSourceRevision(sourceRevision: workout.sourceRevision)
        device = workout.device.map(TrackedWorkoutDevice.init)
        metadata = TrackedMetadata.values(from: workout.metadata)

        let events = workout.workoutEvents ?? []
        workoutEvents = events.isEmpty ? nil : events.map(TrackedWorkoutEvent.init)
        self.routeSegments = routeSegments.isEmpty ? nil : routeSegments
        self.quantityMetrics = quantityMetrics.isEmpty ? nil : quantityMetrics

        let rawCoordinates = locations.map(RouteCoordinate.init)
        let sampledCoordinates = RouteSampler.downsample(rawCoordinates, limit: 1_200)
        routeSummary = TrackedRouteSummary(
            locations: locations,
            sampledCoordinateCount: sampledCoordinates.count
        )
        coordinates = sampledCoordinates
        fullCoordinates = Self.fullCoordinatesIfSampled(
            rawCoordinates: rawCoordinates,
            sampledCoordinates: sampledCoordinates
        )
    }

    var activityType: HKWorkoutActivityType {
        HKWorkoutActivityType(rawValue: activityTypeRawValue) ?? .other
    }

    var needsHealthDataRefresh: Bool {
        healthDataVersion != Self.currentHealthDataVersion
    }

    var stravaActivityID: Int64? {
        if let value = metadata?["strava.id"]?.stringValue,
           let activityID = Int64(value) {
            return activityID
        }

        let idPrefix = "strava-"
        if id.hasPrefix(idPrefix),
           let activityID = Int64(id.dropFirst(idPrefix.count)) {
            return activityID
        }

        let bundlePrefix = "com.strava.activity."
        if let bundleIdentifier = sourceRevision?.bundleIdentifier,
           bundleIdentifier.hasPrefix(bundlePrefix),
           let activityID = Int64(bundleIdentifier.dropFirst(bundlePrefix.count)) {
            return activityID
        }

        return nil
    }

    var isStravaSource: Bool {
        stravaActivityID != nil || sourceRevision?.sourceName == "Strava"
    }

    var stravaSportType: String? {
        metadata?["strava.sportType"]?.stringValue
    }

    var routeDataSourceTitle: String {
        if isRouteCollectionSource {
            if isMergedRouteCollectionSource {
                return AppLocalization.text(.routeMerge)
            }

            return AppLocalization.text(.routeCollection)
        }

        if isStravaSource {
            return AppLocalization.text(.strava)
        }

        return AppLocalization.text(.appleHealth)
    }

    var sportKind: TrackedWorkoutSportKind {
        switch stravaSportType {
        case "Run":
            return .running
        case "TrailRun":
            return .trailRunning
        case "Walk":
            return .walking
        case "Hike":
            return .hiking
        case "Swim":
            return .outdoorSwimming
        case "VirtualRide":
            return .virtualCycling
        case "VirtualRun":
            return .virtualRunning
        default:
            break
        }

        switch activityType {
        case .cycling:
            return .cycling
        case .hiking:
            return .hiking
        case .walking:
            return .walking
        case .running:
            return .running
        case .swimming:
            return .outdoorSwimming
        default:
            return .outdoorWorkout
        }
    }

    var title: String {
        if let routeCollectionTitle {
            return routeCollectionTitle
        }

        return sportKind.title
    }

    var symbolName: String {
        sportKind.symbolName
    }

    var routeColor: UIColor {
        .label
    }

    var activeEnergyBurnedKilocalories: Double? {
        quantityMetric(for: HKQuantityTypeIdentifier.activeEnergyBurned.rawValue)?.sum ?? totalEnergyBurnedKilocalories
    }

    var estimatedEnergyBurnedKilocalories: Double? {
        guard activeEnergyBurnedKilocalories.flatMap(Self.positiveFiniteValue) == nil,
              !isRouteCollectionSource else {
            return nil
        }

        if let durationSeconds = energyEstimateDurationSeconds(),
           let cyclingPowerEstimate = cyclingPowerEnergyEstimate(durationSeconds: durationSeconds) {
            return cyclingPowerEstimate
        }

        if let durationSeconds = energyEstimateDurationSeconds(),
           let metEstimate = metabolicEquivalentEnergyEstimate(durationSeconds: durationSeconds) {
            return metEstimate
        }

        return distanceEnergyEstimate()
    }

    var displayEnergyBurnedKilocalories: Double? {
        if let calories = activeEnergyBurnedKilocalories.flatMap(Self.positiveFiniteValue) {
            return calories
        }

        return estimatedEnergyBurnedKilocalories
    }

    var isDisplayEnergyBurnedEstimated: Bool {
        activeEnergyBurnedKilocalories.flatMap(Self.positiveFiniteValue) == nil
            && estimatedEnergyBurnedKilocalories != nil
    }

    var distanceText: String {
        if distanceMeters >= 1000 {
            return String(format: "%.2f km", distanceMeters / 1000)
        } else if distanceMeters > 0 {
            return AppLocalization.format(.distanceMetersFormat, distanceMeters)
        } else {
            return AppLocalization.text(.unknownDistance)
        }
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startDate)
    }

    var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard let endDate else {
            return formatter.string(from: startDate)
        }

        let endFormatter = DateFormatter()
        endFormatter.dateFormat = Calendar.current.isDate(startDate, inSameDayAs: endDate) ? "HH:mm" : "yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: startDate)) - \(endFormatter.string(from: endDate))"
    }

    var navigationDateText: String {
        let calendar = Calendar.current
        let workoutDay = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())
        let dayDifference = calendar.dateComponents([.day], from: workoutDay, to: today).day

        switch dayDifference {
        case 0:
            return AppLocalization.text(.today)
        case 1:
            return AppLocalization.text(.yesterday)
        case 2:
            return AppLocalization.text(.dayBeforeYesterday)
        default:
            return formattedNavigationDateText()
        }
    }

    private func formattedNavigationDateText() -> String {
        let language = AppLanguageStore.shared.language
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current

        switch language {
        case .chinese:
            formatter.locale = Locale(identifier: "zh_Hans")
            formatter.dateFormat = "yyyy 年 M 月 d 日"
        case .japanese:
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy年M月d日"
        case .korean:
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "yyyy년 M월 d일"
        case .english:
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMM d, yyyy"
        }

        return formatter.string(from: startDate)
    }

    var durationText: String {
        guard let durationSeconds, durationSeconds > 0 else {
            return AppLocalization.text(.unknownDuration)
        }

        let totalMinutes = Int(durationSeconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return AppLocalization.format(.durationHoursMinutesFormat, hours, minutes)
        }
        return AppLocalization.format(.durationMinutesFormat, max(minutes, 1))
    }

    var displayElevationGainMeters: Double? {
        if isMergedRouteCollectionSource,
           let elevationGainMeters = metadata?["routeCollection.merge.elevationGainMeters"]?.doubleValue,
           elevationGainMeters.isFinite,
           elevationGainMeters > 0 {
            return elevationGainMeters
        }

        return routeSummary?.elevationGainMeters
    }

    var elevationGainText: String? {
        guard let elevationGainMeters = displayElevationGainMeters,
              elevationGainMeters.isFinite,
              elevationGainMeters > 0 else {
            return nil
        }

        return AppLocalization.format(.elevationGainFormat, elevationGainMeters.rounded())
    }

    var displayCoordinates: [CLLocationCoordinate2D] {
        CoordinateTransformer.displayCoordinates(for: coordinates.map(\.coordinate))
    }

    var routeDetailCoordinates: [RouteCoordinate] {
        guard let fullCoordinates, !fullCoordinates.isEmpty else {
            return coordinates
        }

        return fullCoordinates
    }

    var routeDetailDisplayCoordinates: [CLLocationCoordinate2D] {
        CoordinateTransformer.displayCoordinates(for: routeDetailCoordinates.map(\.coordinate))
    }

    nonisolated func listPreview(maximumCoordinateCount: Int) -> TrackedWorkout {
        TrackedWorkout(
            id: id,
            healthDataVersion: healthDataVersion,
            activityTypeRawValue: activityTypeRawValue,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            totalEnergyBurnedKilocalories: totalEnergyBurnedKilocalories,
            sourceRevision: sourceRevision,
            device: device,
            metadata: metadata,
            workoutEvents: nil,
            routeSegments: nil,
            routeSummary: routeSummary,
            quantityMetrics: nil,
            coordinates: RouteSampler.downsample(coordinates, limit: maximumCoordinateCount),
            fullCoordinates: nil
        )
    }

    nonisolated func statisticsPreview() -> TrackedWorkout {
        TrackedWorkout(
            id: id,
            healthDataVersion: healthDataVersion,
            activityTypeRawValue: activityTypeRawValue,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            totalEnergyBurnedKilocalories: totalEnergyBurnedKilocalories,
            sourceRevision: sourceRevision,
            device: device,
            metadata: metadata,
            workoutEvents: nil,
            routeSegments: nil,
            routeSummary: routeSummary,
            quantityMetrics: nil,
            coordinates: Self.routeEndpointCoordinates(from: coordinates),
            fullCoordinates: nil
        )
    }

    private nonisolated static func routeEndpointCoordinates(from coordinates: [RouteCoordinate]) -> [RouteCoordinate] {
        guard let firstCoordinate = coordinates.first else {
            return []
        }

        guard let lastCoordinate = coordinates.last,
              !isSameCoordinate(firstCoordinate.coordinate, lastCoordinate.coordinate) else {
            return [firstCoordinate]
        }

        return [firstCoordinate, lastCoordinate]
    }

    private nonisolated static func isSameCoordinate(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    nonisolated static func fullCoordinatesIfSampled(
        rawCoordinates: [RouteCoordinate],
        sampledCoordinates: [RouteCoordinate]
    ) -> [RouteCoordinate]? {
        rawCoordinates.count > sampledCoordinates.count ? rawCoordinates : nil
    }

    private func quantityMetric(for identifier: String) -> TrackedWorkoutQuantityMetric? {
        quantityMetrics?.first { $0.identifier == identifier }
    }

    private nonisolated static let assumedBodyMassKilograms: Double = 70

    private nonisolated static func positiveFiniteValue(_ value: Double) -> Double? {
        guard value.isFinite, value > 0 else {
            return nil
        }

        return value
    }

    private func energyEstimateDurationSeconds() -> TimeInterval? {
        if let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 {
            return durationSeconds
        }

        if let endDate {
            let inferredDuration = endDate.timeIntervalSince(startDate)
            if inferredDuration.isFinite, inferredDuration > 0 {
                return inferredDuration
            }
        }

        guard let routeStartDate = routeDetailCoordinates.first?.timestamp,
              let routeEndDate = routeDetailCoordinates.last?.timestamp else {
            return nil
        }

        let routeDuration = routeEndDate.timeIntervalSince(routeStartDate)
        guard routeDuration.isFinite, routeDuration > 0 else {
            return nil
        }

        return routeDuration
    }

    private func energyEstimateDistanceMeters() -> Double? {
        if distanceMeters.isFinite, distanceMeters > 0 {
            return distanceMeters
        }

        if let measuredDistanceMeters = routeSummary?.measuredDistanceMeters,
           measuredDistanceMeters.isFinite,
           measuredDistanceMeters > 0 {
            return measuredDistanceMeters
        }

        let routeDistanceMeters = Self.distanceMeters(for: routeDetailCoordinates)
        guard routeDistanceMeters.isFinite, routeDistanceMeters > 0 else {
            return nil
        }

        return routeDistanceMeters
    }

    private func cyclingPowerEnergyEstimate(durationSeconds: TimeInterval) -> Double? {
        guard isCyclingEnergyEstimateSport,
              let averagePowerWatts = averagePowerWatts(),
              durationSeconds > 0 else {
            return nil
        }

        let estimatedKilocalories = averagePowerWatts * durationSeconds / 1_000
        return Self.validEnergyEstimate(estimatedKilocalories)
    }

    private var isCyclingEnergyEstimateSport: Bool {
        switch activityType {
        case .cycling, .handCycling:
            return true
        default:
            return sportKind == .cycling || sportKind == .virtualCycling
        }
    }

    private func metabolicEquivalentEnergyEstimate(durationSeconds: TimeInterval) -> Double? {
        guard durationSeconds > 0 else {
            return nil
        }

        let speedMetersPerSecond = averageSpeedMetersPerSecond(durationSeconds: durationSeconds)
        let baseMET = baseMetabolicEquivalent(speedMetersPerSecond: speedMetersPerSecond)
        let adjustedMET = baseMET * heartRateIntensityMultiplier()
        let durationMinutes = durationSeconds / 60
        let estimatedKilocalories = adjustedMET * 3.5 * Self.assumedBodyMassKilograms / 200 * durationMinutes
        return Self.validEnergyEstimate(estimatedKilocalories)
    }

    private func distanceEnergyEstimate() -> Double? {
        guard let distanceMeters = energyEstimateDistanceMeters() else {
            return nil
        }

        let distanceKilometers = distanceMeters / 1_000
        let bodyMassKilograms = Self.assumedBodyMassKilograms
        let baseKilocaloriesPerKilogramKilometer: Double

        switch sportKind {
        case .running, .virtualRunning:
            baseKilocaloriesPerKilogramKilometer = 1.0
        case .trailRunning:
            baseKilocaloriesPerKilogramKilometer = 1.08
        case .walking:
            baseKilocaloriesPerKilogramKilometer = 0.53
        case .hiking:
            baseKilocaloriesPerKilogramKilometer = 0.68
        case .cycling, .virtualCycling, .outdoorSwimming, .outdoorWorkout:
            return nil
        }

        var estimatedKilocalories = distanceKilometers * bodyMassKilograms * baseKilocaloriesPerKilogramKilometer
        estimatedKilocalories += elevationGainEnergyEstimate()
        estimatedKilocalories *= heartRateIntensityMultiplier()
        return Self.validEnergyEstimate(estimatedKilocalories)
    }

    private func averagePowerWatts() -> Double? {
        if let averagePower = quantityMetric(for: HKQuantityTypeIdentifier.cyclingPower.rawValue)?.average,
           let value = Self.positiveFiniteValue(averagePower) {
            return value
        }

        return Self.averageValue(
            routeDetailCoordinates.compactMap { coordinate in
                guard let powerWatts = coordinate.powerWatts,
                      powerWatts.isFinite,
                      powerWatts >= 0 else {
                    return nil
                }

                return powerWatts
            }
        )
    }

    private func averageHeartRateBeatsPerMinute() -> Double? {
        if let averageHeartRate = quantityMetric(for: HKQuantityTypeIdentifier.heartRate.rawValue)?.average,
           averageHeartRate.isFinite,
           averageHeartRate >= 35,
           averageHeartRate <= 230 {
            return averageHeartRate
        }

        return Self.averageValue(
            routeDetailCoordinates.compactMap { coordinate in
                guard let heartRate = coordinate.heartRateBeatsPerMinute,
                      heartRate.isFinite,
                      heartRate >= 35,
                      heartRate <= 230 else {
                    return nil
                }

                return heartRate
            }
        )
    }

    private func averageSpeedMetersPerSecond(durationSeconds: TimeInterval) -> Double? {
        if let averageSpeedMetersPerSecond = routeSummary?.averageSpeedMetersPerSecond,
           averageSpeedMetersPerSecond.isFinite,
           averageSpeedMetersPerSecond > 0 {
            return averageSpeedMetersPerSecond
        }

        guard let distanceMeters = energyEstimateDistanceMeters(),
              durationSeconds > 0 else {
            return nil
        }

        let speed = distanceMeters / durationSeconds
        guard speed.isFinite, speed > 0 else {
            return nil
        }

        return speed
    }

    private func baseMetabolicEquivalent(speedMetersPerSecond: Double?) -> Double {
        let speedKilometersPerHour = speedMetersPerSecond.map { $0 * 3.6 }

        switch sportKind {
        case .cycling, .virtualCycling:
            return Self.cyclingMetabolicEquivalent(speedKilometersPerHour: speedKilometersPerHour)
        case .running, .virtualRunning:
            return Self.runningMetabolicEquivalent(speedKilometersPerHour: speedKilometersPerHour)
        case .trailRunning:
            return Self.runningMetabolicEquivalent(speedKilometersPerHour: speedKilometersPerHour) + 1.0
        case .walking:
            return Self.walkingMetabolicEquivalent(speedKilometersPerHour: speedKilometersPerHour)
        case .hiking:
            return 6.0
        case .outdoorSwimming:
            return 7.0
        case .outdoorWorkout:
            return Self.defaultMetabolicEquivalent(for: activityType)
        }
    }

    private nonisolated static func cyclingMetabolicEquivalent(speedKilometersPerHour: Double?) -> Double {
        guard let speedKilometersPerHour else {
            return 8.0
        }

        switch speedKilometersPerHour {
        case ..<16:
            return 4.0
        case ..<19.2:
            return 6.8
        case ..<22.4:
            return 8.0
        case ..<25.6:
            return 10.0
        case ..<30.6:
            return 12.0
        default:
            return 15.8
        }
    }

    private nonisolated static func runningMetabolicEquivalent(speedKilometersPerHour: Double?) -> Double {
        guard let speedKilometersPerHour else {
            return 9.8
        }

        switch speedKilometersPerHour {
        case ..<8.0:
            return 8.3
        case ..<9.7:
            return 9.8
        case ..<11.3:
            return 11.0
        case ..<12.9:
            return 11.8
        case ..<14.5:
            return 12.8
        default:
            return 14.5
        }
    }

    private nonisolated static func walkingMetabolicEquivalent(speedKilometersPerHour: Double?) -> Double {
        guard let speedKilometersPerHour else {
            return 3.5
        }

        switch speedKilometersPerHour {
        case ..<3.2:
            return 2.5
        case ..<4.8:
            return 3.3
        case ..<5.6:
            return 4.3
        default:
            return 5.0
        }
    }

    private nonisolated static func defaultMetabolicEquivalent(for activityType: HKWorkoutActivityType) -> Double {
        switch activityType {
        case .paddleSports:
            return 5.0
        case .rowing:
            return 7.0
        case .sailing:
            return 3.0
        case .surfingSports:
            return 3.5
        case .snowSports, .skatingSports:
            return 7.0
        case .handCycling:
            return 6.0
        default:
            return 5.0
        }
    }

    private func heartRateIntensityMultiplier() -> Double {
        guard let averageHeartRate = averageHeartRateBeatsPerMinute() else {
            return 1
        }

        let intensity = (averageHeartRate - 60) / 130
        let multiplier = 1 + (intensity - 0.55) * 0.45
        return min(max(multiplier, 0.82), 1.22)
    }

    private func elevationGainEnergyEstimate() -> Double {
        guard let elevationGainMeters = displayElevationGainMeters,
              elevationGainMeters.isFinite,
              elevationGainMeters > 0 else {
            return 0
        }

        let joules = Self.assumedBodyMassKilograms * 9.80665 * elevationGainMeters
        let kilocaloriesAtTwentyFivePercentEfficiency = joules / 4_184 / 0.25
        return max(kilocaloriesAtTwentyFivePercentEfficiency, 0)
    }

    private nonisolated static func averageValue(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }

    private nonisolated static func validEnergyEstimate(_ value: Double) -> Double? {
        guard value.isFinite, value > 0 else {
            return nil
        }

        return min(value, 50_000)
    }

    private nonisolated static func distanceMeters(for coordinates: [RouteCoordinate]) -> Double {
        guard coordinates.count > 1 else {
            return 0
        }

        var totalDistance: CLLocationDistance = 0
        var previousLocation = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
        for coordinate in coordinates.dropFirst() {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            totalDistance += location.distance(from: previousLocation)
            previousLocation = location
        }

        return totalDistance
    }
}
