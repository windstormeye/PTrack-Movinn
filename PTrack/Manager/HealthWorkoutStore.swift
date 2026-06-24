//
//  HealthWorkoutStore.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import CoreLocation
import Foundation
import HealthKit

final class HealthWorkoutStore {
    static let authorizationStateDidChangeNotification = Notification.Name(
        "studio.pj.PTrack.health.authorizationStateDidChange"
    )

    private lazy var healthStore = HKHealthStore()
    private let defaults: UserDefaults

    var progressHandler: ((String) -> Void)?

    enum AuthorizationState {
        case notDetermined
        case authorized
        case needsAttention
    }

    enum AuthorizationRequestAvailability {
        case canRequest
        case settingsRequired
    }

    private enum DefaultsKey {
        static let authorizationRequested = "studio.pj.PTrack.health.authorizationRequested"
        static let authorizationNeedsAttention = "studio.pj.PTrack.health.authorizationNeedsAttention"
        static let authorizationVerified = "studio.pj.PTrack.health.authorizationVerified"
    }

    private static let sourceLookupRetryDelays: [TimeInterval] = [0.35, 0.9, 1.6]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var authorizationState: AuthorizationState {
        guard defaults.bool(forKey: DefaultsKey.authorizationRequested) else {
            return .notDetermined
        }

        guard HKHealthStore.isHealthDataAvailable(),
              !defaults.bool(forKey: DefaultsKey.authorizationNeedsAttention),
              defaults.bool(forKey: DefaultsKey.authorizationVerified) else {
            return .needsAttention
        }

        return .authorized
    }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        for spec in quantityMetricSpecs {
            if let quantityType = spec.quantityType {
                types.insert(quantityType)
            }
        }

        return types
    }

    private static let quantityMetricSpecs: [HealthQuantityMetricSpec] = [
        HealthQuantityMetricSpec(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            unitLabel: "kcal",
            options: .cumulativeSum
        ),
        HealthQuantityMetricSpec(
            identifier: .basalEnergyBurned,
            unit: .kilocalorie(),
            unitLabel: "kcal",
            options: .cumulativeSum
        ),
        HealthQuantityMetricSpec(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            unitLabel: "count/min",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        ),
        HealthQuantityMetricSpec(
            identifier: .distanceWalkingRunning,
            unit: .meter(),
            unitLabel: "m",
            options: .cumulativeSum
        ),
        HealthQuantityMetricSpec(
            identifier: .distanceCycling,
            unit: .meter(),
            unitLabel: "m",
            options: .cumulativeSum
        ),
        HealthQuantityMetricSpec(
            identifier: .stepCount,
            unit: .count(),
            unitLabel: "count",
            options: .cumulativeSum
        ),
        HealthQuantityMetricSpec(
            identifier: .flightsClimbed,
            unit: .count(),
            unitLabel: "count",
            options: .cumulativeSum
        ),
        HealthQuantityMetricSpec(
            identifier: .appleExerciseTime,
            unit: .minute(),
            unitLabel: "min",
            options: .cumulativeSum
        ),
        HealthQuantityMetricSpec(
            identifier: .appleMoveTime,
            unit: .minute(),
            unitLabel: "min",
            options: .cumulativeSum
        ),
        HealthQuantityMetricSpec(
            identifier: .runningSpeed,
            unit: .meter().unitDivided(by: .second()),
            unitLabel: "m/s",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        ),
        HealthQuantityMetricSpec(
            identifier: .runningPower,
            unit: .watt(),
            unitLabel: "W",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        ),
        HealthQuantityMetricSpec(
            identifier: .runningStrideLength,
            unit: .meter(),
            unitLabel: "m",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        ),
        HealthQuantityMetricSpec(
            identifier: .runningVerticalOscillation,
            unit: .meter(),
            unitLabel: "m",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        ),
        HealthQuantityMetricSpec(
            identifier: .runningGroundContactTime,
            unit: .second(),
            unitLabel: "s",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        ),
        HealthQuantityMetricSpec(
            identifier: .cyclingSpeed,
            unit: .meter().unitDivided(by: .second()),
            unitLabel: "m/s",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        ),
        HealthQuantityMetricSpec(
            identifier: .cyclingPower,
            unit: .watt(),
            unitLabel: "W",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        ),
        HealthQuantityMetricSpec(
            identifier: .cyclingCadence,
            unit: HKUnit.count().unitDivided(by: .minute()),
            unitLabel: "count/min",
            options: [.discreteAverage, .discreteMin, .discreteMax]
        )
    ]

    func requestAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            markAuthorizationNeedsAttention()
            completion(.failure(HealthWorkoutStoreError.healthDataUnavailable))
            return
        }

        let readTypes = Self.readTypes
        requestAuthorization(readTypes: readTypes, attempt: 0, completion: completion)
    }

    private func requestAuthorization(
        readTypes: Set<HKObjectType>,
        attempt: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        healthStore = HKHealthStore()

        print(
            "PTrack HealthKit: requesting authorization on main thread: \(Thread.isMainThread), read type count: \(readTypes.count), attempt: \(attempt + 1)"
        )
        if attempt == 0 {
            progressHandler?(AppLocalization.text(.healthAuthorizationProgress))
        }
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            print("PTrack HealthKit: authorization request completed, success: \(success), error: \(String(describing: error))")
            if let error {
                if self.shouldRetryAuthorization(after: error, attempt: attempt) {
                    let delay = Self.sourceLookupRetryDelays[attempt]
                    print(
                        "PTrack HealthKit: source lookup not ready after reinstall, retrying authorization in \(delay)s"
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.requestAuthorization(
                            readTypes: readTypes,
                            attempt: attempt + 1,
                            completion: completion
                        )
                    }
                    return
                }

                if Self.isAuthorizationSourceLookupError(error) {
                    self.markAuthorizationNotDetermined()
                    completion(.failure(HealthWorkoutStoreError.authorizationTemporarilyUnavailable))
                    return
                }

                self.updateAuthorizationState(for: error)
                completion(.failure(error))
            } else if success {
                self.markAuthorizationRequiresVerification()
                completion(.success(()))
            } else {
                self.markAuthorizationNeedsAttention()
                completion(.failure(HealthWorkoutStoreError.authorizationDenied))
            }
        }
    }

    func authorizationRequestAvailability(
        completion: @escaping (Result<AuthorizationRequestAvailability, Error>) -> Void
    ) {
        guard HKHealthStore.isHealthDataAvailable() else {
            markAuthorizationNeedsAttention()
            completion(.failure(HealthWorkoutStoreError.healthDataUnavailable))
            return
        }

        healthStore.getRequestStatusForAuthorization(
            toShare: [],
            read: Self.readTypes
        ) { status, error in
            if let error {
                self.updateAuthorizationState(for: error)
                completion(.failure(error))
                return
            }

            switch status {
            case .shouldRequest, .unknown:
                completion(.success(.canRequest))
            case .unnecessary:
                completion(.success(.settingsRequired))
            @unknown default:
                completion(.success(.settingsRequired))
            }
        }
    }

    private func shouldRetryAuthorization(after error: Error, attempt: Int) -> Bool {
        Self.isAuthorizationSourceLookupError(error)
            && Self.sourceLookupRetryDelays.indices.contains(attempt)
    }

    private static func isAuthorizationSourceLookupError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == HKError.errorDomain,
              nsError.code == HKError.Code.errorInvalidArgument.rawValue else {
            return false
        }

        return nsError.localizedDescription.localizedCaseInsensitiveContains("Failed to look up source")
    }

    func loadTrackedWorkouts(
        after startDate: Date?,
        excludingIDs excludedIDs: Set<String>,
        onNewDataDetected: ((Int) -> Void)? = nil,
        onTrackedWorkout: @escaping (TrackedWorkout) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        let types: [HKWorkoutActivityType] = [.cycling, .hiking, .walking, .running]
        let typePredicates = types.map { HKQuery.predicateForWorkouts(with: $0) }
        var predicates: [NSPredicate] = [
            NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        ]

        if let startDate {
            predicates.append(HKQuery.predicateForSamples(
                withStart: startDate.addingTimeInterval(-60),
                end: nil,
                options: .strictStartDate
            ))
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, error in
            guard let self else { return }
            if let error {
                print("PTrack HealthKit: workout query failed: \(error)")
                self.updateAuthorizationState(for: error)
                completion(.failure(error))
                return
            }

            let workouts = ((samples as? [HKWorkout]) ?? [])
                .filter { !excludedIDs.contains($0.uuid.uuidString) }
            print("PTrack HealthKit: found \(workouts.count) new cycling/hiking/walking/running workouts")
            if !workouts.isEmpty {
                self.markAuthorizationVerified()
            }
            if !workouts.isEmpty {
                onNewDataDetected?(workouts.count)
            }
            self.progressHandler?("找到 \(workouts.count) 条运动记录，正在逐条读取轨迹...")
            self.loadRoutes(
                for: workouts,
                onTrackedWorkout: onTrackedWorkout,
                completion: completion
            )
        }

        healthStore.execute(query)
    }

    private func markAuthorizationAuthorized() {
        defaults.set(true, forKey: DefaultsKey.authorizationRequested)
        defaults.set(false, forKey: DefaultsKey.authorizationNeedsAttention)
        defaults.set(true, forKey: DefaultsKey.authorizationVerified)
        notifyAuthorizationStateDidChange()
    }

    private func markAuthorizationRequiresVerification() {
        defaults.set(true, forKey: DefaultsKey.authorizationRequested)
        defaults.set(true, forKey: DefaultsKey.authorizationNeedsAttention)
        defaults.set(false, forKey: DefaultsKey.authorizationVerified)
        notifyAuthorizationStateDidChange()
    }

    private func markAuthorizationNotDetermined() {
        defaults.set(false, forKey: DefaultsKey.authorizationRequested)
        defaults.set(false, forKey: DefaultsKey.authorizationNeedsAttention)
        defaults.set(false, forKey: DefaultsKey.authorizationVerified)
        notifyAuthorizationStateDidChange()
    }

    func markAuthorizationNeedsAttention() {
        defaults.set(true, forKey: DefaultsKey.authorizationRequested)
        defaults.set(true, forKey: DefaultsKey.authorizationNeedsAttention)
        defaults.set(false, forKey: DefaultsKey.authorizationVerified)
        notifyAuthorizationStateDidChange()
    }

    func markAuthorizationVerified() {
        markAuthorizationAuthorized()
    }

    private func notifyAuthorizationStateDidChange() {
        NotificationCenter.default.post(name: Self.authorizationStateDidChangeNotification, object: self)
    }

    private func updateAuthorizationState(for error: Error) {
        guard let healthKitError = error as? HKError else {
            return
        }

        switch healthKitError.code {
        case .errorAuthorizationNotDetermined:
            markAuthorizationNotDetermined()
        case .errorAuthorizationDenied:
            markAuthorizationNeedsAttention()
        default:
            break
        }
    }

    private func loadRoutes(
        for workouts: [HKWorkout],
        onTrackedWorkout: @escaping (TrackedWorkout) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard !workouts.isEmpty else {
            completion(.success(0))
            return
        }

        var trackedWorkoutCount = 0
        var firstError: Error?

        func loadNextWorkout(at index: Int) {
            guard index < workouts.count else {
                if let firstError, trackedWorkoutCount == 0 {
                    completion(.failure(firstError))
                } else {
                    completion(.success(trackedWorkoutCount))
                }
                return
            }

            let workout = workouts[index]
            progressHandler?("正在读取 \(index + 1)/\(workouts.count)，已找到 \(trackedWorkoutCount) 条轨迹")

            loadRouteDetails(for: workout) { result in
                switch result {
                case .success(let routeDetails):
                    print(
                        "PTrack HealthKit: \(workout.workoutActivityType.rawValue) \(workout.startDate) route locations: \(routeDetails.locations.count)"
                    )

                    guard routeDetails.locations.count > 1 else {
                        loadNextWorkout(at: index + 1)
                        return
                    }

                    self.progressHandler?("正在读取 \(workout.startDate) 的运动指标...")
                    self.loadQuantityMetrics(for: workout) { quantityMetrics in
                        trackedWorkoutCount += 1
                        onTrackedWorkout(TrackedWorkout(
                            workout: workout,
                            locations: routeDetails.locations,
                            routeSegments: routeDetails.segments,
                            quantityMetrics: quantityMetrics
                        ))
                        loadNextWorkout(at: index + 1)
                    }
                    return
                case .failure(let error):
                    print(
                        "PTrack HealthKit: route load failed for \(workout.workoutActivityType.rawValue) \(workout.startDate): \(error)"
                    )
                    if firstError == nil {
                        firstError = error
                    }
                }

                loadNextWorkout(at: index + 1)
            }
        }

        loadNextWorkout(at: 0)
    }

    private func loadRouteDetails(
        for workout: HKWorkout,
        completion: @escaping (Result<LoadedWorkoutRouteDetails, Error>) -> Void
    ) {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let query = HKSampleQuery(
            sampleType: routeType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let self else { return }
            if let error {
                print("PTrack HealthKit: route sample query failed: \(error)")
                self.updateAuthorizationState(for: error)
                completion(.failure(error))
                return
            }

            let routes = (samples as? [HKWorkoutRoute]) ?? []
            print("PTrack HealthKit: \(workout.workoutActivityType.rawValue) \(workout.startDate) routes: \(routes.count)")
            self.progressHandler?("正在读取 \(workout.startDate) 的 \(routes.count) 段轨迹...")
            self.collectRouteDetails(from: routes, completion: completion)
        }

        healthStore.execute(query)
    }

    private func collectRouteDetails(
        from routes: [HKWorkoutRoute],
        completion: @escaping (Result<LoadedWorkoutRouteDetails, Error>) -> Void
    ) {
        guard !routes.isEmpty else {
            completion(.success(LoadedWorkoutRouteDetails(locations: [], segments: [])))
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var allLocations: [CLLocation] = []
        var segments: [TrackedWorkoutRouteSegment] = []
        var firstError: Error?

        for route in routes {
            group.enter()

            var routeLocations: [CLLocation] = []
            var isFinished = false
            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                func finishRouteIfNeeded() {
                    guard !isFinished else { return }
                    isFinished = true
                    lock.lock()
                    allLocations.append(contentsOf: routeLocations)
                    segments.append(TrackedWorkoutRouteSegment(
                        route: route,
                        locationCount: routeLocations.count
                    ))
                    lock.unlock()
                    group.leave()
                }

                if let error {
                    print("PTrack HealthKit: workout route query failed: \(error)")
                    self.updateAuthorizationState(for: error)
                    lock.lock()
                    if firstError == nil {
                        firstError = error
                    }
                    lock.unlock()
                    finishRouteIfNeeded()
                    return
                }

                if let locations {
                    routeLocations.append(contentsOf: locations)
                }

                if done {
                    finishRouteIfNeeded()
                }
            }

            healthStore.execute(routeQuery)
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            if let firstError, allLocations.isEmpty {
                completion(.failure(firstError))
            } else {
                completion(.success(LoadedWorkoutRouteDetails(
                    locations: allLocations.sorted { $0.timestamp < $1.timestamp },
                    segments: segments.sorted { $0.startDate < $1.startDate }
                )))
            }
        }
    }

    private func loadQuantityMetrics(
        for workout: HKWorkout,
        completion: @escaping ([TrackedWorkoutQuantityMetric]) -> Void
    ) {
        let metricsToLoad = Self.quantityMetricSpecs.compactMap { spec -> (HealthQuantityMetricSpec, HKQuantityType)? in
            guard let quantityType = spec.quantityType else {
                return nil
            }
            return (spec, quantityType)
        }

        guard !metricsToLoad.isEmpty else {
            completion([])
            return
        }

        let predicate = HKQuery.predicateForObjects(from: workout)
        let group = DispatchGroup()
        let lock = NSLock()
        var metrics: [TrackedWorkoutQuantityMetric] = []

        for (spec, quantityType) in metricsToLoad {
            if let workoutStatistics = workout.statistics(for: quantityType) {
                let metric = Self.quantityMetric(from: workoutStatistics, spec: spec)
                if metric.hasValues {
                    metrics.append(metric)
                    continue
                }
            }

            group.enter()
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: spec.options
            ) { _, statistics, error in
                defer { group.leave() }

                if let error {
                    print("PTrack HealthKit: metric query failed for \(spec.identifier.rawValue): \(error)")
                    return
                }

                guard let statistics else {
                    return
                }

                let metric = Self.quantityMetric(from: statistics, spec: spec)

                guard metric.hasValues else {
                    return
                }

                lock.lock()
                metrics.append(metric)
                lock.unlock()
            }

            healthStore.execute(query)
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            completion(metrics.sorted { $0.identifier < $1.identifier })
        }
    }

    nonisolated private static func quantityMetric(
        from statistics: HKStatistics,
        spec: HealthQuantityMetricSpec
    ) -> TrackedWorkoutQuantityMetric {
        TrackedWorkoutQuantityMetric(
            identifier: spec.identifier.rawValue,
            unit: spec.unitLabel,
            sum: statistics.sumQuantity()?.doubleValue(for: spec.unit),
            average: statistics.averageQuantity()?.doubleValue(for: spec.unit),
            minimum: statistics.minimumQuantity()?.doubleValue(for: spec.unit),
            maximum: statistics.maximumQuantity()?.doubleValue(for: spec.unit)
        )
    }
}

private struct LoadedWorkoutRouteDetails {
    let locations: [CLLocation]
    let segments: [TrackedWorkoutRouteSegment]
}

private struct HealthQuantityMetricSpec {
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
    let unitLabel: String
    let options: HKStatisticsOptions

    var quantityType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: identifier)
    }
}
